# Atlas Stream Processing Skill - Evaluations

Automated test suite for the `atlas-stream-processing` skill.

## Overview

This test suite validates that the skill correctly handles Atlas Stream Processing workflows including workspace management, connection configuration, processor deployment, debugging, and production operations.

## Test Categories

### Basic Operations (Tests 1-4)
- Workspace creation with correct region mapping
- Connection setup (Kafka, Atlas Cluster)
- Resource listing and inspection
- Health diagnostics

### Processor Creation & Deployment (Tests 5-6, 11, 13, 15, 20)
- Simple Kafka → MongoDB pipelines
- Windowed aggregations with tumbling windows
- Change stream → Kafka patterns
- HTTPS enrichment with external APIs
- AWS Lambda integration (async execution)
- S3 sink configuration

### Debugging & Troubleshooting (Tests 7-8, 17, 22, 23)
- Failed processor diagnosis
- Zero-output scenarios (idle partition detection)
- Operational log retrieval
- Processor type classification (alert vs transformation)
- Billing error handling (402)

### Workflow & Safety (Tests 9-10, 14, 16, 19, 21)
- Pre-deployment connection validation
- Processor lifecycle (stop, modify, start)
- Safe workspace deletion with confirmation
- Billing warnings before starting processors
- Knowledge search before processor creation

### Advanced Patterns (Tests 12, 18, 24-25)
- Tier sizing with parallelism calculation
- Region format validation (AWS/GCP/Azure)
- Multi-connection workspace setup
- Chained processor patterns

## Key Assertions Tested

Each eval validates that the skill:

1. **Calls correct MCP tools** - Uses `atlas-streams-discover`, `atlas-streams-build`, `atlas-streams-manage`, or `atlas-streams-teardown` appropriately
2. **Sequences operations correctly** - E.g., validates connections before creating processors, stops before modifying
3. **Includes safety checks** - Warns about billing, confirms destructive actions, validates inputs
4. **Provides actionable guidance** - Root cause identification, specific fix steps, proper field names
5. **References authoritative sources** - Calls `search-knowledge`, mentions ASP_example repo

## Expected Behaviors

### Pre-Deployment Validation
- Always list and inspect connections before creating processors
- Validate connection names match intended targets
- Present connection summary to user for confirmation

### Pipeline Construction
- Start with `$source`, end with `$merge`/`$emit`
- Include DLQ configuration for production processors
- Add `partitionIdleTimeout` for windowed Kafka pipelines
- Use `onError: "dlq"` for `$https` and `$externalFunction` stages

### Debugging Workflow
1. Call `diagnose-processor` first
2. Retrieve operational logs
3. Identify specific root cause
4. Provide ordered fix steps

### Billing Awareness
- Warn before starting any processor
- Mention per-second charging
- Offer `sp.process()` as free alternative
- Never retry on 402 errors

## Running the Tests

These evaluations are designed to be run with LLM-based evaluation frameworks that:
1. Send the prompt to an agent with the `atlas-stream-processing` skill loaded
2. Verify the agent's response matches the expected behavior
3. Check for proper MCP tool calls and sequencing
4. Validate safety checks and user confirmations

## Connection Requirements

Tests assume the following connections exist in test workspaces:
- Kafka connections: `events-kafka`, `kafka-prod`
- Atlas Cluster connections: `atlas-main`, `sample_stream_solar`
- HTTPS connections: For API enrichment tests
- AWS Lambda connections: For Lambda integration tests
- S3 connections: For S3 sink tests

## Notes

- Tests do not execute actual MCP tool calls (no real Atlas resources created)
- Focus is on validating the skill's guidance and tool invocation patterns
- Region format validation (Test 18) is critical as incorrect formats cause cryptic errors
- Idle partition detection (Test 8) catches a common production issue
