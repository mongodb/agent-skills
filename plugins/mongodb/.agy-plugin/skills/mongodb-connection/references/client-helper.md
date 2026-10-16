# Canonical server-only client helper

Use this as the default shape for the native Node.js driver on Vercel. Adapt names, the import alias, and the database name to the project. If the project already has a helper with these properties, keep it.

```ts
// lib/mongodb.ts — server-only. Never import from client components.
import { MongoClient, type MongoClientOptions } from "mongodb";

const options: MongoClientOptions = { appName: "my-app" }; // driver defaults otherwise

// globalThis survives Next.js dev hot reloads. In production it is still
// per runtime instance: each Vercel instance/region has its own client and pools.
const globalForMongo = globalThis as typeof globalThis & {
  _mongoClientPromise?: Promise<MongoClient>;
};

export function getMongoClient(): Promise<MongoClient> {
  const cached = globalForMongo._mongoClientPromise;
  if (cached) return cached;

  // Read env lazily so importing this module never needs Atlas or the URI at build time.
  const uri = process.env.MONGODB_URI;
  if (!uri) throw new Error("MONGODB_URI is not set");

  const client = new MongoClient(uri, options);

  // Publish the in-flight promise before anything awaits it, so concurrent
  // first requests share one client.
  const promise = client.connect();
  globalForMongo._mongoClientPromise = promise;

  promise.catch(() => {
    // Recover on the next call, but never clear a newer attempt.
    if (globalForMongo._mongoClientPromise === promise) {
      globalForMongo._mongoClientPromise = undefined;
    }
    void client.close().catch(() => {});
  });
  return promise;
}

export async function getDb(name = "app") {
  return (await getMongoClient()).db(name);
}
```

Route usage (Next.js App Router):

```ts
import { getDb } from "@/lib/mongodb";

export const runtime = "nodejs"; // the native driver does not run on Edge

export async function GET() {
  const db = await getDb();
  const doc = await db.collection("items").findOne({}, { projection: { _id: 1 } });
  return Response.json({ ok: true, found: doc !== null });
}
```

## What this shape guarantees

- One `MongoClient` per runtime instance and connection configuration. Separate credentials or clusters get separate helpers. Never merge them to cut connection counts.
- No network activity or env access at import time, so `next build` works without a database unless the app prerenders data.
- Concurrent first calls share one `connect()`. A rejected attempt is cleared so a later call retries, and a stale failure cannot clear a newer attempt.
- No per-request `close()`. Finite scripts and tests close the clients they own.
- Pool size and timeouts stay at driver defaults until measurements justify a change.

## Hot reload

The `globalThis` cache is the Next.js convention for surviving dev-server module re-evaluation. Other frameworks and bundlers differ. Check the project's framework and version, and its existing pattern, before choosing where to cache. Then confirm in a dev session that editing a file does not create a new client.

## Only with Fluid compute: `attachDatabasePool`

Add this only when the project runs on Vercel Fluid compute and the user is working on connection release or suspension. It is not needed for a basic working deployment. See [fluid-compute.md](fluid-compute.md) for the full mechanism.

```ts
import { attachDatabasePool } from "@vercel/functions";

const options: MongoClientOptions = {
  appName: "my-app",
  maxIdleTimeMS: 5_000, // required: the adapter's wait window; default 0 releases nothing
};

// inside getMongoClient(), right after `new MongoClient(...)`:
attachDatabasePool(client);
```

Pass the `MongoClient` itself. A `Db`, the connect promise, or `mongoose.connection` throws.

## Mongoose

Keep Mongoose's own connection lifecycle, and cache the `mongoose.connect()` promise the same way. With Fluid compute, register the underlying driver client once `connect()` has been called:

```ts
const conn = mongoose.connect(uri, { maxIdleTimeMS: 5_000 });
attachDatabasePool(mongoose.connection.getClient());
```

## Tests that prove the lifecycle

- Two handlers importing the helper receive the same client. Count `new MongoClient` and `connect` calls, not sockets.
- Twenty concurrent first calls trigger one `connect()`.
- A first `connect()` rejection is followed by a successful later call.
- A stale rejection does not clear a newer cached promise. To reach this state in a test, reset the cache by hand between attempts so an older rejected promise settles after a newer one is cached.
- Completing a request does not close the client.
- Helpers for different credentials or clusters return different clients.
- Editing a file in the dev server does not construct a new client.
