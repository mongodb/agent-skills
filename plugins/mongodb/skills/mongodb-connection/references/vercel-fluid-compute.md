# Fluid compute and `attachDatabasePool`

## How the adapter treats MongoDB

Verified on October 12, 2026 against `@vercel/functions` 3.9.11 (`db-connections/index.js`), `mongodb` 6.18.0, and `mongoose` 8.24.5 by reading the source and running a local check:

- **Accepted object:** a `MongoClient`. The adapter recognizes MongoDB by `client.on` plus `"maxIdleTimeMS" in client.options`.
- **Rejected objects:** `Db`, the `connect()` promise, and `mongoose.connection` throw (`Unsupported database pool type` or a `TypeError`). For Mongoose, pass `mongoose.connection.getClient()`, which is the underlying `MongoClient` and is accepted.
- **Mechanism:** the adapter listens to the driver's `connectionCheckedOut` event. After each checkout it calls `waitUntil` with a timer of `maxIdleTimeMS + 100` ms, capped by the invocation deadline. This keeps the instance alive long enough for the driver to prune idle connections before suspension.
- **`maxIdleTimeMS` is what makes it work.** The driver default is `0`, meaning connections are never pruned. With the default, the adapter waits about 100 ms and releases nothing, so the call is effectively a no-op. Set a non-zero value when using the adapter.
- **Scope:** the adapter is inert unless both `VERCEL_URL` and `VERCEL_REGION` are set, so it does nothing in local development or during builds.
- **Docs status:** Vercel's Functions API reference lists MongoDB as supported but shows only a `pg` example. The facts above come from the package source, not the docs.

## Wiring it

Call `attachDatabasePool` once per client, right after constructing it and before connecting, and set a non-zero `maxIdleTimeMS` in the client options (for example 5000). In an application, do this inside the lazy cached helper described in [vercel-client-lifecycle.md](vercel-client-lifecycle.md), not at bare module scope. With Mongoose, call it with `mongoose.connection.getClient()` after `mongoose.connect()` has been called, and pass `maxIdleTimeMS` to `connect()`.

## Choosing `maxIdleTimeMS`

- The value is both the driver's idle-prune threshold and the adapter's post-checkout wait window.
- A few seconds (for example 5000) releases idle sockets soon after a burst ends. Very short values cause reconnect churn on steady traffic; long values keep the instance and its connections alive longer after the last request.
- State the chosen value and the reason in the change. Adjust it from observed connection counts and creation rate, not by guesswork.

## Other versions

The adapter detects pool types structurally, so behavior can change between releases. For other versions of `@vercel/functions`, check the installed `db-connections/index.js` (the MongoDB branch and `getIdleTimeout`) and record what you found. Do not block on this when the installed versions match or are close to the ones above. Report the check you did and continue.

## What a deployed check should show

A local test cannot exercise suspension. On an approved non-production deployment, send a burst of requests, let traffic go idle for longer than `maxIdleTimeMS`, and confirm in Atlas metrics that connections from the app drop and recover cleanly on the next request. Compare connection count and creation rate with and without the adapter.

## Sources

- [Vercel Functions API: `attachDatabasePool`](https://vercel.com/docs/functions/functions-api-reference/vercel-functions-package.md)
- [Fluid compute pooling guide](https://vercel.com/kb/guide/efficiently-manage-database-connection-pools-with-fluid-compute.md)
- `@vercel/functions` package source: `db-connections/index.js` in the installed version
- [Node.js driver connection pools](https://www.mongodb.com/docs/drivers/node/current/connect/connection-options/connection-pools/). Use the docs for the installed driver version.
- [Atlas: Integrate with Vercel](https://www.mongodb.com/docs/atlas/reference/partner-integrations/vercel.md) is the source for native integration behavior (`MONGODB_URI`, network defaults, generated user, billing). It does not cover client code or the adapter.
