# Ephemeral Atlas Clusters: How to provision and hand off

**Important:** Ephemeral Clusters are in Public Preview. Treat the
[Create an Ephemeral Cluster documentation](https://www.mongodb.com/docs/atlas/tutorial/create-ephemeral-cluster.md?utm_source=agent-skills) as the source of truth for current behavior and limitations.

## Before you create anything

However you reached this file, do these steps first. Skip them only if the user has already said yes to your question in [SKILL.md step 2](../SKILL.md#2-recommend-deployment-by-goal). If the request itself gives an explicit go-ahead to create ("go ahead, you have my go-ahead"), do step 1 and the disclosures in step 2, skip the question, and create.

1. Run the existing-deployment check in [SKILL.md step 1](../SKILL.md#1-check-for-an-existing-deployment), and tell the user which variables are set, by name only.
2. Tell the user what an Ephemeral cluster is: in Public Preview; temporary and claimable; pauses about 48 hours after creation; deleted 7 days after creation unless claimed; open to the internet until claimed, so no real or sensitive data. Then ask once whether to create it.
3. Stop and wait for the answer. Create nothing before it.

A request that names an Ephemeral cluster ("spin me up an ephemeral cluster"), urgency, or "don't ask me anything" is not a yes.

## API contract

Base URL: `https://cloud.mongodb.com`.

No authentication on either endpoint.

### Create a cluster

```http
POST /api/atlas/v2/unauth/ephemeralClusters:create
Accept: application/vnd.atlas.preview+json     <-- REQUIRED, exact version
Content-Type: application/json

{ "clusterName": "optional-name" }     // body required: send {} to default to Cluster0
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

- `400` — invalid `clusterName`, or no body (`INVALID_JSON`): send `{}`.
- `429` — two distinct cases, handle differently (see "When provisioning is refused").
- `500` — server error.

### Check cluster status

```http
GET /api/atlas/v2/unauth/ephemeralClusters/{clusterId}
Accept: application/vnd.atlas.preview+json     <-- REQUIRED, exact version
```

Returns the same field set as create, with one difference: **the `connectionString` password is redacted to a placeholder.** Only the create response carries the real one.

`200` ok, `404` not found / missing id, `429`, `500`.

## Provision

1. Confirm the project's env file is git-ignored: check `.gitignore`, and that the file isn't already tracked. If it isn't ignored, add it, since a live credential is about to be written to it.

   If the project has no env file, use `.env.local` for a framework that loads it automatically (Next.js, Vite), and `.env` otherwise, since plain `dotenv` reads only `.env`. Add it to `.gitignore` before the script creates it.

2. Pick the variable name. List the MongoDB variable names the code and env files use (this prints names only, never values):

   ```bash
   grep -rIhoE '\b(MONGO(DB)?_UR[IL]|DATABASE_URL|MDB_MCP_CONNECTION_STRING)\b' --exclude-dir={.git,node_modules,dist,build,.next,.venv} . | sort -u
   ```

   Combine that with the names the SKILL.md step 1 check found, then choose:

   - One of `MONGODB_URI`, `MONGO_URI`, `MONGO_URL`, or `MONGODB_URL`: use it.
   - Several of those: ask the user which one the app reads.
   - Only `DATABASE_URL`: use it only if the project's database is MongoDB (a MongoDB driver or ODM in its dependencies, and no other database's). Otherwise it likely points at another database, so use `MONGODB_URI` and tell the user the app must read that name.
   - None: use `MONGODB_URI`.

   Don't list or read the env file any other way.

3. Create the cluster with [scripts/create-ephemeral.sh](../scripts/create-ephemeral.sh), never with a hand-written `curl`:

   ```bash
   bash <this skill's directory>/scripts/create-ephemeral.sh <env file> <variable name> [clusterName]
   ```

   Pass `clusterName` only if the user named it. The create response holds the only copy of the real password (the status endpoint redacts it), so the script writes the connection string to the env file in double quotes, under a `# ephemeral-cluster: var=… claimUrl=… expiresAt=…` comment. It prints only `clusterId`, `claimUrl`, `status`, and `expiresAt`. Never read the env file afterwards, and never print the connection string.

   Every run except exits 2 and 3 sends a create request, and counts toward the limit in [When provisioning is refused](#when-provisioning-is-refused-the-two-429s).

   - **Exit 3:** the variable is already in the env file, and nothing was sent. Ask the user whether to replace that entry or use a different name. To replace it, rerun with `--replace` as the first argument; the script removes the old entry itself. Never edit the env file by hand.
   - **Exit 2:** nothing was sent. `jq` is missing, an argument is invalid, or the env file isn't writable. Tell the user what to fix; don't call the endpoint yourself.
   - **Exit 1:** no `201`. The script prints the HTTP status with the API's error code and detail, or a curl network error. Handle a `429` as in [When provisioning is refused](#when-provisioning-is-refused-the-two-429s). For a `400`, tell the user why the name was rejected; for anything else, report the error and don't retry. After a network error the cluster may exist anyway, so don't retry.
   - **Exit 4:** the cluster was created, but the connection string couldn't be saved, and the password is lost. Don't create another. Give the user the printed claim URL: after claiming, they can set a new database user password in Atlas.

   Give the user the claim URL in your reply.

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

  Advise them not to put real, sensitive, or production data in it before claiming. If they want to anyway, that's their decision: don't refuse, and don't switch them to another deployment.

  Claiming is what closes off open access.

- **Don't leak the credentials.** The connection string embeds a database username and password, and the claim URL grants access.

  Tell the user not to commit either to version control or share them publicly.

## Claiming (the hand-off)

Surface the `claimUrl` and tell the user to open it. For a cluster created earlier, the claim URL and `expiresAt` are in the marker comment above its variable in the env file; `grep -H '^# ephemeral-cluster:' .env* 2>/dev/null` prints only those lines, with the file each is in and, in `var=`, the variable each belongs to. Don't print other comment lines: they can hold commented-out credentials.

They register or log in, and the cluster transfers into their own Atlas org; a paused cluster resumes automatically on claim.

Work built during the window (collections, documents, indexes) is preserved.

If a claim fails, they can retry from the same URL.

Two limitations to note upfront:

- The organization selector shows only organizations for which the user already has the Organization Owner role.
- Users in federated organizations can claim an ephemeral cluster into an organization only if they have the Organization Owner role.

## When provisioning is refused (the two 429s)

- **High demand** — the `429` has **no** `retry-after` header.

  Do not retry. Tell the user that Ephemeral clusters are seeing high demand right now and to try again later, and offer to guide them through standard Atlas registration instead. Don't relay the API's error detail or mention a cap or limit.

- **Per-IP rate limit** — the `429` **includes** a `retry-after` header.

  Wait as instructed, then retry once.

Never loop-retry the endpoint. Make at most two create requests in total: the first, and one retry after a `retry-after` wait. Without `retry-after`, the first request is the only one.

## Fixed constraints (don't offer choices the feature doesn't have)

Ephemeral clusters are always the free tier on AWS in us-east-1, one per request.

Do not offer region, provider, or tier selection on this path — those can be configured after claiming, via the normal paid-cluster flow.
