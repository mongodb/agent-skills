# MongoDB Connection Monitoring Guide

This reference provides detailed guidance on monitoring connection pool health, interpreting metrics, and taking action based on what you observe. Consult this when users need to verify their configuration is working or troubleshoot connection-related issues.

---

## Driver-Level Metrics (Client-Side)

Modern MongoDB drivers expose connection pool telemetry, providing a client-side view of connection health. Access methods vary by driver:
- **Node.js**: Event listeners (`client.on('connectionPoolCreated', ...)`)
- **Python**: `client.get_server_pool_stats()`
- **Java**: `ConnectionPoolListener` interfaces
- **Go**: Monitoring through driver configuration

### Connections Created (`totalCreated`)

**What it is**: The total number of connections the pool has established since initialization.

**What to watch for**: Rapid increases indicate connection churn due to network issues or misconfiguration.

**Healthy pattern**: Gradual increase during application startup as the pool warms up, then relatively stable. You should see increases mainly when:
- Application restarts
- Pool size is increased
- Network disruptions force reconnections

**Troubleshooting**:
- **Rapid growth** (+100 connections/hour in steady state): Indicates connection churn. Check:
  - `maxIdleTimeMS` is not too aggressive
  - Network stability
  - Application not creating new clients repeatedly
  - Serverless functions caching clients properly

---

### Connections In-Use

**What it is**: The number of connections currently borrowed from the pool and serving application requests.

**What to watch for**: Consistently high values approaching `maxPoolSize` signal potential pool exhaustion.

**Healthy pattern**: Fluctuates with application traffic while maintaining headroom. Should correlate with request volume.

**Action thresholds**:
- **Sustained >80% of maxPoolSize**: Increase `maxPoolSize` by 20-30%
- **Consistently 100%**: Pool is definitely exhausted; immediate action needed
- **High percentage with high wait queue times**: Clear sign of undersized pool

**Diagnosis questions**:
- Does it correlate with traffic spikes?
- Are operations taking longer than expected to complete?
- Are there any long-running queries holding connections?

---

### Connections Available (Idle)

**What it is**: The number of open but unused connections ready in the pool.

**What to watch for**: Consistently zero means the pool is undersized.

**Healthy pattern**: Some available connections (at least 10-20% of `maxPoolSize`) ready to handle sudden traffic spikes without waiting for new connection establishment.

**Action thresholds**:
- **Always zero during traffic**: Pool is too small; connections are never released
- **Very low during normal load**: Consider increasing `maxPoolSize` or `minPoolSize`

---

### Wait Queue Size

**What it is**: The number of operations currently waiting for an available connection because the pool is at capacity.

**What to watch for**: Any value above zero indicates possible pool exhaustion. This is a critical metric.

**Healthy pattern**: Zero most of the time, or very brief, occasional spikes during peak loads (and only if those spikes resolve quickly).

**Action thresholds**:
- **Any sustained queue (>0 for >10 seconds)**: Immediate action required
- **Repeated queuing**: Increase `maxPoolSize` or reduce operation duration
- **Queue correlates with specific operations**: Those operations may be holding connections too long

**Why this matters**: Operations in the wait queue add latency directly to user-facing requests. If `waitQueueTimeoutMS` is reached, users see errors.

---

### Wait Queue Time

**What it is**: The duration operations spend waiting for connections to become available.

**What to watch for**: This wait time directly adds to application latency. Even moderate wait times (50-100ms) can degrade user experience.

**Healthy pattern**: Consistently near-zero milliseconds.

**Action thresholds**:
- **>50ms consistently**: Pool is under pressure; investigate sizing
- **>100ms**: Immediate action required; users experiencing degraded performance
- **Spikes to >waitQueueTimeoutMS**: Users seeing timeout errors

---

## Server-Level Metrics (MongoDB-Side)

Server-side metrics provide the MongoDB server's perspective on connection usage. Access via:
- `db.adminCommand({ serverStatus: 1 }).connections`
- MongoDB Atlas monitoring dashboards
- Integration with monitoring platforms (Prometheus, Datadog, etc.)

