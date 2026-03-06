# External Documentation Links

Use these links when directing users to official MongoDB documentation for infrastructure troubleshooting, driver-specific details, or advanced configuration topics.

## Table of Contents
- [Infrastructure Troubleshooting](#infrastructure-troubleshooting)
- [Driver Documentation](#driver-documentation--connection-options)
- [Monitoring & Metrics](#monitoring--metrics-documentation)

---

## Infrastructure Troubleshooting

### MongoDB Atlas

- **IP Access List Configuration**: https://www.mongodb.com/docs/atlas/security/ip-access-list/
  - Use when users cannot connect due to IP restrictions

- **VPC Peering**: https://www.mongodb.com/docs/atlas/security-vpc-peering/
  - For private network connectivity between application VPC and Atlas

- **Private Endpoints (AWS PrivateLink)**: https://www.mongodb.com/docs/atlas/security-private-endpoint/
  - For secure, private connectivity without internet traversal

- **Connection String Formats**: https://www.mongodb.com/docs/manual/reference/connection-string/
  - Complete reference for connection string syntax and options

- **DNS Seed List (SRV) Connections**: https://www.mongodb.com/docs/manual/reference/connection-string/#dns-seed-list-connection-format
  - For troubleshooting `mongodb+srv://` connection strings

### Network & Connectivity

- **Connection Troubleshooting Guide**: https://www.mongodb.com/docs/atlas/troubleshoot-connection/
  - Comprehensive guide for diagnosing connection failures

- **TLS/SSL Configuration**: https://www.mongodb.com/docs/manual/tutorial/configure-ssl/
  - For certificate validation and TLS issues

---

## Driver Documentation & Connection Options

### Node.js Driver

- **MongoClient Options**: https://mongodb.github.io/node-mongodb-native/6.11/interfaces/MongoClientOptions.html
  - Complete list of configuration options

- **Connection Pool Monitoring**: https://mongodb.github.io/node-mongodb-native/6.11/classes/MongoClient.html#on
  - Event listeners for pool telemetry

- **Node.js Driver Documentation Home**: https://www.mongodb.com/docs/drivers/node/current/

### Python Drivers

**PyMongo (Synchronous)**
- **MongoClient API**: https://pymongo.readthedocs.io/en/stable/api/pymongo/mongo_client.html
  - PyMongo client configuration and connection options

- **Connection Pooling**: https://pymongo.readthedocs.io/en/stable/api/pymongo/pool.html
  - Pool behavior and configuration

**Motor (Asynchronous)**
- **AsyncIOMotorClient**: https://motor.readthedocs.io/en/stable/api-asyncio/asyncio_motor_client.html
  - Async/await driver for Python asyncio

- **Motor Tutorial**: https://motor.readthedocs.io/en/stable/tutorial-asyncio.html

### Java Driver

- **MongoClientSettings**: https://mongodb.github.io/mongo-java-driver/5.2/apidocs/mongodb-driver-core/com/mongodb/MongoClientSettings.html
  - Client configuration builder

- **Connection Pool Settings**: https://mongodb.github.io/mongo-java-driver/5.2/apidocs/mongodb-driver-core/com/mongodb/connection/ConnectionPoolSettings.html
  - Detailed pool configuration options

- **Java Driver Documentation Home**: https://www.mongodb.com/docs/drivers/java/sync/current/

### Go Driver

- **Client Options**: https://pkg.go.dev/go.mongodb.org/mongo-driver/mongo/options#ClientOptions
  - Go driver configuration options

- **Go Driver Documentation**: https://www.mongodb.com/docs/drivers/go/current/

### C# (.NET) Driver

- **MongoClientSettings**: https://mongodb.github.io/mongo-csharp-driver/2.28.0/apidocs/html/T_MongoDB_Driver_MongoClientSettings.htm
  - .NET client configuration

- **Connection String Options**: https://www.mongodb.com/docs/drivers/csharp/current/fundamentals/connection/connection-options/
  - Options that can be set via connection string

- **C# Driver Documentation Home**: https://www.mongodb.com/docs/drivers/csharp/current/

### Ruby Driver

- **Client Options**: https://www.mongodb.com/docs/ruby-driver/current/reference/create-client/#client-options
  - Ruby driver configuration

- **Ruby Driver Documentation**: https://www.mongodb.com/docs/ruby-driver/current/

### PHP Driver

- **Connection URI Options**: https://www.mongodb.com/docs/php-library/current/reference/method/Client__construct/
  - PHP library client constructor options

- **PHP Driver Documentation**: https://www.mongodb.com/docs/drivers/php/

### Rust Driver

- **Client Options**: https://docs.rs/mongodb/latest/mongodb/options/struct.ClientOptions.html
  - Rust driver configuration

- **Rust Driver Documentation**: https://www.mongodb.com/docs/drivers/rust/

### Kotlin Driver (Coroutine)

- **MongoClient**: https://www.mongodb.com/docs/drivers/kotlin/coroutine/current/
  - Kotlin coroutine driver for async operations

---

## Monitoring & Metrics Documentation

### Connection Pool Monitoring

- **Connection Pool Monitoring Specification**: https://www.mongodb.com/docs/manual/reference/connection-pool-monitoring/
  - Standard events across all drivers implementing CMAP (Connection Monitoring and Pooling)

- **Server Selection Events**: https://www.mongodb.com/docs/manual/reference/server-selection-monitoring/
  - Events related to server selection in replica sets

### MongoDB Atlas Monitoring

- **Atlas Metrics**: https://www.mongodb.com/docs/atlas/tutorial/monitor-metrics/
  - Using Atlas monitoring dashboards

- **Real-Time Performance Panel**: https://www.mongodb.com/docs/atlas/real-time-performance-panel/
  - Real-time operation metrics

- **Atlas Alerts**: https://www.mongodb.com/docs/atlas/configure-alerts/
  - Setting up alerts for connection thresholds

### Self-Hosted Monitoring

- **serverStatus Command**: https://www.mongodb.com/docs/manual/reference/command/serverStatus/
  - Complete reference for serverStatus output including connections

- **MongoDB Monitoring Best Practices**: https://www.mongodb.com/docs/manual/administration/monitoring/
  - Official monitoring guidelines

### Third-Party Monitoring Integration

- **Prometheus MongoDB Exporter**: https://github.com/percona/mongodb_exporter
  - Export MongoDB metrics to Prometheus

- **Datadog MongoDB Integration**: https://docs.datadoghq.com/integrations/mongo/
  - MongoDB monitoring in Datadog

---

## Advanced Topics

### Connection String URI Format

- **URI Options Reference**: https://www.mongodb.com/docs/manual/reference/connection-string/#connection-string-options
  - All options that can be specified in connection strings

### Authentication

- **Authentication Mechanisms**: https://www.mongodb.com/docs/manual/core/authentication-mechanisms/
  - SCRAM, X.509, LDAP, Kerberos options

- **SCRAM**: https://www.mongodb.com/docs/manual/core/security-scram/
  - Default authentication mechanism details

### Network Compression

- **Network Compression**: https://www.mongodb.com/docs/manual/reference/program/mongod/#std-option-mongod.--networkMessageCompressors
  - Server-side compression configuration

- **Driver Compression Options**: https://www.mongodb.com/docs/manual/reference/connection-string/#urioption.compressors
  - Client-side compression configuration

### Serverless/FaaS

- **Best Practices for AWS Lambda**: https://www.mongodb.com/docs/atlas/manage-connections-aws-lambda/
  - MongoDB-specific guidance for Lambda

- **Managing Connections (General)**: https://www.mongodb.com/docs/manual/reference/connection-string/
  - Connection management strategies

### Replica Sets

- **Read Preference**: https://www.mongodb.com/docs/manual/core/read-preference/
  - Directing reads to specific replica set members

- **Write Concern**: https://www.mongodb.com/docs/manual/reference/write-concern/
  - Controlling write acknowledgment

- **Replica Set Configuration**: https://www.mongodb.com/docs/manual/replication/
  - Understanding replica set topology

### Sharded Clusters

- **Sharding**: https://www.mongodb.com/docs/manual/sharding/
  - Sharded cluster architecture and connection considerations

- **mongos Configuration**: https://www.mongodb.com/docs/manual/reference/program/mongos/
  - Routing service configuration

---

## When to Use These Links

### Infrastructure Issues (Not Client Configuration)

When you identify problems that cannot be solved by client configuration alone, direct users to the appropriate infrastructure documentation:

- **Cannot connect at all** → Connection Troubleshooting Guide
- **IP access denied** → IP Access List Configuration
- **Cross-VPC connectivity** → VPC Peering or Private Endpoints
- **Certificate errors** → TLS/SSL Configuration
- **DNS resolution failures** → DNS Seed List format guide

### Driver-Specific Questions

When users need details beyond what you provide in configuration:

- **Complete option reference** → Driver's MongoClient documentation
- **Language-specific patterns** → Driver documentation home
- **Advanced features** → Driver tutorials and guides

### Monitoring Setup

When users need to implement monitoring:

- **Event-based monitoring** → Connection Pool Monitoring spec
- **Atlas dashboards** → Atlas Metrics guide
- **Third-party integration** → Specific integration docs (Prometheus, Datadog, etc.)

---

## Link Maintenance

These links are current as of early 2025. Driver versions and documentation URLs may change. Always verify links are still valid before sharing with users.

For the most current documentation, users can search:
- **MongoDB Manual**: https://www.mongodb.com/docs/manual/
- **Drivers Hub**: https://www.mongodb.com/docs/drivers/
- **Atlas Documentation**: https://www.mongodb.com/docs/atlas/
