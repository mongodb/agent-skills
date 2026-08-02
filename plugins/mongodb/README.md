# MongoDB (Self-Managed MCP)

For deployments you manage yourself — **Community**, **Enterprise Advanced**, a local dev container, or an Atlas cluster — this plugin connects your agent using nothing more than a connection string. It runs the [MongoDB MCP server](https://www.mongodb.com/docs/mcp-server/) locally via `npx`, giving your agent tools to explore databases and collections, run queries and aggregations, and manage indexes.

To get started, see the [Community & Enterprise Advanced setup guide](../../README.community.md).

## Skills

These skills come bundled with the plugin and activate automatically when relevant:

- **`mongodb-mcp-setup`** — Walks you through configuring the MCP server's connection string and environment variables.
- **`mongodb-connection`** — Reviews and tunes client connection configuration (pools, timeouts, patterns) across driver languages.
- **`mongodb-natural-language-querying`** — Turns natural-language requests into read-only `find` queries and aggregation pipelines.
- **`mongodb-query-optimizer`** — Diagnoses slow queries and recommends indexes to fix them.
- **`mongodb-schema-design`** — Applies MongoDB schema design patterns and steers you clear of common anti-patterns, whether modeling from scratch or migrating from SQL.
- **`mongodb-search-and-ai`** — Helps build Atlas Search (full-text), Vector Search (semantic), and hybrid search implementations.
- **`mongodb-atlas-stream-processing`** — Manages Atlas Stream Processing workspaces, connections, and processors for streaming workloads.
