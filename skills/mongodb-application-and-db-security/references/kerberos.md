# Kerberos (GSSAPI)

Kerberos needs self-managed MongoDB Enterprise. Atlas doesn't offer it, so for Atlas users
recommend OIDC workforce identity (people) or x.509 or OIDC workload identity (applications).
MongoDB supports MIT Kerberos. The steps below are for Linux. Windows uses SSPI and differs.

## Prerequisites

Check these before giving any commands:

- A service principal for each `mongod`/`mongos` host: `mongodb/<HOST_FQDN>@<REALM>`. The
  service name defaults to `mongodb`, and the realm is uppercase.
- A keytab containing that principal, readable only by the user that runs `mongod`. Never put
  it in source control or a world-readable path.
- Forward (A) and reverse (PTR) DNS records for every host.
- Clocks within 5 minutes of the KDC. Run NTP.
- `authorization` enabled, and ideally a SCRAM break-glass admin created first
  (see `enable-auth-first-admin.md`).

## TLS baseline

Kerberos authenticates the identity. It doesn't encrypt or integrity-protect MongoDB
traffic, so Kerberos alone is never enough transport protection. In production, require TLS
alongside it:

```yaml
net:
  tls:
    mode: requireTLS
    certificateKeyFile: <SERVER_PEM_PATH>
    CAFile: <CA_PEM_PATH>
```

- Clients connect with `--tls` (mongosh) or `tls=true` (URI) and trust the CA with
  `--tlsCAFile` / `tlsCAFile`.
- The server certificate's SAN must contain the FQDN clients connect to. That's the same FQDN
  the Kerberos service principal uses.
- Never set `tlsAllowInvalidCertificates` or `tlsAllowInvalidHostnames`.

## Server

Point `KRB5_KTNAME` at the keytab and enable GSSAPI:

```bash
env KRB5_KTNAME=<KEYTAB_PATH> mongod --config <MONGOD_CONF_PATH>
```

```yaml
security:
  authorization: enabled
setParameter:
  authenticationMechanisms: "GSSAPI,SCRAM-SHA-256"
```

Leave out `SCRAM-SHA-256` if no local SCRAM users need to keep working.

## Users

Create each Kerberos principal as a user in `$external`, with the realm in uppercase:

```javascript
db.getSiblingDB("$external").createUser({
  user: "<PRINCIPAL_NAME>@<REALM>",
  roles: [ { role: "<CUSTOM_ROLE>", db: "<ROLE_DB>" } ]
})
```

Kerberos proves who the principal is. The roles on this `$external` user decide what it can do,
so design them with `rbac-custom-roles.md`.

## Connect

Get a ticket with `kinit` first (for services, `kinit -k -t <CLIENT_KEYTAB_PATH> <PRINCIPAL>`).
Then connect using the host's fully qualified domain name, not an IP address or short name:

```bash
mongosh --host <HOST_FQDN> --tls --tlsCAFile <CA_PEM_PATH> \
  --authenticationMechanism=GSSAPI \
  --authenticationDatabase='$external' --username <PRINCIPAL_NAME>@<REALM>
```

Connection string options:

- `tls=true&authMechanism=GSSAPI&authSource=%24external`
- If the service name isn't `mongodb`, add `authMechanismProperties=SERVICE_NAME:<NAME>`.
- Percent-encode the principal in the URI.

## Pitfalls

- Connecting by IP address or short hostname, so the service principal lookup fails.
- Realm written in lowercase in the `$external` user name.
- Clock skew larger than 5 minutes.
- Keytab readable by other users on the host.
