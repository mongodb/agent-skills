# LDAP authentication and authorization

**Always tell the user first:** LDAP authentication and authorization are deprecated starting
in MongoDB 8.0, and will be removed in a future release. MongoDB recommends:

- **People:** Workforce Identity Federation (OIDC). See `oidc.md`.
- **Applications:** Workload Identity Federation. Use x.509 if workload identity isn't an option.

If the user still needs LDAP (an existing directory, a migration in progress), continue.

Availability:

- **Self-managed:** MongoDB Enterprise only.
- **Atlas:** clusters running 7.0+, not Free or Flex. Configure it through Atlas, not
  `mongod.conf` (see `atlas.md`).

## Pick the mode

| Mode | What LDAP does | What MongoDB stores |
|---|---|---|
| Authentication only | Checks the password | One `$external` user per LDAP user, with the exact authentication username, holding MongoDB roles |
| Authentication and authorization | Checks the password and returns group membership | Roles in `admin` whose names exactly match LDAP group DNs. No `$external` users. |

With LDAP authorization on, any existing `$external` users become inaccessible. Plan the
cutover before turning it on.

## Prerequisite: trust the LDAP server's CA

mongod checks the LDAP server's certificate through the operating system's LDAP library, not
through a mongod setting. Before any MongoDB change, the user must:

1. **Install the LDAP server's CA certificate for the OS library.**
   - Linux: set `TLS_CACERT` (or `TLS_CACERTDIR`) in `ldap.conf`, usually
     `/etc/openldap/ldap.conf`.
   - Windows: import the CA with the platform's certificate management tool.

   If mongod can't read the CA, it can't open TLS connections to the LDAP server.
2. **Check that the certificate matches.** The names in `security.ldap.servers` must match the
   LDAP server certificate's SAN or CN. Use hostnames, not IP addresses, unless the certificate
   lists the IPs.
3. **Test that it fails closed.** Run `mongoldap` against a server name that isn't in the
   certificate, or with the CA removed, and confirm the connection is refused. If it succeeds,
   the OS library isn't verifying certificates. Fix that before rollout, for example by
   removing any `TLS_REQCERT never` or `allow` setting.

## Self-managed configuration (native LDAP, OS libraries)

The settings live under `security.ldap` in `mongod.conf`. `security.ldap.servers` is the only
required one. When you explain a setting, give its full dotted name, for example
`security.ldap.bind.queryUser`, so the user can find it in the configuration reference.

```yaml
security:
  authorization: enabled
  ldap:
    servers: "<LDAP_HOST_1>,<LDAP_HOST_2>"
    transportSecurity: tls
    bind:
      method: simple
      queryUser: "<BIND_USER_DN_OR_UPN>"
      queryPassword:
        __exec: "<COMMAND_THAT_PRINTS_BIND_PASSWORD>"
        type: "string"
        trim: "whitespace"
    userToDNMapping:
      '[ { match: "(.+)", ldapQuery: "<BASE_DN>??sub?(userPrincipalName={0})" } ]'
    authz:
      queryTemplate: "<BASE_DN>??sub?(&(objectClass=group)(member:1.2.840.113556.1.4.1941:={USER}))"
setParameter:
  authenticationMechanisms: "PLAIN,SCRAM-SHA-256"
```

- **`transportSecurity`:** `tls` is the default, shown here for clarity. Never set it to `none`.
  The bind and user passwords would cross the network in plain text.
- **`queryPassword`:** keep it out of the config file. The `__exec` expansion directive shown
  above is one way; `__rest` fetches it from a REST endpoint instead. Either needs `mongod`
  started with `--configExpand "exec"` (or `"rest"`). With `__exec`, the config file must be writable only by the
  user that runs `mongod`. With `__rest`, it must be readable only by that user. Keep
  `trim: "whitespace"`: without it, the trailing newline most commands print becomes part of
  the password and the bind fails.
- **Rotating the bind password:** the `ldapQueryPassword` setParameter accepts an array of
  passwords, so you can roll it over without downtime.
- **`authz`:** include `authz.queryTemplate` only in authentication-and-authorization mode.
  The template above is the Active Directory nested-group pattern from MongoDB's tutorial.
  Adapt it for OpenLDAP and similar directories.
