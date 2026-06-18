# Cache and Sessions

When to use this reference: configuring Laravel's cache or session store to use MongoDB. Both ship with the `mongodb/laravel-mongodb` package and need only configuration plus a TTL index.

## Cache

```php
// config/cache.php
return [
    'default' => env('CACHE_STORE', 'mongodb'),

    'stores' => [
        'mongodb' => [
            'driver'          => 'mongodb',
            'connection'      => 'mongodb',
            'collection'      => 'cache',
            'lock_connection' => 'mongodb',
            'lock_collection' => 'cache_locks',
        ],
    ],
];
```

Create a TTL index so expired entries are purged automatically:

```php
Schema::connection('mongodb')->create('cache', function (Blueprint $c): void {
    $c->unique('key');
    $c->expire('expiration', 0);
});

Schema::connection('mongodb')->create('cache_locks', function (Blueprint $c): void {
    $c->unique('key');
    $c->expire('expiration', 0);
});
```

## Sessions

```php
// config/session.php
return [
    'driver'     => env('SESSION_DRIVER', 'mongodb'),
    'connection' => 'mongodb',
    'table'      => 'sessions',   // collection name; keep the key 'table' for Laravel compatibility
    'lifetime'   => 120,
];
```

```php
Schema::connection('mongodb')->create('sessions', function (Blueprint $c): void {
    $c->unique('id');
    $c->index('user_id');
    $c->index('last_activity');
});
```

## Usage

```php
use Illuminate\Support\Facades\Cache;

Cache::put('user:1', $user, now()->addMinutes(10));
Cache::remember('movies:top10', 300, fn () => Movie::orderBy('rating', 'desc')->take(10)->get());
```

No code changes are required at the call site — only configuration and indexes.