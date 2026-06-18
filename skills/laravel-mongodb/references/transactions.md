# Transactions

When to use this reference: wrapping multi-document writes in an atomic transaction. Single-document operations in MongoDB are already atomic — you only need transactions when more than one document (often across collections) must change together.

## Requirements

- A MongoDB **replica set** or **sharded cluster**. Standalone `mongod` does not support transactions.
- All collections involved must exist **before** the transaction starts — create collections and indexes in migrations, not inside transaction callbacks.

## Usage

```php
<?php

declare(strict_types=1);

use Illuminate\Support\Facades\DB;
use App\Models\Order;
use App\Models\Payment;

DB::connection('mongodb')->transaction(function (): void {
    $order = Order::create([
        'customer_id' => $customerId,
        'total'       => 9900,
    ]);

    Payment::create([
        'order_id' => (string) $order->_id,
        'amount'   => 9900,
        'status'   => 'captured',
    ]);
});
```

## Manual control

```php
$connection = DB::connection('mongodb');
$connection->beginTransaction();

try {
    // writes...
    $connection->commit();
} catch (\Throwable $e) {
    $connection->rollBack();
    throw $e;
}
```

## When NOT to use transactions

```php
// Single-document update is atomic — no transaction needed
Post::whereKey($id)->increment('views');

// Equivalent raw update — also atomic at the single-document level
Post::where('_id', $id)->update(['$inc' => ['views' => 1]]);
```

Prefer schema design that keeps related data in a single document (embedding) to avoid transactions entirely. Transactions increase latency and lock contention.

## Known limitations

- **Nested transactions** are not supported.
- **Laravel testing traits** `DatabaseTransactions` and `RefreshDatabase` are **not supported** — they rely on SQL transaction behaviour. Use `RefreshDatabase` with the `$connectionsToTransact` property set, or seed/truncate collections manually in tests.
- **Parallel operations** within a single session/transaction are not supported.
- Transactions require a replica set or sharded cluster. A standalone `mongod` will throw at runtime.

## Cross-references

> For embedding vs referencing decisions that often eliminate the need for transactions, see the **mongodb-schema-design** skill.