# Atlas Stream Processing Skill — Evaluations

Automated test suite for the `mongodb-atlas-stream-processing` skill.

## Overview

This suite validates that the skill correctly handles Atlas Stream Processing (ASP) workflows: workspace management, connection configuration, processor deployment, debugging, and production operations.

Every case is single-turn and judge-graded. Each has an `expected_output` (the narrative answer) plus an `expectations` array (the specific, checkable criteria the judge scores). `expectations` is the primary grading target; `expected_output` is the fallback when no expectations are present.

## Test Categories

A case appears under every category it exercises, so a few IDs are cross-listed.

### Workspace & Discovery (1, 3, 18, 24, 40)
- Workspace creation with the correct Atlas region mapping
- Listing workspaces and inspecting processors
- GCP region format validation (`US_CENTRAL1`, not `us-central1`)
- Multi-connection workspace setup
- Workspace tier changes for OOM conditions

### Connections (2, 14, 26, 29, 30, 35, 42, 50, 51)
- Kafka and Atlas Cluster connection creation
- Pre-deployment connection validation (`list-connections` + `inspect-connection`)
- PrivateLink setup for Confluent Kafka on AWS
- Kinesis connection type and IAM prerequisites
- Schema Registry / Avro `$emit` configuration
- Networking immutability (delete and recreate, not update)
- `get-networking` scope (project-level PrivateLink only; no VPC peering listing)
- GCP Pub/Sub connection and sink

### Processor Creation (5, 6, 11, 13, 15, 20, 21, 29, 32, 33, 37, 38, 39, 41, 45, 47, 48, 54)
- Kafka → Atlas `$merge`
- Windowed aggregations (tumbling, hopping, session)
- Change stream → Kafka, including `fullDocument: "updateLookup"`
- HTTPS enrichment and `$https` sink constraints
- AWS Lambda `$externalFunction` (async sink, sync/async enrichment)
- S3 `$emit` with `path`, format, and compression
- Kinesis source/sink with `stream` and `partitionKey`
- JavaScript UDFs (`$function`, flag-gated, SP30+ minimum)
- Async `$externalFunction` must omit `as`
- All five terminal sink stages
- `$emit` to Atlas collections, including time-series

### Pipeline Semantics (27, 28, 31, 38, 43, 44, 46)
- `$$ROOT` and `$$CURRENT` are supported by the ASP engine, but MCP server versions through at least v3.3.0 reject them on `atlas-streams-build` (regression test for the corrected guidance)
- `$$NOW` remains invalid (case 43)
- `$$SEARCH_META` is silently missing rather than throwing (case 46)
- `$validate` accepts any match expression, with `validationAction: "dlq"` (not `"error"`)
- Parallelism is not available on `$externalFunction`/`$https`/top-level `$source` (case 44)
- HTTPS connections are enrichment/sink only, never `$source`

### Lifecycle & Safety (9, 10, 16, 19, 23, 34, 40, 52, 53, 55)
- Stopping processors
- Modify in any state except STARTED, stopping first only when the processor is running, including the `resumeFromCheckpoint` window constraints
- Modifying from FAILED without delete/recreate
- Start-tier ceiling against the workspace `maxTierSize`
- Read-only MCP mode blocks build/manage/teardown
- Safe workspace deletion with inspection and confirmation
- Billing warnings before starting a processor
- 402 billing error handling without retry
- Tier changes via `update-workspace`

### Debugging & Troubleshooting (4, 7, 8, 17, 22, 36, 49, 56)
- Processor health diagnostics
- Failed-processor diagnosis, including the Atlas UI Logs tab (the MCP tools have no log-retrieval action, and `diagnose-processor` returns no error log)
- Zero-output windowed pipelines (idle partitions)
- Processor type classification (alert vs transformation)
- MCP servers/tools unavailable fallback
- `responseFormat` applies to list actions and `inspect-workspace`; the other inspect and diagnose actions accept but ignore it

### Sizing & Architecture (12, 25)
- Tier sizing from the parallelism formula
- Chained processors for multiple sinks (single-terminal-sink constraint)

### Pipeline Variables (Tests 27-28)
- `$$ROOT` is valid and can be used in `$addFields`, `$group`, or `$replaceRoot`
- `$$NOW` remains unavailable; use a timestamp field from the source document instead

## Key Assertions Tested

Each eval validates that the skill:

