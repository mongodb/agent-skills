# Enable access control and create the first admin (self-managed)

This file applies to self-managed deployments only. Access control can't be disabled on Atlas,
and there's no localhost bootstrap there: the first database user is created in the Atlas UI,
CLI, or Admin API. If the deployment is Atlas, use `atlas.md` instead.

## How the localhost exception works

- When access control is on and the instance has **no users and no roles**, a client connected
  through the localhost interface can create exactly one first user or one first role.
- Running `db.createUser()` or `db.createRole()` **ends the exception automatically**. There's no
  separate step to close it.
- Create a role first only when you're setting up LDAP authorization (see `ldap.md`). In every
  other case, the first object must be a user that can create other users. Otherwise the
  instance is left with no way to add an admin.
- The exception also lets you run `replSetInitiate` (`rs.initiate()`) on a new replica set. Wait
  until the set elects a primary before creating the first user.
- **Sharded clusters:** the exception applies to each shard on its own as well as to the
  cluster through `mongos`. After creating the cluster admin through `mongos`, protect every
  shard in one of two ways:
  - create a user administrator on each shard's primary, or
  - start each shard with `enableLocalhostAuthBypass` set to `false`. It's a startup-only
    parameter:

    ```yaml
    setParameter:
      enableLocalhostAuthBypass: false
    ```

## Standalone: bootstrap without an unauthenticated window

Turn on authorization before the first user exists, keep the instance bound to localhost, and
use the localhost exception to create the admin. Clients never see an open instance.

1. Configure `mongod.conf`:

   ```yaml
   net:
     port: 27017
     bindIp: 127.0.0.1
   security:
     authorization: enabled
   ```

   The command-line equivalent of `security.authorization: enabled` is `--auth`.

2. On the same host, connect with `mongosh --host 127.0.0.1 --port 27017`.

3. Create the bootstrap administrator:

   ```javascript
   use admin
   db.createUser({
     user: "<ADMIN_USERNAME>",
     pwd: passwordPrompt(),
     roles: [ { role: "userAdminAnyDatabase", db: "admin" } ]
   })
   ```

   The official tutorial also grants `readWriteAnyDatabase`. Leave it out: the bootstrap
   admin's only job is to manage users. `userAdminAnyDatabase` is effectively a superuser role,
   because its holder can grant itself any privilege. Treat this account as break-glass: keep
   its credentials in a secret manager and don't use it from applications.

4. Reconnect as that user. `-p` with no value makes mongosh prompt for the password:

   ```bash
   mongosh --host 127.0.0.1 --port 27017 -u <ADMIN_USERNAME> -p --authenticationDatabase admin
   ```

5. Create the users people will actually work with. Examples: an operations user with
   `clusterAdmin` or `clusterMonitor`, and each application's user with a custom role from
   `rbac-custom-roles.md`.

6. Only after that, expose the instance to the network. Add the specific interface addresses to
   `net.bindIp` and turn on TLS. Don't use `net.bindIpAll`.

Checks for this procedure:

- **Pre-change check:** `net.bindIp` is `127.0.0.1` only, and you're on the host itself.
- **Post-change checks:**
  - After step 4, `connectionStatus` shows the admin.
  - After step 6, an unauthenticated remote connection can't list databases.
- **Rollback criterion:** if the admin login in step 4 fails, don't continue to step 6. Keep the
  instance bound to localhost. Recovery:
  1. Stop `mongod`.
  2. Restart it bound to `127.0.0.1` with `security.authorization` removed.
  3. Fix or recreate the admin user.
  4. Restore `security.authorization: enabled` and restart.
  5. Repeat step 4.

## Replica sets: internal authentication is required

Members must authenticate to each other before client access control works. Use one of:

- `security.keyFile`: a shared secret. Setting it also turns on client access control.
- `security.clusterAuthMode: x509`: member certificates. MongoDB recommends this for
  production. Set it up with the documented member x.509 procedure.

Keyfile requirements:

- 6–1024 characters, base64 set only
- identical on every member
- on Unix, no group or world permissions

Generate one:

```bash
openssl rand -base64 756 > <KEYFILE_PATH>
chmod 400 <KEYFILE_PATH>
```

Make sure the user that runs `mongod` owns the file.

**New replica set:**

1. Start every member with `security.keyFile` and `replication.replSetName`.
2. On one member, connect over localhost and run `rs.initiate()`.
3. Wait for a primary.
4. Connect to the primary over localhost and create the bootstrap admin as in step 3 above.

**Existing replica set that can't take downtime:** use `security.transitionToAuth`.

**Go/no-go checklist.** Don't start unless every item is confirmed:

- [ ] **Restricted network path:** while `transitionToAuth` is on, unauthenticated clients get
  full access. Only application hosts, members, and admin hosts can reach the members:
  firewall or security group rules are in place, and there's no public `bindIp`.
- [ ] **Tested admin login:** the user admin and `clusterAdmin` users exist, and a test login
  with each works. They work even before enforcement, because credentials are checked when
  they're sent.
- [ ] **Updated clients:** every application and tool sends credentials, and a test connection
  from each one authenticates.
- [ ] **Healthy majority:** `rs.status()` shows every member healthy and secondaries caught up.
  You can lose one member to a restart and keep a majority.
- [ ] **Documented rollback point:** keep a copy of each member's current `mongod.conf`. The
  rollback is to restart the affected member with its previous config, one member at a time.
  Roll back if a restarted member doesn't return to `SECONDARY` within your agreed window, or
  if an application starts failing authentication.

1. While access control is still off, create the user admin, a `clusterAdmin` user, and the
   application users.
2. Update every client to send credentials.
3. Generate the keyfile and copy it to every member.
4. Restart each secondary and arbiter, one at a time, with `security.keyFile` and
   `security.transitionToAuth: true`.
5. Run `rs.stepDown()` on the primary, then restart it the same way.
6. Restart each secondary and arbiter again without `transitionToAuth`, keeping `keyFile`.
7. Step down the primary and restart it without `transitionToAuth`.

While `transitionToAuth` is on, the members accept unauthenticated connections with full read,
write, and admin access. Keep that window short.

Checks during the procedure:

- **Before each restart:** confirm the member you're about to restart isn't needed for the
  majority.
- **After each restart:** confirm it returns to `SECONDARY` (or `PRIMARY`) in `rs.status()`, and
  that an authenticated test connection still works.
- **After steps 6–7:** an unauthenticated `listDatabases` must fail with a "requires
  authentication" error.

## Sharded clusters

- Configure the same internal authentication (keyfile or x.509) on every shard member,
  config server member, and `mongos`.
- Create the cluster admin through `mongos`. Then protect each shard as described in the
  localhost exception section above.
- To turn on access control in an existing sharded cluster without downtime, follow MongoDB's
  sharded-cluster keyfile procedure. The order differs from the replica set procedure, so don't
  improvise it from the steps above.

## Verify

```javascript
// As the new admin:
db.runCommand({ connectionStatus: 1 })   // authInfo.authenticatedUsers shows the admin
```

```bash
# Without credentials, this must fail with a "requires authentication" error:
mongosh --host 127.0.0.1 --port 27017 --eval 'db.adminCommand({ listDatabases: 1 })'
```

## Pitfalls

- Creating a role first on a deployment that isn't using LDAP authorization. That ends the
  localhost exception with no admin user in place.
- Enabling `security.authorization` on replica set members without a keyfile or x.509 member
  authentication.
- Leaving shards unprotected after creating the admin only through `mongos`.
- Passing the password after `-p` on the command line, where it ends up in shell history and
  process listings.
