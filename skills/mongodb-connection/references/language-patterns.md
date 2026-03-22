# Language-Specific Connection Patterns

This reference provides language-specific patterns and considerations for MongoDB connection management. Consult this when working with a specific driver or when users ask about best practices for their language.

**Note**: See "General Patterns Across Languages" at the bottom for best practices that apply to all drivers.

## Node.js

### Key Characteristics
- **Async/event-loop based**: Non-blocking I/O model
- **Single-threaded**: Event loop handles concurrency
- **Connection pool per `MongoClient` instance**
- **Default pool size: 100** (modern drivers: Node.js Driver 4.x+, Mongoose 6.x+, released 2021+)
  - Legacy versions (Node.js Driver 3.x, Mongoose 5.x, pre-2021) defaulted to 5

### Best Practices
- **Event loop efficiency**: Node.js can handle high concurrency with fewer connections than thread-based runtimes due to its async model
- **Typical range**: 10-50 connections often sufficient for most Node.js workloads

---

## Python

PyMongo is the official MongoDB driver for Python, supporting synchronous and asynchronous operations.
Motor is the legacy asynchronous Python driver. Motor's EOL is **May 14th, 2026**. Critical bug fixes continue until May 14th, 2027.

#### Synchronous API (`pymongo`)

**Key Characteristics**:
- **Blocking I/O**: Each operation blocks the calling thread
- **Thread-safe**: One client per application, shared across threads
- **Pool size relative to thread count**

**Best Practices**:
- **Pool size should match or exceed thread pool size**
- **Use `with` statements for session management**

#### Asynchronous API (`pymongo.asynchronous` and Motor)

**Key Characteristics**:
- **Non-blocking async/await**: Built on asyncio
- **Event-loop based**: Similar efficiency to Node.js
- **More efficient with smaller pools**

**Best Practices**:
- **Smaller pool sizes work well**: Event loop enables high concurrency with fewer connections
- **Use async context managers for session management**

---

## Java

### Key Characteristics
- **Both sync and async APIs**: Choose based on application architecture
- **Thread-per-request common**: Traditional servlet containers
- **Reactive Streams support**: For reactive frameworks

### Best Practices
- **Use singleton pattern via dependency injection**
- **Thread pool coordination**: For sync API, pool size often matches thread pool size

---

## Go

### Key Characteristics
- **Context-based timeouts**: Idiomatic Go pattern for cancellation and timeouts
- **Goroutine-safe**: Client can be shared across goroutines
- **Default pool size**: `maxPoolSize` defaults to 100 connections

### Best Practices
- **Initialize at package level and share**
- **Prefer context timeouts over driver timeouts**: Use `context.WithTimeout` for operation-level control

---

## C# (.NET)

### Key Characteristics
- **Connection string-based configuration**: Many options can be set via connection string
- **Thread-safe client**: Share single `MongoClient` instance
- **Async/await support**: Modern asynchronous programming model

### Best Practices
- **Register as singleton in ASP.NET Core via dependency injection**
- **Connection string OR MongoClientSettings**: Choose one approach for clarity

---

## Ruby

### Key Characteristics
- **Thread-safe client**: Can be shared across threads
- **Pool per server**: In replica sets, separate pools for each member
- **Rack middleware available**: For connection management in web apps

### Best Practices
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

### Best Practices (All Drivers, except PHP)

**Note**: PHP differs significantly from other languages due to its unique request lifecycle. See the PHP section for PHP-specific patterns.

- **Initialize once at startup, reuse across application**
- **Client creation is expensive—create once only**
- **Use default pool size (100) unless you have specific needs**
- **Serverless: Initialize outside handler function**

### Default Pool Sizes

All modern MongoDB drivers default to **`maxPoolSize: 100`** (Node.js, Python, Java, Go, C#, Ruby, PHP, etc.).

**When defaults are appropriate**:
- For most applications, the default maxPoolSize is a reasonable starting point
- Modern async drivers can handle high concurrency with fewer connections due to non-blocking I/O

**When to adjust**:
- Increase if you observe sustained connection pool exhaustion (wait queue growth, >80% utilization)
- Decrease for low-traffic applications to reduce resource footprint
- Decrease for serverless environments

### Connection Lifecycle
1. **Initialize once**: Create client at application startup
2. **Share globally**: Use singleton or dependency injection patterns
3. **Never create per-operation**: Extremely expensive
4. **Let the driver manage**: Don't manually close connections unless shutting down

### Monitoring Access
Drivers provide Event listeners: Subscribe to connection pool events