- **`authenticationMechanisms`:** `PLAIN` enables LDAP. Keep `SCRAM-SHA-256` in the list only
  if local SCRAM users (such as a break-glass admin) must keep working. Those users then have to
  authenticate with `SCRAM-SHA-256` explicitly.
- **`bind.method: sasl` with `DIGEST-MD5`:** this makes `mongod` fail to start on hosts with
  Cyrus SASL 2.1.28 or later. Use `simple` over TLS, or SASL `PLAIN` over TLS.
- **The alternative:** binding through `saslauthd` also works on Linux, with its own
  `saslauthd.conf`.

## Test before restarting

Run `mongoldap` against the same config file before changing any running `mongod`.

**Default: test the mapping without a password.** `--password` isn't required for LDAP
authorization checks. This confirms that the servers are reachable over TLS, that
`userToDNMapping` resolves, and which `admin` roles the user maps to:

```bash
mongoldap --config=<MONGOD_CONF_PATH> --user="<TEST_LDAP_USERNAME>"
```

**Testing authentication itself** needs a password. Don't put a real account's password on
the command line. Arguments can be seen in process listings (`ps`), CI logs, and shell
telemetry, even with shell history turned off. If the user must test authentication with
`mongoldap`:

- Use a dedicated test account with a short-lived password and no MongoDB privileges.
- Run it interactively on the host, never in CI or a shared script.
- Disable or rotate the test account afterwards.

The alternative is to test authentication with `mongosh ... -p` against a non-production
instance, since mongosh prompts for the password.

`mongoldap`'s documented way to test authentication is to pass the password as an argument,
and the docs don't say whether it prompts when the argument is left out. For that reason this
skill doesn't give a password-bearing `mongoldap` command. The recommended path is:

1. Test the mapping with `mongoldap` and no password (above).
2. Apply the LDAP settings to one non-production instance, or to a single hidden or secondary
   member you can take out of rotation.
3. Test authentication there with `mongosh --authenticationMechanism PLAIN
   --authenticationDatabase '$external' -u <TEST_LDAP_USERNAME> -p`, which prompts for the
   password.

## Users and roles

**Authorization mode.** Create one role in `admin` per LDAP group, named with the group's
exact DN:

```javascript
db.getSiblingDB("admin").createRole({
  role: "CN=<GROUP_NAME>,OU=<GROUPS_OU>,DC=<DOMAIN>,DC=<TLD>",
  privileges: [],
  roles: [ { role: "read", db: "reporting" } ]
})
```

On a fresh deployment using LDAP authorization, this is the one case where the first object
created through the localhost exception should be a role (for the admins' group) instead of a
user.

**Authentication-only mode.** Create an `$external` user whose name matches what the client
authenticates with. There's no password in MongoDB:

```javascript
db.getSiblingDB("$external").createUser({
  user: "<LDAP_USERNAME>",
  roles: [ { role: "<CUSTOM_ROLE>", db: "<ROLE_DB>" } ]
})
```

Make sure at least one LDAP-authenticated identity can administer users on `$external` (for
example through `userAdmin` on `$external`). Without one, you can't manage LDAP users at all.

## Rollout

- **Replica sets:** configure secondaries and arbiters first, one member at a time, then step
  down and configure the primary.
- **Sharded clusters:** configure the config servers and every `mongos`. Configure shards too if
  you use shard-local users.

## Connect

```bash
mongosh --host <HOST> --tls --username "<LDAP_USERNAME>" -p \
  --authenticationDatabase '$external' --authenticationMechanism PLAIN
```

- Keep `$external` in single quotes in the shell.
- In a connection string, use `authMechanism=PLAIN&authSource=%24external`.
- `PLAIN` sends the password to the server, so TLS between client and server is mandatory.

## Pitfalls

- Using `authSource=admin` for an LDAP user. It must be `$external`.
- A role name that doesn't match the group DN exactly (case, spacing, RDN order), which leaves
  users authenticated with no privileges.
- Turning on LDAP authorization and losing access for existing `$external` users.
- On Atlas: turning on LDAP authorization blocks OIDC connections, AWS IAM authentication, and
  Atlas-managed x.509 users.
