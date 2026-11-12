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

**Field mapping:** Set `projectId` and only the fields for the selected resource: workspace (`workspaceName`, `cloudProvider`, `region`, `tier`); connection (`workspaceName`, `connectionName`, `connectionType`, `connectionConfig`); processor (`workspaceName`, `processorName`, `pipeline`, optional `dlq`, `autoStart`, `processorTier`, `autoscaling`); PrivateLink (`privateLinkConfig`, project-level; omit `workspaceName`). See the references for schemas and pipeline requirements.

### atlas-streams-manage — ALL update/state operations
| Action | Notes |
|--------|-------|
| `start-processor` | Begins billing. Optional `tier` override (bounded by the workspace `streamConfig.maxTierSize`), `resumeFromCheckpoint` (a **start** parameter, not a modify one), `autoscaling` |
| `stop-processor` | Stops billing. Retains state 45 days |
| `modify-processor` | Works in any state **except** STARTED — CREATED, STOPPED, and FAILED are all modifiable. Change pipeline, DLQ, name, tier, or autoscaling. **Exception:** a pipeline containing an S3 `$emit` stage cannot be modified at all — delete and recreate it |
| `update-workspace` | Change tier or region (`newTier` maps to Admin API `streamConfig.tier`). A region change requires the workspace to have **zero processors** — delete them first |
| `update-connection` | Update config. Auth/credentials are updatable; networking, connection **type**, and **region** are immutable — delete and recreate |
| `accept-peering` / `reject-peering` | VPC peering management |

**Field mapping:** Always set `projectId`, `workspaceName`, and `resourceName` where applicable. `start-processor` accepts optional `tier`, `resumeFromCheckpoint`, ISO 8601 `startAtOperationTime`, and `autoscaling`; the tier cannot exceed workspace `maxTierSize`. `modify-processor` requires at least one of `pipeline`, `dlq`, `newName`, `tier`, or `autoscaling`; `resumeFromCheckpoint` belongs to start, not modify. `update-workspace` takes `newRegion` or `newTier`. `update-connection` takes `resourceName` and `connectionConfig`: credentials can be updated, but networking, connection type, and region are immutable. Peering actions take `peeringId`; accepting also needs requester account and VPC IDs.

### atlas-streams-teardown — ALL delete operations
| Resource | Safety behavior |
|----------|----------------|
| `processor` | Auto-stops before deleting |
| `connection` | Blocks if referenced by running processor |
| `workspace` | Cascading delete of all connections and processors |
| `privatelink` / `peering` | Remove networking resources |

**Field mapping:** Always set `projectId` and `resource`; use `workspaceName` for workspaces, connections, and processors, and `resourceName` for connections, processors, PrivateLinks, and peerings. PrivateLinks and peerings are project-level.

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

ASP supports `$$ROOT` and `$$CURRENT`, but MCP Server versions through at least v3.3.0 reject them through `atlas-streams-build`; use explicit fields or deploy through `modify-processor`/the Admin API. `$$NOW`, `$$CLUSTER_TIME`, and `$$USER_ROLES` are unavailable; `$$SEARCH_META` evaluates to missing. `$where` and `$accumulator` are rejected. `$function` requires the usually-disabled `enableFunctionExpression` flag.

Use supported sources and sinks: HTTPS is not a `$source`, Kafka sources need `topic`, Lambda uses `$externalFunction`, and deployed pipelines need exactly one terminal sink. `$validate` supports only `"discard"` or `"dlq"`.

For stage fields and connection requirements—including change-stream `fullDocument`, Kinesis `stream`/`partitionKey`, S3 `path`, `$externalFunction` sync/async `as`, `$validate`, and `$lookup` parallelism—see [references/pipeline-patterns.md](references/pipeline-patterns.md). Confirm AWS IAM roles are registered through Atlas Cloud Provider Access before creating connections. For SchemaRegistry, use its distinct connection type and lowercase schema types; see [references/connection-configs.md](references/connection-configs.md).

## MCP Tool Behaviors

**Elicitation:** When creating connections, the build tool auto-collects missing sensitive fields (passwords, bootstrap servers) via MCP elicitation. Do NOT ask the user for these — let the tool collect them.

The tool normalizes `bootstrapServers` arrays, `schemaRegistryUrls` strings, and Cluster `dbRoleToExecute`; Lambda and GCP Pub/Sub networking uses `publicPrivateNetworking`.

**Pipeline validation at build time** (`atlas-streams-build` only):
- The **first stage must be `$source`**, and pipelines containing `$$NOW`, `$$ROOT`, or `$$CURRENT` are rejected. (`$$CLUSTER_TIME` and `$$USER_ROLES` are not in this validator — the engine rejects them when the processor starts.)
- Every referenced connection — including the DLQ connection — is checked to exist. If the connection listing itself fails, the check is skipped silently.
- **The terminal-sink check is not performed by MCP** — starting with `$source` and ending with exactly one sink is an API/engine requirement, so validate it yourself before calling the tool.

**DLQ:** Do not add one unless requested or needed by a stage's default `onError: "dlq"`.

On create, autoscaling is passed in processor `options`; on modify, omission preserves it and `{enabled: false}` disables it.

See [references/sizing-and-parallelism.md](references/sizing-and-parallelism.md) for autoscaling and tier behavior. `includeSampleData` defaults to `true`. Regions use Atlas-specific names; see the mapping in [references/connection-configs.md](references/connection-configs.md).

For source/sink support, networking, and connection configuration by type, see [references/connection-configs.md](references/connection-configs.md). Remember: Kafka uses `$emit`, not `$merge`; async `$externalFunction` stages must omit `as`.

## Core Workflows

### Setup from scratch
1. `atlas-streams-discover` → `list-workspaces` (check existing)
2. `atlas-streams-build` → `resource: "workspace"` (region near data, SP10 for dev)
3. `atlas-streams-build` → `resource: "connection"` (for each source/sink/enrichment)
4. **Validate connections:** `atlas-streams-discover` → `list-connections` + `inspect-connection` for each — verify names match targets, present summary to user
5. Call `search-knowledge` to validate field names. Fetch relevant examples from https://github.com/mongodb/ASP_example
6. `atlas-streams-build` → `resource: "processor"` (add a DLQ only if requested or needed by a stage's default error handling)
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
2. Identify the likely cause from evidence; if inconclusive, state what evidence is needed rather than guessing.
3. Use [references/output-diagnostics.md](references/output-diagnostics.md) to interpret symptoms, then give ordered fix or evidence-gathering steps. Detailed operational logs are in the Atlas UI processor Logs tab; `diagnose-processor` returns no error log.

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
