# Eval Metadata Files

This directory contains detailed assertion specifications for critical test cases. Each JSON file defines:

1. **Assertions** - Specific checks to validate agent behavior
2. **Expected tool calls** - Exact parameters for MCP tool invocations
3. **Expected pipeline structures** - JSON schemas for processor pipelines
4. **Common mistakes** - Errors to watch for and their fixes
5. **Workflow sequences** - Multi-step operation ordering
6. **Test lifecycle** - Pre-test setup, validation, and cleanup procedures
7. **Resource naming strategies** - How to avoid conflicts with existing resources

## File Naming Convention

Files are named `{eval_id}-{eval_name}.json` matching the corresponding test in `../evals.json`.

## Resource Naming Strategy

**Critical Design Decision:** Tests use **unique resource names** to avoid conflicts with existing resources.

### Naming Patterns

1. **Timestamp-based** (Recommended)
   - Pattern: `{base-name}-test-{timestamp}`
   - Example: `dev-streams-test-1710096847`
   - Pros: Unique, sortable, easy to identify test resources
   - Cons: Not human-friendly for manual inspection

2. **Increment-based**
   - Pattern: `{base-name}-test-{counter}`
   - Example: `dev-streams-test-001`
   - Pros: Clean, sequential
   - Cons: Requires state tracking, race conditions

3. **UUID-based**
   - Pattern: `{base-name}-{uuid}`
   - Example: `dev-streams-a1b2c3d4`
   - Pros: Guaranteed unique
   - Cons: Long names, harder to read

### Safety Guarantees

