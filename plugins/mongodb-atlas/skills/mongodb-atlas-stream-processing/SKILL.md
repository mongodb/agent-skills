---
name: mongodb-atlas-stream-processing
description: "Manages MongoDB Atlas Stream Processing (ASP) workflows. Handles workspace provisioning, data source/sink connections, processor lifecycle operations, debugging diagnostics, and tier sizing. Supports Kafka, Atlas clusters, S3, HTTPS, and Lambda integrations for streaming data workloads and event processing. NOT for general MongoDB queries or Atlas cluster management. Requires MongoDB MCP Server with Atlas API credentials."
license: Apache-2.0
metadata:
  version: "1.0.0"
  user-invocable: "true"
---

# MongoDB Atlas Streams

Build, operate, and debug Atlas Stream Processing (ASP) pipelines using four MCP tools from the MongoDB MCP Server.

## Prerequisites

This skill requires the **MongoDB MCP Server** connected with:
- Atlas API credentials (`apiClientId` and `apiClientSecret`)

The 4 tools: `atlas-streams-discover`, `atlas-streams-build`, `atlas-streams-manage`, `atlas-streams-teardown`.

**All operations require an Atlas project ID.** If unknown, call `atlas-list-projects` first to find your project ID.

**Read-only mode:** if the MCP server runs with `--readOnly`, only `atlas-streams-discover` works. `build`, `manage`, and `teardown` all fail — do not retry them; explain the restriction and give the user the equivalent Atlas UI or Admin API steps.

## If MCP tools are unavailable

If the MongoDB MCP Server is not connected or the streams tools are missing, see [references/mcp-troubleshooting.md](references/mcp-troubleshooting.md) for diagnostic steps and fallback options.

## Tool Selection Matrix

### atlas-streams-discover — ALL read operations
| Action | Use when |
|--------|----------|
| `list-workspaces` | See all workspaces in a project |
| `inspect-workspace` | Review workspace config, state, region |
| `list-connections` | See all connections in a workspace |
| `inspect-connection` | Check connection state, config, health |
| `list-processors` | See all processors in a workspace |
| `inspect-processor` | Check processor state, pipeline, config |
| `diagnose-processor` | Full health report: state, autoscaling, stats, health warning, DLQ config, pipeline, connection health, recommended actions. **It returns no error log or log lines** — for actual errors use the Atlas UI Logs tab or read the DLQ collection |
| `get-networking` | Project-level PrivateLink endpoints. Optional: `cloudProvider` + `region` to get Atlas account details for PrivateLink setup. **It does not list VPC peerings** — peerings are only accepted/rejected (`manage`) or torn down (`teardown`) |

**Pagination** (all list actions): `limit` (1-100, default 20), `pageNum` (default 1).
**Response format**: `responseFormat` applies only to the list actions (`"concise"` default) and to `inspect-workspace` (`"detailed"` default). `inspect-connection`, `inspect-processor`, and `diagnose-processor` are always detailed: the field is accepted but ignored, not rejected.
**Parameter naming:** `inspect-processor`, `inspect-connection`, and `diagnose-processor` take `resourceName` (not `processorName` or `connectionName`). `workspaceName` is required for all actions except `list-workspaces` and `get-networking`.

### atlas-streams-build — ALL create operations
| Resource | Key parameters |
|----------|---------------|
| `workspace` | `cloudProvider`, `region`, `tier` (default SP10), `includeSampleData` |
| `connection` | `connectionName`, `connectionType` (exact values: `Kafka`/`Cluster`/`S3`/`Https`/`AWSKinesisDataStreams`/`AWSLambda`/`SchemaRegistry`/`Sample`/`GCPPubSub`), `connectionConfig` |
| `processor` | `processorName`, `pipeline` (must start with `$source`, end with a sink stage: `$merge`/`$emit`/`$iceberg`/`$https`/`$externalFunction`), `dlq` (only when the user asks for one), `autoStart`, `processorTier`, `autoscaling` |
| `privatelink` | `privateLinkConfig` (project-level, not tied to a specific workspace) |

**Field mapping — only fill fields for the selected resource type:**

