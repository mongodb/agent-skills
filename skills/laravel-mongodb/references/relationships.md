# Relationships

## The ObjectId vs string trap

Eloquent compares keys with `==`. A native `ObjectId` and a string `"6708..."` are **not equal** — `belongsTo()` silently returns null when both sides hold a native ObjectId.

```php
// WRONG — both sides store native ObjectId; belongsTo returns null
final class Post extends Model
{
    public function author(): BelongsTo
    {
        return $this->belongsTo(User::class, 'author_id');
    }
}

// CORRECT — cast FK to string on child; string keyType on parent
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

Use MongoDB-aware relation classes when in doubt:

```php
use MongoDB\Laravel\Relations\BelongsTo;
use MongoDB\Laravel\Relations\HasMany;
```

## Embedded documents

Embedded relations live inside the parent document — no second collection, no FK.

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

$post->comments()->create(['body' => 'hi']);
$post->comments->where('approved', true);
```

`Comment` / `Author` extend `MongoDB\Laravel\Eloquent\Model` but are never persisted standalone.

## Cross-database relationships (MongoDB ↔ SQL)

The SQL table must store the MongoDB `_id` as a **string column** (`VARCHAR(24)`).

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

// SQL model → MongoDB child (apply HybridRelations on the SQL side)
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

## Eager loading

MongoDB cannot join Eloquent relations server-side (except via `$lookup`). Every `with()` is an extra round-trip — use it deliberately:

```php
$posts = Post::with(['author', 'tags'])->get();
```
