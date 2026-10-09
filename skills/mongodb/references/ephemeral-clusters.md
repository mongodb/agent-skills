# Ephemeral Atlas Clusters: How to provision and hand off

**Important:** Ephemeral Clusters are in Public Preview. Treat the
[Create an Ephemeral Cluster documentation](https://www.mongodb.com/docs/atlas/tutorial/create-ephemeral-cluster.md?utm_source=agent-skills) as the source of truth for current behavior and limitations.

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

2. Read `clusterId`, `claimUrl`, `status`, and `expiresAt` from that file. Never print `connectionString` or the whole file, including when a command fails. Pass the connection string from the file straight into the env file in step 3.

3. Write the connection string into the project's env file now, before checking status. The saved response is the only copy of the password.

   Before writing, confirm that env file is git-ignored — check `.gitignore` (and that the file isn't already tracked); if it isn't ignored, add it, since you're writing a live credential to disk.

   For the variable name, match what the project already uses: list the variable names in the existing env file (`cut -d= -f1 <env file>`) and grep the codebase for an existing MongoDB URI variable (e.g. `MONGODB_URI`, `MONGO_URL`, `DATABASE_URL`) and reuse it; if there's none, default to `MONGODB_URI`.

   Do not read the env file's values. If the variable name is already in the file, ask the user whether to replace that entry or use a different name before writing anything. Otherwise, append the new entry with `>>`, starting with a newline in case the file doesn't end with one; do not overwrite the file.

   Write the value in double quotes, so an `&` in its query string survives when the file is loaded. Put the claim URL and `expiresAt` as comments directly above it so they survive after the chat ends.

   Give the user the claim URL in your reply. Then delete the saved response file.

4. Check `status`.

   If it's `ACTIVE`, continue.

   If it's `PROVISIONING`, the cluster isn't connectable yet — poll `GET /ephemeralClusters/{clusterId}` (the status endpoint above) every few seconds until `status` is `ACTIVE`.

   Don't loop indefinitely: if it hasn't gone `ACTIVE` after 10 seconds, tell the user it's still provisioning, that the connection string is already saved in the env file, and that you can verify the connection when they're ready. Then stop.

   Treat `429` and `500` from the status check the same as elsewhere — don't retry a `429` without a `retry-after`.

5. Connect using the user's existing driver, or the MongoDB MCP server if that's their setup.

6. Confirm the connection works with the ping in [Get connected](../SKILL.md#get-connected), then start building.

   If the ping fails, wait a few seconds and retry once. If it still fails, report the error without printing the connection string, give the user the claim URL, and stop rather than looping.

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
