# Client lifecycle on Vercel (Node.js)

Describes the client lifecycle for the native Node.js driver on Vercel Functions. Adapt names and structure to the project, and keep an existing helper that already has these properties. The `attachDatabasePool` adapter is covered separately in [vercel-fluid-compute.md](vercel-fluid-compute.md).

## Required properties

- **One lazy, server-only module per connection configuration**, imported by every handler. Separate credentials or clusters get separate clients. Never merge them to cut connection counts.
- **Per runtime instance, not global.** Each Vercel instance and region has its own client and pools. Caching the client does not cache query results.
- **No work at import time.** Read the URI and construct the client on first use, so `next build` does not need Atlas unless the app prerenders data.
- **Cache the in-flight `connect()` promise, and publish it before anything awaits it**, so concurrent first requests share one client.
- **Recover from a failed connect.** On rejection, clear the cache only if the rejected promise is still the current one, close that client, and let the next call retry. A cached rejected promise that is never cleared fails every later request. Do not add unbounded retries.
- **Never create and close a client per request.** Finite scripts and tests close the clients they own.
- **Node.js runtime only.** The native driver does not run on Edge routes.
- **With an ODM**, keep its supported lifecycle and cache its connect promise the same way. Do not add a parallel native-driver singleton.
- **Keep driver defaults** for pool size and timeouts until measurements justify a change.

Agents often get the recovery step wrong. This is the shape of it:

```ts
const promise = client.connect();
cache = promise;
promise.catch(() => {
  if (cache === promise) cache = undefined; // never clear a newer attempt
  void client.close().catch(() => {});
});
```

## Hot reload

Next.js development re-evaluates modules, which recreates a module-local cache. The convention is to keep the cache on `globalThis`. Other frameworks and bundlers differ, so check the project's framework, version, and existing pattern first. Then confirm in a dev session that editing a file does not create a new client.

## Tests that prove the lifecycle

- Two handlers importing the helper receive the same client. Count `new MongoClient` and `connect` calls, not sockets.
- Twenty concurrent first calls trigger one `connect()`.
- A first `connect()` rejection is followed by a successful later call.
- A stale rejection does not clear a newer cached promise. A test reaches this state only by resetting the cache by hand between attempts, so an older rejected promise settles after a newer one is cached.
- Completing a request does not close the client.
- Helpers for different credentials or clusters return different clients.
- Editing a file in the dev server does not construct a new client.