1. **Calls correct MCP tools** — `atlas-streams-discover`, `atlas-streams-build`, `atlas-streams-manage`, or `atlas-streams-teardown`
2. **Sequences operations correctly** — e.g., validates connections before creating processors, and stops only when the processor is running before modifying
3. **Includes safety checks** — billing warnings, destructive-action confirmation, input validation
4. **Provides actionable guidance** — root-cause identification, specific fix steps, correct field names
5. **References authoritative sources** — `search-knowledge`, the `ASP_example` repo

## Expected Behaviors

### Pre-Deployment Validation
- Always list and inspect connections before creating processors
- Validate connection names match intended targets
- Present a connection summary to the user for confirmation

### Pipeline Construction
- Start with `$source`, end with exactly one of `$merge`/`$emit`/`$iceberg`/`$https`/`$externalFunction`
- Omit `as` whenever `$externalFunction` uses `execution: "async"`; require it for sync
- Configure a DLQ when the user asks for one, or when `$https`/`$externalFunction` relies on the default `onError: "dlq"`
- Add `partitionIdleTimeout` for windowed Kafka pipelines
- Use `onError: "dlq"` for `$https` and `$externalFunction` stages
- The ASP engine supports `$$ROOT`/`$$CURRENT`; MCP server versions through at least v3.3.0 reject them on `atlas-streams-build` — use explicit field references or deploy via `modify-processor`/the Admin API; never use `$$NOW`

### Debugging Workflow
1. Call `diagnose-processor` first
2. Direct the user to the Atlas UI processor Logs tab (the MCP tools have no log-retrieval action)
3. Commit to a specific root cause
4. Provide ordered fix steps

### Billing Awareness
- Warn before starting any processor
- Mention per-second charging
- Offer `sp.process()` as the free alternative
- Never retry on 402 errors

## Running the Evaluations

### Official QA harness (preferred)

The repository's QA harness (`10gen/agent-skills-evals`) runs these cases with and without the skill and grades against `expectations`. A maintainer triggers it on a PR with:

```
/qa-eval mongodb-atlas-stream-processing
```

The verdict and per-case JSON are reported on the `qa-eval` check run. Any change under `testing/mongodb-atlas-stream-processing/` also makes the skill eligible for a PR-wide `/qa-eval`.

### Local validation

```bash
npm ci --prefix testing
node testing/validate-evals.mjs          # schema + duplicate ids + asset checks
npm test --prefix testing                # validator unit tests
node testing/lint-item-echo.mjs          # answer-echo lint (advisory)
```

## Connection Requirements

Cases assume these connections exist when the harness has live Atlas access:

- Workspace: `prod-streams` (used by cases 4, 19, 26, 42, 53)
- Kafka: `events-kafka`, `kafka-prod`
- Atlas Cluster: `atlas-main`, `sample_stream_solar`
- HTTPS: for API enrichment
- AWS Lambda: for `$externalFunction` tests
- S3: for `$emit` sink tests
- Kinesis: for Kinesis source/sink tests
- Schema Registry: for Avro `$emit` tests

## Notes

- Cases are judge-graded guidance tests; they do not create real Atlas resources.
- Cases 27 and 28 are the regression pair for the root-variable correction: 27 asserts the ASP engine supports `$$ROOT`, 28 asserts it supports `$$CURRENT` (which references the current document like `$$ROOT`) while `$$NOW` is not. Both also expect the answer to flag that MCP server versions through at least v3.3.0 reject `$$ROOT`/`$$CURRENT` on `atlas-streams-build`, so those deployments need an alternative. Case 43 separately asserts `$$NOW` is unavailable and points to `{"$meta": "stream.source.ts"}` for event time; case 46 asserts `$$SEARCH_META` is missing rather than throwing.
- Case 21 covers calling `search-knowledge` to validate field names (S3 `$emit` in particular) before building a processor.
- Case 17 verifies the `diagnose-processor` + Atlas UI Logs-tab workflow: the streams MCP tools have no `get-logs` action.
- Case 4 and the root-cause part of case 7 need a live MCP connection to score fully; without one, they grade the described call rather than its result.
- Pipeline-field nesting and naming are asserted explicitly: `config.fullDocument` for change streams, `config.auto_offset_reset` for Kafka sources, `config.key`/`keyFormat` for Kafka sinks, `config.consumerARN` for Kinesis sources, and `boundary` (not `boundaryType`, at the top level of the window stage) for windows.
- Case 41 covers `$lookup` enrichment (Kafka → Atlas collection → `$merge`); case 42 covers auth-only Kafka credential rotation via `update-connection` without delete/recreate.
