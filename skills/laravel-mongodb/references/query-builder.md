# Query Builder

When to use this reference: writing any Eloquent or `DB::` query against a MongoDB connection, especially when an LLM is reaching for `withCount`, `toSql`, `distinct`, `groupBy`, `JOIN`, or `inRandomOrder`. Covers the unsupported helpers and their MongoDB replacements.

## Unsupported helpers and replacements

| Standard Eloquent | Status | MongoDB replacement |
|---|---|---|
| `toSql()` / `toRawSql()` | unsupported | `->dump()` / `->dd()` — prints the MongoDB filter array |
| `withCount()` / `withAvg()` / `withSum()` | unsupported | aggregation `$lookup` + `$size` / `$avg` / `$sum`, or `loadCount()` after fetch |
| `groupByRaw()` / `orderByRaw()` / `havingRaw()` | unsupported | aggregation `$group` / `$sort` |
| `whereFulltext()` | unsupported | Atlas Search `$search` stage |
| `union()` | unsupported | aggregation `$unionWith` |
| `whereColumn()` | unsupported | aggregation `$expr` with `$eq` |
| `inRandomOrder()` | unsupported | aggregation `$sample` |
| SQL `JOIN` | unsupported | aggregation `$lookup` |

## `distinct()` returns a Collection, not an array

```php
// WRONG — caller expects scalar array, gets Collection of stdClass / arrays
$genres = Movie::distinct('genre')->get();

// CORRECT — Collection of scalars
$genres = Movie::distinct()->pluck('genre');

// CORRECT — explicit aggregation
$genres = Movie::raw(fn ($c) => $c->aggregate([
    ['$group' => ['_id' => '$genre']],
    ['$sort'  => ['_id' => 1]],
]))->pluck('_id');
```

## Replacing `withCount`

```php
// WRONG
$posts = Post::withCount('comments')->get();

// CORRECT — server-side via aggregation
$posts = Post::raw(fn ($c) => $c->aggregate([
    ['$lookup' => [
        'from'         => 'comments',
        'localField'   => '_id',
        'foreignField' => 'post_id',
        'as'           => 'comments',
    ]],
    ['$addFields' => ['comments_count' => ['$size' => '$comments']]],
    ['$project'   => ['comments' => 0]],
]));

// CORRECT — client-side via loadCount (extra round-trip, OK for small sets)
$posts = Post::all();
$posts->loadCount('comments');
```

## Inspecting the generated query

```php
// WRONG — toSql() does not exist
$sql = User::where('active', true)->toSql();

// CORRECT — dump the MongoDB filter / pipeline
User::query()->where('active', true)->dump();
// or with the helper
dd(User::query()->where('active', true)->toMql());
```

## Random sampling

```php
// WRONG
$movies = Movie::inRandomOrder()->take(5)->get();

// CORRECT
$movies = Movie::raw(fn ($c) => $c->aggregate([
    ['$sample' => ['size' => 5]],
]));
```

## `whereColumn` replacement

```php
// WRONG
User::whereColumn('created_at', 'updated_at')->get();

// CORRECT
User::whereRaw(['$expr' => ['$eq' => ['$created_at', '$updated_at']]])->get();
```

## MongoDB-specific operators

```php
Post::where('tags', 'all', ['mongo', 'laravel'])->get();   // $all
Post::where('views', '>=', 100)->get();
Post::whereBetween('year', [2000, 2010])->get();
Post::where('metadata.draft', true)->get();                // dotted path into sub-doc
```

## Raw aggregation entry point

```php
$result = Post::raw(fn ($collection) => $collection->aggregate([
    ['$match' => ['published' => true]],
    ['$group' => ['_id' => '$author_id', 'total' => ['$sum' => 1]]],
    ['$sort'  => ['total' => -1]],
    ['$limit' => 10],
]));
```

## Cross-references

> For query plan analysis, index hints, and slow-query diagnosis, see the **mongodb-query-optimizer** skill.
> For full-text and vector search inside aggregation, see the **mongodb-search-and-ai** skill.