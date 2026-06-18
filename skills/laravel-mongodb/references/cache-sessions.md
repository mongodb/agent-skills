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

Create a TTL index so expired entries are purged automatically. The package writes the expiry timestamp into `expires_at`:

```php
Schema::connection('mongodb')->create('cache', function (Blueprint $c): void {
    $c->expire('expires_at', 0);
});

Schema::connection('mongodb')->create('cache_locks', function (Blueprint $c): void {
    $c->expire('expires_at', 0);
});
```

> The TTL field is `expires_at`, **not** `expiration`. Cache keys are stored in `_id` — no separate unique index needed.

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
    $c->index('user_id');
    $c->index('last_activity');
    $c->expire('expires_at', 0);  // session handler writes expires_at
});
```

> Session IDs are stored in `_id` — do not add `$c->unique('id')`.

## Usage

```php
use Illuminate\Support\Facades\Cache;

Cache::put('user:1', $user, now()->addMinutes(10));
Cache::remember('movies:top10', 300, fn () => Movie::orderBy('rating', 'desc')->take(10)->get());
```

No code changes are required at the call site — only configuration and indexes.
