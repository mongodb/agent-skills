# Search Engine (Atlas Search via Laravel Scout)

No Algolia, Meilisearch, or Elasticsearch needed — `mongodb/laravel-mongodb` ships a Scout engine targeting Atlas Search natively.

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
    ],
];
```

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
        return 'products';   // collection name, not the Atlas Search index name
        // The Atlas Search index name is always 'scout' by default.
        // Scout stores documents in a SEPARATE collection — do not use the model's main collection.
    }
}
```

## Creating the Atlas Search index

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

## Queries

```php
$results = Product::search('wireless headphones')->get();
$page    = Product::search('headphones')->paginate(15);
```

Scout `where()` supports **equality filters only** in the MongoDB engine. Range filters are not supported via Scout:

```php
// WRONG — range filter not supported via Scout
$results = Product::search('headphones')->where('price', '<=', 200)->get();

// CORRECT — use raw aggregation for range filters
$results = Product::raw(fn ($c) => $c->aggregate([
    ['$search' => ['index' => 'scout', 'text' => ['query' => 'headphones', 'path' => 'name']]],
    ['$match'  => ['price' => ['$lte' => 200]]],
]));
```

## Vector search

```php
// Using the package builder (v5.x+)
$matches = Product::vectorSearch(
    index: 'products_vector',
    path: 'embedding',
    queryVector: $queryVector,
    numCandidates: 200,
    limit: 10,
);

// Or via raw aggregation
$matches = Product::raw(fn ($c) => $c->aggregate([
    ['$vectorSearch' => [
        'index'         => 'products_vector',
        'path'          => 'embedding',
        'queryVector'   => $queryVector,
        'numCandidates' => 200,
        'limit'         => 10,
    ]],
]));
```
