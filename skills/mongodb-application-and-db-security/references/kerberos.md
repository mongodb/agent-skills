# Kerberos (GSSAPI)

Load this file when the user wants to set up Kerberos for MongoDB, review an existing Kerberos
setup, or work out why a Kerberos login fails. Everything here is advice. The user runs every
command through their own change process.

## Where Kerberos is available

- Kerberos needs self-managed MongoDB Enterprise. Community Edition and Atlas don't offer it.
- For Atlas, recommend a supported alternative instead: OIDC workforce identity for people, and
  OIDC workload identity, AWS IAM, or x.509 for applications (see `oidc.md`, `atlas.md`,
  `x509.md`).
- On Linux, MongoDB uses the MIT Kerberos libraries and service keytabs. The KDC can still be
  Active Directory.
- Windows uses SSPI and credentials managed by the operating system. Don't apply the Linux
  keytab steps below to Windows.

## What to ask for, and what never to ask for

You only need names and metadata to review Kerberos. Ask for:

- MongoDB edition and version, server OS, topology, client driver and version, and KDC type.
- The hostnames clients connect to, and the member or router names they discover after
  connecting.
- The service principal each `mongod` and `mongos` uses.
- Key version numbers, encryption types, file permissions, and redacted error messages.

Never ask for passwords, keytab contents, private keys, ticket caches, or raw Kerberos keys.
Never offer to get tickets, generate or rotate keytabs, change service principals, restart
processes, or run login tests yourself.

Base every finding on what the user shared. If something wasn't shown, say it's unverified. A
successful login doesn't prove that TLS, roles, credential handling, or failover are secure.

## When the deployment is Atlas

Kerberos is not available on Atlas at all — see "Where Kerberos is available" above. When an
Atlas user asks for it, name the supported alternative and give the Atlas path concretely: Atlas
database users are created through the Atlas UI, Atlas CLI or Admin API, never `db.createUser()`.
Read `atlas.md` and give those steps rather than describing them in the abstract.

## Prerequisites

Confirm these before giving any configuration:

- **A service principal for every `mongod` and `mongos`:** `mongodb/<HOST_FQDN>@<REALM>`. The
  service name is `mongodb` unless there's a reason to change it.
- **A keytab per Linux instance** holding that principal's keys, readable only by the account
  that runs the process. A keytab is a credential, not configuration: keep it out of source
  control, container image layers, and shared storage. Say this whenever you tell someone where
  to put a keytab — it is the step most often skipped when a service account is set up in a
  hurry.
- **DNS:** forward (A) and reverse (PTR) records for every host. Check them from the
  application host or container, not only from the database host or a DBA's laptop, because
  that's what the client actually sees.
- **Time:** MongoDB's default maximum clock skew is five minutes, and the effective policy may
  be stricter. Recommend reliable time sync and drift monitoring well inside that limit.
- **Access control:** `authorization` on, and a break-glass admin that doesn't depend on the
  KDC (see `enable-auth-first-admin.md`).
- **Owners:** who manages DNS, service accounts, keytabs, certificates, and application
  credentials. Most fixes need one of those teams, not the DBA alone.

## Kerberos doesn't replace TLS

Kerberos proves who the principal is. It doesn't encrypt MongoDB traffic, so production always
needs TLS alongside it:

```yaml
net:
  tls:
    mode: requireTLS
    certificateKeyFile: <SERVER_PEM_PATH>
    CAFile: <CA_PEM_PATH>
```

- Clients must validate the CA and the certificate hostname. Never suggest
  `tlsAllowInvalidCertificates`, `tlsAllowInvalidHostnames`, or any other bypass to get past a
  login problem.
- The certificate SANs must cover every name clients use, including names they discover during
  failover.
- With DNS aliases, the TLS hostname and the Kerberos service hostname can differ. Check each
  one separately and confirm both point at the intended server.
- Treat certificate renewal and keytab rotation as separate processes.

## Server setup

Point the service at its keytab and enable GSSAPI:

```bash
env KRB5_KTNAME=<KEYTAB_PATH> mongod --config <MONGOD_CONF_PATH>
```

```yaml
security:
  authorization: enabled
setParameter:
  authenticationMechanisms: "GSSAPI,SCRAM-SHA-256"
```

