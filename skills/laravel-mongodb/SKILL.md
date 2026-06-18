---
name: laravel-mongodb
description: Implementation specialist for the mongodb/laravel-mongodb package. Use this skill whenever a Laravel project uses MongoDB as a database, cache, session, queue, or search backend. Triggers on "Laravel MongoDB", "mongodb/laravel-mongodb", "Eloquent MongoDB", "MongoDB model", "MongoDB Eloquent", "_id", "ObjectId in Laravel", "MongoDB queue driver", "MongoDB cache driver", "MongoDB session driver", "Atlas Search Laravel", "Laravel Scout MongoDB", "embedsMany", "embedsOne", "hasManyIn", "withCount MongoDB", "distinct MongoDB Eloquent", "Laravel aggregation pipeline", "cross-database relationship MongoDB". Corrects the common LLM mistakes that arise when standard Laravel/MySQL patterns are applied to MongoDB (auto-increment IDs, withCount/withAvg/withSum, toSql, raw SQL helpers, distinct returning arrays, JOIN, native ObjectId in relationships, inRandomOrder, whereFulltext, union, whereColumn).
license: Apache-2.0
metadata:
  author: https://github.com/mongodb
  version: "1.0.0"
  domain: backend
  triggers: laravel-mongodb, mongodb/laravel-mongodb, eloquent mongodb, mongodb model, _id, ObjectId, embedsMany, embedsOne, hasManyIn, mongodb queue, mongodb cache, mongodb session, atlas search laravel, laravel scout mongodb, aggregation pipeline, withCount mongodb, distinct mongodb, mongodb migration, mongodb transaction
  role: specialist
  scope: implementation
  output-format: code
  related-skills: mongodb-connection, mongodb-schema-design, mongodb-query-optimizer
---

# Laravel MongoDB

Implementation skill for the official `mongodb/laravel-mongodb` package. It exists because Laravel developers (and LLMs) routinely apply MySQL/Eloquent assumptions to MongoDB and produce broken code: auto-increment IDs, `withCount()`, `toSql()`, `JOIN`, `distinct()->get()` expecting scalar arrays, and `belongsTo()` over native `ObjectId` foreign keys. This skill replaces those patterns with the correct MongoDB idioms.

## Core Workflow

1. Identify which layer is involved: model, query builder, relationship, schema/index, queue/cache/session, search, or transaction.
2. Confirm the model extends `MongoDB\Laravel\Eloquent\Model` (or uses the `DocumentModel` trait when extending a non-MongoDB base class).
3. Map every foreign key and `_id` reference: ObjectId on the database, **string** in Eloquent. Cast accordingly.
4. Replace unsupported Eloquent helpers (`withCount`, `toSql`, `groupByRaw`, `whereFulltext`, `union`, `inRandomOrder`, `whereColumn`) with the documented MongoDB alternative (aggregation pipeline, `dump()`, `$sample`, etc.).
5. Validate: run `php artisan migrate`, the relevant Pest tests, and `phpcs` / `phpstan` before finishing.

## Reference Guide

| Topic | Reference file | Load When |
|---|---|---|
| Models, casts, `_id` mapping | `references/eloquent-models.md` | Defining or modifying a model |
| Query builder gotchas, aggregation | `references/query-builder.md` | Writing queries, `withCount`, `distinct`, grouping |
| Embedded, hybrid, cross-database relations | `references/relationships.md` | `belongsTo`, `hasMany`, `embedsMany`, `hasManyIn` |
| Connection setup | `references/connection.md` | `config/database.php`, multiple connections |
| Indexes, migrations | `references/schema.md` | Creating indexes, migrations, collections |
| Queue driver | `references/queues.md` | Dispatching jobs, queue config |
| Transactions | `references/transactions.md` | Multi-document atomic writes |
| Cache & sessions | `references/cache-sessions.md` | Configuring cache / session stores |
| Atlas Search / Scout | `references/search-engine.md` | Full-text or vector search |

## Constraints

### MUST DO

- Use PHP 8.2+ with `declare(strict_types=1);` and typed properties / return types in every example.
- Extend `MongoDB\Laravel\Eloquent\Model` for MongoDB models (or apply `MongoDB\Laravel\Eloquent\DocumentModel` to a base class you cannot change).
- Cast `_id` to `string` in every API resource: `'id' => (string) $this->_id`.
- Store ObjectId foreign keys as strings via `$casts` or set `protected $keyType = 'string';` on the parent model so `belongsTo()` / `hasMany()` match.
- Eager-load relationships with `::with()`. MongoDB cannot do server-side joins for Eloquent relations — N+1 problems are 100% client-side.
- Use the aggregation pipeline (`Model::raw(fn($c) => $c->aggregate([...]))`) for grouping, counting per group, joining (`$lookup`), and random sampling (`$sample`).
- Create indexes through migrations: `Schema::create('posts', fn (Blueprint $c) => $c->index('user_id'));`.
- Use `DB::connection('mongodb')->transaction(...)` only when targeting a replica set / sharded cluster.

