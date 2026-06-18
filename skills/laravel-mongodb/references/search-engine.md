# Search Engine (Atlas Search via Laravel Scout)

When to use this reference: adding full-text or vector search to Laravel models backed by MongoDB Atlas. The `mongodb/laravel-mongodb` package ships a Scout engine that targets Atlas Search natively — no Algolia, Meilisearch, or Elasticsearch needed.

## Installation

```
composer require laravel/scout
php artisan vendor:publish --provider="Laravel\Scout\ScoutServiceProvider"
```

## Configuration

```php
// config/scout.php
return [
    'driver' => env('SCOUT_DRIVER', 'mongodb'),

    'mongodb' => [
        'connection' => env('SCOUT_MONGODB_CONNECTION', 'mongodb'),
        'index-definitions' => [
            // optional pre-defined Atlas Search index definitions
        ],
    ],
];
```

`.env`:

```
SCOUT_DRIVER=mongodb
```

## Searchable model

```php
<?php

declare(strict_types=1);

namespace App\Models;

use Laravel\Scout\Searchable;
use MongoDB\Laravel\Eloquent\Model;

final class Product extends Model
{
    use Searchable;

    protected $fillable = ['name', 'description', 'price', 'tags'];

    public function toSearchableArray(): array
    {
        return [
            'name'        => $this->name,
            'description' => $this->description,
            'tags'        => $this->tags,
            'price'       => (float) $this->price,
        ];
    }

    public function searchableAs(): string
    {
        return 'products';   // searchable collection name (not the Atlas Search index name)
    }
}
```

> The MongoDB Scout engine uses a **constant** Atlas Search index name `scout` by default — `searchableAs()` returns the collection name, not the index name.
> Scout stores searchable documents in a **separate** collection. Do not use the same collection name as the model's main collection.

## Creating the Atlas Search index

Atlas Search indexes can be managed through Laravel migrations using the package's schema builder:

```php
Schema::connection('mongodb')->create('products', function (Blueprint $c): void {
    $c->searchIndex([
        'mappings' => [
            'dynamic' => false,
            'fields'  => [
                'name'        => ['type' => 'string'],
                'description' => ['type' => 'string'],
                'tags'        => ['type' => 'string'],
                'price'       => ['type' => 'number'],
            ],
        ],
    ]);
});
```

Alternatively, create the index via the Atlas UI or Atlas Admin API.

## Queries

```php
// Full-text search
$results = Product::search('wireless headphones')->get();

// Pagination
$page = Product::search('headphones')->paginate(15);
```

> Scout's `where()` only supports **equality** filters in the MongoDB engine (translated to Atlas Search `equals`). Range filters like `->where('price', '<=', 200)` are not supported via Scout — use a raw aggregation instead.

```php
// WRONG — range filter not supported via Scout
$results = Product::search('headphones')->where('price', '<=', 200)->get();

// CORRECT — use aggregation pipeline for range filters
$results = Product::raw(fn ($c) => $c->aggregate([
    ['$search' => ['index' => 'scout', 'text' => ['query' => 'headphones', 'path' => 'name']]],
    ['$match'  => ['price' => ['$lte' => 200]]],
]));
```

## Vector search

For semantic / RAG use cases, store embeddings in a `vector` field and create an Atlas **Vector Search** index. Use either the package's `vectorSearch()` builder method or a raw aggregation pipeline:

```php
// Using the package builder (available in v5.x)
$matches = Product::vectorSearch(
    index: 'products_vector',
    path: 'embedding',
    queryVector: $queryVector,
    numCandidates: 200,
    limit: 10,
);

// Or via raw aggregation
$matches = Product::raw(fn ($c) => $c->aggregate([
    [
        '$vectorSearch' => [
            'index'         => 'products_vector',
            'path'          => 'embedding',
            'queryVector'   => $queryVector,
            'numCandidates' => 200,
            'limit'         => 10,
        ],
    ],
]));
```

## Cross-references

> For Atlas Search index design, vector / hybrid search patterns, and relevance tuning, see the **mongodb-search-and-ai** skill.