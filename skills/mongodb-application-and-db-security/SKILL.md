---
name: mongodb-application-and-db-security
description: >
  When the user wants to enable MongoDB authentication or authorization, review the
  authentication and access-control posture of configuration or command output they share,
  create the first admin user, choose or configure an authentication mechanism (SCRAM-SHA-256, x.509, LDAP,
  Kerberos/GSSAPI, OIDC workforce or workload identity, AWS IAM on Atlas), design least-privilege
  custom roles, or connect an application with the right authSource and mechanism. Covers
  self-managed Community and Enterprise Advanced (standalone, replica set, sharded cluster) and
  Atlas. Advisory only: produces steps and configuration for the user to review and apply; never
  applies changes itself or inspects a live cluster. Do NOT use this skill for driver
  connection-pool or timeout tuning, auditing a cluster against general deployment best
  practices or production notes, Queryable Encryption
  or CSFLE, audit-log configuration, or writing queries and aggregation pipelines.
license: Apache-2.0
metadata:
  version: "1.0.0"
---

# MongoDB Authentication and Access Control

Design authentication and least-privilege authorization for MongoDB, and assess the
authentication and access-control posture from information the user provides. The output is
guidance the user applies: findings, ordered steps, commands, config snippets, and connection
settings, scoped to the privileges the workload requires.

## Advisory only: the agent never applies changes

This skill produces steps. The user, not the agent, runs every command and applies every change.
A wrong auth change can lock every user out of a production cluster, so:

- Never run shell commands, mongosh commands, Atlas CLI commands, or Admin API calls from this
  skill. That includes read-only checks: give the user the check to run and ask for the output.
- Never edit `mongod.conf`, keyfiles, certificates, keytabs, or application config files.
- Never call MongoDB MCP tools (or any other tool) that create, change, or drop users, roles,
  access-list entries, identity providers, or server parameters, even if the user asks you to.
  Say that this skill only provides the steps, and give them.
- Never claim to have verified anything about the user's deployment. Conclusions rest on what
  the user shared, and the answer must say so.
- Present every change as a numbered step the user performs, in the order it must happen, with
  what to check before moving on. For any change that needs a restart or can block logins, also
  say how to back it out.

## Scope gates

Proceed when the request is about who can connect (authentication) or what a connected
identity can do (authorization, roles, privileges).

Stop and route when the request is about:

- Connection management (pool size, timeouts, retries, or `ECONNREFUSED`-style connection errors) → use the
  `mongodb-connection` skill. If the same request also needs credentials, answer the auth part
  here and hand off the pool part.
- A general audit of a deployment against best practices or production notes (storage, backups,
  OS tuning, sizing, and so on) → out of scope. Say so in one line, then offer the posture
  review below. Read `references/posture-review.md` first, so the read-only checks you offer
  come from its checklist and not from memory.
- A request to connect to, scan, or inspect a live cluster → decline the inspection. Offer the
  posture review below instead: the user runs the read-only checks and shares the output. Read
  `references/posture-review.md` for those checks.
- Queryable Encryption, CSFLE, encryption at rest, or `auditLog` settings → out of scope. Say so
  in one line.
- Queries, aggregation pipelines, or schema design → out of scope.
- When declining a general audit, read `references/posture-review.md` for the read-only checks to offer.


**In scope: advisory posture review.** When the user shares configuration files, architecture
notes, user and role listings, or command output and asks what's wrong with their
authentication or access control, review it. Before writing findings, read
`references/posture-review.md`. It has the checklist, the read-only checks to give the user, and
the format that keeps the review separate from a live audit.

Certificate issuance and TLS rollout procedures are out of scope; link the MongoDB TLS
documentation for them. TLS itself is a required prerequisite (see below), not optional.

## Prerequisites: establish these before writing any configuration

1. **Deployment type:** Atlas, self-managed Enterprise Advanced, or self-managed Community.
   Atlas manages users and roles through the Atlas UI, Atlas CLI, or Admin API. `db.createUser()`
   and `db.createRole()` are not supported there, and Atlas rolls back changes made outside
   those tools. Self-managed deployments use mongosh and `mongod.conf`.
2. **Edition and version.** On self-managed hosts, confirm Enterprise with `mongod --version`
   (look for `modules: enterprise` or `modules: subscription`). LDAP, Kerberos, and OIDC
   require Enterprise.
3. **Topology:** standalone, replica set, or sharded cluster. Replica sets and sharded clusters
   need internal member authentication before access control works.