### `connections.current`

**What it is**: The number of active client connections currently established to the MongoDB server.

**What to watch for**: Approaching `maxIncomingConnections` (default: 65,536) indicates server-side saturation.

**Healthy pattern**: Stable value with headroom for growth. Should roughly match the sum of all client pool sizes across all application instances.

**Action thresholds**:
- **>90% of maxIncomingConnections**: Server at risk of refusing new connections
- **Unexpected spikes**: May indicate runaway connection creation from clients
- **Steady growth**: May need to scale server tier (Atlas) or adjust configuration (self-hosted)

**Calculation example**: If you have 10 application instances each with `maxPoolSize: 50`, you could have up to 500 connections in a single-server deployment. In a 3-member replica set, potentially 1,500 total connections across all members.

---

### `connections.available`

**What it is**: How many more connections the server can accept before hitting its configured limit.

**What to watch for**: Low values indicate risk of connection refusal for new clients or scaling operations.

**Healthy pattern**: Substantial headroom even during peak traffic. At least 20-30% of `maxIncomingConnections` should remain available.

**Action thresholds**:
- **<10% available**: High risk; urgent capacity planning needed
- **<5% available**: Critical; new client connections may be refused

---

### `connections.totalCreated`

**What it is**: The cumulative total of all connections created since the MongoDB server started.

**What to watch for**: The rate of increase indicates connection churn. Compare snapshots over time to calculate rate.

**Healthy pattern**: Increases mainly during:
- Application deployments/restarts
- Scaling events (adding new app instances)
- Legitimate traffic growth

**Diagnosis**:
- **Baseline calculation**: After initial warmup, calculate connections created per hour
- **Rapid increase** (much faster than app restart cadence): Indicates connection churn across one or more clients
- **Correlation with client metrics**: Cross-reference with driver-level `totalCreated` to identify which clients are churning

**Example**: If you see `totalCreated` increasing by 1,000 connections/hour but you only restart apps once per day, something is causing unnecessary connection cycling.

---

### WiredTiger Tickets Available

**What it is**: MongoDB's WiredTiger storage engine uses a ticket-based concurrency control system. Tickets represent slots for concurrent read and write operations. When all tickets are in use, additional operations must wait.

**Default ticket counts** (MongoDB 3.6+):
- Read tickets: 128
- Write tickets: 128

**What to watch for**: Low available tickets indicate the server is at maximum concurrency capacity, regardless of connection availability.

**Healthy pattern**: Should have available tickets even during normal load. If tickets are frequently exhausted while connections are available, the bottleneck is server-side processing capacity, not connections.

**Action thresholds**:
- **Tickets available = 0 frequently**: Server is at capacity; operations will queue even if connections are available
- **Persistent ticket exhaustion**: Consider query optimization, indexing improvements, or scaling server tier
- **Tickets exhausted + low CPU**: May indicate lock contention or slow I/O

**Important diagnostic pattern**:
- **Client shows wait queue + Server has tickets available**: Increase client `maxPoolSize`
- **Client pool healthy + Server tickets exhausted**: Server-side bottleneck; optimize queries or scale server
- **Both exhausted**: Need both client pool increase AND server capacity/optimization

**How to check**: Query `db.serverStatus().wiredTiger.concurrentTransactions` to see:
- `read.available` / `write.available` - Tickets currently available
- `read.out` / `write.out` - Tickets currently in use
- `read.totalTickets` / `write.totalTickets` - Total ticket count (typically 128 each)