### MUST NOT DO

- Do not use `withCount()`, `withAvg()`, `withSum()` — they silently produce wrong results or throw. Use `$lookup` + `$count` aggregation or `loadCount()` on a collection.
- Do not call `toSql()` or `toRawSql()` — there is no SQL. Use `->dump()` / `->dd()` which prints the MongoDB query array.
- Do not assume `distinct('field')->get()` returns an array of scalars — it returns a Collection. Use `distinct()->pluck('field')` or an aggregation `$group`.
- Do not use `groupByRaw()`, `orderByRaw()`, `havingRaw()`, `whereFulltext()`, `union()`, `whereColumn()` — none are supported. Switch to aggregation.
- Do not use `inRandomOrder()` — unsupported. Use `Model::raw(fn($c) => $c->aggregate([['$sample' => ['size' => N]]]))`.
- Do not use auto-increment IDs. MongoDB primary keys are ObjectIds.
- Do not mix native `ObjectId` foreign keys with default `belongsTo()` — either cast to string or use `MongoDB\Laravel\Relations\BelongsTo`.
- Do not store unencrypted PII/credentials in documents — use Laravel encrypted casts or Queryable Encryption.

## Code Templates

### 1. Eloquent model

```php
<?php

declare(strict_types=1);

namespace App\Models;

use MongoDB\BSON\ObjectId;
use MongoDB\Laravel\Eloquent\Model;

final class Post extends Model
{
    protected $connection = 'mongodb';
    protected $collection = 'posts';

    protected $fillable = ['title', 'body', 'author_id', 'tags', 'published_at'];

    protected $casts = [
        'author_id'    => 'string',   // ObjectId stored as string in PHP
        'tags'         => 'array',
        'published_at' => 'datetime',
    ];
}
```

### 2. Relationship with correct ObjectId/string casting

```php
<?php

declare(strict_types=1);

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;
use MongoDB\Laravel\Relations\BelongsTo;
use MongoDB\Laravel\Relations\EmbedsMany;
use MongoDB\Laravel\Relations\HasMany;

final class Post extends Model
{
    protected $keyType  = 'string';
    protected $casts    = ['author_id' => 'string'];

    public function author(): BelongsTo
    {
        return $this->belongsTo(User::class, 'author_id');
    }

    public function comments(): EmbedsMany
    {
        return $this->embedsMany(Comment::class);
    }

    public function relatedPosts(): HasMany
    {
        // hasManyIn → foreign key is an *array* of ObjectIds in this document
        return $this->hasManyIn(Post::class, 'related_ids');
    }
}
```

### 3. Query builder with aggregation (replacement for `withCount`)

```php
<?php

declare(strict_types=1);

use App\Models\Post;

// WRONG: $posts = Post::withCount('comments')->get();
// CORRECT: aggregation pipeline with $lookup + $addFields
$posts = Post::raw(fn ($collection) => $collection->aggregate([
    [
        '$lookup' => [
            'from'         => 'comments',
            'localField'   => '_id',
            'foreignField' => 'post_id',
            'as'           => 'comments',
        ],
    ],
    ['$addFields' => ['comments_count' => ['$size' => '$comments']]],
    ['$project'   => ['comments' => 0]],
]));
```

### 4. Queue job using the MongoDB queue driver

```php
<?php

declare(strict_types=1);

namespace App\Jobs;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

final class IndexPostJob implements ShouldQueue
{
    use Dispatchable;
    use InteractsWithQueue;
    use Queueable;
    use SerializesModels;

    public function __construct(public string $postId) {}

    public function handle(): void
    {
        // dispatch on the mongodb queue connection
    }
}

// dispatch:
IndexPostJob::dispatch((string) $post->_id)->onConnection('mongodb');
```

### 5. Feature test (Pest)

```php
<?php

declare(strict_types=1);

use App\Models\Post;

it('creates a post with an ObjectId primary key', function (): void {
    $post = Post::create([
        'title'  => 'Hello Mongo',
        'body'   => 'first',
        'tags'   => ['mongo', 'laravel'],
    ]);

    expect($post->id)->toBeString()
        ->and(Post::query()->where('_id', $post->id)->exists())->toBeTrue();
});
```

## Validation Checkpoints

| Stage | Command | Expected Result |
|---|---|---|
| Style | `vendor/bin/phpcbf && vendor/bin/phpcs` | No violations |
| Static analysis | `vendor/bin/phpstan analyse` | Level 8 clean |
| Indexes / migration | `php artisan migrate --database=mongodb` | Migrations run; indexes created |
| Tests | `vendor/bin/pest` | All green, including MongoDB feature tests |
| Manual query check | `Model::query()->where(...)->dump()` | Prints MongoDB filter array (no SQL) |