- **resource = "workspace":** Fill: `projectId`, `workspaceName`, `cloudProvider`, `region`, `tier`, `includeSampleData`. Leave empty: all connection and processor fields.
- **resource = "connection":** Fill: `projectId`, `workspaceName`, `connectionName`, `connectionType`, `connectionConfig`. Leave empty: all workspace and processor fields. (See [references/connection-configs.md](references/connection-configs.md) for type-specific schemas.)
- **resource = "processor":** Fill: `projectId`, `workspaceName`, `processorName`, `pipeline`, `dlq` (only when the user asks, or when an `$https`/`$externalFunction` stage needs its default DLQ destination), `autoStart` (optional), `processorTier`/`autoscaling` (optional). Leave empty: all workspace and connection fields. (See [references/pipeline-patterns.md](references/pipeline-patterns.md) for pipeline examples.)
- **resource = "privatelink":** Fill: `projectId`, `privateLinkConfig`. Note: PrivateLink is **project-level**, not workspace-level. `workspaceName` is not required — omit it. Leave empty: all connection and processor fields.

### atlas-streams-manage — ALL update/state operations
| Action | Notes |
|--------|-------|
| `start-processor` | Begins billing. Optional `tier` override (bounded by the workspace `streamConfig.maxTierSize`), `resumeFromCheckpoint` (a **start** parameter, not a modify one), `autoscaling` |
| `stop-processor` | Stops billing. Retains state 45 days |
| `modify-processor` | Works in any state **except** STARTED — CREATED, STOPPED, and FAILED are all modifiable. Change pipeline, DLQ, name, tier, or autoscaling. **Exception:** a pipeline containing an S3 `$emit` stage cannot be modified at all — delete and recreate it |
| `update-workspace` | Change tier or region (`newTier` maps to Admin API `streamConfig.tier`). A region change requires the workspace to have **zero processors** — delete them first |
| `update-connection` | Update config. Auth/credentials are updatable; networking, connection **type**, and **region** are immutable — delete and recreate |
| `accept-peering` / `reject-peering` | VPC peering management |

**Field mapping** — always fill `projectId`, `workspaceName`, then by action:

- `"start-processor"` → `resourceName`. Optional: `tier` (cannot exceed the workspace `streamConfig.maxTierSize`), `resumeFromCheckpoint`, `startAtOperationTime` (an **ISO 8601 string** to resume from a specific point — the tool accepts only a string, so a BSON `Timestamp` object fails validation), `autoscaling`
- `"stop-processor"` → `resourceName`
- `"modify-processor"` → `resourceName`. At least one of: `pipeline`, `dlq`, `newName`, `tier`, `autoscaling`. `resumeFromCheckpoint` is **not** a modify parameter — set it on `start-processor`
- `"update-workspace"` → `newRegion` or `newTier` (Admin API field: `streamConfig.tier`; SPM uses `tier`)
- `"update-connection"` → `resourceName`, `connectionConfig`. Use for auth/credential changes (e.g., Kafka password rotation) — do not delete/recreate. **Exception: networking config (e.g., PrivateLink), the connection type, and the connection's region cannot be modified after creation** — delete and recreate. Verify afterwards with `inspect-connection`.
- `"accept-peering"` → `peeringId`, `requesterAccountId`, `requesterVpcId`
- `"reject-peering"` → `peeringId`

**State pre-checks:**
- `start-processor` → errors if processor is already STARTED
- `stop-processor` → no-ops if already STOPPED or CREATED (not an error)
- `modify-processor` → errors only if processor is STARTED; CREATED, STOPPED, and FAILED are all accepted

**Processor states:** `CREATED` → `STARTED` (via start) → `STOPPED` (via stop). Can also enter `FAILED` on runtime errors. Modify works in any state except STARTED.

**Teardown safety checks:**
- **Processor deletion** → auto-stops before deleting (no need to stop manually first)
- **Connection deletion** → blocks if any running processor references it. Stop/delete referencing processors first.
- **Workspace deletion** → See "Before deleting a workspace" below.

### atlas-streams-teardown — ALL delete operations
| Resource | Safety behavior |
|----------|----------------|
| `processor` | Auto-stops before deleting |
| `connection` | Blocks if referenced by running processor |
| `workspace` | Cascading delete of all connections and processors |
| `privatelink` / `peering` | Remove networking resources |

**Field mapping** — always fill `projectId`, `resource`, then:

- `resource: "workspace"` → `workspaceName`
- `resource: "connection"` or `"processor"` → `workspaceName`, `resourceName`
- `resource: "privatelink"` or `"peering"` → `resourceName` (the ID). These are project-level resources, not tied to a specific workspace.

**Before deleting a workspace**, inspect it first:
1. `atlas-streams-discover` → `inspect-workspace` — get connection/processor counts
2. Present to user: "Workspace X contains N connections and M processors. Deleting permanently removes all. Proceed?"
3. Wait for confirmation before calling `atlas-streams-teardown`

