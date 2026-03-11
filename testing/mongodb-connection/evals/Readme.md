# MongoDB Connection Skill - Comprehensive Test Suite

## Overview

The evaluation suite now contains **5 diverse test scenarios** covering different problem domains, languages, and skill boundaries. Each scenario tests all **7 assertions** to ensure comprehensive skill validation.

---

## Test Scenarios

### Test 1: Node.js Timeout Errors (Basic Diagnostic)
**Language**: Node.js
**Problem Type**: Connection pool exhaustion under load
**Key Learning**: Context gathering before configuration

**Prompt**:
> "My Node.js app is getting connection timeout errors connecting to MongoDB Atlas. We have a 3-node replica set on M30 and about 12 app instances running in Kubernetes."

**Expected Behavior**:
- Ask diagnostic questions about current config and load patterns
- Explain Node.js driver defaults
- Calculate connection footprint
- Guide on monitoring
- Avoid arbitrary parameters without justification

---

### Test 2: AWS Lambda Infrastructure Issue
**Language**: Node.js (Lambda)
**Problem Type**: VPC networking / infrastructure
**Key Learning**: Identifying skill boundaries - when NOT to suggest client config

**Prompt**:
> "We're getting ECONNREFUSED errors when trying to connect to our MongoDB Atlas cluster from our Node.js application running in AWS Lambda. The connection string is correct and we're using the latest driver. We've tried increasing maxPoolSize to 100 and adding various timeout parameters but nothing helps. The error message is: MongoServerSelectionError: connect ECONNREFUSED. This started happening after we moved the Lambda functions to a new VPC for security compliance. What connection pool settings should we use to fix this?"

**Expected Behavior**:
- Recognize ECONNREFUSED + VPC migration = infrastructure issue
- Explain why pool parameters won't help
- Ask about VPC configuration (NAT Gateway, security groups)
- Redirect to infrastructure troubleshooting
- Do NOT suggest connection pool changes

**Assertion Focus**: `identifies_infrastructure_issues` - core boundary test

---

### Test 3: Node.js Connection Leak (Anti-Pattern)
**Language**: Node.js (Express)
**Problem Type**: Application architecture anti-pattern
**Key Learning**: Identifying MongoClient lifecycle issues

**Prompt**:
> "We're running a Node.js Express app and every few hours our MongoDB Atlas cluster shows thousands of connections and eventually our app crashes with connection errors. We restart and it's fine for a while."

**Expected Behavior**:
- Ask how MongoClient is instantiated
- Identify per-request MongoClient anti-pattern
- Explain pooling fundamentals (singleton client)
- Show connection explosion math
- Focus on architectural fix, not pool parameters

**Assertion Focus**: `asks_diagnostic_questions`, `avoids_arbitrary_parameters` - architectural diagnosis

---

### Test 4: Python Microservices Capacity Planning
**Language**: Python (PyMongo)
**Problem Type**: Over-provisioned connection pools at scale
**Key Learning**: Aggressive reduction for high-instance-count topologies

**Prompt**:
> "We have about 200 Python microservices connecting to a 3-member replica set on Atlas M40. We keep hitting the connection limit even though each service doesn't do much."

**Expected Behavior**:
- Calculate default footprint: 200 × (100 + 2) × 3 = 61,200 connections
- Explain why defaults are inappropriate at this scale
- Recommend aggressive maxPoolSize reduction (5-10) justified by low activity
- Show improved footprint calculation
- Mention file descriptor and memory constraints

**Assertion Focus**: `calculates_connection_footprint` - capacity planning at scale

---

### Test 5: PHP Request Lifecycle Pattern
**Language**: PHP (Laravel)
**Problem Type**: Language-specific connection behavior
**Key Learning**: Understanding runtime-specific pooling models

**Prompt**:
> "We're running a Laravel app with the MongoDB PHP driver and connections seem to get created and dropped constantly. Our Atlas metrics show a sawtooth pattern in the connections graph. Is this normal for PHP?"

**Expected Behavior**:
- Explain PHP's request-based lifecycle vs. long-running processes
- Ask about PHP runtime (PHP-FPM, worker count)
- Explain persistent connections configuration
- Relate sawtooth pattern to request lifecycle
- Suggest persistent connections based on FPM worker count

**Assertion Focus**: `explains_driver_defaults` - language-specific behavior understanding

---

## Assertion Coverage Matrix

