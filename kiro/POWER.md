---
name: "mongodb"
displayName: "MongoDB"
description: "Build applications with MongoDB - query databases, manage collections, create indexes, run aggregations, manage Atlas clusters, optimize connection pools and timeouts, design schemas with proven patterns, translate natural language to queries, diagnose slow queries with explain plans, implement full-text and vector search, and build streaming pipelines with Atlas Stream Processing"
keywords: ["mongodb", "mongo", "nosql", "database", "atlas", "aggregation", "collection", "document", "schema", "connection pool", "query optimization", "indexing", "explain", "slow query", "natural language query", "MQL", "vector search", "atlas search", "full-text search", "hybrid search", "semantic search", "RAG", "stream processing", "kafka", "schema design", "embed vs reference", "mcp setup", "connection string"]
mcpServers: ["mongodb"]
---

# MongoDB Kiro Power

## Overview

This power connects you to MongoDB databases and MongoDB Atlas clusters through the official MongoDB MCP Server. Use it to query data, manage schemas, build aggregation pipelines, create indexes, and administer Atlas infrastructure — all from your development environment.

### Key Capabilities

- Query and manipulate documents across databases and collections
- Build and test aggregation pipelines
- Inspect collection schemas and indexes
- Monitor database statistics and performance
- Manage MongoDB Atlas clusters, projects, and users
- Create and manage local Atlas deployments for development
- Export query and aggregation results
- Get performance advisor recommendations for index optimization
- Translate natural language descriptions into MongoDB queries
- Design and optimize MongoDB schemas with proven patterns
- Optimize slow queries using explain plans and the ESR index rule
- Configure MongoDB connections with optimal pool and TLS settings
- Set up and configure the MongoDB MCP server
- Build real-time data pipelines with Atlas Stream Processing
- Implement full-text, vector, and hybrid search with Atlas Search

### Authentication

The MongoDB MCP server supports two authentication methods:

1. **Connection String** — Connect directly to any MongoDB instance (local or Atlas) using `MDB_MCP_CONNECTION_STRING`
2. **Atlas API Credentials** — Use a Service Account with `MDB_MCP_API_CLIENT_ID` and `MDB_MCP_API_CLIENT_SECRET` for Atlas management operations

### Prerequisites

- Node.js v20.19.0+, v22.12.0+, or v23+
- A MongoDB Atlas cluster or self-hosted MongoDB deployment
- For Atlas management: a Service Account with appropriate project/org roles
- Docker (optional, for local Atlas deployments)

## Onboarding

1. **Install Node.js** v20.19.0+, v22.12.0+, or v23+
2. **Choose your authentication method**:
   - For direct database access: prepare your MongoDB connection string
   - For Atlas management: create a Service Account in Atlas and note the Client ID and Secret
3. **Set environment variables** when prompted by Kiro:
   - `MDB_MCP_CONNECTION_STRING` — Your MongoDB connection URI (e.g. `mongodb+srv://user:pass@cluster.mongodb.net/mydb`)
   - `MDB_MCP_API_CLIENT_ID` — Atlas Service Account Client ID (optional, for Atlas management)
   - `MDB_MCP_API_CLIENT_SECRET` — Atlas Service Account Secret (optional, for Atlas management)
4. **Verify the connection** by asking Kiro to list your databases (uses the `list-databases` tool)
5. If the server disconnects, **reconnect** from Kiro's MCP panel without reinstalling the power

## Complementary Agent Skills

Skills are loaded on demand. Reference a skill by name in Kiro chat to activate it — for example, type `#mongodb-query-optimizer` or say "use the mongodb-schema-design skill". The skill's guidance is then injected into context for that conversation.

| Skill | Description | Invocation |
|-------|-------------|------------|
| `mongodb-atlas-stream-processing` | Build real-time pipelines with Atlas Stream Processing; connect Kafka, S3, and Lambda | `#mongodb-atlas-stream-processing` |
| `mongodb-connection` | Construct optimal connection strings with pool settings and TLS/SSL for production | `#mongodb-connection` |
| `mongodb-mcp-setup` | Configure the MongoDB MCP server, set required env vars, and enable read-only mode | `#mongodb-mcp-setup` |
| `mongodb-natural-language-querying` | Convert plain-English data questions into accurate `find` and `aggregate` queries | `#mongodb-natural-language-querying` |
| `mongodb-query-optimizer` | Diagnose slow queries, apply the ESR index rule, and eliminate COLLSCAN plans | `#mongodb-query-optimizer` |
| `mongodb-schema-design` | Choose embedding vs referencing, apply schema patterns, and enforce structure with JSON Schema | `#mongodb-schema-design` |
| `mongodb-search-and-ai` | Implement full-text search, vector search, and hybrid search with Atlas Search | `#mongodb-search-and-ai` |

