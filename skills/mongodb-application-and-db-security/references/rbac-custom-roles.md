# Least-privilege roles

The mongosh commands here are for self-managed deployments. On Atlas, `db.createRole()` isn't
supported. Build the same design and create it with the Atlas commands in `atlas.md`.

## Method

1. Write out the permission matrix: identity → database → collection → operations → what is
   explicitly *not* allowed.
2. For "read everything in a database", inherit the built-in `read` role scoped to that
   database.
3. For writes, grant explicit CRUD actions (`insert`, `update`, `remove`, plus `find`) on the
   exact collections, or on `{ db: "<DB>", collection: "" }` if every collection needs them.
   Don't use `readWrite` for data writes. It also grants `dropCollection`, `dropIndex`,
   `renameCollectionSameDB`, `createIndex`, and other schema changes. Use `readWrite` only when
   the user confirms the application must manage schema.
4. Collection creation: grant only what the application's actual creation path needs. Ask how
   collections come into existence if it isn't clear.
   - **Implicit creation** (the first insert creates the collection): `insert` on that
     collection is enough.
   - **Explicit, ordinary creation** (`db.createCollection("<name>")` or `create` for a
     non-capped collection): MongoDB accepts either `createCollection` on the database or
     `insert` on the collection being created. If you already grant `insert` on that
     collection, don't add `createCollection`.
   - **Creation with special options:**
     - Capped collections need `createCollection` on the database *and* `convertToCapped` on the
       collection.
     - Views need `createCollection` on the database, plus `find` on the source collection and
       on every collection the view's pipeline references.
     - Collections created with `encryptedFields` need permission to both create and modify the
       collection. That's Queryable Encryption, outside this skill.
     - For other options (validators, time series, clustered), confirm the exact command and
       check the `create` command's Access Control table for the target version.
   - Never add `createCollection` "just in case". It lets the identity create any collection in
     the database.
5. Grant the application user only the custom role.

Explicit CRUD role for an application that writes to two collections and manages no schema:

```javascript
use <APP_DB>
db.createRole({
  role: "<APP_ROLE>",
  privileges: [
    {
      resource: { db: "<APP_DB>", collection: "<COLLECTION_1>" },
      actions: [ "find", "insert", "update", "remove" ]
    },
    {
      resource: { db: "<APP_DB>", collection: "<COLLECTION_2>" },
      actions: [ "find", "insert" ]
    }
  ],
  roles: []
})
```

## Where a role lives

- A role created in any database other than `admin` can only hold privileges on its own
  database, and can only inherit roles from that database.
- A role created in `admin` can hold privileges on any database or the cluster, and can
  inherit roles from any database.

Create the role in the application's own database when its privileges stay inside that
database. That limits the role's reach even if someone edits it later. Use `admin` only when the
role spans databases or needs cluster actions.

The database a user is created in is its authentication database (`authSource`). It doesn't
limit which roles the user can hold.

## Resource documents

- `{ db: "<DB>", collection: "<COLL>" }`: one collection.
- `{ db: "<DB>", collection: "" }`: every collection in that database **except system
  collections**. Name a system collection explicitly if it's needed.
- `{ db: "", collection: "" }`: every non-system collection in every database. Only roles
  created in `admin` can use it. Don't use it for applications.
- `{ cluster: true }`: cluster-wide actions only (for example `serverStatus`).

## Operations and privilege actions

| Operation | Action |
|---|---|
| `find`, `aggregate` without `$out`/`$merge`, `countDocuments`, `distinct` | `find` |
| `insertOne` / `insertMany` (the driver sends the `insert` command) | `insert` |
| `updateOne` / `updateMany` / `replaceOne` | `update` |
| `deleteOne` / `deleteMany` | `remove` |
| List collections (Compass, BI tools, many ORMs) | `listCollections` |
| List indexes | `listIndexes` |
| Create indexes | `createIndex` |
| Open a change stream | `changeStream` (plus `find`) |

A user can always kill their own cursors without the `killCursors` action.

The built-in `read` role grants these actions on all non-system collections of its database:
`changeStream`, `collStats`, `dbHash`, `dbStats`, `find`, `killCursors`, `listCollections`,
`listIndexes`, `listSearchIndexes`. `readWrite` adds `insert`, `update`, and `remove`. It also
adds `createCollection`, `createIndex`, `dropCollection`, `dropIndex`,
`renameCollectionSameDB`, `convertToCapped`, and the search index actions. Those extra
schema-changing actions are why `readWrite` is usually too broad for an application that only
writes data.

## Worked example

> Read every collection in `reporting`, but insert only into `reporting.audit_logs`.

Permission matrix:

| Identity | Database | Collection | Allowed | Not allowed |
|---|---|---|---|---|
| reporting app | `reporting` | all (non-system) | read, list collections and indexes | any write |
| reporting app | `reporting` | `audit_logs` | read, insert | update, remove, drop |

Role, created in `reporting` because every privilege stays inside that database:

```javascript
use reporting
db.createRole({
  role: "reportingReadAuditInsert",
  privileges: [
    {
      resource: { db: "reporting", collection: "audit_logs" },
      actions: [ "insert" ]
    }
  ],
  roles: [ { role: "read", db: "reporting" } ]
})
```

- The inherited `read` role covers "read every collection". It includes `listCollections`
  and `listIndexes`, so tools that inspect collection metadata or indexes work. If you grant
  only `find` on `{ db: "reporting", collection: "" }`, queries still work, and so does
  `listCollections` with both `authorizedCollections: true` and `nameOnly: true`. A plain
  `listCollections` call and `listIndexes` both fail.
