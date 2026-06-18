# Eloquent Models

When to use this reference: defining, extending or auditing an Eloquent model that maps to a MongoDB collection. Covers the base class, `_id` / `id` mapping, ObjectId casts, and the `DocumentModel` trait for non-MongoDB base classes.

## Base class

```php
// WRONG — standard Laravel Eloquent does not understand MongoDB types
use Illuminate\Database\Eloquent\Model;

// CORRECT
use MongoDB\Laravel\Eloquent\Model;
```

A complete model:

```php
<?php

declare(strict_types=1);

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

final class Movie extends Model
{
    protected $connection = 'mongodb';
    protected $collection = 'movies';      // not $table
    protected $primaryKey = '_id';         // default
    protected $keyType    = 'string';      // ObjectId surfaced as string

    protected $fillable = ['title', 'year', 'genres', 'released_at'];

    protected $casts = [
        'year'        => 'integer',
        'genres'      => 'array',
        'released_at' => 'datetime',
    ];
}
```

## `_id` vs `id`

- The BSON field is `_id` (ObjectId).
- The PHP attribute is exposed as `id` *and* `_id` — both work.
- In API resources, **always cast to string** so the client receives `"6708..."` and not `{"$oid":"6708..."}`:

```php
public function toArray(Request $request): array
{
    return [
        'id'    => (string) $this->_id,
        'title' => $this->title,
    ];
}
```

## ObjectId casts

Foreign keys are stored as ObjectId but Eloquent compares them as strings. Always cast:

```php
protected $casts = [
    'author_id' => 'string',           // simplest, recommended
    // OR keep the native type:
    // 'author_id' => \MongoDB\BSON\ObjectId::class,
];
```

When the FK is stored as `ObjectId` *and* read as `ObjectId`, `belongsTo()` fails to match unless both sides agree. Casting to `string` on both ends is the safest default.

## Extending a non-MongoDB base class

If you cannot extend `MongoDB\Laravel\Eloquent\Model` (e.g. a vendor base model), use the trait:

```php
<?php

declare(strict_types=1);

namespace App\Models;

use MongoDB\Laravel\Eloquent\DocumentModel;
use Vendor\Package\BaseModel;

final class AuditLog extends BaseModel
{
    use DocumentModel;

    protected $connection = 'mongodb';
    protected $collection = 'audit_logs';
    protected $primaryKey = '_id';
    protected $keyType    = 'string';
}
```

## Encryption

Use Laravel's encrypted casts for sensitive fields, or MongoDB Queryable Encryption when you need server-side equality on encrypted data:

```php
protected $casts = [
    'ssn' => 'encrypted',
];
```

Never store credit-card / PII unencrypted.

## Cross-references

> For document modeling, embedding vs referencing, and schema anti-patterns, see the **mongodb-schema-design** skill.