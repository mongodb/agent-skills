# MongoDB (Self-Managed MCP)

For deployments you manage yourself — **Community**, **Enterprise Advanced**, a local dev container, or an Atlas cluster — this plugin connects your agent using nothing more than a connection string. It runs the [MongoDB MCP server](https://www.mongodb.com/docs/mcp-server/) locally via `npx`, giving your agent tools to explore databases and collections, run queries and aggregations, and manage indexes.

To get started, see the [Community & Enterprise Advanced setup guide](https://github.com/mongodb/agent-skills/blob/main/README.community.md).

## Install in OpenCode

```bash
opencode plugin add opencode-plugin-mongodb
```

Run `opencode plugin update` after a new release. For other clients, see the
[repository README](https://github.com/mongodb/agent-skills#readme).

## Skills

These skills come bundled with the plugin and activate automatically when relevant:

- **`mongodb-mcp-setup`** — Walks you through configuring the MCP server's connection string and environment variables.
- **`mongodb-connection`** — Reviews and tunes client connection configuration (pools, timeouts, patterns) across driver languages.
- **`mongodb-natural-language-querying`** — Turns natural-language requests into read-only `find` queries and aggregation pipelines.
- **`mongodb-qe-size-estimation`** — Estimates the storage and memory impact of encrypting fields in collections with Queryable Encryption (QE) enabled. Doesn't apply to collections that use Client-Side Field Level Encryption (CSFLE).
- **`mongodb-query-optimizer`** — Diagnoses slow queries and recommends indexes to fix them.
- **`mongodb-schema-design`** — Applies MongoDB schema design patterns and steers you clear of common anti-patterns, whether modeling from scratch or migrating from SQL.
- **`mongodb-search-and-ai`** — Helps build Atlas Search (full-text), Vector Search (semantic), and hybrid search implementations.
- **`mongodb-atlas-stream-processing`** — Manages Atlas Stream Processing workspaces, connections, and processors for streaming workloads.