4. **TLS:** required whenever credentials, certificates, or tokens cross a network. On
   self-managed deployments that means `net.tls.mode: requireTLS`; Atlas always has it on. It
   also means clients verify the server certificate: no `tlsAllowInvalidCertificates`,
   `tlsAllowInvalidHostnames`, or `tlsInsecure`.
   - **The user says TLS is off, or that verification is disabled:** stop. Tell them to enable
     TLS first, link the MongoDB TLS docs, and don't give remote credential configuration until
     they confirm it's done.
   - **TLS status is unknown:** make "confirm TLS is on and certificates are verified" the
     first step, and include `tls=true` (or the driver equivalent) in every client example.
   - **Exception:** bootstrapping the first admin on localhost, on the same host.
5. **Identity source:** passwords managed in MongoDB, an existing PKI, LDAP/Active Directory,
   Kerberos, an OIDC identity provider, or AWS IAM.
6. **Client:** driver and language, mongosh, or Compass.

If a missing answer changes the commands (most often Atlas vs self-managed), ask one focused
question. If it does not, state your assumptions in the first line of the answer, continue, and
tell the user to confirm those assumptions before applying any step.

## Mechanism availability

| Mechanism | `authMechanism` | Community | Enterprise Advanced | Atlas |
|---|---|---|---|---|
| SCRAM | `SCRAM-SHA-256` (default), `SCRAM-SHA-1` | Yes | Yes | Yes |
| x.509 | `MONGODB-X509` | Yes | Yes | Yes (Atlas-managed or self-managed CA) |
| LDAP | `PLAIN` | No | Yes, deprecated since 8.0 | Dedicated clusters, 7.0+, deprecated since 8.0 |
| Kerberos | `GSSAPI` | No | Yes | No |
| OIDC | `MONGODB-OIDC` | No | 7.0.11+, Linux only | M10+, 7.0.11+ |
| AWS IAM | `MONGODB-AWS` | No | No | Yes |

Atlas Free and Flex clusters support only password authentication (SCRAM-SHA-1), x.509, and
AWS IAM.

## Choosing a mechanism

Pick the mechanism that matches the identity system the user already runs:

- **People with a corporate IdP (Okta, Entra ID, Ping, ADFS):** OIDC workforce identity.
- **Applications on Azure, GCP, or Kubernetes with an OIDC-capable deployment:** OIDC workload
  identity. On Atlas, workload identity works only through supported drivers, not mongosh or
  Compass.
- **Applications on AWS connecting to Atlas:** AWS IAM with IAM roles.
- **Applications with an existing PKI, or where mutual TLS is required:** x.509.
- **Everything else:** SCRAM-SHA-256 with a dedicated user per application.
- **LDAP:** only when the user already depends on it. Always state that LDAP is deprecated
  starting in 8.0 and that MongoDB recommends OIDC for people and workload identity or x.509
  for applications.
- **Kerberos:** only for self-managed Enterprise deployments that already run MIT Kerberos
  or Active Directory Kerberos.

For a "which mechanism should I use" question, answer from this section and the table above.
Do not load reference files or produce configuration unless the user asks for it.

## Workflow

1. Apply the scope gates and prerequisites above.
2. Choose the mechanism.
3. Turn the requirement into a permission matrix: identity, database, collection, allowed
   operations, and explicit exclusions.
4. Load the matching reference files below. Load every one whose trigger applies.
5. Write the answer in the response shape below, as steps the user performs.
6. Wrap every change in a **deployment-ready procedure** with three parts:
   - **Pre-change check:** what the user confirms before starting. For example, a working admin
     login, a healthy replica set majority, clients already updated, or TLS on.
   - **Post-change check:** what proves it worked: `db.runCommand({ connectionStatus: 1 })`, one
     operation that must succeed, and one that must fail with `Unauthorized` (code 13).
   - **Rollback criterion and action:** the observable condition that means stop and roll back
     (for example "the admin can't log in" or "a member doesn't rejoin within N minutes"), and
     the exact steps to return to the last known-good state.

   These are required for anything involving a restart, a change of authentication mechanism,
   administrator access, or network restrictions.
7. Keep verification production-safe:
   - Run positive write tests against a designated test namespace or a clearly labeled test
     record. Say what they leave behind and how an admin cleans it up.
   - Keep every negative write test inside a designated disposable namespace, such as
     `<DB>.authz_verify_disposable`, seeded by an admin and dropped afterwards. Never run a
     negative write test against a real collection, and never rely on a filter being assumed not
     to match. Confirm denied actions on real collections from the `connectionStatus` privilege
     list instead.
   - Where the user has one, prefer running the full test in a non-production environment first.

## Reference files: load when the trigger applies

- If the user shares configuration or command output for review, read
  `references/posture-review.md` before writing findings.
- If the user is enabling access control, creating the first user, or asks about the localhost
  exception or keyfiles, read `references/enable-auth-first-admin.md` before writing commands.
  It has the bootstrap order and the replica set and sharded cluster steps that prevent lockout.
- If the user needs a custom role, or asks which role to grant, read
  `references/rbac-custom-roles.md`. It maps operations to privilege actions and explains the
  rules for where a role is created.
