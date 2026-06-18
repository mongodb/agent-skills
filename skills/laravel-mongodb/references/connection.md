# Connection

When to use this reference: configuring the MongoDB connection in `config/database.php`, setting up multiple connections, or wiring a Laravel app that uses MongoDB alongside MySQL/PostgreSQL.

## `config/database.php`

```php
<?php

declare(strict_types=1);

return [
    'default' => env('DB_CONNECTION', 'mongodb'),

    'connections' => [
        'mongodb' => [
            'driver'   => 'mongodb',
            'dsn'      => env('MONGODB_URI', 'mongodb://localhost:27017'),
            'database' => env('MONGODB_DATABASE', 'laravel'),
            // Optional driver options (forwarded to MongoDB\Client)
            'options'  => [
                'appName' => env('APP_NAME', 'laravel'),
            ],
        ],

        // You can keep a SQL connection in parallel
        'mysql' => [
            'driver'   => 'mysql',
            // ...
        ],
    ],
];
```

## `.env`

```
DB_CONNECTION=mongodb
MONGODB_URI="mongodb+srv://user:pass@cluster0.mongodb.net/?retryWrites=true&w=majority"
MONGODB_DATABASE=laravel
```

Prefer the full `mongodb+srv://` URI when targeting Atlas. Pool sizing, timeouts and TLS all go into the URI.

## Service-provider registration

The package auto-registers via Laravel's package discovery. If you opted out, add to `bootstrap/providers.php`:

```php
return [
    MongoDB\Laravel\MongoDBServiceProvider::class,
];
```

## Using the connection from code

```php
use Illuminate\Support\Facades\DB;

// Query builder
DB::connection('mongodb')->table('logs')->insert(['msg' => 'hi']);

// Raw MongoDB objects (use these instead of deprecated getMongoDB/getMongoClient)
$db     = DB::connection('mongodb')->getDatabase();  // MongoDB\Database
$client = DB::connection('mongodb')->getClient();    // MongoDB\Client

// Raw collection (bypasses Eloquent/query builder)
$collection = DB::connection('mongodb')->getCollection('logs');
```

> `getMongoDB()` and `getMongoClient()` are deprecated since v5.2. Use `getDatabase()` and `getClient()`.
> `DB::connection('mongodb')->collection()` does not exist. Use `->table()` for the query builder.

## Connection pooling and timeouts

The PHP driver maintains a connection pool per process. Tune via the URI:

```
mongodb+srv://.../db?maxPoolSize=50&minPoolSize=5&serverSelectionTimeoutMS=5000&socketTimeoutMS=30000
```

## Cross-references

> For pool sizing per workload (web, queue worker, octane, serverless), TLS, and timeout tuning, see the **mongodb-connection** skill.
