# Language-Specific Connection Patterns

This reference provides language-specific patterns and considerations for MongoDB connection management. Consult this when working with a specific driver or when users ask about best practices for their language.

## Node.js

### Key Characteristics
- **Async/event-loop based**: Non-blocking I/O model
- **Single-threaded**: Event loop handles concurrency
- **Connection pool per `MongoClient` instance**
- **Default pool size: 100** (modern drivers: Node.js Driver 4.x+, Mongoose 6.x+, released 2021+)
  - Legacy versions (Node.js Driver 3.x, Mongoose 5.x, pre-2021) defaulted to 5

### Best Practices
- **Default is usually sufficient**: The default of 100 works well for most applications
- **Event loop efficiency**: Node.js can handle high concurrency with fewer connections than thread-based runtimes due to its async model
- **Typical range**: 10-50 connections often sufficient for most Node.js workloads
- **Singleton pattern**: Create one `MongoClient` instance and export it
- **Module-level initialization**: For serverless, initialize outside the handler

**Alternative scaling approaches**:
- Multiple `MongoClient` instances across different Node processes/instances
- Horizontal scaling (more application instances with smaller pools each)
- If you hit Node's scaling limits, consider multi-threaded drivers (Python, Java, Go)

**Note for legacy applications**: If you're maintaining older code with Node.js Driver 3.x or Mongoose 5.x, remember these versions defaulted to pool size 5. Consider upgrading to modern versions (4.x+/6.x+) for the improved default of 100 and better performance

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

All modern MongoDB drivers default to **`maxPoolSize: 100`** (Node.js, Python, Java, Go, C#, Ruby, PHP, etc.).

**When defaults are appropriate**:
- For most applications, the default of 100 is a reasonable starting point
- Modern async drivers (Node.js 4.x+, Motor) can handle high concurrency with fewer connections due to non-blocking I/O
- Sync drivers' default of 100 handles moderate traffic well

**When to adjust**:
- Increase if you observe sustained connection pool exhaustion (wait queue growth, >80% utilization)
- Decrease for low-traffic applications to reduce resource footprint
- Decrease for serverless environments (3-10 per function instance)
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