- If the mechanism is SCRAM, read `references/scram.md`.
- If the mechanism is x.509, read `references/x509.md`. It has the certificate rules that
  otherwise grant a client full cluster permissions by mistake.
- If the mechanism is LDAP, read `references/ldap.md`.
- If the mechanism is Kerberos, read `references/kerberos.md`.
- If the mechanism is OIDC or the user mentions SSO or an identity provider, read
  `references/oidc.md`.
- If the deployment is Atlas, read `references/atlas.md` in addition to the mechanism file.
  Atlas commands replace the mongosh user and role commands.


## Security rules

- Follow the advisory-only rules above without exception. A user's "go ahead" doesn't change
  them: reply with the steps to run.
- Never ask the user to paste passwords, private keys, keytabs, or tokens into the chat. Never
  log, echo, or print a full connection string that contains credentials.
- Use placeholders such as `<DB_USERNAME>`, `<CLUSTER_HOST>`, `<CA_FILE_PATH>`, and
  `<CERT_SUBJECT_DN>`. Read secrets from environment variables or a secret manager. Use
  `passwordPrompt()` in mongosh, and use `-p` with no value so mongosh prompts instead of
  leaving the password in shell history.
- Never recommend disabling authentication or TLS, `tlsAllowInvalidCertificates`,
  `tlsInsecure`, `net.bindIpAll` on a host without access control, or a `0.0.0.0/0` Atlas access
  list entry, even as a temporary fix. Give the secure fix for the underlying error instead.
  The one exception is lockout recovery on a self-managed host: restart bound to `127.0.0.1`
  only with authorization off, fix the admin user, and turn authorization back on. It appears
  only as a rollback action, never as a normal step.
- `userAdminAnyDatabase`, `userAdmin` on `admin`, `dbOwner` on `admin`, `root`, and Atlas
  `atlasAdmin` are effectively superuser roles. A user with `userAdminAnyDatabase` can grant
  itself any privilege. Recommend them only for a bootstrap or break-glass admin, say so
  explicitly, and create narrower users for daily work.
- Apply least privilege: give each application its own identity with a specific role scoped to
  the databases and collections it uses. Never give an application an
  `*AnyDatabase` role or a human admin's credentials. Whenever the answer grants `readWrite` or `dbOwner`, 
  add the one-line caveat and the narrower CRUD-role alternative, even when the user named the role.
- Authentication does not encrypt traffic. Kerberos, SCRAM, and OIDC authenticate the
  identity, but only TLS protects the data on the connection. `PLAIN` (LDAP) sends the password
  to the server, so it must never run without TLS.

## Response shape

For configuration requests, use these sections and skip any that don't apply:

1. **Assumptions to confirm and recommendation:** deployment type, version, topology, the mechanism, and
   why it fits.
2. **Steps for you to apply:** numbered, in order, with the server or Atlas settings this
   mechanism needs, each wrapped in its pre-change check, post-change check, and rollback
   criterion.
3. **Users and roles:** the role definition, where it is created, and a one-line reason for
   each privilege.
4. **Client connection:** URI options or driver code, with `authSource` stated. For SCRAM, use
   the database the user was created in (usually `admin`). For x.509, LDAP (`PLAIN`), Kerberos,
   and AWS IAM, use `$external`. For `MONGODB-OIDC`, drivers already use `$external`, so leave
   `authSource` unset.
5. **Verify (you run these):** `connectionStatus`, one allowed operation, and one operation that
   must be denied, all production-safe. Say what they leave behind and how to clean it up.
6. **Pitfalls:** the two or three mistakes most likely for this exact setup.

For posture reviews, use the format in `references/posture-review.md`. For conceptual questions,
answer in prose or a table with no configuration dump.

## Cross-cutting failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `Authentication failed` (code 18) with a valid password | Client `authSource` doesn't match the database the user was created in | Set `authSource` to that database. Atlas SRV strings default to `admin`. |
| External users fail to authenticate | `authSource=admin` used with an external mechanism | Use `$external` (percent-encoded as `%24external` in a URI). |
| `Unauthorized` (code 13) on an operation the user expects to work | The role lacks that action on that resource | Add the specific action on the specific namespace. Don't switch to a broader built-in role. |
| Driver rejects the URI or credentials are garbled | Reserved characters in the username or password | Percent-encode with `encodeURIComponent`, or pass credentials as client options. |
| Replica set members won't start or can't talk after enabling auth | No internal authentication configured | Add `security.keyFile` or x.509 member auth. See `references/enable-auth-first-admin.md`. |
| Commands work in mongosh but not on Atlas | Using `db.createUser`/`db.createRole` on Atlas | Use the Atlas UI, CLI, or Admin API. See `references/atlas.md`. |
