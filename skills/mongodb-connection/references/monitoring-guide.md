# MongoDB Connection Monitoring Guide

This reference provides detailed guidance on monitoring connection pool health, interpreting metrics, and taking action based on what you observe. Consult this when users need to verify their configuration is working or troubleshoot connection-related issues.

---

## Driver-Level Metrics (Client-Side)

Modern MongoDB drivers expose connection pool telemetry events, providing a client-side view of connection health. Access methods vary by driver. For example:
- **Node.js**: Event listeners (`client.on('connectionPoolCreated', ...)`)
- **Python (PyMongo and Motor)**: Event listeners via `monitoring.ConnectionPoolListener`
- **Java**: `ConnectionPoolListener` interfaces

Consult your driver's [documentation](https://www.mongodb.com/docs/drivers/) for how to subscribe to these standard events.

Subscribe to the required events and keep stats for the relevant properties.

### Connections Created

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

---

### Connections Available (Idle Connections)

**What it is**: The number of open but unused connections ready in the pool.

**What to watch for**: Consistently zero means the pool is undersized.

**Healthy pattern**: Some available connections (10-20% of `maxPoolSize`) ready to handle sudden traffic spikes without waiting for new connection establishment.

**Action thresholds**:
- **Always zero during traffic**: Pool is too small; connections are never released
- **Very low during normal load**: Consider increasing `maxPoolSize` or `minPoolSize`

---

### Wait Queue Size

**What it is**: The number of operations currently waiting for an available connection because the pool is at capacity.

**What to watch for**: Any value above zero indicates possible pool exhaustion. This is a critical metric.

**Healthy pattern**: Zero most of the time, or occasional spikes during peak loads.

**Action thresholds**:
- **Any sustained queue (>0 for >10 seconds)**: Immediate action required
- **Repeated queuing**: Increase `maxPoolSize` or reduce operation duration
- **Queue correlates with specific operations**: Those operations may be holding connections too long

**Why this matters**: If `waitQueueTimeoutMS` is reached, users see errors.

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

### `connections.current`

**What it is**: The number of active client connections currently established to the MongoDB server.

**What to watch for**: Approaching `maxIncomingConnections` indicates server-side saturation.

**Default maxIncomingConnections values per OS**: 
- Windows: 1,000,000
- Linux/Unix: `(RLIMIT_NOFILE / 2) * 0.8` (MongoDB enforces this limit even if configured higher)

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
- **Correlation with client metrics**: Cross-reference with driver-level total connections to identify which clients are churning

**Example**: If you see `totalCreated` increasing by 1,000 connections/hour but you only restart apps once per day (not serverless), something is causing unnecessary connection cycling.

---

### WiredTiger Tickets Available

**What it is**: MongoDB's WiredTiger storage engine uses a ticket-based concurrency control system. Tickets represent slots for concurrent read and write operations. When all tickets are in use, additional operations must wait.

**Ticket counts**:
  - **Maximum**: 128 read tickets and 128 write tickets (never exceeds this)
  - **MongoDB 7.0+**: Uses dynamic adjustment algorithm that starts with a much lower baseline and adjusts based on workload
  - **Pre-7.0**: Fixed value (documentation does not specify the exact default)

**What to watch for**: Low available tickets indicate the server is at maximum concurrency capacity, regardless of connection availability.

**Healthy pattern**: Should have available tickets. If tickets are frequently exhausted while connections are available, the bottleneck is server-side processing capacity, not connections.

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
- `read.totalTickets` / `write.totalTickets` - Total ticket count

**Reference**: [WiredTiger concurrentTransactions](https://www.mongodb.com/docs/manual/reference/command/serverStatus/#mongodb-serverstatus-serverstatus.wiredTiger.concurrentTransactions)

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
