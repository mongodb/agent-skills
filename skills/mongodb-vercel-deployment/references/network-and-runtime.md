# Network and runtime decision reference

Documentation reviewed October 12, 2026. Check current plan capabilities and the user's project settings before applying changes.

## Choose by the actual traffic source

| Situation | Check | Avoid |
| --- | --- | --- |
| Local access works, Preview fails | Preview env bindings, runtime, actual egress path, Atlas access list | Assuming the developer's IP covers Vercel |
| Restricted Atlas public endpoint | Approved Static IPs or another supported path | Hardcoding an observed dynamic egress IP |
| Private Atlas endpoint | End-to-end routing, private DNS, supported cloud/region topology | Treating static public egress as private networking |
| Build fails but runtime config looks right | Whether prerender queries Atlas; build network path and env scope | Assuming runtime egress settings apply to builds |
| Builds, then fails at request time with driver errors about `net`, `tls`, or `dns` | The route's runtime: the native driver needs Node.js, not Edge | Network changes; an HTTP data layer before simply switching the runtime |
| Authentication error | Database user, auth source, URI encoding, environment selection | Widening the access list to fix bad credentials |
| Server selection timeout | Nested error, DNS/SRV, routing, TLS, cluster availability | Treating every timeout as pool exhaustion |

## Facts to rely on

- **Native integration** (from [Atlas: Integrate with Vercel](https://www.mongodb.com/docs/atlas/reference/partner-integrations/vercel.md)):
  - It sets `MONGODB_URI`, creates a Vercel-managed Atlas organization and project, and bills through Vercel.
  - It adds `0.0.0.0/0` if absent, because "Vercel deployments use dynamic IP addresses".
  - It creates `Vercel-Admin-[resource name]` with `readWriteAnyDatabase` on non-system databases.
  - It does not offer a restricted network mode. Check the actual project and environment bindings after setup.
- **Manual versus native:** do not silently replace managed credentials or remove managed access rules. Check dependent apps before disconnecting the integration or deleting resources. If policy forbids the defaults, use a manually connected cluster with a restricted path.
- **Static IPs:**
  - Vercel's Static IPs are a shared egress-IP service on Pro and Enterprise, distinct from dedicated Secure Compute. Enabling them may cost extra.
  - Addresses are assigned per configured region. Use the actual assignments, then redeploy.
  - Build-traffic routing is a separate setting. Check whether it is enabled for the project.
- **Access lists:** Atlas IP access lists are project network controls, not a substitute for database-user permissions. Removing an entry may not end existing connections.
- **Runtime:** the native Node.js driver needs a Node.js runtime. Edge routes that import it may build, then fail at request time.
- **`attachDatabasePool`** (Fluid compute only) accepts the `MongoClient` and needs a non-zero `maxIdleTimeMS` to release idle connections. Details are in the `mongodb-connection` skill's `references/fluid-compute.md`.

## Sources

Use the Atlas integration guide for native provisioning, credentials, environment variables, billing, and lifecycle. Use Vercel docs for platform networking and compute, and the driver docs that match the installed version for pooling.

- [Atlas: Integrate with Vercel](https://www.mongodb.com/docs/atlas/reference/partner-integrations/vercel.md)
- [Vercel Static IPs](https://vercel.com/docs/connectivity/static-ips.md) and [setup](https://vercel.com/docs/connectivity/static-ips/getting-started.md)
- [Atlas IP access lists](https://www.mongodb.com/docs/atlas/security/ip-access-list.md)
- [Vercel Functions API: attachDatabasePool](https://vercel.com/docs/functions/functions-api-reference/vercel-functions-package.md)
- [Node.js driver connection pools](https://www.mongodb.com/docs/drivers/node/current/connect/connection-options/connection-pools/)
