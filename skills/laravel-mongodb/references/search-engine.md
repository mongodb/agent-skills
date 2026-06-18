# Search Engine (Atlas Search via Laravel Scout)

When to use this reference: adding full-text or vector search to Laravel models backed by MongoDB Atlas. The `mongodb/laravel-mongodb` package ships a Scout engine that targets Atlas Search natively — no Algolia, Meilisearch, or Elasticsearch needed.

## Configuration

```php
// config/scout.php
return [
    'driver' => env('SCOUT_DRIVER', 'mongodb'),

    'mongodb' => [
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
        return 'products';   // Atlas Search index name
    }
}
```

## Creating the Atlas Search index

Define the index in the Atlas UI or via the Atlas Admin API. A minimal definition:

```json
{
    "mappings": {
        "dynamic": false,
        "fields": {
            "name":        { "type": "string" },
            "description": { "type": "string" },
            "tags":        { "type": "string" },
            "price":       { "type": "number" }
        }
    }
}
```

## Queries

```php
// Full-text
$results = Product::search('wireless headphones')->get();

// With filters (translated to $search compound)
$results = Product::search('headphones')
    ->where('price', '<=', 200)
    ->take(20)
    ->get();

// Pagination
$page = Product::search('headphones')->paginate(15);
```

## Vector search

For semantic / RAG use cases, store embeddings in a `vector` field and create an Atlas **Vector Search** index. Run the query through the aggregation pipeline rather than Scout:

```php
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