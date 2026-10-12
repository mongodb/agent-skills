# Advisory posture review (authentication and access control)

Use this when the user shares configuration, architecture notes, user or role listings, or
command output, and asks what's weak in their authentication or access control.

This is a review of **supplied evidence**, not a live audit:

- The agent never connects to the cluster and never runs the checks below.
- The user runs them and shares the output.
- Every conclusion is labeled as based on what was shared.
- Anything not shared is listed as unknown. It isn't assumed to be fine or broken.

Stay inside authentication, authorization, internal authentication, and the transport and
network settings that protect credentials. If the material also raises storage, backup,
sizing, or OS tuning questions, say they're outside this review in one line.

## Before you start

- Ask the user to inspect and redact everything before sharing. For `getCmdLineOpts`, that means
  **both** `argv` (the raw startup arguments) and `parsed` (the effective settings from the
  command line and config file). A secret passed on the command line appears in `argv` even
  when `parsed` looks clean. MongoDB documents redaction only for a few TLS key-file passwords,
  so don't assume other values are hidden. Redact:
  - passwords, including `security.ldap.bind.queryPassword`;
  - key file contents and private keys;
  - tokens;
  - expansion-directive commands or URLs that reveal where secrets are stored;
  - internal hostnames or IPs the user's policy treats as sensitive.
- If the shared material still contains a secret, don't repeat it. Record it as a finding: that
  secret has now been exposed through this conversation, so rotating it is recommended.
- Confirm deployment type, version, edition, and topology. These change what "correct" means
  (see `SKILL.md` prerequisites).

## Read-only checks to give the user

These only read state, but they still need privileges. The user should run them as an existing
admin or a user with `viewUser`, `viewRole`, and `clusterMonitor`.

**Self-managed:**

```javascript
// Effective startup settings: authorization, keyFile, clusterAuthMode, net.tls, bindIp, setParameter
db.adminCommand({ getCmdLineOpts: 1 })

// Mechanisms the server accepts
db.adminCommand({ getParameter: 1, authenticationMechanisms: 1 })

// All users and their roles. Keep credentials off; omit customData (5.2+), which can hold
// personal or application data. On versions before 5.2, drop showCustomData and redact
// customData by hand.
db.getSiblingDB("admin").runCommand({
  usersInfo: { forAllDBs: true },
  showCredentials: false,
  showCustomData: false
})

// Custom roles with privileges and authentication restrictions, per database.
// Repeat with getSiblingDB("<APP_DB>") for each application database.
db.getSiblingDB("admin").getRoles({
  rolesInfo: 1,
  showPrivileges: true,
  showBuiltinRoles: false,
  showAuthenticationRestrictions: true
})

// Authentication restrictions for one sensitive user (admins, break-glass, automation).
// The all-users query above can't include restrictions, so check these users one at a time.
db.getSiblingDB("<USER_DB>").getUser("<USERNAME>", {
  showCredentials: false,
  showCustomData: false,
  showAuthenticationRestrictions: true
})
```

Read restriction output carefully. A restriction field that's missing because it wasn't
requested says nothing. Only report "no restriction" for a role or user whose output was
fetched with `showAuthenticationRestrictions: true`. For every other sensitive identity, list
restrictions as unknown.

Run `mongod --version` on the host to see the edition.

`getCmdLineOpts` describes only the process it was run on. Members of one replica set can
drift, and each shard, config server, and router has its own startup settings. Ask for
`getCmdLineOpts` and `authenticationMechanisms` output from **every** member of every replica
set, every config server member, and every `mongos`. When some are missing:

- report findings only for the processes actually shown, naming each by host and port;
- list every unexamined member and router under Unknowns;
- never extend one node's settings to the rest of the deployment.

**Atlas:**

```bash
atlas dbusers list --projectId <PROJECT_ID>
atlas customDbRoles list --projectId <PROJECT_ID>
atlas accessLists list --projectId <PROJECT_ID>
```

Also ask for a description (not a screenshot of secrets) of Federation Management (OIDC) and
any LDAP configuration on the project.

## What to assess