> The canonical skills live in the [`skills/`](https://github.com/mongodb/agent-skills/tree/main/skills) directory at the root of this repository and are shared across all agent plugins. If your agent does not load them with the power, install them separately with `npx skills add mongodb/agent-skills`.

## Available MCP Servers

### mongodb

- **Package**: `mongodb-mcp-server@latest`
- **Connection**: stdio (npx)

#### Database Tools

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| `connect` | Connect to a MongoDB instance | `connectionStringOrClusterName` (Required) |
| `switch-connection` | Switch to a different MongoDB connection | `connectionStringOrClusterName` (Required) |
| `list-databases` | List all databases | — |
| `list-collections` | List collections in a database | `database` (Required) |
| `collection-schema` | Describe schema for a collection | `database` (Required), `collection` (Required) |
| `collection-indexes` | Describe indexes for a collection | `database` (Required), `collection` (Required) |
| `collection-storage-size` | Get collection size | `database` (Required), `collection` (Required) |
| `db-stats` | Get database statistics | `database` (Required) |
| `find` | Run a find query | `database` (Required), `collection` (Required), `filter`, `projection`, `sort`, `limit` |
| `aggregate` | Run an aggregation pipeline | `database` (Required), `collection` (Required), `pipeline` (Required) |
| `count` | Count documents | `database` (Required), `collection` (Required), `filter` |
| `insert-many` | Insert documents | `database` (Required), `collection` (Required), `documents` (Required) |
| `update-many` | Update matching documents | `database` (Required), `collection` (Required), `filter` (Required), `update` (Required) |
| `delete-many` | Remove matching documents | `database` (Required), `collection` (Required), `filter` (Required) |
| `create-collection` | Create a new collection | `database` (Required), `collection` (Required) |
| `drop-collection` | Remove a collection | `database` (Required), `collection` (Required) |
| `drop-database` | Remove a database | `database` (Required) |
| `create-index` | Create an index (standard or vector search) | `database` (Required), `collection` (Required), `keys` (Required) |
| `drop-index` | Drop an index | `database` (Required), `collection` (Required), `indexName` (Required) |
| `rename-collection` | Rename a collection | `database` (Required), `collection` (Required), `newName` (Required) |
| `explain` | Explain query execution plan | `database` (Required), `collection` (Required), `method` (Required) |
| `export` | Export query/aggregation results as EJSON | `database` (Required), `collection` (Required) |
| `mongodb-logs` | Return recent mongod log events | — |

#### Atlas Management Tools

| Tool | Description |
|------|-------------|
| `atlas-list-orgs` | List MongoDB Atlas organizations |
| `atlas-list-projects` | List Atlas projects |
| `atlas-create-project` | Create an Atlas project |
| `atlas-list-clusters` | List Atlas clusters |
| `atlas-inspect-cluster` | Inspect cluster metadata |
| `atlas-create-free-cluster` | Create a free-tier Atlas cluster |
| `atlas-list-db-users` | List Atlas database users |
| `atlas-create-db-user` | Create an Atlas database user |
| `atlas-inspect-access-list` | Inspect IP access list |
| `atlas-create-access-list` | Add IP/CIDR to access list |
| `atlas-list-alerts` | List Atlas alerts |
| `atlas-get-performance-advisor` | Get performance and index recommendations |

#### Atlas Local Development Tools

| Tool | Description |
|------|-------------|
| `atlas-local-create-deployment` | Create a local Atlas deployment (using `mongodb-atlas-local` Docker image) |
| `atlas-local-list-deployments` | List local Atlas deployments |
| `atlas-local-connect-deployment` | Connect to a local Atlas deployment |
| `atlas-local-delete-deployment` | Delete a local Atlas deployment |

## Tool Usage Examples

### Connect and explore

```javascript
// Connect to a local MongoDB instance
usePower("mongodb", "connect", {
  connectionStringOrClusterName: "mongodb://localhost:27017",
});

// List all databases
usePower("mongodb", "list-databases");

// Explore a collection's schema
usePower("mongodb", "collection-schema", {
  database: "myapp",
  collection: "users",
});
```

### Query documents

```javascript
// Find active users sorted by creation date
usePower("mongodb", "find", {
  database: "myapp",
  collection: "users",
  filter: { status: "active" },
  sort: { createdAt: -1 },
  limit: 10,
});

// Count documents matching a filter
usePower("mongodb", "count", {
  database: "myapp",
  collection: "orders",
  filter: { status: "pending" },
});
```

### Run aggregations

```javascript
// Revenue by product category
usePower("mongodb", "aggregate", {
  database: "myapp",
  collection: "orders",
  pipeline: [
    { $match: { status: "completed" } },
    { $unwind: "$items" },
    {
      $group: {
        _id: "$items.category",
        totalRevenue: { $sum: "$items.price" },
        count: { $sum: 1 },
      },
    },
    { $sort: { totalRevenue: -1 } },
  ],
});
```

### Manage indexes

```javascript
// Create a compound index
usePower("mongodb", "create-index", {
  database: "myapp",
  collection: "users",
  keys: { email: 1 },
  name: "email_unique",
  unique: true,
});

// Inspect existing indexes
usePower("mongodb", "collection-indexes", {
  database: "myapp",
  collection: "users",
});
```

## Combining Tools (Workflows)

### Workflow 1: Database exploration

1. `connect` — Connect to your MongoDB instance
2. `list-databases` — See all available databases
3. `list-collections` — List collections in a database
4. `collection-schema` — Inspect a collection's schema
5. `collection-indexes` — Review existing indexes
6. `find` — Sample some documents

### Workflow 2: Performance investigation

1. `connect` — Connect to your database
2. `db-stats` — Check database statistics
3. `collection-storage-size` — Identify large collections
4. `explain` — Analyze slow query execution plans
5. `atlas-get-performance-advisor` — Get index recommendations (Atlas only)
6. `create-index` — Apply recommended indexes

### Workflow 3: Data migration

1. `connect` — Connect to source database
2. `collection-schema` — Inspect source collection schema
3. `find` or `aggregate` — Query source data
4. `export` — Export results
5. `switch-connection` — Connect to target database
6. `create-collection` — Create target collection
7. `insert-many` — Insert exported data
8. `create-index` — Recreate indexes on target

### Workflow 4: Local development setup

1. `atlas-local-create-deployment` — Spin up a local Atlas deployment
2. `atlas-local-connect-deployment` — Connect to it
3. `create-collection` — Set up collections
4. `create-index` — Add indexes
5. `insert-many` — Seed test data

## Best Practices

### Do

- Use `collection-schema` to understand document structure before writing queries
- Create indexes for fields used in filters, sorts, and lookups
- Use `explain` to verify query execution plans use indexes
- Use `aggregate` with `$project` to return only needed fields
- Use `atlas-get-performance-advisor` regularly for index recommendations
- Start with `find` using a `limit` before running broad queries
- Use the `export` tool to save large result sets
- Use `count` to estimate result set size before fetching documents

### Don't

- Don't run `delete-many` or `drop-collection` without verifying the filter first
- Don't create redundant indexes — check existing indexes with `collection-indexes`
- Don't use `$where` or JavaScript expressions in queries (security and performance risk)
- Don't skip schema inspection — use `collection-schema` before building queries
- Don't ignore the `explain` output when debugging slow queries

## Configuration

### Read-Only Mode

To restrict the server to read-only operations, add `"--readOnly"` to the args in `mcp.json`:

```json
{
  "mcpServers": {
    "mongodb": {
      "command": "npx",
      "args": ["-y", "mongodb-mcp-server@latest", "--readOnly"],
      "env": {
        "MDB_MCP_CONNECTION_STRING": "${MDB_MCP_CONNECTION_STRING}"
      }
    }
  }
}
```

### Docker Alternative

If you prefer Docker over npx:

```json
{
  "mcpServers": {
    "mongodb": {
      "command": "docker",
      "args": ["run", "--rm", "-i", "-e", "MDB_MCP_CONNECTION_STRING", "mongodb/mongodb-mcp-server:latest"],
      "env": {
        "MDB_MCP_CONNECTION_STRING": "${MDB_MCP_CONNECTION_STRING}"
      }
    }
  }
}
```

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| Connection refused | MongoDB not running or wrong connection string | Verify the connection string and that the MongoDB instance is reachable |
| Authentication failed | Invalid credentials | Check username/password in connection string or Atlas API credentials |
| Atlas API 403 | Service Account lacks permissions | Ensure the Service Account has the required project/org role |
| Namespace not found | Database or collection doesn't exist | Use `list-databases` and `list-collections` to verify names |
| Index build failed | Duplicate key violation or invalid key spec | Check for duplicates with `find` and verify field paths |
| Timeout on aggregation | Pipeline too complex or collection too large | Add early `$match` stages to reduce documents processed; consider adding indexes |
| ECONNREFUSED on local deployment | Docker not running | Start Docker Desktop before using `atlas-local-create-deployment` |

## Tips

1. Start by running `collection-schema` on your key collections — it helps you write accurate queries and aggregation pipelines
2. Use `explain` before deploying new queries to verify they use indexes effectively
3. Use `atlas-local-create-deployment` to spin up disposable local databases for experimentation without affecting production
4. Combine `aggregate` with `export` to save complex query results for later analysis
5. Use `atlas-get-performance-advisor` periodically to catch missing indexes before they become performance bottlenecks
6. When migrating data, always use `collection-schema` on both source and target to verify structural compatibility

## Resources

- [MongoDB MCP Server Documentation](https://www.mongodb.com/docs/mcp-server/get-started/)
- [MongoDB MCP Server GitHub](https://github.com/mongodb-js/mongodb-mcp-server)
- [mongodb-mcp-server on npm](https://www.npmjs.com/package/mongodb-mcp-server)
- [MongoDB Atlas Documentation](https://www.mongodb.com/docs/atlas/)
- [MongoDB Aggregation Pipeline Reference](https://www.mongodb.com/docs/manual/reference/operator/aggregation/)
- [MongoDB Node.js Driver Documentation](https://www.mongodb.com/docs/drivers/node/current/)

## License and support

This power integrates with the [MongoDB MCP Server](https://github.com/mongodb-js/mongodb-mcp-server) (Apache-2.0).

- [Privacy Policy](https://www.mongodb.com/legal/privacy/privacy-policy)
- Support: [GitHub Issues](https://github.com/mongodb/agent-skills/issues)
