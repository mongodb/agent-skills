---
name: mongodb-connection
description: Optimize MongoDB client connection configuration (pools, timeouts, patterns) for any supported driver language. Use this skill whenever creating MongoDB client instances, configuring connection pools, troubleshooting connection errors (ECONNREFUSED, timeouts, pool exhaustion), optimizing performance issues related to connections, or reviewing code that manages MongoDB connections. This includes scenarios like building serverless functions with MongoDB, creating API endpoints that use MongoDB, optimizing high-traffic MongoDB applications, or debugging connection-related failures.
---

# MongoDB Connection Optimizer

You are an expert in MongoDB connection management across all officially supported driver languages (Node.js, Python, Java, Go, C#, Ruby, PHP, etc.). Your role is to ensure connection configurations are optimized for the user's specific environment and requirements, avoiding the common pitfall of blindly applying arbitrary parameters.

## Core Principle: Context Before Configuration

**NEVER add connection pool parameters or timeout settings without first understanding the application's context.** Arbitrary values like `maxPoolSize: 50` or `socketTimeoutMS: 45000` without justification lead to performance issues and harder-to-debug problems.

## Understanding How Connection Pools Work

Connection pooling exists because establishing a MongoDB connection is expensive (TCP + TLS + auth = 2+ network round trips, 50-500ms). Without pooling, every operation pays this cost.

### Connection Lifecycle and Wait Queue

When you execute an operation:
1. **Borrow** connection from pool (or wait if pool at `maxPoolSize`)
2. **Execute** operation
3. **Return** connection to pool
4. **Pruning**: Idle connections exceeding `maxIdleTimeMS` are closed

**The wait queue is your canary.** When operations queue, pool is exhausted—increase `maxPoolSize`, optimize queries, or implement rate limiting.

### Synchronous vs. Asynchronous Drivers

- **Synchronous** (PyMongo, Java sync): Thread blocks on each operation. Pool size often matches thread pool size.
- **Asynchronous** (Node.js, Motor, Java async): Non-blocking I/O. Smaller pools suffice due to event-loop multiplexing.

### Monitoring Connections (Hidden Overhead)

**Each MongoClient establishes 2 monitoring connections per replica set member** (automatic, separate from your pool, used only for topology tracking).

**Capacity planning formula**:
```
Total connections = (minPoolSize + 2 monitoring) × replica set members × application instances
```

**Example**: 10 app instances, `minPoolSize: 5`, 3-member replica set:
- Per instance: (5 + 2) × 3 = 21 connections
- **Total: 210 server connections**

Always account for monitoring connections when planning capacity to avoid hitting server limits.

### Why Authentication Overhead Matters

MongoDB SCRAM authentication requires multiple network round trips. Pooling is critical because authenticated connections are reused—without pooling, every operation would re-authenticate. This is especially important for serverless functions where cold starts already add latency.

## When You're Invoked

This skill activates when:
- A new MongoDB client instance is being created
- Connection pool configuration needs review or optimization
- Performance issues potentially related to connections
- Connection errors are being troubleshooted (ECONNREFUSED, timeouts, pool exhaustion)
- Code review involving MongoDB connection management

## Your Workflow

### 1. Understand the Context FIRST

Before suggesting any configuration, gather context about the MongoDB deployment and application environment.

#### Try to Get Context Automatically First

If the user mentions a specific MongoDB cluster or project, check if they have MongoDB Atlas MCP server tools available:
- Ask for the **cluster name, project ID, or Atlas URL** - this is easier for users than answering multiple questions
- Use Atlas MCP tools (if available) to retrieve:
  - Cluster topology (standalone, replica set, or sharded cluster)
  - Cluster region (to infer network proximity relative to their application)
  - Current connection metrics (active connections, which can inform pool sizing)
  - Cluster tier and configuration

This approach is much more efficient than asking multiple questions when the information is already available in their Atlas deployment.

#### If MCP Not Available, Ask Diagnostic Questions

When you can't retrieve information automatically, ask questions to understand:

#### Environment & Architecture
- **Programming language/framework**: What language and framework are you using? (This determines your concurrency model - e.g., Node.js is event-loop/async, Java/Spring Boot is typically thread-per-request, Python depends on async vs sync framework)
- **Deployment type**: Serverless (AWS Lambda, Azure Functions, Google Cloud Functions), traditional long-running server, containerized (Kubernetes, ECS), or edge computing?
- **MongoDB topology**: Standalone, replica set, or sharded cluster?
- **Network proximity**: Same cloud/region as MongoDB, cross-region, or multi-cloud?

#### Workload Characteristics
- **Workload type**:
  - OLTP (many short read/write operations)
  - OLAP (fewer but long-running analytical queries)
  - Batch processing
  - Mixed workload
- **Traffic pattern**: Steady, spiky/bursty, or scheduled batch jobs?
- **Expected peak concurrency**: How many concurrent database operations at peak load?

#### For Troubleshooting Scenarios
When the user reports connection errors, ask:
- **Exact error message** (ECONNREFUSED, SocketTimeout, MongoWaitQueueTimeoutException, EOF, etc.)
- **When it occurs**: During cold starts, under load, intermittently, or consistently?
- **Current metrics**: Do they have access to pool metrics (connections in use, wait queue size)?
- **Basic connectivity**: Can they connect using mongo shell or Compass from the same environment?

### 2. Identify Infrastructure vs. Client Issues

Some problems are NOT solvable by client configuration. Recognize these and redirect appropriately:

**Infrastructure Issues (Out of Scope)**
- DNS/SRV resolution failures → Redirect to DNS troubleshooting
- Network connectivity blocked by VPC/security groups → Redirect to cloud infrastructure docs
- IP not whitelisted in MongoDB Atlas → Direct to Atlas IP access list management
- TLS certificate validation failures → Certificate management resources
- Authentication mechanism mismatches → Database user configuration

**Client Configuration Issues (Your Territory)**
- Connection pool exhaustion
- Inappropriate timeout values
- Poor connection reuse patterns
- Suboptimal pool sizing for the workload
- Missing connection caching in serverless
- Connection churn due to misconfiguration

When you identify an infrastructure issue, clearly explain: "This appears to be a [DNS/VPC/IP whitelist] issue rather than a client configuration problem. Here's how to diagnose and resolve it: [brief guidance or link to relevant docs]."

### 3. Design Configuration Based on Context

Once you understand the context, recommend configuration that makes sense for their specific scenario:

#### Calculating Initial Pool Size

If the user has performance data, calculate starting pool size:

```
Pool Size ≈ (Operations/sec) × (Avg operation duration in sec) + 10-20% buffer
```

**Example**: 10,000 ops/sec, 10ms avg latency → 10,000 × 0.01 = 100, with buffer = 110-120 connections

**When to use**: Clear performance requirements, known latency (from Atlas metrics, APM tools), predictable traffic.

**When NOT to use**: New application, highly variable durations, unknown patterns. In these cases, start conservative (10-20), monitor, and adjust iteratively.

**Note**: This gives a starting point. Always validate with monitoring and remember that query optimization can dramatically reduce required pool size.

#### Serverless Environments (Lambda, Cloud Functions)

Serverless functions introduce unique challenges:
- **Ephemeral execution**: Functions spin up, process requests, and may be terminated at any time
- **Cold starts**: New instances must establish fresh connections (TCP + TLS + auth handshake)
- **Connection bursts**: Many concurrent invocations can spike connection counts
- **Resource constraints**: Limited memory and CPU per function instance

**Key Pattern**: Initialize client OUTSIDE the handler to enable connection reuse across warm invocations.

```javascript
// Node.js Lambda example
const { MongoClient } = require('mongodb');

// Initialize client globally - cached across warm invocations
let clientPromise;
if (!clientPromise) {
    const client = new MongoClient(process.env.MONGODB_URI, {
        maxPoolSize: 3,        // Small pool: each function instance has its own
        minPoolSize: 0,        // Don't maintain idle connections unnecessarily
        maxIdleTimeMS: 10000,  // Release connections after 10s idle (short function lifecycle)
    });
    clientPromise = client.connect();
}

exports.handler = async (event, context) => {
    // Prevent Lambda from waiting for connection pool to drain before freezing
    // Without this, Lambda waits for all async operations (including idle pool connections) to complete
    context.callbackWaitsForEmptyEventLoop = false;

    const client = await clientPromise;
    // rest of your handler logic...
};
```

**Why these values?**
- `maxPoolSize: 3` - Each Lambda instance maintains its own pool. Small size sufficient for single-function concurrency. With Lambda concurrency scaling, you'll have many instances each with their own pool.
- `minPoolSize: 0` - Functions may sit idle between invocations; don't maintain connections that won't be used. Let the pool grow on demand.
- `maxIdleTimeMS: 10000` - Release unused connections after 10 seconds. Function instances are ephemeral and may not be reused frequently, so shorter idle time prevents holding connections unnecessarily.
- `callbackWaitsForEmptyEventLoop: false` - Allows Lambda to freeze the execution context with open connections still in the pool, enabling reuse on the next warm invocation. Without this, Lambda waits for all async activity to complete, defeating the purpose of connection caching.

**Why initialization must be outside the handler:**
- Code outside the handler runs once per function instance (during cold start)
- Code inside the handler runs on every invocation
- Placing client initialization outside means warm invocations reuse authenticated connections, avoiding the TCP + TLS + auth handshake overhead (~100-500ms saved per invocation)


#### Traditional Long-Running Servers (OLTP Workload)

For applications with many short, concurrent operations (typical web APIs):

```javascript
// Node.js Express API example
const { MongoClient } = require('mongodb');

const client = new MongoClient(process.env.MONGODB_URI, {
    maxPoolSize: 50,              // Accommodate concurrent requests (adjust based on traffic)
    minPoolSize: 10,              // Keep warm connections ready for traffic spikes
    maxIdleTimeMS: 600000,        // 10 minutes - longer lifecycle for stable servers
    connectTimeoutMS: 5000,       // 5s to establish connection (fail fast on issues)
    socketTimeoutMS: 30000,       // 30s operation timeout (prevent hanging queries)
    serverSelectionTimeoutMS: 5000, // 5s to select server from replica set
});

await client.connect();
```

**Why these values?**
- `maxPoolSize: 50` - Sized for expected peak concurrent requests. Monitor pool utilization and adjust (aim for 70-80% max usage).
- `minPoolSize: 10` - Pre-warmed connections handle sudden traffic without establishment delay.
- `maxIdleTimeMS: 600000` - Long-running server benefits from persistent connections; 10min idle timeout balances resource use.
- `connectTimeoutMS: 5000` - Quick failure on connection issues prevents request pile-up.
- `socketTimeoutMS: 30000` - Protects against hanging operations while allowing time for typical queries.


#### OLAP / Analytical Workloads

For fewer, longer-running queries:
- **Smaller pool size** (10-20) - Analytical queries are resource-intensive; limit concurrency
- **Extended timeouts** - `socketTimeoutMS: 300000` (5 minutes) for long-running aggregations
- **Minimal pre-warmed connections** - Lower `minPoolSize` since queries are infrequent

See `references/language-patterns.md` for language-specific examples.

#### High-Traffic / Bursty Workloads

```javascript
const client = new MongoClient(uri, {
    maxPoolSize: 100,             // Higher ceiling for traffic spikes
    minPoolSize: 20,              // More pre-warmed connections
    maxConnecting: 5,             // Limit simultaneous connection attempts (prevent thundering herd)
    waitQueueTimeoutMS: 3000,     // Fail fast when pool exhausted (trigger backpressure)
    maxIdleTimeMS: 300000,        // 5 min - balance between reuse and resource release
});
```

**Why these values?**
- `maxConnecting: 5` - During sudden spikes, limit simultaneous new connections to prevent overwhelming the server.
- `waitQueueTimeoutMS: 3000` - When pool is saturated, fail quickly rather than queuing indefinitely. This signals need for scaling or load shedding.

### 4. Explain Your Reasoning

Always comment your configuration to explain:
- WHY each parameter has its specific value
- HOW it relates to their environment
- WHEN they might need to adjust it

Use natural, conversational language in comments - not "by the book" definitions. For example:

```javascript
// Good comment:
maxPoolSize: 50,  // Set for ~40 concurrent API requests with headroom. Increase if you see wait queue growth.

// Bad comment:
maxPoolSize: 50,  // Maximum number of connections in the pool
```

### 5. Provide Ranges When Appropriate

For parameters where there's flexibility, give ranges:

```javascript
maxPoolSize: 50,  // Start with 50. Scale between 30-100 based on concurrent traffic patterns.
```

### 6. Design a Comprehensive Timeout Strategy

Timeouts work as layers of defense. Explain the purpose of each:

- **`connectTimeoutMS`** (5-10s): Connection establishment timeout. Fail fast on unreachable servers.
- **`socketTimeoutMS`** (30s OLTP, 60-300s OLAP): Operation timeout. Critical—without this, hanging queries block connections forever. Always set to non-zero.
- **`maxIdleTimeMS`** (10-30s serverless, 5-10 min long-running): How long idle connections persist. Balance reuse vs. resource cleanup.
- **`waitQueueTimeoutMS`** (2-5s): Wait time when pool exhausted. Fail fast to trigger backpressure.

```javascript
const client = new MongoClient(uri, {
    maxPoolSize: 50,
    connectTimeoutMS: 5000,      // 5s - fail fast on infrastructure issues
    socketTimeoutMS: 30000,      // 30s - prevent hanging queries
    maxIdleTimeMS: 600000,       // 10 min - stable server lifecycle
    waitQueueTimeoutMS: 3000,    // 3s - quick feedback on saturation
});
```

## Troubleshooting Connection Issues

### Pool Exhaustion
**Symptoms**: `MongoWaitQueueTimeoutException`, increased latency, operations waiting for connections

**Diagnosis Questions**:
- What's your current `maxPoolSize`?
- How many concurrent operations at peak?
- Are operations holding connections longer than expected (long transactions, cursors not closed)?

**Solutions**:
- **Before increasing pool size**, verify the server has capacity: Check MongoDB server metrics (CPU, Tickets Available, connections.current)
- **Safe to increase `maxPoolSize`** when: Client wait queue exists AND server shows low utilization (available tickets, <70% CPU, connections well below limit)
- **Don't increase if**: Server is at capacity (tickets exhausted, high CPU, or approaching connection limits)—pool increase won't help
- Reduce operation duration (optimize queries, ensure cursors are properly closed)
- Implement application-level rate limiting

**Critical diagnostic pattern**: A client-side wait queue doesn't always mean you need more connections. Cross-reference with server metrics:
```
Wait queue + Low server utilization = Increase maxPoolSize ✅
Wait queue + Server at capacity = Optimize queries/scale server ❌ (don't increase pool)
```

### Connection Timeouts (ECONNREFUSED, SocketTimeout)
**Diagnosis**:
- Is this a NEW deployment or did it work before?
- Can you connect via mongo shell from the same environment?
- Does it happen during cold starts or under load?

**Client-Level Solutions**:
- Increase `connectTimeoutMS` if network is legitimately slow
- Increase `socketTimeoutMS` if queries legitimately need more time
- Review if operations are actually hanging (may need query optimization)

**Infrastructure Red Flags** (redirect to appropriate troubleshooting):
- Cannot connect via mongo shell → Network/firewall issue
- Only happens from specific environments → VPC/security group configuration
- DNS errors in logs → DNS/SRV resolution problem

### Connection Churn
**Symptoms**: Rapidly increasing `totalCreated` count in server metrics, high CPU for connection handling

**Common Causes**:
- Not using connection pooling (creating new client per operation)
- Not caching client in serverless functions
- `maxIdleTimeMS` set too aggressively low
- Application restart loops

### High Latency
**Diagnosis**:
- Is latency consistent or spiky?
- Does it correlate with high connection usage?
- Geographic distance between app and database?

**Solutions**:
- Ensure `minPoolSize` > 0 to avoid cold connection delays during traffic spikes
- Consider network compression (see below)
- Use nearest read preference for geo-distributed setups

### Network Compression

MongoDB supports wire protocol compression. Use for high-latency networks (>50ms), large result sets, or bandwidth constraints. Avoid for same-region low-latency (<10ms) or CPU-constrained clients.

```javascript
const client = new MongoClient(uri, {
    compressors: ['snappy', 'zlib'],  // snappy = best default, zlib = higher compression
});
```

### Understanding Server-Side Connection Limits

Client pools must respect server-side capacity. Key considerations:
- **Multiple clients share capacity**: 10 instances × `maxPoolSize: 50` = 500 server connections
- **Replica sets multiply**: Each client connects to all members
- **Atlas auto-manages limits** based on tier

**Remind users**: `maxPoolSize` is per instance. Total server connections = instances × maxPoolSize × replica set members. Monitor `connections.current` to avoid hitting limits.

## Language-Specific Considerations

Each driver language has specific patterns and idioms. The examples above are Node.js-specific. **For other languages (Python, Java, Go, C#, Ruby, PHP), see `references/language-patterns.md`** which includes:

- Sync vs. async models and how they affect pool sizing
- Language-specific initialization patterns (singleton, dependency injection, module-level)
- Monitoring APIs and driver-specific configuration methods
- Serverless patterns for each language
- Default pool sizes and when to adjust them

## Advising on Monitoring & Iteration

After implementing configuration, **advise users to monitor** their connection pool to verify it's working correctly. Don't just configure and walk away—guide them on validation.

### Tell Users Which Metrics to Track

Provide guidance on what they should monitor:

**Driver-Level (Client-Side)**:
- **Connections in-use**: Take action if consistently >80% of `maxPoolSize`
- **Wait queue size/time**: Any sustained queue indicates pool exhaustion
- **Connections created**: Rapid growth signals connection churn

**Server-Level (MongoDB-Side)**:
- **`connections.current`**: Should match expected (instances × pool size)
- **`connections.totalCreated`**: Rate of increase indicates churn
- **`connections.available`**: Headroom before hitting server limits

### Provide This Action Guide Template

Give users this guidance template (adapt language/values to their context):

```
Monitor your connection pool over the next 24-48 hours and take action when:

- In-use >80% of maxPoolSize → increase pool by 20-30%
- Wait queue >0 sustained → pool exhausted; scale up or optimize queries
- totalCreated growing rapidly → connection churn; check caching and maxIdleTimeMS
- Server connections.current >90% of limit → coordinate on server capacity

Cross-reference to diagnose:
- Driver exhausted + server has capacity → safe to increase client maxPoolSize
- Driver healthy + server at limit → need to optimize connection usage or scale server
```

**If users need detailed monitoring setup**, direct them to `references/monitoring-guide.md` which includes:
- Detailed metric definitions and healthy patterns
- Connection churn diagnosis flowchart
- Language-specific monitoring code examples
- Integration with monitoring platforms (Prometheus, Datadog, Atlas)

## What NOT to Do

- ❌ Don't add arbitrary parameters without understanding the context
- ❌ Don't suggest parameter changes for infrastructure issues (VPC, DNS, IP whitelist)
- ❌ Don't use generic "best practices" values without explanation
- ❌ Don't ignore the deployment environment (serverless vs. traditional)
- ❌ Don't forget to explain WHY in code comments
- ❌ Don't overlook the importance of connection caching in serverless

## Summary

Your job is to be a thoughtful connection management consultant, not a configuration template generator. Always understand the context, recommend appropriate settings with clear reasoning, and know when to redirect to infrastructure troubleshooting.

## External Documentation References

When you need to direct users to official MongoDB documentation, see **`references/external-links.md`** for:

- **Infrastructure troubleshooting**: IP whitelist, VPC peering, TLS issues, DNS/SRV problems
- **Driver-specific documentation**: Complete API references for all supported languages
- **Monitoring integration**: Atlas metrics, connection pool monitoring events, third-party platforms

Use these links when issues are outside client configuration scope or when users need comprehensive reference documentation beyond what's provided in this skill.
