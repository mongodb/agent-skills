---
name: mongodb-vercel-deployment
description: Configure and troubleshoot MongoDB Atlas deployments on Vercel. Use when connecting an existing application or Marketplace integration to Atlas, wiring server-only environment variables, configuring Atlas network access, selecting a compatible runtime, or diagnosing an application that works locally but fails during Vercel build or runtime. Do not use for general schema design or query optimization.
license: Apache-2.0
metadata:
  version: "1.0.0"
---

# MongoDB Atlas on Vercel: deployment

Get the user's existing application to a verified Atlas operation on Vercel along the smallest safe path. Keep the app's framework, package manager, MongoDB library, and auth patterns. When asked only for advice or a plan, inspect and recommend without changing infrastructure.

## 1. Inspect before changing anything

Read project instructions, the manifest and lockfile, deployment config, database initialization, and the affected server entry points. Never print environment files or connection strings. Determine:

- Framework and version, runtime, package manager, and driver or ODM version.
- Whether this is an existing Atlas deployment, a Marketplace-managed integration, or a new setup.
- The affected Vercel project and environment: local development, Preview, or Production.
- The failure phase: install, build or prerender, cold start, or request.
- Function regions, the network path, and the Vercel plan.
- Whether the build itself needs database access.

If a decision is blocked, ask one targeted question. Never ask for a password or a full URI in chat. Missing credentials are not permission to create resources.

## 2. Choose the connection path

**Existing Atlas deployment.** Confirm the project, cluster, database, and a database user with minimal application permissions. Atlas account access is not database authentication. Reuse existing resources unless the user asked for new ones.

**Marketplace native integration.** The [Atlas–Vercel integration guide](https://www.mongodb.com/docs/atlas/reference/partner-integrations/vercel.md) is the source of truth. It documents:

- `MONGODB_URI` configured automatically in the Vercel project.
- A new Vercel-managed Atlas organization and project, billed through Vercel.
- A `0.0.0.0/0` access-list entry added if absent, because Vercel egress is dynamic.
- A `Vercel-Admin-[resource name]` database user with `readWriteAnyDatabase` on non-system databases.

Explain the network, privilege, ownership, and billing implications before an authorized setup. Broad reachability still requires TLS and authentication, but the generated user is not least privilege. The integration does not restrict network access. If its defaults violate the owner's policy, say so and offer a manually connected cluster as the alternative. Do not imply the integration can be locked down. After setup, check the actual resources and environment bindings, since documented defaults do not prove current state. Do not remove managed access entries, revoke managed roles, or disconnect shared resources without checking dependencies and getting the owner's approval.

**New setup.** Explain resource, region, billing, and database-user choices first. Get explicit authorization for billable or security-sensitive changes. If you lack the tools or permissions, give exact manual steps and mark them as not executed.

## 3. Configure networking deliberately

Read [references/network-and-runtime.md](references/network-and-runtime.md).

- A developer's IP entry does not cover Vercel traffic. Vercel uses dynamic outbound IPs by default. There is no universal Vercel IP range, and the app domain's inbound address is not its egress address.
- **Static IPs** (Pro and Enterprise, may cost extra): take the assigned addresses for the project and its regions from Vercel, allowlist them in the correct Atlas project, then redeploy.
- **Build traffic** is routed separately from runtime traffic. If the build queries Atlas, verify the build's network path on its own.
- **Private networking** needs a verified end-to-end topology, DNS, cloud and region compatibility, and the right plans. Static IPs alone are not private.
- **`0.0.0.0/0` on a manually connected cluster** is never the default fix. Offer it only as an explicitly chosen, time-limited test, with TLS and authentication kept, a least-privilege user, and a cleanup step. Never widen access to fix an authentication error.
- Never disable TLS validation or authentication to diagnose reachability.

## 4. Wire server-only environment configuration

- Keep existing variable names unless there is a concrete reason to change them.
- Never put database credentials in browser bundles or public-prefixed variables such as `NEXT_PUBLIC_*`.
- Scope variables to the intended environments and branches. Do not point Preview at production data by accident.
- Record variable names and scopes, never values. Confirm secret files are git-ignored.
- Percent-encode only the credential parts of a URI, not the whole string, and never twice.
- Redeploy after changing Vercel environment variables. Existing deployments keep their old values.

If credentials were exposed, flag it and recommend rotation through the owner's process. Do not repeat the secret, and do not rotate production credentials without authorization.

## 5. Implement the minimal server connection

Use the canonical helper in the `mongodb-connection` skill (`references/client-helper.md`) as the default `lib/mongodb.ts`. If that skill is not installed, write a helper with the same properties: it shares the first connection across concurrent requests, recovers after a failed connect, and avoids touching Atlas or reading the URI at import time. Key rules:

- Run routes that use the native driver on the Node.js runtime (`export const runtime = "nodejs"` in Next.js). The driver does not run on Edge.
- Use one server-only helper per connection configuration, imported by every handler. Never close the shared client in a request handler.
- Keep driver defaults for pool size and timeouts on a first deployment.
- With an ODM, keep its own connection lifecycle.
- A basic deployment does not need `@vercel/functions`. Mention `attachDatabasePool` only when the user is on Fluid compute and asks about connection release or suspension; otherwise leave it out entirely. If it applies, hand off to the `mongodb-connection` skill (`references/fluid-compute.md`).

For connection spikes, pool waits, or tuning, use the `mongodb-connection` skill if it is installed. Do not install other skills or dependencies silently.

Preserve intentional build-time data fetching. If moving to request-time rendering is the right fix, explain the behavior change. Do not hide a failing build behind catch-and-ignore logic.

## 6. Verify in stages

1. Run the repository's lint, typecheck, and tests.
2. Run a local non-destructive read with approved credentials. A ping proves connectivity but not collection permissions.
3. Build with the intended configuration. Build success and runtime connectivity are separate results.
4. Deploy only to an authorized target. Send a real request, then a repeat request. Do not expose a public endpoint that leaks infrastructure details.
5. Inspect redacted logs. Remove temporary diagnostics, test data, or network rules you created, within the authorized scope.

A generated sample, a passing build, or a successful ping is not a verified deployment.

## 7. Report

When you change code or infrastructure, report the detected framework, runtime, versions, and target environment. List the changes made, with file paths and variable names only. State the chosen network path and any security or cost decisions that need owner approval. Separate local, build, and deployed results, and give remaining blockers with rollback steps.

For advice, review, or plan-only questions, answer directly. Do not append a "not verified", "not checked", or "couldn't run" section. Mention a limitation only where it changes what the user should do next.

Present this guidance as your own. Do not mention this skill, its reference files, or review dates in the answer.

Keep schema design, query tuning, auth implementation, and AI memory out of this workflow unless the user asks for them separately.