- Check `KRB5_KTNAME` and `KRB5_CONFIG` in the environment the service actually runs in. A
  value set in an interactive shell often doesn't reach a systemd unit or a container.
- Don't remove `SCRAM-SHA-256` just because people have moved to Kerberos. Check which clients
  and break-glass accounts still depend on it first, then keep only the mechanisms the
  deployment needs.
- Changing `authenticationMechanisms` needs a restart. On a replica set, restart one member at
  a time with a pre-change check, a post-change check, and a rollback criterion.

## Hostnames and service principals

Follow the name from start to finish: the name the client connects to, what hostname
canonicalization turns it into, the service principal the client requests, and the identity
the server presents and holds keys for. A mismatch anywhere along that path breaks the login.
Use fully qualified names throughout.

### `saslHostName`

- Overrides the hostname MongoDB uses for SASL and Kerberos only.
- Use it when the system hostname is short or differs from the intended Kerberos identity, and
  only after confirming the chosen FQDN matches the service principal and how clients pick it.
- It doesn't fix DNS, certificate SANs, network binding, or replica set member names.
- It's startup-only, so any change needs a restart and an availability plan.

### `saslServiceName`

- Keep `mongodb` unless there's a real reason to change it. A custom name isn't a security
  improvement on its own.
- If it's custom, three values must match: the server's `saslServiceName`, the service part of
  the KDC and keytab principal, and the client's `SERVICE_NAME` property. Check that every
  client supports it, including admin, backup, and monitoring tools.
- It's startup-only. Don't suggest changing it at runtime with `setParameter`.

### `CANONICALIZE_HOST_NAME`

- This is a client property, not a server parameter. It affects which Kerberos identity the
  client asks for. It doesn't replace TLS hostname validation.
- Its values and defaults depend on the driver. For example, the connection string reference
  uses a Boolean, while the Node.js driver uses `none`, `forward`, or `forwardAndReverse`.
  Confirm the syntax for the installed driver before suggesting a value.
- Recommend it only when the naming design needs it and DNS supports it. Don't use reverse
  lookup as a blanket fix for inconsistent names.

### Cross-realm setups

Separate the user's realm from the service realm, and review realm mapping and trust with the
identity team. Use `SERVICE_REALM` only where the client supports it and the setup needs it.

## Users and roles

Create each Kerberos principal as a user in `$external`:

```javascript
db.getSiblingDB("$external").createUser({
  user: "<PRINCIPAL_NAME>@<REALM>",
  roles: [ { role: "<CUSTOM_ROLE>", db: "<ROLE_DB>" } ]
})
```

- Copy the principal exactly as the identity system spells it, including the realm's case.
  Realms are usually uppercase, but rewriting an existing principal without checking breaks the
  mapping.
- Kerberos proves identity. The roles on the `$external` user decide what it can do, so design
  them with `rbac-custom-roles.md`. Kerberos on its own doesn't map AD groups to roles.
- Use named accounts for people and one identity per application, each with least-privilege
  roles. Flag shared accounts, unused users, and broad roles.
- If a login works but an operation is denied, fix the specific missing action. Don't broaden
  the role.
- Client GSSAPI doesn't secure traffic between replica set or shard members. Review the
  existing keyfile or x.509 member authentication separately. Never suggest GSSAPI as
  `clusterAuthMode`.

## Connecting

The client needs a ticket first, from `kinit` or, for a service, a client keytab. Then it
connects by fully qualified hostname, never by IP address or short name:

```bash
mongosh --host <HOST_FQDN> --tls --tlsCAFile <CA_PEM_PATH> \
  --authenticationMechanism=GSSAPI \
  --authenticationDatabase='$external' --username <PRINCIPAL_NAME>@<REALM>
```

Connection string options:

- `tls=true&authMechanism=GSSAPI&authSource=%24external`
- Add `authMechanismProperties=SERVICE_NAME:<NAME>` only if the service name isn't `mongodb`.
- Percent-encode the principal in the URI.

## Keytabs and ticket caches

- Only the account that runs `mongod` or `mongos` can read the server keytab. Check the
  directory, mounts, and backups as well as the file itself. Keep keytabs out of source
  control, container image layers, and shared storage.
