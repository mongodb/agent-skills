# MongoDB Atlas (Managed MCP)

Connects your agent to **MongoDB Atlas** clusters through MongoDB's hosted Atlas MCP server (`https://mcp.mongodb.com/`) over OAuth — sign in with your Atlas account and skip the local setup and connection strings entirely. From there, your agent can explore databases and collections, run queries and aggregations, manage indexes, and manage Atlas resources such as clusters, projects, database users, and network access.

Running a deployment you manage yourself — Community, Enterprise Advanced, self-hosted? Use the [`mongodb` plugin](../mongodb/README.md) instead.

To get started, see the [repository README](../../README.md).

## Skills

These skills come bundled with the plugin and activate automatically when relevant:

- **`mongodb-connection`** — Reviews and tunes client connection configuration (pools, timeouts, patterns) across driver languages.
- **`mongodb-natural-language-querying`** — Turns natural-language requests into read-only `find` queries and aggregation pipelines.
- **`mongodb-query-optimizer`** — Diagnoses slow queries and recommends indexes to fix them.
- **`mongodb-schema-design`** — Applies MongoDB schema design patterns and steers you clear of common anti-patterns, whether modeling from scratch or migrating from SQL.
- **`mongodb-search-and-ai`** — Helps build Atlas Search (full-text), Vector Search (semantic), and hybrid search implementations.
- **`mongodb-atlas-stream-processing`** — Manages Atlas Stream Processing workspaces, connections, and processors for streaming workloads.
