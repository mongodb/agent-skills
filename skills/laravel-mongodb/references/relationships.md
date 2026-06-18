# Relationships

When to use this reference: defining `belongsTo`, `hasMany`, `hasOne`, embedded, or cross-database (MongoDB + SQL) relationships. Covers the ObjectId / string casting trap that breaks `belongsTo()` and the MongoDB-only relations `embedsMany`, `embedsOne`, `hasManyIn`.

## The ObjectId vs string trap

Eloquent compares keys with `==`. A native `ObjectId` instance and a string `"6708..."` are **not equal**, so a relationship over a native ObjectId FK returns empty results.

```php
// WRONG — both sides store native ObjectId, belongsTo silently returns null
final class Post extends Model
{
    public function author(): BelongsTo
    {
        return $this->belongsTo(User::class, 'author_id');
    }
}

// CORRECT — cast the FK to string on the child, and force string keyType on the parent
final class Post extends Model
{
    protected $casts = ['author_id' => 'string'];

    public function author(): BelongsTo
    {
        return $this->belongsTo(User::class, 'author_id');
    }
}

final class User extends Model
{
    protected $keyType = 'string';
}
```

Use the MongoDB-aware relation classes when in doubt:

```php
use MongoDB\Laravel\Relations\BelongsTo;
use MongoDB\Laravel\Relations\HasMany;
```

## Embedded documents

Embedded relations live **inside** the parent document — no second collection, no FK.

```php
<?php

declare(strict_types=1);

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;
use MongoDB\Laravel\Relations\EmbedsMany;
use MongoDB\Laravel\Relations\EmbedsOne;

final class Post extends Model
{
    public function comments(): EmbedsMany
    {
        return $this->embedsMany(Comment::class);
    }

    public function author(): EmbedsOne
    {
        return $this->embedsOne(Author::class);
    }
}

// Usage
$post->comments()->create(['body' => 'hi']);
$post->comments->where('approved', true);
```

`Comment` and `Author` here extend `MongoDB\Laravel\Eloquent\Model` but are never persisted on their own — they belong to `$post`.

## `hasManyIn` — array of foreign keys

When the parent document stores **an array of ObjectIds** referencing siblings:

```php
// Document shape: { _id, related_ids: [ObjectId, ObjectId, ...] }
public function related(): HasMany
{
    return $this->hasManyIn(Post::class, 'related_ids');
}
```

## Cross-database relationships (MongoDB ↔ SQL)

You can relate a MongoDB model to a MySQL/PostgreSQL model, **but** you must use the relation classes from `MongoDB\Laravel\Relations` on the MongoDB side and ensure key types match (string on both ends).

```php
// MongoDB model → SQL child
use MongoDB\Laravel\Relations\HasMany;

final class MongoUser extends \MongoDB\Laravel\Eloquent\Model
{
    public function orders(): HasMany
    {
        return $this->hasMany(\App\Models\Order::class, 'user_id');
    }
}

// SQL model → MongoDB child
use MongoDB\Laravel\Eloquent\HybridRelations;

final class Order extends \Illuminate\Database\Eloquent\Model
{
    use HybridRelations;

    public function user(): \MongoDB\Laravel\Relations\BelongsTo
    {
        return $this->belongsTo(MongoUser::class, 'user_id');
    }
}
```

The SQL table must store the MongoDB `_id` as a **string column** (`VARCHAR(24)`).

## Eager loading

MongoDB cannot join Eloquent relations on the server (except via aggregation `$lookup`). Every `with()` call is an extra round-trip. Use it — but be deliberate:

```php
$posts = Post::with(['author', 'tags'])->get();
```

## Cross-references

> For when to embed vs reference, see the **mongodb-schema-design** skill.