## CRITICAL: Validate Before Creating Processors

**You MUST call `search-knowledge` before composing any processor pipeline.** This is not optional.
- **Field validation:** Query with the sink/source type, e.g. "Atlas Stream Processing $emit S3 fields" or "Atlas Stream Processing Kafka $source configuration". This catches errors like `prefix` vs `path` for S3 `$emit`.
- **Pattern examples:** Query with `dataSources: [{"name": "devcenter"}]` for working pipelines, e.g. "Atlas Stream Processing tumbling window example".

Also fetch examples from the official ASP examples repo when building non-trivial processors: **https://github.com/mongodb/ASP_example** (quickstarts, example processors, Terraform examples). Start with `example_processors/README.md` for the full pattern catalog.

Key quickstarts:
| Quickstart | Pattern |
|-----------|---------|
| `00_hello_world.json` | Inline `$source.documents` with `$match` (no external connection needed) |
| `01_changestream_basic.json` | Change stream → tumbling window → `$merge` to Atlas |
| `03_kafka_to_mongo.json` | Kafka source → tumbling window rollup → `$merge` to Atlas |
| `04_mongo_to_mongo.json` | Chained processors: rollup → archive to separate collection |
| `05_kafka_tail.json` | Real-time Kafka topic monitoring (sinkless, like `tail -f`) |

## Pipeline Rules & Warnings

**`$$ROOT` and `$$CURRENT`** — the ASP engine supports both (they reference the whole current document). MongoDB MCP Server versions through at least v3.3.0 reject any pipeline containing them when **creating a processor with `atlas-streams-build`** ("not available in streaming request"). If your server version does, use explicit field references (e.g. copy fields in `$addFields`), or deploy via `modify-processor` / `atlas api streams createStreamProcessor`, which do not run that validator.