**Reference**: [WiredTiger concurrentTransactions](https://www.mongodb.com/docs/manual/reference/command/serverStatus/#mongodb-serverstatus-serverstatus.wiredTiger.concurrentTransactions)

---

## Practical Monitoring Guidance

Use this template when advising users on what to monitor after implementing configuration:


> Monitor your connection pool over the next 24-48 hours:
>
> ### Driver-Side Metrics (from your application)
> 
> 1. Connections In-Use:
>   - If consistently >80% of maxPoolSize → increase maxPoolSize by 20-30%
>   - Track peak usage to determine appropriate sizing
>
> 2. Wait Queue:
>   - If size >0 during normal traffic → pool exhausted, scale up or optimize operations
>   - If wait time >50ms → investigate immediately
>
> 3. Connections Created (totalCreated):
>   - If growing rapidly (+100/hour in steady state) → connection churn issue
>   - Compare growth rate to application restart frequency
>
> ### Server-Side Metrics (from MongoDB)
>
> 1. connections.current:
>   - Should be stable and match expected (instances × maxPoolSize)
>   - If approaching 90% of maxIncomingConnections → coordinate with DBA about server limits or scaling
>
> 2. connections.totalCreated:
>   - Compare rate of increase over time
>   - If increasing much faster than app deployment/restart cycle → check client connection caching
>
> ### Cross-Reference Patterns (Critical for Diagnosing Pool Issues)
>
> Before increasing `maxPoolSize`, always cross-reference client and server metrics. A wait queue doesn't automatically mean you need more connections.
> 
> - **Driver shows pool exhaustion (wait queue >0) + Server has available capacity (low CPU, tickets available, connections well below limit)**
  → ✅ **Safe to increase client maxPoolSize**—server can handle more connections
>
> - **Driver shows pool exhaustion + Server at capacity (tickets exhausted, high CPU, or >90% of connection limit)**
  → ❌ **Don't increase pool**—optimize queries or scale server tier instead
>
> - **Driver shows healthy pool + Server at capacity limits**
  → Need to optimize connection usage or scale server tier (not a pool sizing issue)
>
> - **Both show high connection creation (totalCreated growing rapidly)**
  → Investigate client caching, maxIdleTimeMS settings, or network stability
>
> - **Wait queue grows but server metrics show available capacity**
  → Client pool undersized; increase maxPoolSize
>
> **Key insight from MongoDB best practices**: Only increase `maxPoolSize` when you observe a request queue in the application **AND** MongoDB server metrics show low utilization. This prevents the common mistake of increasing pool size when the actual bottleneck is server capacity or query performance.

---

## Connection Churn Diagnosis

Connection churn—rapid creation and destruction of connections—wastes resources and degrades performance. Identifying and resolving churn is critical for stable operation.

### Symptoms

- **Driver-side**: `totalCreated` increasing rapidly relative to stable connection counts
- **Server-side**: `connections.totalCreated` growing much faster than expected
- **High CPU on server**: Connection establishment is CPU-intensive (handshakes, authentication)
- **Logs**: Frequent connection open/close events (enable debug logging)

### Common Causes and Solutions

#### 1. Not Using Connection Pooling

**Problem**: Application creates a new `MongoClient` for each operation instead of reusing one.

**Detection**:
- `totalCreated` increases with each operation
- Connection count never stabilizes
- Code review reveals client creation in request handlers

**Solution**: Create the MongoClient once at application initialization and reuse it throughout the application lifecycle. The client manages the connection pool internally—creating a new client for each operation bypasses pooling entirely and forces new connection establishment every time.

#### 2. Serverless Functions Not Caching Client

**Problem**: Serverless function creates new client inside the handler function instead of outside.

**Detection**:
- Cold starts create connections as expected
- Warm invocations also show new connection creation
- Connection count increases with invocation count, not instance count

**Solution**: Initialize the MongoClient **outside** the handler function (at module/global scope). This allows the client to be reused across warm invocations of the same function instance. Clients created inside the handler are recreated on every invocation, defeating connection pooling entirely.

#### 3. `maxIdleTimeMS` Set Too Low

**Problem**: Connections are closed and recreated too frequently during normal operation.

**Detection**:
- Connection creation correlates with traffic patterns
- Connections created during low-traffic periods after idle time
- `maxIdleTimeMS` < 60 seconds for most applications

**Solution**:
- Increase `maxIdleTimeMS` to balance reuse and resource cleanup
- Serverless: 10-30 seconds (ephemeral context)
- Long-running servers: 5-10 minutes (300,000-600,000ms)
- Consider intermediate network device timeouts

#### 4. Application Restart Loops

**Problem**: Application continuously restarting due to crashes or orchestration issues.

**Detection**:
- Server logs show frequent application connections/disconnections
- Deployment platform shows high restart rate
- Each restart creates `minPoolSize` connections immediately

**Solution**: Fix root cause of application instability.

#### 5. Network Issues

**Problem**: Frequent network disruptions force reconnections.

**Detection**:
- Connection creation correlates with network errors in logs
- May see "connection reset" or "EOF" errors
- Intermittent connectivity to MongoDB

**Solution**:
- Investigate network stability between application and database
- Check intermediate devices (firewalls, load balancers, proxies)
- Verify network configurations (VPC peering, security groups, DNS)

---

## Setting Up Monitoring

### Application-Level Monitoring

#### Event-Based Monitoring

All MongoDB drivers implement the [Connection Monitoring and Pooling specification](https://github.com/mongodb/specifications/blob/master/source/connection-monitoring-and-pooling/connection-monitoring-and-pooling.md), which defines standard events for tracking pool lifecycle and connection state:

**Pool lifecycle events**:
- `connectionPoolCreated` / `connectionPoolClosed` - Track when pools are initialized or shut down

**Connection lifecycle events**:
- `connectionCreated` / `connectionClosed` - Monitor connection churn (rapid creation = pooling issues)

**Check-out events**:
- `connectionCheckOutStarted` - Operation requests a connection
- `connectionCheckedOut` / `connectionCheckedIn` - Track when connections are borrowed/returned
- `connectionCheckOutFailed` - **Critical alert signal** - indicates pool exhaustion

**What to instrument**: Send `connectionCheckOutFailed` events and rapid `connectionCreated` events to your monitoring system immediately.

**Implementation**: Consult your driver's documentation for how to subscribe to these standard events. Search for "connection pool monitoring" or "connection pool events" in your driver's API documentation. This is the official driver documentation url: https://www.mongodb.com/docs/drivers/

### Server-Level Monitoring

#### Querying Server Status

Use `db.serverStatus().connections` (via MongoDB shell or driver equivalent) to retrieve server-side connection metrics:

**Available fields**:
- `current` - Total active client connections
- `available` - Remaining capacity before hitting `maxIncomingConnections`
- `totalCreated` - Cumulative connections created since server start
- `active` - Connections currently executing operations
- `exhaustIsMaster` / `exhaustHello` - Streaming topology monitoring connections
- `awaitingTopologyChanges` - Connections waiting for topology updates

**Reference**: [db.serverStatus() documentation](https://www.mongodb.com/docs/manual/reference/command/serverStatus/#connections)

#### Monitoring Integration

Most monitoring platforms support MongoDB:

- **MongoDB Atlas**: Built-in metrics dashboard with connection monitoring
- **Prometheus**: Use mongodb_exporter for metrics collection
- **Datadog**: MongoDB integration with connection metrics
- **New Relic**: MongoDB monitoring with connection tracking

**Key metrics to track**:
- `connections.current` (gauge)
- `connections.totalCreated` (counter - calculate rate)
- `connections.available` (gauge)
- Pool in-use percentage (calculated: in_use / maxPoolSize)
- Wait queue size (gauge)
- Wait queue time (histogram)

**Alerting thresholds**:
- Alert if in-use > 80% for > 5 minutes
- Alert if wait queue > 0 for > 30 seconds
- Alert if wait queue time > 100ms
- Alert if connections.current > 90% of maxIncomingConnections
- Alert if connection churn rate exceeds baseline by 3x

---

## Summary

Effective monitoring requires tracking both driver and server metrics, understanding what healthy patterns look like, and knowing when to take action. Use this guide to:

1. Set up proper instrumentation in your application and monitoring platform
2. Establish baselines for normal operation
3. Set meaningful alerts for abnormal conditions
4. Diagnose issues quickly when they occur
5. Make informed decisions about pool sizing and configuration adjustments

Remember: connection metrics are leading indicators of performance issues. Proactive monitoring prevents user-facing problems.