| Scenario | Language | asks_diagnostic | explains_driver | calculates_footprint | monitoring_guidance | avoids_arbitrary | addresses_timeout | identifies_infra |
|----------|----------|----------------|-----------------|---------------------|--------------------|--------------------|-------------------|------------------|
| 1. Node.js Timeout | Node.js | ✓ Pool config | ✓ Node defaults | ✓ 12 instances calc | ✓ Pool metrics | ✓ Context-based | ✓ Timeout diagnosis | N/A Client issue |
| 2. AWS Lambda VPC | Node.js | ✓ VPC config | ⚠️ Irrelevant | ⚠️ Premature | ✓ Network diagnostics | ✓ **Core test** | ✓ ECONNREFUSED | ✓ **Core test** |
| 3. Express Leak | Node.js | ✓ **MongoClient lifecycle** | ✓ Pooling fundamentals | ⚠️ Explosion calc | ✓ Connection trends | ✓ **Architectural fix** | ✓ Exhaustion | N/A Client issue |
| 4. Python Microservices | Python | ✓ Current pools | ✓ PyMongo defaults | ✓ **61,200 calc** | ✓ Server-side | ✓ Justified reduction | ✓ Capacity limit | N/A Client issue |
| 5. PHP Lifecycle | PHP | ✓ **Runtime setup** | ✓ **Request-based** | ⚠️ Worker-based | ✓ Connection rate | ✓ Persistent first | ✓ Sawtooth pattern | N/A Client issue |

**Legend**:
- ✓ = Expected to pass/apply
- ⚠️ = Expected behavior differs from typical
- N/A = Not applicable for scenario type

---

## Coverage Diversity

### Problem Domains
1. **Pool Exhaustion**: Test 1 (Node.js timeout)
2. **Infrastructure Issues**: Test 2 (AWS VPC)
3. **Anti-Patterns**: Test 3 (Connection leak)
4. **Capacity Planning**: Test 4 (Python scale)
5. **Language-Specific**: Test 5 (PHP lifecycle)

### Languages
- Node.js: 3 scenarios (timeout, Lambda, Express leak)
- Python: 1 scenario (microservices)
- PHP: 1 scenario (request lifecycle)

### Skill Boundaries
- **Client Config Scope**: Tests 1, 3, 4, 5
- **Infrastructure Scope**: Test 2 (must redirect, not configure)
- **Architecture Scope**: Test 3 (must identify anti-pattern)

### Deployment Patterns
- Kubernetes: Test 1
- AWS Lambda: Test 2
- Express app: Test 3
- Microservices (200 instances): Test 4
- PHP-FPM: Test 5

---

## Assertion Definitions

### 1. asks_diagnostic_questions
Gathers context before suggesting configuration. Questions should be relevant to the problem domain (pool config, infrastructure, architecture).

### 2. explains_driver_defaults
Explains language-specific driver defaults and why they may be insufficient for the scenario. Adapts to each driver's behavior model.

### 3. calculates_connection_footprint
Shows the multiplication effect: `instances × (maxPoolSize + 2 monitoring) × RS members`. Critical for capacity planning.

### 4. provides_monitoring_guidance
Guides on what to monitor based on problem type (pool metrics, network diagnostics, connection trends, etc.).

### 5. avoids_arbitrary_parameters
Does NOT suggest arbitrary values without justification from user's context. All parameters must be explained with reasoning.

### 6. addresses_timeout_specifically
Directly addresses the symptom reported (timeout, ECONNREFUSED, leak, capacity, sawtooth) with appropriate diagnosis.

### 7. identifies_infrastructure_issues
Recognizes when the problem is outside client config scope (VPC, network, security groups) and redirects appropriately. Core boundary test.

---

## Success Criteria

**Per-Test**:
- Applicable assertions: ≥ 80% pass rate
- N/A assertions: Correctly identified and skipped

**Overall Suite**:
- All 7 assertions tested across multiple scenarios
- Each assertion has at least one "core test" where it's the primary focus
- Diverse coverage: languages, problem types, deployment patterns
- Boundary cases: Tests both "what to do" and "what NOT to do"

---

## Running the Tests

To evaluate the skill against this comprehensive suite:

1. Load each test prompt into an agent with the mongodb-connection skill
2. Grade the response against all 7 assertions
3. Record pass/fail/N/A for each assertion
4. Calculate per-test and overall scores
5. Compare with baseline (without skill) to measure improvement

**Key Metrics**:
- Per-test scores (e.g., 5.5/7, with N/A excluded)
- Assertion success rate across all tests
- Boundary recognition accuracy (Test 2: infrastructure)
- Anti-pattern identification rate (Test 3: leak)
- Context-gathering discipline (all tests)
