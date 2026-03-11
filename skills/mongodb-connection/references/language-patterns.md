# Language-Specific Connection Patterns

This reference provides language-specific patterns and considerations for MongoDB connection management. Consult this when working with a specific driver or when users ask about best practices for their language.

## Node.js

### Key Characteristics
- **Async/event-loop based**: Non-blocking I/O model
- **Single-threaded**: Event loop handles concurrency
- **Connection pool per `MongoClient` instance**
- **Default pool size: 5** (unlike 100 in most other drivers)

### Why Node.js Has a Smaller Default Pool Size

Node.js defaults to `maxPoolSize: 5`, not 100 like other drivers. This is due to **internal concurrency limitations** in the Node.js runtime:

**The problem**: The driver's connection handling operates on a limited thread pool. Under heavy load with many pooled connections, this thread can become **starved**—too busy managing the pool to service individual connections within the timeout window.

**The symptom**: With larger pools (e.g., 50-100 connections) and busy operations, connections can sit idle in the pool while the handling thread is overwhelmed, leading to connection timeouts even though connections are technically available.

**The solution**: Node.js uses a smaller default (5) to match its single-threaded concurrency model. The event loop efficiently multiplexes many operations over these few connections.

**When to increase**: You can increase `maxPoolSize` beyond 5 for Node.js, but:
- Monitor for connection timeout issues under load
- If you need more concurrency, consider multiple `MongoClient` instances (different Node processes/instances)
- Alternative: Use a more scalable driver (Python, Java) if you hit Node's scaling limits

### Best Practices
- **Singleton pattern**: Create one `MongoClient` instance and export it
- **Efficient with smaller pools**: Event loop multiplexes many operations over fewer connections (5-20 typically sufficient)
- **Module-level initialization**: For serverless, initialize outside the handler
- **Don't blindly increase pool size**: Node.js efficiency comes from its async model, not connection count

---

## Python

### PyMongo (Synchronous)

#### Key Characteristics
- **Blocking I/O**: Each operation blocks the calling thread
- **Thread-safe**: One client per application, shared across threads
- **Pool size relative to thread count**

#### Best Practices
- **One client for the application**: PyMongo internally manages threading
- **Pool size should match or exceed thread pool size**
- **Use `with` statements for session management**

### Motor (Asynchronous)

#### Key Characteristics
- **Non-blocking async/await**: Built on top of asyncio
- **Event-loop based**: Similar efficiency to Node.js
- **More efficient with smaller pools**

#### Best Practices
- **Smaller pool sizes**: Event loop enables high concurrency with few connections
- **Initialize once**: Share client across application
- **Use async context managers**

---

## Java

### Key Characteristics
- **Both sync and async APIs**: Choose based on application architecture
- **Thread-per-request common**: Traditional servlet containers
- **Reactive Streams support**: For reactive frameworks

### Best Practices
- **Spring Boot**: Configure via `MongoClientSettings` bean
- **Thread pool coordination**: For sync API, pool size often matches thread pool size
- **One client per application**: Singleton pattern via dependency injection

---

## Go

### Key Characteristics
- **Context-based timeouts**: Idiomatic Go pattern for cancellation and timeouts
- **Goroutine-safe**: Client can be shared across goroutines
- **Default pool size**: `maxPoolSize` defaults to 100 connections

### Best Practices
- **Prefer context timeouts over driver timeouts**: Use `context.WithTimeout` for operation-level control
- **Default pool usually sufficient**: 100 connections handles most workloads
- **Package-level initialization**: Share client across application

---

## C# (.NET)

### Key Characteristics
- **Connection string-based configuration**: Many options can be set via connection string
- **Thread-safe client**: Share single `MongoClient` instance
- **Async/await support**: Modern asynchronous programming model

### Best Practices
- **One client instance per application lifecycle**: MongoClient is expensive to create
- **Use dependency injection**: Register as singleton in ASP.NET Core
- **Connection string OR MongoClientSettings**: Choose one approach for clarity

---

## Ruby

### Key Characteristics
- **Thread-safe client**: Can be shared across threads
- **Pool per server**: In replica sets, separate pools for each member
- **Rack middleware available**: For connection management in web apps

### Best Practices
- **Global client**: Initialize once, use throughout application
- **Monitor pool metrics**: Use built-in monitoring events
- **Consider Rack middleware**: For Rails/Sinatra applications

---

## PHP

### Key Characteristics
- **Connection per request model**: Traditional PHP request lifecycle
- **Extension + library**: `mongodb` extension + `mongodb/mongodb` library
- **Connection persistence**: Connections persist across requests via extension

### Best Practices
- **Initialize client per request**: In traditional PHP, client is created per request
- **Connection pooling handled by extension**: The C extension manages connection reuse
- **Use MongoDB Library**: High-level API over the extension

### Note on Connection Pooling
The PHP extension manages connection pooling at the process level. In traditional PHP-FPM setups, each worker process maintains its own pool. In PHP async frameworks (Swoole, ReactPHP), connection management differs and requires special consideration.

---

## General Patterns Across Languages

### Default Pool Sizes

Most MongoDB drivers default to **`maxPoolSize: 100`**, with one notable exception:

- **Node.js**: Default is **5** (due to runtime concurrency limitations—see Node.js section above)
- **All other drivers** (Python, Java, Go, C#, Ruby, PHP, etc.): Default is **100**

**When defaults are appropriate**:
- ✅ For most applications, the default is a reasonable starting point
- ✅ Node.js's default of 5 works well for typical event-loop workloads
- ✅ Other drivers' default of 100 handles moderate traffic for sync drivers

**When to adjust**:
- Increase if you observe sustained connection pool exhaustion (wait queue growth, >80% utilization)
- Decrease for low-traffic applications to reduce resource footprint
- **Don't change without reason**—defaults are based on extensive real-world usage patterns

### Connection Lifecycle
1. **Initialize once**: Create client at application startup
2. **Share globally**: Use singleton or dependency injection patterns
3. **Never create per-operation**: Extremely expensive
4. **Let the driver manage**: Don't manually close connections unless shutting down

### Monitoring Access
Most drivers provide:
- **Event listeners**: Subscribe to connection pool events
- **Statistics APIs**: Query current pool state
- **Logging**: Enable debug logging for troubleshooting

### Serverless Considerations
All languages benefit from similar patterns in serverless:
- Initialize client outside handler/function scope
- Use smaller pool sizes (3-5 connections)
- Shorter `maxIdleTimeMS` (10-30 seconds)
- Prevent function runtime from waiting for pool cleanup