- Keep server keytabs, application keytabs, and client ticket caches separate. For each
  application identity, check who owns the cache and how tickets are renewed or reacquired.
- Limit credential forwarding or delegation to what the application actually needs.
- Rotation means reviewing the KDC key state, the deployed key version number, encryption
  types, distribution, and the recovery plan together. Restoring an old keytab doesn't
  necessarily undo a key change on the account.
- Ask for proof that new connections still work after ticket expiry, a restart, and a rotation.
  Pooled connections that are already open don't prove renewal works.

## Active Directory

- Have the identity team review SPN registration. Each SPN must belong to one intended account,
  with no duplicates.
- MongoDB's documented AD setup uses a user service account, not a machine account.
- If AES is used, confirm the service account supports it and the keytab holds matching keys.
- If the principal and encryption types look right but logins still fail, look at the key salt.
  AD and Linux keytab tools can use different salt conventions.
- Never suggest RC4-HMAC to get around a salt problem. Work with the identity team on an
  approved AES keytab process instead. Don't paste key-generation recipes into the answer: they
  can change account attributes or keys.

## Outages and timing

Review KDC, DNS, and time service dependencies together with ticket lifetimes and how the
application reconnects. Don't promise that cached tickets will cover an outage, or that
disabling an identity cuts off connections that are already open. Ask for evidence from the
real workload.

## Narrowing down a failure

| Symptom | Look at first |
|---|---|
| Works in a shell but not as a service | The service's run-as account, its environment, keytab and cache access, Kerberos config |
| First connection works but failover fails | Discovered member names, DNS results, service principals, certificate SANs |
| An alias passes TLS but fails GSSAPI | The requested SPN, canonicalization, the server's SASL identity |
| Only one client accepts a custom service name | `saslServiceName`, the client's `SERVICE_NAME`, driver support |
| Failures start after an account rotation | Current key version number, deployed keytab, encryption types, AD salt |
| Failures appear on the next day's reconnect | Ticket expiry, renewal, cache ownership, new-connection behaviour |
| Login works but an operation is denied | The exact `$external` user and its roles |
| Server logs "GSSAPI error acquiring credentials" | Hostname and principal alignment, keytab presence and permissions |
| Client reports a GSSAPI negotiation error | Client credentials, target FQDN, requested principal, clock, auth properties |

These are places to start, not diagnoses. A negotiation error on its own isn't evidence of an
attack.

## Troubleshooting tools

- MongoDB recommends `mongokerberos`. It doesn't change configuration, but client mode does
  request tickets, so it isn't a passive check. Without `--host`, client mode skips hostname DNS
  validation. A pass doesn't replace a test with the real application driver, and it says
  nothing about TLS or roles.
- For a persistent Linux problem, suggest a short, approved `KRB5_TRACE` capture with
  restricted access, redaction, and a set cleanup date.

## Reporting findings

For each finding, give the evidence, the risk or operational impact, the recommended action,
the team that owns it, and what would show it's fixed. Keep confirmed gaps separate from likely
causes and missing evidence.

Mark each control as `aligned`, `gap`, `not assessed`, or `not applicable`. Set priority by
real exposure and availability impact. Never give a compliance verdict or an overall security
score from partial configuration.

## Pitfalls

- Connecting by IP address or short hostname, so the service principal lookup fails.
- The realm written in the wrong case in the `$external` user name.
- Clock drift close to the skew limit.
- A keytab readable by other accounts on the host.
- A keytab path set in the shell but not in the service's environment.

## MongoDB documentation

Use the docs for the user's exact versions:

- [Kerberos authentication](https://www.mongodb.com/docs/manual/core/kerberos/)
- [Server parameters](https://www.mongodb.com/docs/manual/reference/parameters/)
- [Connection string options](https://www.mongodb.com/docs/manual/reference/connection-string-options/)
- [Node.js driver Kerberos](https://www.mongodb.com/docs/drivers/node/current/security/authentication/kerberos/)
- [Troubleshoot Kerberos](https://www.mongodb.com/docs/manual/tutorial/troubleshoot-kerberos/)
- [mongokerberos](https://www.mongodb.com/docs/manual/reference/program/mongokerberos/)
- [Internal membership authentication](https://www.mongodb.com/docs/manual/core/security-internal-authentication/)