| Severity | Condition in the evidence | Fix reference |
|---|---|---|
| Critical | `security.authorization` not enabled, with no keyfile or x.509 member auth to imply it | `enable-auth-first-admin.md` |
| Critical | `net.bindIpAll: true` or a public `bindIp` on a host without access control | `enable-auth-first-admin.md` |
| Critical | TLS disabled (`net.tls.mode: disabled`, or not set), or clients using `tlsAllowInvalidCertificates`, `tlsAllowInvalidHostnames`, or `tlsInsecure` | `SKILL.md` TLS prerequisite |
| Critical | Atlas access list contains `0.0.0.0/0` | `atlas.md` |
| Critical | An application identity holds `root`, `atlasAdmin`, `dbOwner` on `admin`, `userAdminAnyDatabase`, or any `*AnyDatabase` role | `rbac-custom-roles.md` |
| Critical | Secret exposure established or reasonably suspected: credentials in shared output (including this conversation), source control, CI logs, container images, or a file readable by other OS users | Rotate the secret and remove it from that location; `scram.md`, `ldap.md` |
| High | TLS available but not enforced for all connections (`net.tls.mode: allowTLS` or `preferTLS`). Some clients can still connect without TLS. Target `requireTLS` after confirming every client uses TLS. | `SKILL.md` TLS prerequisite |
| High | Replica set or sharded cluster without `security.keyFile` or `clusterAuthMode: x509` | `enable-auth-first-admin.md` |
| High | `security.transitionToAuth: true` still set after a migration | `enable-auth-first-admin.md` |
| High | Sharded cluster where shards have no local user admin and `enableLocalhostAuthBypass` isn't `false` | `enable-auth-first-admin.md` |
| High | Several people or services sharing one database user | `SKILL.md` security rules |
| High | Client x.509 certificates whose O, OU, and DC match the member certificates | `x509.md` |
| High | `security.ldap.transportSecurity: none`, or `PLAIN` in use without TLS | `ldap.md` |
| Medium | Secret stored in plain text in a config file whose permissions and access haven't been shown. This isn't evidence of exposure on its own. | Check file ownership and permissions and who can read the host. Prefer expansion directives or a secret manager; see `ldap.md`. Recommend rotation only if exposure is found. |
| Medium | Superuser roles held by accounts used for daily work, or by more people than the break-glass process needs | `rbac-custom-roles.md` |
| Medium | Application roles use `readWrite` where explicit CRUD actions would do, or a write action on `collection: ""` | `rbac-custom-roles.md` |
| Medium | Roles created in `admin` whose privileges all sit in one database | `rbac-custom-roles.md` |
| Medium | No break-glass admin that works without an external IdP or directory | `oidc.md`, `ldap.md` |
| Medium | LDAP in use with no migration plan (deprecated since 8.0) | `ldap.md`, `oidc.md` |
| Medium | OIDC `logClaims` set in steady state | `oidc.md` |
| Low | Users with only SCRAM-SHA-1 credentials where every client supports SHA-256 | `scram.md` |

Only report conditions the evidence shows. For each finding, name the process or object it came
from. For each severity row with no evidence, add the
matching item to Unknowns, unless the deployment type makes it irrelevant (for example, keyfiles
on Atlas).

## Output format

1. **Basis.** One line: "Based only on the material you shared on <what was shared>. This isn't
   a live audit, and nothing here was verified against your deployment."
2. **Findings.** A table with columns: Severity | Finding | Evidence (quote the exact setting or
   line) | Why it matters | Fix. The fix names the reference procedure.
3. **Unknowns.** What couldn't be assessed, and which read-only check above would answer it.
4. **Remediation plan.** Order it:
   - Critical items first.
   - Within the same severity, do changes that can't lock anyone out before changes that can.
   - Changes that need restarts go last and are batched into one rolling restart where
     possible.

   Every step carries its pre-change check, post-change check, and rollback criterion (see
   `SKILL.md` workflow step 6).
5. **Next evidence to share.** What the user should run and send next if they want a narrower
   review.

Never describe the deployment as "secure", "compliant", or "passing". Describe what the shared
evidence shows and what remains unknown.
