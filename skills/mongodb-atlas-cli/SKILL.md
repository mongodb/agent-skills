---
name: mongodb-atlas-cli
description: >-
  Use the MongoDB Atlas CLI (`atlas`) to interact with MongoDB Atlas from the terminal:
  install and authenticate the CLI, then run commands against Atlas resources
  (clusters, projects, users, network access, data migration, etc.).
compatibility: >-
  Requires the Atlas CLI and a shell. Cloud operations need Atlas auth.
  Local Atlas clusters need Docker.
---

# MongoDB Atlas CLI

Use the MongoDB Atlas CLI (`atlas`) to interact with MongoDB Atlas from the terminal. Complete `## Set up CLI` before running any other section. Full CLI docs: https://www.mongodb.com/docs/atlas/cli/current/index.md.

> When unsure about a command or flag, run `atlas <command> --help` instead of guessing.

> When navigating to CLI documentation, you can append `.md` to the URL to get the markdown version of the page.

> Append `--output json` for the full field set in machine-parseable form

## What you can do with the Atlas CLI

Run `atlas -h` to see all top-level commands. Broadly, they cover:

- **Account & CLI setup** — `auth` (login / service account), `config` (profiles), `setup` (end-to-end onboarding), `completion` (shell autocompletion), `plugin` (extend the CLI).
- **Orgs, projects, and access** — `organizations`, `projects`, `users` (Atlas console users), `teams`, `dbusers` (database users), `customDbRoles`, `accessLists` (IP allowlist), `federatedAuthentication`.
- **Clusters & deployments** — `clusters` (cloud clusters, incl. search/stream/online-archive subresources), `local` (local Atlas deployments via Docker), `processes`, `accessLogs`, `backups`, `maintenanceWindows`.
- **Networking & security** — `networking` (VPC/peering), `privateEndpoints`, `customDns`, `cloudProviders` (AWS IAM roles), `security`, `auditing`, `integrations` (Slack, PagerDuty, etc.).
- **Observability** — `alerts`, `events`, `metrics`, `logs`, `performanceAdvisor`.
- **Data movement & advanced workloads** — `liveMigrations` (migrate into Atlas), `dataFederation`, `streams` (Atlas Stream Processing), `kubernetes` (Atlas Kubernetes Operator resources).
- **Escape hatch** — `api <tag> <operationId>` exposes the full Atlas Administration API for anything not covered by a first-class subcommand.

Use `atlas <command> --help` to drill into a specific area (e.g., `atlas clusters --help`, `atlas api --help`).

## Set up CLI

### Install CLI

Check whether the CLI is already installed:

```bash
atlas --version
```

If it prints a version (e.g., `atlascli version: 1.53.2`), skip to `### Authenticate CLI`. Otherwise, install via the user's OS package manager:

| OS | Command |
| --- | --- |
| macOS / Linux (Homebrew) | `brew install mongodb-atlas` |
| Debian / Ubuntu (Apt) | `sudo apt-get install -y mongodb-atlas` (after adding MongoDB's apt repo) |
| RHEL / CentOS / Amazon Linux (Yum) | `sudo yum install -y mongodb-atlas` (after adding MongoDB's yum repo) |
| Windows (Chocolatey) | `choco install mongodb-atlas` |

For repo setup details and manual binary downloads, see https://www.mongodb.com/docs/atlas/cli/current/install-atlas-cli.md.

### Authenticate CLI

> **Skip this section if you're only using local clusters.** `atlas local` deployments run against Docker on the user's machine and don't hit the Atlas Admin API, so they don't need authentication. You'll need to authenticate for anything that touches cloud Atlas — `clusters`, `projects`, `dbusers`, `accessLists`, etc.

1. Check current auth state:

    ```bash
    atlas auth whoami
    ```

    - **Exit 0** (e.g., `Logged in as <email> account`) → authenticated; proceed.
    - **Exit 1** (`Error: not logged in with an Atlas account, Service Account or API key`) → continue to step 2.

2. **Hand authentication off to the user.** `atlas auth login` and `atlas auth register` are **interactive** and will block a non-interactive shell — do not run them from the agent. Instead, instruct the user to pick one:

    - **Interactive login** (one-time, for their own use): tell them to run `atlas auth login` themselves and follow the browser prompts.
    - **Programmatic auth** (recommended for agent-driven workflows): tell them to create an Atlas Service Account (see https://www.mongodb.com/docs/atlas/configure-api-access.md) and export these in their shell profile:

      ```bash
      export MONGODB_ATLAS_CLIENT_ID="<client_id>"
      export MONGODB_ATLAS_CLIENT_SECRET="<client_secret>"
      ```

      Once set, `atlas` commands authenticate automatically with no prompts. For the full list of available environment variables, see https://www.mongodb.com/docs/atlas/cli/current/atlas-cli-env-variables.md.

3. Confirm auth works by running `atlas projects list` (exit 0). `atlas auth whoami` only checks that auth is configured, not that credentials are valid — if `projects list` fails with `Forbidden`, send the user back to step 2.

> **Never handle credentials directly.** Don't prompt the user to paste credentials into chat, don't run `atlas auth login` or `atlas auth register` yourself, and don't write credentials to files on their behalf. The user adds env vars to their own shell profile or runs the interactive login in their own terminal.

### Select Project and Organization

Most `atlas clusters` commands require `--projectId`, and some require `--orgId`. After authenticating, establish a default project (and org) so the agent doesn't have to pass these flags on every command.

1. Discover the user's orgs and projects. Both commands are read-only and stateless:

    ```bash
    atlas orgs list
    atlas projects list
    ```

    Each prints an `ID   NAME` table. Append `--output json` for machine-parseable output. To scope projects to a specific org: `atlas projects list --orgId <orgId>`.

    > If the user has exactly one org and one project, just use those. If they have several, confirm which one they want — don't guess.

2. Instruct the user to set defaults in their shell profile (same hand-off pattern as auth — the agent doesn't edit shell profiles):

    ```bash
    export MONGODB_ATLAS_ORG_ID="<orgId>"
    export MONGODB_ATLAS_PROJECT_ID="<projectId>"
    ```

    Once set, `atlas` commands use these as defaults. `--orgId` / `--projectId` passed on a specific command still override them.

> **Need a new project?** Run `atlas projects create <name> --orgId <orgId>`. A new project is sometimes required — e.g., M0 (free-tier) clusters are limited to one per project (see the M0 caveats under `### Create cloud cluster`).

> **Profiles as an alternative to env vars.** `atlas config set <prop> <value>` persists settings across sessions (e.g., `atlas config set project_id <id>`, `atlas config set org_id <id>`). Useful when the user juggles multiple Atlas accounts or environments — create named profiles and target with `--profile <name>` on any `atlas` command. Use `atlas config list` / `atlas config describe <name>` to inspect. **Avoid `atlas config edit`** — it opens `$EDITOR` and blocks the shell.

## Cluster Management

The project defaults to `MONGODB_ATLAS_PROJECT_ID` or the active profile; override per-command with `--projectId <id>`.

### List Clusters

List all clusters in the current project:

```bash
atlas clusters list
```

Useful flags:

- `--tier <value>` — filter by exact tier (e.g., `FLEX`, `M0`, `M10`, `M30`).
- `--autoScalingMode independentShardScaling` — clusters with per-shard scaling only.
- `--page <n>` / `--limit <n>` — pagination (default 100 per page, max 500).

> **For details beyond the list.** Run `atlas clusters describe <clusterName>` for the full cluster spec, or `atlas clusters connectionStrings describe <clusterName>` for the SRV connection string. Both are stateless and agent-safe.

### Create Cluster

Two flavors: **local** (Docker-backed `atlas local` deployments, for dev/testing) and **cloud** (hosted Atlas clusters via `atlas clusters create`). Pick based on the user's goal:
1. Local is free and offline-capable
2. Cloud is required for anything production-like, shared access, or Atlas-only features at scale.

#### Create Local Cluster

> Requires Docker installed and running. Local deployments do **not** count against Atlas project quotas and do not need Atlas auth.

Provision a local MongoDB Atlas deployment:

```bash
atlas local setup <deploymentName> --force --connectWith connectionString
```

`--force` skips the interactive confirmation prompt. `--connectWith` picks the post-setup connection method; without it, the CLI prompts — use `connectionString` for agent-driven workflows (alternatives: `mongosh`, `compass`, `vscode`).

Useful flags:

- `--mdbVersion <version>` — e.g., `8`, `8.2`, `8.2.1`, or `latest` (default is latest stable).
- `--port <n>` — host port the deployment listens on. Pick an unused port if running multiple local deployments.
- `--bindIpAll` — bind to all interfaces instead of `127.0.0.1` (needed if another container or remote host needs to reach it).
- `--username <name>` / `--password <value>` — create an initial database user. Omit for no-auth local dev.
- `--loadSampleData true` — preload the Atlas sample datasets.
- `--image <ref>` / `--skipPullImage` — override the default `mongodb/mongodb-atlas-local` image, or reuse a cached one.

List, inspect, and connect:

```bash
atlas local list
atlas local connect <deploymentName> --connectWith connectionString
```

> **Lifecycle.** `atlas local start|stop|delete <deploymentName>` manage the underlying containers. `atlas local logs <deploymentName>` tails deployment logs. Run `atlas local <subcommand> --help` for each.

#### Create Cloud Cluster

> Requires authentication. See [Authenticate CLI](#authenticate-cli) for more information.

Provision a cloud Atlas cluster in the current project. Quick form for a default three-member replica set:

```bash
atlas clusters create <clusterName> \
  --provider AWS \
  --region US_EAST_1 \
  --tier M10 \
  --mdbVersion 8.0 \
  --diskSizeGB 10
```

Returns immediately after the API accepts the request (status `CREATING`); provisioning continues in the background.

> **Don't use `--watch`.** M10/FLEX clusters take ~7–10 min to reach `IDLE` — too long for an agent turn. Check status with `atlas clusters describe <clusterName> --output json` (one-shot) or hand off `atlas clusters watch <clusterName>` to the user if they want to block. Anything depending on the cluster (db users, seeding, connection tests) must wait for ready state.
>
> Ready when `stateName == "IDLE"` **and** `connectionStrings.standardSrv` (or `.standard`) is populated. While provisioning, `stateName` is `CREATING` and connection strings are empty. Other states you may see: `UPDATING` (config change in progress, cluster usable), `REPAIRING`, `DELETING`, `DELETED`.

Required (unless using `--file`):

- `--provider` — `AWS`, `AZURE`, or `GCP`.
- `--region` — provider-specific region code (e.g., `US_EAST_1` for AWS, `EASTERN_US` for GCP, `US_EAST_2` for Azure). Full lists: https://dochub.mongodb.org/core/aws-atlas, https://dochub.mongodb.org/core/azure-atlas, https://dochub.mongodb.org/core/gcp-atlas.

Commonly useful flags:

- `--tier <value>` — instance size. Defaults to `FLEX` if omitted. Valid tiers include `M0` (free), `FLEX`, `M10`, `M20`, `M30`, etc. Note: `M2` / `M5` are deprecated and silently remapped to `FLEX`.
- `--mdbVersion <major>` — e.g., `7.0`, `8.0`. Defaults to the latest stable.
- `--diskSizeGB <n>` — root volume size (default 2).
- `--members <n>` — replica set size (default 3).
- `--type REPLICASET|SHARDED` / `--shards <n>` — for sharded clusters.
- `--autoScalingMode clusterWideScaling|independentShardScaling` — per-shard scaling for sharded deployments.
- `--backup` — enable Continuous Cloud Backup (M10+ only).
- `--enableTerminationProtection` — require disabling protection before `atlas clusters delete` will succeed.
- `--tag key=value` — attach tags (repeatable).
- `--file <path>` — use a JSON cluster spec for advanced or multi-cloud configs (https://dochub.mongodb.org/core/cluster-config-file-atlascli). When `--file` is set, most other flags are ignored.

Requires a Project Owner role on the target project.

> **Free tier (M0) caveats.** Creating an M0 cluster uses the same command as paid tiers, just with `--tier M0` (and typically `--provider` + `--region` restricted to the free-tier-supported set). Keep in mind:
>
> - **One M0 per project.** If the project already has an M0, creation will fail — either reuse it or create the cluster in a different project.
> - **Limited regions and providers.** Only a subset of regions support M0; surface a clear error to the user if their requested region isn't supported rather than silently picking a different one.
> - **No backup, no dedicated resources, shared CPU/RAM.** Don't recommend M0 for anything beyond learning/prototyping.
> - **Upgrade uses a different subcommand.** M0 → M10+ is in place but requires `atlas clusters upgrade <clusterName>`, not `atlas clusters update`. The upgrade incurs **downtime** during the tier change, starts billing, and is **one-way** — you can't scale back down from M10+ to M0 or FLEX.

### Modify Cluster

Day-2 changes go through one of three commands, depending on the cluster type and the setting:

- `atlas clusters update <clusterName>` — **dedicated (M10+)** clusters. Flag-driven: `--tier`, `--diskSizeGB`, `--mdbVersion`, `--tag`, `--autoScalingMode`, `--enableTerminationProtection` / `--disableTerminationProtection`. For changes that aren't expressible as a flag (provider/region, multi-region topology, replica set → single-shard), pass `--file cluster-config.json` (https://dochub.mongodb.org/core/cluster-config-file-atlascli — unsupported fields are silently ignored).
- `atlas clusters upgrade <clusterName>` — **shared (M0/FLEX)** clusters. Same flag set minus sharding knobs. Moving out of shared into M10+ incurs downtime and is one-way (see the M0 upgrade note under `#### Create Cloud Cluster`).
- `atlas clusters advancedSettings update <clusterName>` — engine-level tunables: `--oplogSizeMB`, `--oplogMinRetentionHours`, `--readConcern`, `--writeConcern`, `--tlsProtocol`, `--enableJavascript` / `--disableJavascript`, `--enableTableScan` / `--disableTableScan`. M10+ only.

Rules to surface to the user before running any modify command:

- **Cluster name is immutable.** No rename.
- **MongoDB major version cannot be downgraded** unless FCV was pinned before the upgrade.
- **M10+ cannot be scaled back down to M0 or FLEX.** One-way.
- **Rolling updates are the default** — Atlas cycles through replica set members one at a time; `stateName` goes to `UPDATING` and the cluster stays available throughout.
- **Expect downtime or an initial sync** for: shared → dedicated tier changes, cross-region or cross-provider moves, NVMe ↔ general-storage transitions, and customer KMS changes. Initial-sync time scales with data size.

Run `atlas clusters update --help` (or `upgrade --help` / `advancedSettings update --help`) for the exact flag set shipped with the installed CLI — the set grows over time.

### Pause and Resume

**M10+ only.** While paused, only storage is billed (no compute/transfer); reads, writes, backups, alerts, and `$search` all stop. Search Nodes are rebuilt on resume.

```bash
atlas clusters pause <clusterName>
atlas clusters start <clusterName>
```

Surface to the user: **30-day cap** (Atlas auto-resumes and billing restarts), **60-min minimum uptime** before re-pausing, can't pause if disk >95% or NVMe storage. Requires `Project Cluster Manager` role.

- **M0:** no manual pause — Atlas auto-pauses after 30 days idle and resumes on connect.
- **FLEX:** not supported; delete and recreate instead.

## Delete Cluster

### Delete Cloud Cluster

```bash
atlas clusters delete <clusterName> --force
```

`--force` skips the interactive confirm. Requires `Project Owner`. Deletion is permanent: data, backup snapshots, and unique tags are all removed. If `atlas clusters describe` shows `terminationProtectionEnabled: true`, disable first with `atlas clusters update <clusterName> --disableTerminationProtection`.

> **Don't pass `--watch`.** Deletion takes several minutes. Poll with `atlas clusters describe <clusterName>` — errors once gone.

### Delete Local Cluster

```bash
atlas local delete <deploymentName> --force
```

Removes the container **and the local data volume** — no undo.

## Migrate Cluster

Data movement between deployments. In-place changes (scale, pause, provider/region, version) belong in `### Modify Cluster` — clarify intent, since users often call those "migrations."

Migrations are multi-step and have tight prerequisites (source type, version, network, destination tier). Don't improvise — point the user at the right docs and run commands from there:

- **Push live migration** (source monitored in Cloud Manager / Ops Manager) — the CLI drives this via `atlas liveMigrations`. Docs: https://www.mongodb.com/docs/atlas/import/c2c-push-live-migration.md.
- **Pull live migration** (arbitrary self-managed source, reachable over public IP) — Atlas UI-driven, not CLI. Docs: https://www.mongodb.com/docs/atlas/import/c2c-pull-live-migration.md.
- **Scripted / private-network migrations** — use `mongosync` (https://www.mongodb.com/docs/mongosync/current.md) or `mongomirror` (https://www.mongodb.com/docs/atlas/reference/mongomirror.md).
- **Small datasets or downtime OK** — `mongodump` + `mongorestore`.
- **Local → cloud promotion** — no in-place path. Create the cloud cluster (`#### Create Cloud Cluster`), then move data with one of the options above.

General migration docs: https://www.mongodb.com/docs/atlas/import.md.

> **Destination constraint across all paths:** M0 and FLEX are not valid destinations for live migration — the destination must be M10+.