**Invalid constructs** — these are NOT valid in streaming pipelines:
- **`$$NOW`**, **`$$CLUSTER_TIME`**, **`$$USER_ROLES`** — never seeded in ASP; using them throws "Builtin variable ... is not available". Use the document's own timestamp field or `{"$meta": "stream.source.ts"}` for event time instead of `$$NOW`.
- **`$$SEARCH_META`** — spelled with two `$$`, and it does **not** throw: when unset it evaluates to *missing*. ASP has no `$search` stage, so it is effectively always missing — guard any use with `$ifNull`, or omit it.
- **`$where` and `$accumulator`** — always rejected by the engine.
- **`$$ROOT`/`$$CURRENT` when creating via `atlas-streams-build` on MCP server versions through at least v3.3.0** — blocked by the server's validator (see above), even though the engine supports them.
- **`$function` unless the `enableFunctionExpression` feature flag is on** — the engine rejects it when the flag is off, which is the default. Check with the user before relying on it (see [references/pipeline-patterns.md](references/pipeline-patterns.md#function-javascript-udf)).
- **HTTPS connections as `$source`** — HTTPS is for `$https` enrichment or sink only, NOT as a data source
- **Kafka `$source` without `topic`** — topic field is required
- **Pipelines without a sink** — terminal stage (`$merge`, `$emit`, `$iceberg`, `$https`, or `$externalFunction`) required for deployed processors (sinkless only works via `sp.process()`)
- **Lambda as `$emit` target** — Lambda uses `$externalFunction` (mid-pipeline or sink), not `$emit`
- **`$validate` with `validationAction: "error"`** — not supported; only `"discard"` (default) and `"dlq"` are valid

**Required fields by stage:**
- **`$source` (change stream)**: include `config: { fullDocument: "updateLookup" }` to get the full document content (also `config.fullDocumentBeforeChange` for pre-images)
- **`$source` (Kinesis)**: use `stream` (NOT `streamName` or `topic`)
- **`$emit` (Kinesis)**: MUST include `partitionKey`
- **`$emit` (S3)**: use `path` (NOT `prefix`)
- **`$https`**: must include `connectionName`. `path` and `method` (default `GET`) are optional; `as` is required for mid-pipeline enrichment and optional for a sink; set `onError: "dlq"` (the default) to route failures to the DLQ.
- **`$externalFunction`**: must include `connectionName` and `functionName`. `execution` (default `sync`) and `onError` (default `dlq`) are optional. Include `as` for **sync mid-pipeline** stages so the response has somewhere to land; a sync **sink** may omit it. Omit `as` whenever `execution: "async"` — supplying it errors, sink or mid-pipeline.
- **`$validate`**: must include `validator`. `validationAction` defaults to `"discard"`; set `"dlq"` when the user wants rejected documents captured — that also requires a DLQ connection. `validator` accepts **any match expression** (`$jsonSchema`, `$expr`, etc.) — `$jsonSchema` is one option, not a requirement.
- **`$lookup`**: include `parallelism` setting (e.g., `parallelism: 2`) for concurrent I/O. `$externalFunction` has **no** `parallelism` field, and `$source` has none at the top level (only change-stream `initialSync.parallelism`).
- **AWS connections** (S3, Kinesis, Lambda): IAM role ARN must be registered via Atlas Cloud Provider Access first. Always confirm this with user. See [references/connection-configs.md](references/connection-configs.md) for details.

See [references/pipeline-patterns.md](references/pipeline-patterns.md) for stage field examples with JSON syntax.

**SchemaRegistry connection:** `connectionType` must be `"SchemaRegistry"` (not `"Kafka"`). Schema type values are case-sensitive (use lowercase `avro`, not `AVRO`). See [references/connection-configs.md](references/connection-configs.md#schemaregistry) for required fields and auth types.

## MCP Tool Behaviors

**Elicitation:** When creating connections, the build tool auto-collects missing sensitive fields (passwords, bootstrap servers) via MCP elicitation. Do NOT ask the user for these — let the tool collect them.

**Auto-normalization:**
- `bootstrapServers` array → auto-converted to comma-separated string
- `schemaRegistryUrls` string → auto-wrapped in array
- `dbRoleToExecute` → defaults to `{role: "readWriteAnyDatabase", type: "BUILT_IN"}` for Cluster connections
- **Networking** → config is moved between `networking` and `publicPrivateNetworking` depending on type (Lambda and GCP Pub/Sub use `publicPrivateNetworking`); setting `connectionId` infers `access.type: "PRIVATE_LINK"`; conflicting values in both fields throw

**Pipeline validation at build time** (`atlas-streams-build` only):
- The **first stage must be `$source`**, and pipelines containing `$$NOW`, `$$ROOT`, or `$$CURRENT` are rejected. (`$$CLUSTER_TIME` and `$$USER_ROLES` are not in this validator — the engine rejects them when the processor starts.)
- Every referenced connection — including the DLQ connection — is checked to exist. If the connection listing itself fails, the check is skipped silently.
- **The terminal-sink check is not performed by MCP** — starting with `$source` and ending with exactly one sink is an API/engine requirement, so validate it yourself before calling the tool.

**DLQ:** include one only when the user explicitly asks, or when an `$https`/`$externalFunction` stage relies on its default `onError: "dlq"` and so needs a destination. Do not add a DLQ silently.

**Autoscaling:** `{enabled: boolean, minTier, maxTier}`. `maxTier` cannot exceed the workspace `maxTierSize`. On create, `autoscaling` is forwarded to the processor's `options`, so set it there when the user asks for it — omitted means disabled at creation, and `minTier`/`maxTier` default to the workspace bounds. On modify, omitting `autoscaling` preserves it and `{enabled: false}` disables it; the tool's schema does not accept a `null` object, so send `enabled: false` rather than null.

**Effective tier:** `inspect-processor` reports both the baseline `tier` and the read-only `effectiveTier`. A `tier` change takes effect at the next `start-processor`, not immediately.

**Workspace creation:** `includeSampleData` defaults to `true`, which auto-creates the `sample_stream_solar` connection.

**Region naming:** The `region` field uses Atlas-specific names that differ by cloud provider. Using the wrong format returns a cryptic `dataProcessRegion` error.

| Provider | Cloud Region | Streams `region` Value |
|----------|-------------|----------------------|
| **AWS** | us-east-1 | `VIRGINIA_USA` |
| **AWS** | us-east-2 | `OHIO_USA` |
| **AWS** | eu-west-1 | `DUBLIN_IRL` |
| **GCP** | us-central1 | `US_CENTRAL1` |
| **GCP** | europe-west1 | `EUROPE_WEST1` |
| **Azure** | eastus | `eastus` |
| **Azure** | westeurope | `westeurope` |

See [references/connection-configs.md](references/connection-configs.md) for the full region mapping table. If unsure, inspect an existing workspace with `atlas-streams-discover` → `inspect-workspace` and check `dataProcessRegion.region`.

## Connection Capabilities — Source/Sink Reference

Know what each connection type can do before creating pipelines:

| Connection Type | As Source ($source) | As Sink ($merge / $emit) | Mid-Pipeline | Notes |
|-----------------|---------------------|--------------------------|--------------|-------|
| **Cluster** | ✅ Change streams | ✅ $merge to collections; `$emit` (incl. timeseries) | ✅ $lookup | Change streams monitor insert/update/delete/replace operations |
| **Kafka** | ✅ Topic consumer | ✅ $emit to topics | ❌ | Source MUST include `topic` field |
| **Sample Stream** | ✅ Sample data | ❌ Not valid | ❌ | Testing/demo only |
| **S3** | ❌ Not valid | ✅ $emit to buckets; `$iceberg` (SP10+) | ❌ | Sink only - use `path` and `config.outputFormat` (no top-level `format`); `compression` under `config`. Supports AWS PrivateLink. |
| **Https** | ❌ Not valid | ✅ $https as sink | ✅ $https enrichment | Can be used mid-pipeline for enrichment OR as final sink stage |
| **AWSLambda** | ❌ Not valid | ✅ $externalFunction (sync or async) | ✅ $externalFunction (sync or async) | **Sink:** sync or async; async recommended, and `as` must be omitted whenever `execution: "async"`. **Sync mid-pipeline:** `as` required; a sync sink may omit it. |
| **AWS Kinesis** | ✅ Stream consumer | ✅ $emit to streams | ❌ | Similar to Kafka pattern |
| **GCPPubSub** | ❌ Not valid | ✅ $emit to topics | ❌ | Sink only. Needs `topic`, `projectId`, `region`; private networking uses `publicPrivateNetworking` |
| **SchemaRegistry** | ❌ Not valid | ❌ Not valid | ✅ Schema resolution | **Metadata only** - used by Kafka connections for Avro schemas |

**Common connection usage mistakes to avoid:**
- ❌ Setting `as` with `execution: "async"` → `as` must be omitted whenever execution is async, sink or mid-pipeline; only sync mid-pipeline stages require it
- ❌ Forgetting change streams exist → Atlas Cluster is a powerful source, not just a sink
- ❌ Using `$merge` with Kafka → Use `$emit` for Kafka sinks

See [references/connection-configs.md](references/connection-configs.md) for detailed connection configuration schemas by type.

## Core Workflows

### Setup from scratch
1. `atlas-streams-discover` → `list-workspaces` (check existing)
2. `atlas-streams-build` → `resource: "workspace"` (region near data, SP10 for dev)
3. `atlas-streams-build` → `resource: "connection"` (for each source/sink/enrichment)
4. **Validate connections:** `atlas-streams-discover` → `list-connections` + `inspect-connection` for each — verify names match targets, present summary to user
5. Call `search-knowledge` to validate field names. Fetch relevant examples from https://github.com/mongodb/ASP_example
6. `atlas-streams-build` → `resource: "processor"` (add a DLQ only if the user asks for one)
7. `atlas-streams-manage` → `start-processor` (warn about billing)

### Workflow Patterns

**Incremental pipeline development (recommended):**
See [references/development-workflow.md](references/development-workflow.md) for the full 5-phase lifecycle.
1. Start with basic `$source` → `$merge` pipeline (validate connectivity)
2. Add `$match` stages (validate filtering)
3. Add `$addFields` / `$project` transforms (validate reshaping)
4. Add windowing or enrichment (validate aggregation logic)
5. Add error handling / DLQ configuration

**Modify a processor pipeline:**
1. `atlas-streams-manage` → `action: "stop-processor"` — only needed when the processor is STARTED; CREATED, STOPPED, and FAILED can be modified directly
2. `atlas-streams-manage` → `action: "modify-processor"` — provide new pipeline
3. `atlas-streams-manage` → `action: "start-processor"` — restart

A pipeline containing an S3 `$emit` stage is the exception: it cannot be modified at all, so delete and recreate the processor.

**Debug a failing processor:**
1. `atlas-streams-discover` → `diagnose-processor` — one-shot health report. Always call this first.
2. **Commit to a specific root cause.** Match symptoms to diagnostic patterns:
   - **Error 419 + "no partitions found"** → Kafka topic doesn't exist or is misspelled
   - **State: FAILED + multiple restarts** → connection-level error (bypasses DLQ), check connection config
   - **State: STARTED + zero output + windowed pipeline** → likely idle Kafka partitions blocking window closure; add `partitionIdleTimeout` to Kafka `$source` (e.g., `{"size": 30, "unit": "second"}`)
   - **State: STARTED + zero output + non-windowed** → check if source has data; inspect Kafka offset lag
   - **High memoryUsageBytes approaching tier limit** → OOM risk; recommend higher tier
   - **DLQ count increasing** → per-document errors; use MongoDB `find` on DLQ collection
   See [references/output-diagnostics.md](references/output-diagnostics.md) for the full pattern table.
3. Classify processor type before interpreting output volume (alert vs transformation vs filter).
4. Provide concrete, ordered fix steps specific to the diagnosed root cause. Do NOT present a list of hypothetical scenarios.
5. Always direct the user to the Atlas UI for detailed operational logs: **Atlas → Stream Processing → Workspace → Processor → Logs tab**.

### Chained processors (multi-sink pattern)
**CRITICAL: A single pipeline can only have ONE terminal sink** (`$merge`, `$emit`, `$iceberg`, `$https`, or `$externalFunction`). When users request multiple output destinations (e.g., "write to Atlas AND emit to Kafka"), you MUST acknowledge the single-sink constraint and propose chained processors using an intermediate destination. See [references/pipeline-patterns.md](references/pipeline-patterns.md) for the full pattern with examples.

## Pre-Deploy & Post-Deploy Checklists

See [references/development-workflow.md](references/development-workflow.md) for the complete pre-deploy quality checklist (connection validation, pipeline validation) and post-deploy verification workflow.

## Tier Sizing & Performance

**Tier guidance:** the control plane **enforces** the minimum tier the engine reports for a pipeline. Starting below that minimum is rejected with "current tier is below the minimum tier required by this pipeline", and the same check runs on modify, including against the autoscaling `minTier`. `$function` (JavaScript UDF) and `$sessionWindow` pipelines require **SP30 or higher**; do not start one below SP30. `$tumblingWindow`/`$hoppingWindow` usually fit SP10–SP30; very large window state may need SP50. `$function` also needs the `enableFunctionExpression` feature flag, which is off by default.

See [references/sizing-and-parallelism.md](references/sizing-and-parallelism.md) for tier specifications, parallelism formulas, complexity scoring, and performance optimization strategies.

## Troubleshooting

See [references/development-workflow.md](references/development-workflow.md) for the complete troubleshooting table covering processor failures, API errors, configuration issues, and performance problems.

## Billing & Cost

**Atlas Stream Processing has no free tier.** All deployed processors incur continuous charges while running.

- Charges are per-hour, calculated per-second, only while the processor is running
- `stop-processor` stops billing; stopped processors retain state for 45 days at no charge
- **For prototyping without billing:** Use `sp.process()` in mongosh — runs pipelines ephemerally without deploying a processor
- See `references/sizing-and-parallelism.md` for tier pricing and cost optimization strategies

## Safety Rules

- `atlas-streams-teardown` and `atlas-streams-manage` require user confirmation — do not bypass
- **BEFORE calling `atlas-streams-teardown` for a workspace**, you MUST first inspect the workspace with `atlas-streams-discover` to count connections and processors, then present this information to the user before requesting confirmation
- **BEFORE creating any processor**, you MUST validate all connections per the "Pre-Deployment Validation" section in [references/development-workflow.md](references/development-workflow.md)
- Deleting a workspace removes ALL connections and processors permanently
- After stopping a processor, state is preserved 45 days — then checkpoints are discarded
- `resumeFromCheckpoint: false` drops all window state — warn user first
- Moving processors between workspaces is not supported (must recreate)
- Dry-run / simulation is not supported — explain what you would do and ask for confirmation
- Always warn users about billing before starting processors
- Store API authentication credentials in connection settings, never hardcode in processor pipelines

## Reference Files

| File | Read when... |
|------|-------------|
| [`references/pipeline-patterns.md`](references/pipeline-patterns.md) | Building or modifying processor pipelines |
| [`references/connection-configs.md`](references/connection-configs.md) | Creating connections (type-specific schemas) |
| [`references/development-workflow.md`](references/development-workflow.md) | Following lifecycle management or debugging decision trees |
| [`references/output-diagnostics.md`](references/output-diagnostics.md) | Processor output is unexpected (zero, low, or wrong) |
| [`references/sizing-and-parallelism.md`](references/sizing-and-parallelism.md) | Choosing tiers, tuning parallelism, or optimizing cost |
