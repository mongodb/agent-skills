# SCRAM (username and password)

## Server side (self-managed)

- `db.createUser()` creates both `SCRAM-SHA-1` and `SCRAM-SHA-256` credentials by default.
- If every client supports SHA-256, create only the SHA-256 credential. Keep SCRAM-SHA-1 only
  for legacy clients that can't negotiate SHA-256.

  ```javascript
  use admin
  db.createUser({
    user: "<APP_USERNAME>",
    pwd: passwordPrompt(),
    roles: [ { role: "<CUSTOM_ROLE>", db: "<ROLE_DB>" } ],
    mechanisms: [ "SCRAM-SHA-256" ]
  })
  ```

- SCRAM-SHA-256 requires server-side password digesting, which is the default
  (`passwordDigestor: "server"`). Don't set `passwordDigestor: "client"`: it's incompatible with
  SHA-256.
- The database a user is created in is its authentication database. The client's `authSource`
  must name that database. On Atlas, every SCRAM user authenticates against `admin`.

For Atlas users, see `atlas.md`.

## Client side

- Follow least privilege. The application user gets one specific role for its own databases and
  collections (see `rbac-custom-roles.md`), never `readWriteAnyDatabase` or an admin role.

- Drivers negotiate the mechanism, preferring SCRAM-SHA-256. Set
  `authMechanism=SCRAM-SHA-256` only when policy requires pinning it, and never on Atlas Free
  or Flex clusters, which support SCRAM-SHA-1 only.
- Always set `authSource` explicitly on self-managed deployments. On Atlas, the SRV record sets
  `authSource=admin` and `mongodb+srv://` turns on TLS automatically.
- Credentials come from environment variables or a secret manager. Never hardcode them in
  source, `.env` files committed to git, or container images.
- If credentials go into a URI, percent-encode the username and password. The alternative is
  passing them as driver client options, which avoids encoding problems.

Self-managed URI shape, with credentials supplied separately:

```text
mongodb://<HOST_1>:27017,<HOST_2>:27017,<HOST_3>:27017/?replicaSet=<REPLICA_SET_NAME>&authSource=admin&tls=true
```

mongosh without leaving the password in shell history:

```bash
mongosh "mongodb://<HOST>:27017/?authSource=admin&tls=true" -u <APP_USERNAME> -p
```

### Driver code: connect once, and keep it runnable

A driver snippet the user pastes into a file has to run as written. The common way to get this
wrong is `await` at the top level of a CommonJS file — valid in an ES module, a `SyntaxError` in
a `require()` script — so pick one module system and keep the snippet consistent with it. When
in doubt, give the connection options rather than a full program; an options object the user
drops into their own code is more useful than a file that won't start.

CommonJS, with the `await` inside an async function:

```javascript
const { MongoClient } = require("mongodb");

const client = new MongoClient(process.env.MONGODB_URI, {
  auth: {
    username: process.env.MONGODB_USERNAME,
    password: process.env.MONGODB_PASSWORD,
  },
  authSource: "<AUTH_DB>",
  tls: true,
});

async function main() {
  await client.connect();
  // reuse `client` for the process lifetime; don't connect per request
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

In an ES module (`.mjs`, or `"type": "module"`), the same `await client.connect()` may sit at
the top level. Passing credentials through `auth` rather than in the URI avoids percent-encoding
problems when the password contains `@`, `:`, `/` or `%`.

## Rotating passwords

- Change a password with `db.changeUserPassword("<APP_USERNAME>", passwordPrompt())`.
- For zero-downtime rotation, run two users with the same role:
  1. Create the second user.
  2. Deploy the application with the new credentials.
  3. Confirm no connections still use the old user.
  4. Drop the old user. `dropUser` is irreversible, so make sure step 3 is done first.

## Pitfalls

- User created in `admin` but the client leaves out `authSource`, so the driver defaults to the
  database in the URI path (or `admin` if there is none). The result is `Authentication failed`.
- An `@`, `:`, `/`, or `%` in the password breaks URI parsing when it isn't encoded.
- A connection string with credentials logged by application startup code or error handlers.
