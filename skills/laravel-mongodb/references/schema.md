# Schema and Migrations

When to use this reference: creating collections, defining indexes, or writing migrations. MongoDB is schema-flexible — migrations exist almost exclusively to manage indexes and to seed data.

## Migration template

```php
<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Schema;
use MongoDB\Laravel\Schema\Blueprint;

return new class extends Migration {
    protected $connection = 'mongodb';

    public function up(): void
    {
        Schema::connection('mongodb')->create('posts', function (Blueprint $collection): void {
            $collection->index('author_id');
            $collection->unique('slug');
            $collection->index(['created_at' => -1]);          // descending
            $collection->index(['author_id' => 1, 'created_at' => -1]); // compound
            $collection->geospatial('location', '2dsphere');
            $collection->expire('expires_at', 0);              // TTL index
        });
    }

    public function down(): void
    {
        Schema::connection('mongodb')->drop('posts');
    }
};
```

Run with:

```
php artisan migrate --database=mongodb
```

## Useful Blueprint methods

| Method | Purpose |
|---|---|
| `$collection->index($field)` | single-field ascending index |
| `$collection->index([f => 1, g => -1])` | compound / sort-aware index |
| `$collection->unique($field)` | unique index |
| `$collection->expire($field, $seconds)` | TTL index — auto-delete docs after N seconds |
| `$collection->geospatial($field, '2dsphere')` | geo index |
| `$collection->sparse($field)` | sparse index |
| `$collection->dropIndex($name)` | remove an index |

## Atlas Search indexes

Atlas Search indexes are **not** managed by Laravel migrations. Create them via the Atlas UI, the Atlas Admin API, or the MongoDB MCP server. Reference them by name from `$search` aggregation stages.

## No column definitions

```php
// WRONG — MongoDB does not have columns
$collection->string('title');
$collection->integer('views');

// CORRECT — schema is enforced at the model level (casts, validation rules)
// Optionally apply JSON Schema validation server-side via Atlas / shell.
```

## Cross-references

> For embedding vs referencing, document size, time series, and validation rules, see the **mongodb-schema-design** skill.
> For index selection and query plan tuning, see the **mongodb-query-optimizer** skill.