# Ephemeral Atlas Clusters: How to provision and hand off

**Important:** Ephemeral Clusters are in Public Preview. Treat the
[Create an Ephemeral Cluster documentation](https://dochub.mongodb.org/core/create-ephemeral-cluster) as the source of truth for current behavior and limitations.

## API contract

Base URL: `https://cloud.mongodb.com`.

No authentication on either endpoint.

### Create a cluster

```http
POST /api/atlas/v2/unauth/ephemeralClusters:create
Accept: application/vnd.atlas.preview+json     <-- REQUIRED, exact version
Content-Type: application/json

{ "clusterName": "optional-name" }     // body optional; omit to default to Cluster0
```

Success is `201` with this body:

```json
{
  "connectionString": "mongodb+srv://<user>:<pass>@cluster0.example.mongodb.net/",
  "clusterId": "65f1a2b3c4d5e6f7a8b9c0d1", // use for status checks
  "claimUrl": "https://account.mongodb.com/account/register?claimId=<id>",
  "status": "PROVISIONING", // PROVISIONING | ACTIVE
  "expiresAt": "2026-05-29T15:46:00Z", // when it PAUSES if unclaimed (~48h after creation); NOT the deletion time
  "termsOfService": "..." // agreement implied by provisioning
}
```

Error responses:

- `400` — invalid `clusterName`.
- `429` — two distinct cases, handle differently (see "When provisioning is refused").
- `500` — server error.

### Check cluster status

```http
GET /api/atlas/v2/unauth/ephemeralClusters/{clusterId}
```

Returns the same field set as create, with one difference: **the `connectionString` password is redacted to a placeholder.** Only the create response carries the real one.

`200` ok, `404` not found / missing id, `429`, `500`.

## Provision

1. POST the create endpoint above.

   Include `clusterName` only if the user named it.

   Save the response body to a file outside the project (for example `curl -o "$TMPDIR/ec-create.json"`) instead of printing it. It holds the only copy of the real password; the status endpoint redacts it.

2. Read `clusterId`, `claimUrl`, `status`, and `expiresAt` from that file. Never print `connectionString` or the whole file, including when a command fails. Pass the connection string from the file straight into the env file in step 4.

3. Check `status`.

   If it's `ACTIVE`, continue.

   If it's `PROVISIONING` (or `PAUSED`), the cluster isn't connectable yet — poll `GET /ephemeralClusters/{clusterId}` (the status endpoint above) until `status` is `ACTIVE`, waiting a few seconds between checks.

   Don't loop indefinitely: if it hasn't gone `ACTIVE` after 10 seconds, tell the user it's still provisioning and stop rather than hammering the endpoint.

   Treat `429` and `500` from the status check the same as elsewhere — don't retry a `429` without a `retry-after`.

4. Write the connection string into the project's env file.

   Before writing, confirm that env file is git-ignored — check `.gitignore` (and that the file isn't already tracked); if it isn't ignored, add it, since you're writing a live credential to disk.

   For the variable name, match what the project already uses: grep the codebase / existing env file for an existing MongoDB URI variable (e.g. `MONGODB_URI`, `MONGO_URL`, `DATABASE_URL`) and reuse it; if there's none, default to `MONGODB_URI`.

   Read the file first and preserve existing values — do not overwrite.

   Put the claim URL and `expiresAt` as comments directly above it so they survive after the chat ends. Also, give the user the claim URL in your reply.

5. Connect using the user's existing driver, or the MongoDB MCP server if that's their setup.

6. Confirm the connection works: `mongosh "$MONGODB_URI" --eval 'db.runCommand({ ping: 1 })'` (`{ ok: 1 }` means good), then start building.

## Tell the user these things (do not skip)

- **The deadline.** There are two distinct moments, so don't conflate them: the cluster **pauses** at `expiresAt` (~48h from creation) and becomes inaccessible until claimed, then if still unclaimed it is **deleted 7 days after creation** (roughly 5 days after it pauses).

  `expiresAt` is the pause time, not the deletion time.

  State both plainly and early, and tell them to claim to keep their work.

  Claiming any time before deletion (including while paused) recovers the cluster and everything in it.

- **The open-network risk.** The cluster is reachable from anywhere on the internet until it is claimed.

  Do not put real, sensitive, or production data in it before claiming.

  Claiming is what closes off open access.

- **Don't leak the credentials.** The connection string embeds a database username and password, and the claim URL grants access.

  Tell the user not to commit either to version control or share them publicly.

## Claiming (the hand-off)

Surface the `claimUrl` and tell the user to open it.

They register or log in, and the cluster transfers into their own Atlas org; a paused cluster resumes automatically on claim.

Work built during the window (collections, documents, indexes) is preserved.

If a claim fails, they can retry from the same URL.

Two limitations to note upfront:

- The organization selector shows only organizations for which the user already has the Organization Owner role.
- Users in federated organizations can claim an ephemeral cluster into an organization only if they have the Organization Owner role.

## When provisioning is refused (the two 429s)

- **Hourly cap reached** — the `429` has **no** `retry-after` header.

  Do not retry; fall back to guiding the user through standard Atlas registration instead.

- **Per-IP rate limit** — the `429` **includes** a `retry-after` header.

  Wait as instructed, then retry once.

Never loop-retry the endpoint.

## Fixed constraints (don't offer choices the feature doesn't have)

Ephemeral clusters are always the free tier on AWS in us-east-1, one per request.

Do not offer region, provider, or tier selection on this path — those can be configured after claiming, via the normal paid-cluster flow.
