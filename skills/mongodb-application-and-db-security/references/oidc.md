# OIDC / SSO (Workforce and Workload Identity Federation)

## Decide the flow first

| | Workforce identity federation | Workload identity federation |
|---|---|---|
| Who | People (developers, DBAs, analysts) | Applications and services |
| Protocol | OIDC: Authorization Code Flow with PKCE, or Device Authorization Flow | OAuth 2.0 access tokens |
| Typical identity | IdP user or group (Okta, Entra ID, Ping, ADFS) | Azure managed identity or service principal, GCP service account, Kubernetes service account |
| Clients | mongosh, Compass, and drivers with a human callback | Drivers (on Atlas, only supported drivers; mongosh and Compass don't do workload) |

Requirements:

- **Self-managed:** MongoDB Enterprise 7.0.11+, on Linux only.
- **Atlas:** M10+ dedicated clusters on 7.0.11+. See `atlas.md` for the Atlas setup, which runs
  through Federation Management instead of `setParameter`.
- MongoDB accepts only JWT access tokens. Opaque tokens aren't supported.

## Self-managed configuration

`oidcIdentityProviders` is a startup-only parameter, so changing it needs a restart. On
replica sets that means a rolling restart, and in sharded clusters it must be set on every
`mongos`.

Workforce example:

```yaml
security:
  authorization: enabled
setParameter:
  authenticationMechanisms: "MONGODB-OIDC,SCRAM-SHA-256"
  oidcIdentityProviders: |
    [
      {
        "issuer": "<IDP_ISSUER_URL>",
        "audience": "<AUDIENCE>",
        "authNamePrefix": "<PREFIX>",
        "clientId": "<PUBLIC_CLIENT_ID>",
        "authorizationClaim": "groups"
      }
    ]
```

Workload example: set `"supportsHumanFlows": false` and leave out `clientId`.

Keep `SCRAM-SHA-256` enabled with a break-glass SCRAM admin. If the IdP is down or
misconfigured, that account is the only way back in.

| Field | Required | Notes |
|---|---|---|
| `issuer` | Yes | Must match the token's `iss` claim. |
| `audience` | Yes | Exactly one value. Must be unique across configs that share an issuer. |
| `authNamePrefix` | Yes | Prefix for generated user and role names. Alphanumeric characters, `-`, and `_` only. |
| `clientId` | When `supportsHumanFlows` is `true` (the default) | The public client ID registered in the IdP. |
| `supportsHumanFlows` | No (default `true`) | Set to `false` for workload-only providers. |
| `useAuthorizationClaim` | No (default `true`) | `true`: roles come from a token claim. `false`: roles come from a `$external` user. |
| `authorizationClaim` | Unless `useAuthorizationClaim` is `false` | The claim that holds group or role names, e.g. `groups`. Leave it out when `useAuthorizationClaim` is `false`. |
| `principalName` | No (default `sub`) | The claim used as the user name. |
| `matchPattern` | When more than one provider has `supportsHumanFlows: true` | A regex over usernames that picks the IdP. It's routing, not a security control. |
| `requestScopes`, `JWKSPollSecs` | No | Extra scopes to request; JWKS refresh interval. |
| `logClaims` | No | Claims to write to log and audit messages. Leave it unset by default: claims can expose user, group, tenant, and other identity data in server logs. Enable it only while troubleshooting, list only the claims you need, and remove it afterwards. It's a startup parameter, so removing it takes another rolling restart. |

## Map identities to roles

An IdP group gives no MongoDB privileges until you create the matching role.

**`useAuthorizationClaim: true` (the default):** create a role in `admin` named
`<authNamePrefix>/<claim value>`. The name must match exactly, including case.

```javascript
db.getSiblingDB("admin").createRole({
  role: "<PREFIX>/<IDP_GROUP_NAME>",
  privileges: [],
  roles: [ { role: "read", db: "reporting" } ]
})
```

**`useAuthorizationClaim: false`:** create a `$external` user named
`<authNamePrefix>/<value of the principalName claim>`:

```javascript
db.getSiblingDB("$external").createUser({
  user: "<PREFIX>/<PRINCIPAL_CLAIM_VALUE>",
  roles: [ { role: "<CUSTOM_ROLE>", db: "<ROLE_DB>" } ]
})
```

Design the inherited roles with `rbac-custom-roles.md`. Map groups to narrow roles; don't map a
broad "Everyone" group to write access.

## IdP-side setup (workforce)

- Register a public client that uses Authorization Code with PKCE. Use Device Authorization
  Flow only for machines with no browser.
- For mongosh and Compass, register the redirect URI `http://localhost:27097/redirect`.
- Configure the IdP to put the group claim named in `authorizationClaim` into the **access
  token**.
- Token lifetime and refresh follow IdP policy. Short-lived access tokens with refresh tokens
  are the usual choice.

## Connect

People:

```bash
mongosh "mongodb://<HOST>:27017/?tls=true" --authenticationMechanism MONGODB-OIDC
# Headless machine:
mongosh "mongodb://<HOST>:27017/?tls=true" --authenticationMechanism MONGODB-OIDC --oidcFlows=device-auth
```

Applications:

- Use `authMechanism=MONGODB-OIDC` with `authMechanismProperties`:
  - `ENVIRONMENT:azure,TOKEN_RESOURCE:<AUDIENCE>`
  - `ENVIRONMENT:gcp,TOKEN_RESOURCE:<AUDIENCE>`
  - `ENVIRONMENT:k8s`
  - or a custom token callback
- OIDC needs Node.js driver 6.7+, and k8s needs 6.11+. Check the driver docs for other languages.
- Never ask the user for a token, and never log tokens.

## Interaction with LDAP authorization

- **Self-managed:** if LDAP authorization is on, OIDC users with `useAuthorizationClaim: false`
  are authorized through LDAP. With `true`, OIDC uses MongoDB's own role mapping.
- **Atlas:** OIDC connections fail while LDAP authorization is on.

## Pitfalls

- A role name that doesn't match `<authNamePrefix>/<claim value>` exactly, so users
  authenticate but have no privileges.
- The group claim is present in the ID token but missing from the access token.
- Several human-flow IdPs configured without a `matchPattern` on each.
- No break-glass SCRAM admin, so an IdP outage locks everyone out.