✅ **Never deletes existing resources**
✅ **Tests are idempotent** (can run multiple times)
✅ **Tests are isolated** (don't interfere with each other)
✅ **Test artifacts are inspectable** (resources persist after failure for debugging)

### Cleanup Strategy

Tests include optional cleanup steps but default to **preserving test resources**:
- ✅ Useful for debugging test failures
- ✅ Allows manual inspection of results
- ⚠️ May accumulate test resources over time
- 💡 Use `atlas-streams-discover` to list and manually clean up test resources with `-test-` in names

## Test Lifecycle Structure

Each metadata file includes:

### 1. Pre-Test Setup
```json
"pre_test_setup": [
  {
    "step": "check_existing_workspaces",
    "action": "Call atlas-streams-discover to verify resources",
    "optional": true
  }
]
```
- Validates prerequisites exist (connections, workspaces)
- Checks for naming conflicts
- Does NOT modify existing resources

### 2. Test Execution
- Agent receives the prompt
- Agent makes tool calls
- Test framework validates tool calls and responses

### 3. Post-Test Validation
```json
"post_test_validation": [
  {
    "step": "verify_workspace_created",
    "expected": "Workspace exists with correct config",
    "critical": true
  }
]
```
- Validates operation succeeded (not just correct tool calls)
- Checks final state matches expectations
- Critical validations must pass for test to succeed

### 4. Post-Test Cleanup (Optional)
```json
"post_test_cleanup": [
  {
    "step": "delete_test_workspace",
    "action": "Call atlas-streams-teardown",
    "when": "test_complete"
  }
]
```
- Optional cleanup of test resources
- Disabled by default to aid debugging
- Can be enabled via test configuration

### Success Criteria

Tests validate both:
1. **Tool Call Structure** - Correct tool, parameters, sequence
2. **Operation Outcome** - Resource created/modified successfully

Example:
```json
"success_criteria": {
  "operation_succeeds": "Returns 200/201, not 409 Conflict",
  "resource_accessible": "Resource can be inspected after creation",
  "config_matches": "Created resource has expected configuration"
}
```

## Assertion Structure

Each assertion includes:
- `name`: Unique identifier for the check
- `description`: What is being validated
- `critical` (optional): Boolean indicating must-pass assertion
- `reason` (optional): Why this assertion is important
- `note` (optional): Additional context

## Priority Tests with Metadata

### Pipeline Construction (5 tests)
- **01-create-workspace-basic.json** - Region mapping validation (us-east-1 → VIRGINIA_USA)
- **05-create-simple-kafka-to-mongo.json** - Basic pipeline structure, pre-validation workflow
- **06-create-windowed-aggregation.json** - Window configuration, partitionIdleTimeout requirement
- **13-create-https-enrichment.json** - HTTPS enrichment, onError: dlq requirement
- **15-create-lambda-integration.json** - Lambda sink, execution: async requirement
- **20-create-s3-sink.json** - Field name validation (path not prefix)

### Debugging & Validation (3 tests)
- **07-debug-failed-processor.json** - Debugging workflow (diagnose → logs → root cause)
- **08-debug-zero-output-windowed.json** - Idle partition detection and fix
- **14-validate-connections-before-deploy.json** - Pre-deployment connection validation
- **21-search-knowledge-before-processor.json** - Knowledge search requirement

### Configuration (1 test)
- **18-region-format-validation.json** - GCP region format (US_CENTRAL1 not us-central1)

## Critical Assertions Explained

### Field Name Validation
**Why critical:** Atlas Stream Processing uses specific field names that differ from intuitive naming:
- S3: `path` not `prefix`
- Kinesis source: `stream` not `streamName`
- Kafka source: `topic` is required

Using wrong field names causes processor creation to fail with cryptic errors.

### Region Format Validation
**Why critical:** Atlas uses custom region names (e.g., `VIRGINIA_USA` for AWS us-east-1). Using cloud provider formats causes `dataProcessRegion` validation errors.

### partitionIdleTimeout Requirement
**Why critical:** Windowed Kafka processors will produce NO output if partitions go idle, even if connections are healthy and data exists. This is the #1 production issue for windowed pipelines.

### onError: 'dlq' Requirement
**Why critical:** Using `onError: 'fail'` for `$https` or `$externalFunction` stages causes processor crashes on any API error. Production processors must use `onError: 'dlq'` for graceful error handling.

### Lambda execution: 'async' for Sinks
**Why critical:** When `$externalFunction` is the terminal sink stage, `execution` MUST be `'async'`. Using `'sync'` causes configuration validation errors. Mid-pipeline enrichment can use either `'sync'` or `'async'`.

## Test Execution Example

### Before (Incomplete Validation)
```javascript
// Only checked tool call structure
const response = runTest("Create workspace dev-streams in AWS us-east-1");
assert(response.toolCalls[0].tool === "atlas-streams-build");
assert(response.toolCalls[0].params.region === "VIRGINIA_USA");
// ❌ Didn't verify operation succeeded
// ❌ Got 409 Conflict but marked as PASS
```

### After (Complete Validation)
```javascript
const metadata = require('./metadata/01-create-workspace-basic.json');
const workspaceName = `dev-streams-test-${Date.now()}`;

// Pre-test setup
await validatePrerequisites(metadata.pre_test_setup);

// Execute test with unique name
const response = await runTest(
  `Create workspace ${workspaceName} in AWS us-east-1`
);

// Validate tool call structure
for (const assertion of metadata.assertions) {
  assert(validateAssertion(response, assertion));
}

// Validate operation outcome
const workspace = await inspectWorkspace(workspaceName);
assert(workspace.region === "VIRGINIA_USA");
assert(workspace.tier === "SP10");

// Success! Resource created with correct config
```

## Using These Files

### Automated Testing
```javascript
const metadata = require('./metadata/05-create-simple-kafka-to-mongo.json');
const response = await runTest(metadata.prompt);

// Validate assertions
for (const assertion of metadata.assertions) {
  if (assertion.critical && !validateAssertion(response, assertion)) {
    throw new Error(`Critical assertion failed: ${assertion.name}`);
  }
}
```

### Manual Testing
Use assertions as a checklist when manually validating agent responses:
1. Load the metadata file for the test
2. Execute the prompt against the skill
3. Check each assertion against the response
4. Mark critical assertions as pass/fail

## Coverage

**10 of 25 tests** have detailed metadata files covering:
- All pipeline construction patterns (Kafka→Mongo, windowed, HTTPS, Lambda, S3)
- All critical field name validations
- All common debugging scenarios
- All safety/validation workflows

Tests without metadata files have simpler behavioral expectations that don't require field-level validation.

## Test Categories by Resource Impact

### Read-Only Tests (No Unique Names Needed)
Tests that only inspect existing resources:
- **07-debug-failed-processor** - Uses any existing processor
- **14-validate-connections-before-deploy** - Uses any existing connections
- **21-search-knowledge-before-processor** - Read-only knowledge search

**Approach:** Use any available resources in the test environment

### Write Tests (Unique Names Required)
Tests that create new resources:
- **01-create-workspace-basic** - Creates workspace with `{name}-test-{timestamp}`
- **05-create-simple-kafka-to-mongo** - Creates processor with unique name
- **06-create-windowed-aggregation** - Creates processor with unique name
- **18-region-format-validation** - Creates workspace with unique name
- **20-create-s3-sink** - Creates processor with unique name

**Approach:** Append timestamp to all resource names

### Conditional Tests (May Skip)
Tests that require specific prerequisites:
- **20-create-s3-sink** - Requires S3 connection (skip if unavailable)
- **15-create-lambda-integration** - Requires Lambda connection (skip if unavailable)

**Approach:** Validate prerequisites in pre_test_setup, skip gracefully if not met

## Implementation Guide

### Step 1: Generate Unique Name
```javascript
function generateTestName(pattern) {
  const timestamp = Math.floor(Date.now() / 1000);
  return pattern.replace('{timestamp}', timestamp);
}

// Example: "dev-streams-test-{timestamp}" → "dev-streams-test-1710096847"
```

### Step 2: Execute Test with Unique Name
```javascript
const metadata = require('./metadata/01-create-workspace-basic.json');
const workspaceName = generateTestName(metadata.resource_naming_strategy.pattern);

const prompt = metadata.prompt.replace('dev-streams', workspaceName);
// "Create workspace dev-streams-test-1710096847 in AWS us-east-1"
```

### Step 3: Validate Success Criteria
```javascript
// Check tool call structure
validateToolCall(response, metadata.expected_tool_call);

// Check operation outcome
const workspace = await atlasStreamsDiscover({
  action: 'inspect-workspace',
  workspaceName: workspaceName
});

assert(workspace !== null, "Workspace should exist");
assert(workspace.region === "VIRGINIA_USA", "Region should be mapped correctly");
```

### Step 4: Optional Cleanup
```javascript
if (config.cleanup_enabled) {
  await atlasStreamsTeardown({
    resource: 'workspace',
    workspaceName: workspaceName
  });
}
```
