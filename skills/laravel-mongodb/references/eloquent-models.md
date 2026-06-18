# Eloquent Models

## Base class

```php
// WRONG — standard Eloquent does not understand MongoDB types
use Illuminate\Database\Eloquent\Model;

// CORRECT
use MongoDB\Laravel\Eloquent\Model;
```

```php
<?php

declare(strict_types=1);

namespace App\Models;

use MongoDB\Laravel\Eloquent\Model;

final class Movie extends Model
{
    protected $connection = 'mongodb';
    protected $table      = 'movies';   // $table not $collection (removed in v5.0)
    protected $keyType    = 'string';   // ObjectId surfaced as string (already default)

    protected $fillable = ['title', 'year', 'released_at'];

    protected $casts = [
        'year'        => 'integer',
        'released_at' => 'datetime',
        // Do NOT cast native MongoDB arrays to 'array' — stored natively;
        // 'array' cast triggers deprecation and may serialize as JSON.
    ];
}
```

## `_id` vs `id`

- BSON field is `_id` (ObjectId); PHP exposes both `id` and `_id`.
- In API resources, always cast to string so clients receive `"6708..."` not `{"$oid":"6708..."}`:

```php
public function toArray(Request $request): array
{
    return [
        'id'    => (string) $this->_id,
        'title' => $this->title,
    ];
}
```

## ObjectId casts for foreign keys

Eloquent compares keys with `==`. A native `ObjectId` and a string `"6708..."` are **not equal** — casting to string on both ends is the safest default.

```php
protected $casts = [
    'author_id' => 'string',   // simplest: store/read as string for Eloquent matching

    // OR preserve native BSON ObjectId:
    // 'author_id' => MongoDB\Laravel\Eloquent\Casts\ObjectId::class,
    // (use the package cast, NOT \MongoDB\BSON\ObjectId::class)
];
```

## Extending a non-MongoDB base class

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
    protected $table      = 'audit_logs';
    protected $keyType    = 'string';
}
```

## Encryption

```php
protected $casts = [
    'ssn' => 'encrypted',   // Laravel encrypted cast; use Queryable Encryption for server-side equality
];
```