- `insert` is scoped to `reporting.audit_logs` only. There's no `update` or `remove`, so this
  identity can't change or delete existing audit entries.

Create the application user in `admin`, so the client uses `authSource=admin`:

```javascript
use admin
db.createUser({
  user: "<APP_USERNAME>",
  pwd: passwordPrompt(),
  roles: [ { role: "reportingReadAuditInsert", db: "reporting" } ]
})
```

If the user wants literally `find` and nothing else, use this privilege in place of the
inherited role, and say what they give up:

```javascript
{ resource: { db: "reporting", collection: "" }, actions: [ "find", "listCollections", "listIndexes" ] }
```

## Verify (production-safe)

The user runs these as `<APP_USERNAME>`. If a non-production copy exists, run them there first.

**1. Check the privileges without touching data:**

```javascript
db.runCommand({ connectionStatus: 1, showPrivileges: true })
// authInfo.authenticatedUserRoles: only reportingReadAuditInsert@reporting
// authInfo.authenticatedUserPrivileges: insert appears only on reporting.audit_logs
```

**2. Read test (no side effects):**

```javascript
const reporting = db.getSiblingDB("reporting")
reporting.getCollection("<ANY_EXISTING_COLLECTION>").find().limit(1).toArray()  // allowed
```

**3. Negative write tests, confined to a disposable namespace.**

Every negative write test targets `reporting.authz_verify_disposable`. No application uses that
collection and it holds no business data. Never point a negative write test at `audit_logs`
or any other real collection: if the role is misconfigured, the test itself changes real data.

First, an admin seeds the disposable collection so the update and delete tests have something to
target:

```javascript
// Run as an admin, not as <APP_USERNAME>.
db.getSiblingDB("reporting").authz_verify_disposable.insertOne({ _id: "authz-verify-seed" })
```

Then, as `<APP_USERNAME>`:

```javascript
const scratch = reporting.authz_verify_disposable
scratch.insertOne({ _id: "authz-verify-insert" })                          // expected: Unauthorized (13)
scratch.updateOne({ _id: "authz-verify-seed" }, { $set: { touched: true } }) // expected: Unauthorized (13)
scratch.deleteOne({ _id: "authz-verify-seed" })                            // expected: Unauthorized (13)
```

- **Expected effect:** none. Each call must fail with `Unauthorized`.
- **If any call succeeds:** the role is broader than designed. Stop, and fix the role before
  using it in production.
- **Cleanup:** an admin drops `reporting.authz_verify_disposable` afterwards, whatever the
  results.

`remove` and `update` on `audit_logs` itself are denied by design. Confirm that from the
privilege list in step 1, not with a write test against the real collection.

**4. Positive insert test:** this writes one permanent record to `audit_logs`, and this
identity can't remove it. Only do it where that's acceptable. Otherwise stop at step 1 and
confirm the privilege there.

```javascript
reporting.audit_logs.insertOne({
  type: "authz_verification",
  note: "test record from access-control rollout",
  at: new Date()
})
```

Expected effect: one labeled document. Cleanup, if the audit policy allows it, is done by an
admin with delete rights: `deleteOne({ type: "authz_verification" })` on `reporting.audit_logs`.

## Optional hardening: authenticationRestrictions (self-managed)

For sensitive identities, you can restrict where an identity may authenticate from, in
addition to what it can do. This suits break-glass admins, automation accounts, and human DBA
roles. Restrictions can go on a role or on a user:

```javascript
use admin
db.createRole({
  role: "<BREAK_GLASS_ROLE>",
  privileges: [],
  roles: [ { role: "userAdminAnyDatabase", db: "admin" } ],
  authenticationRestrictions: [
    {
      clientSource: [ "<BASTION_IP>", "<ADMIN_SUBNET_CIDR>" ],
      serverAddress: [ "<MONGOD_LISTEN_IP>" ]
    }
  ]
})
```

- **`clientSource`:** the client's IP must be in the list or in one of its CIDR ranges.
  Otherwise the server refuses to authenticate the user.
- **`serverAddress`:** the connection must arrive on one of these server IPs.
- **Combining roles:** a user whose roles carry incompatible restrictions can't authenticate
  at all.
- **Permission to set them:** setting restrictions requires the `setAuthenticationRestriction`
  action.
- **Atlas:** there's no documented way to set restrictions on Atlas custom roles. Use the IP
  access list and private endpoints instead (see `atlas.md`).

Before applying restrictions, warn the user about lockout:

- Check every CIDR against the real source addresses, including NAT, bastion hosts, and
  load balancers, and the addresses clients use in a failover.
- Make sure at least one working admin path is outside the restriction, or test it first on a
  non-production deployment.
- Don't restrict the only user administrator until another admin has confirmed that they can
  still log in.

## Changing a role later

- Add or remove privileges with `db.grantPrivilegesToRole()` and
  `db.revokePrivilegesFromRole()`. Change inherited roles with `db.grantRolesToRole()` and
  `db.revokeRolesFromRole()`.
- Inspect a role with `db.getRole("<ROLE>", { showPrivileges: true })`.
- A role change affects every user that holds the role. Say that before proposing one.

## Pitfalls

- Using `readWrite` or `dbOwner` because the app needs to insert into one collection.
- A privilege with `collection: ""` that includes write actions. That grants writes on every
  collection in the database.
- Creating the role in `admin` when every privilege is in one database.
- Expecting `{ db: "<DB>", collection: "" }` to cover `system.*` collections. It doesn't.
