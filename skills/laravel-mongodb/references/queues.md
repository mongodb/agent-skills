# Queue Driver

When to use this reference: configuring the MongoDB queue driver, dispatching jobs to a MongoDB queue, or running `queue:work` against a MongoDB-backed queue.

## `config/queue.php`

```php
<?php

declare(strict_types=1);

return [
    'default' => env('QUEUE_CONNECTION', 'mongodb'),

    'connections' => [
        'mongodb' => [
            'driver'       => 'mongodb',
            'connection'   => 'mongodb',  // name from config/database.php
            'collection'   => 'jobs',
            'queue'        => 'default',
            'retry_after'  => 90,
            'after_commit' => false,
        ],
    ],

    'failed' => [
        'driver'     => 'mongodb',
        'database'   => 'mongodb',
        'collection' => 'failed_jobs',
    ],
];
```

## Required indexes

Create these once via a migration to keep `queue:work` polling fast:

```php
Schema::connection('mongodb')->create('jobs', function (Blueprint $c): void {
    $c->index('queue');
    $c->index('reserved_at');
    $c->index('available_at');
});

Schema::connection('mongodb')->create('failed_jobs', function (Blueprint $c): void {
    $c->index('failed_at');
});
```

## Dispatch and worker

```php
<?php

declare(strict_types=1);

use App\Jobs\IndexPostJob;

IndexPostJob::dispatch((string) $post->_id)
    ->onConnection('mongodb')
    ->onQueue('indexing');
```

```
php artisan queue:work mongodb --queue=indexing
php artisan queue:failed
php artisan queue:retry all
```

## Job class

```php
<?php

declare(strict_types=1);

namespace App\Jobs;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

final class IndexPostJob implements ShouldQueue
{
    use Dispatchable;
    use InteractsWithQueue;
    use Queueable;
    use SerializesModels;

    public int $tries   = 3;
    public int $timeout = 60;

    public function __construct(public readonly string $postId) {}

    public function handle(): void
    {
        // ...
    }
}
```

## Notes

- Pass `string` IDs into job constructors, never `ObjectId` instances — they must serialize cleanly.
- `after_commit => false` because MongoDB transactions are opt-in; if you wrap dispatching inside `DB::transaction()` on a replica set, set it to `true`.