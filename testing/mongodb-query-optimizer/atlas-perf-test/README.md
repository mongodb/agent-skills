# Atlas Performance Test Setup

This directory contains scripts to insert test data and run slow queries against an Atlas replica set cluster, generating entries in the Atlas slow query log and triggering Performance Advisor index suggestions. These are used to test the `mongodb-query-optimizer` skill's ability to diagnose real cluster performance issues via MCP.

## Prerequisites

- An **Atlas replica set cluster** (M10+ recommended for Performance Advisor; M0/free tier does not support Performance Advisor)
- A database user with read/write access
- An Atlas API key (for the MCP server to call Performance Advisor)
- Node.js 18+

## Setup

### 1. Install dependencies

```bash
cd testing/mongodb-query-optimizer/atlas-perf-test
npm install
```

### 2. Configure MCP server

Before running the eval test cases, configure both the connection string and Atlas API credentials in your MCP config. For Claude Code, this is either `~/.claude/mcp.json` (global) or `.mcp.json` in the project root (project-scoped):

```json
{
  "mcpServers": {
    "mongodb": {
      "command": "npx",
      "args": ["-y", "mongodb-mcp-server@latest"],
      "env": {
        "MDB_MCP_CONNECTION_STRING": "mongodb+srv://<user>:<password>@<cluster>.mongodb.net/",
        "MDB_MCP_API_CLIENT_ID": "<atlas-api-public-key>",
        "MDB_MCP_API_CLIENT_SECRET": "<atlas-api-private-key>"
      }
    }
  }
}
```

**To get Atlas API credentials:**

1. Go to Atlas → Organization Access Manager → API Keys
2. Create a new API key with "Organization Read Only" or "Project Read Only" role
3. Add your IP to the API key's access list
4. Use the public key as `MDB_MCP_API_CLIENT_ID` and private key as `MDB_MCP_API_CLIENT_SECRET`

### 3. Insert test data and run slow queries

```bash
npm run setup "mongodb+srv://<user>:<password>@<cluster>.mongodb.net/"
```

This will:
- Create a `perftest` database with `orders` (10K docs) and `customers` (500 docs) collections
- **No secondary indexes** are created — only the default `_id` index
- Run ~300 unindexed queries over 30 seconds to populate the slow query log

The script produces two slow query patterns:

| Query pattern | Plan | Expected index suggestion |
|---|---|---|
| `find({ status, region }).sort({ createdAt: -1 })` | COLLSCAN + in-memory SORT | `{ status: 1, region: 1, createdAt: -1 }` |
| `find({ customerId })` | COLLSCAN | `{ customerId: 1 }` |

### 4. Wait for Performance Advisor

After the script completes, **wait 5-15 minutes** for Atlas Performance Advisor to process the slow query logs and generate index suggestions. You can verify in the Atlas UI under Performance Advisor.

### 5. Allow MCP tools for subagents

If running evals via subagents (e.g., with the skill-creator), you need to pre-approve MCP tool permissions so subagents don't get blocked on interactive approval. Add the following to `.claude/settings.local.json` (or `.claude/settings.json`):

```json
{
  "permissions": {
    "allow": [
      "mcp__mongodb__*"
    ]
  }
}
```

Without this, subagents will fail with "permission denied" on every MCP tool call.

### 6. Run the eval test cases

The eval test cases (ids 6 and 7 in `evals/evals.json`) are designed to be run after this setup. They ask the skill to:

- Summarize slow queries and performance suggestions for the connected cluster
- Provide optimization recommendations based on Performance Advisor output

These evals require a live MCP server connection — they cannot be run in offline/mock mode.

## Cleanup

```bash
npm run cleanup "mongodb+srv://<user>:<password>@<cluster>.mongodb.net/"
```

This drops the `perftest` database.

## What the eval tests verify

- The MCP server successfully connects to the Atlas cluster
- `atlas-get-performance-advisor` returns slow query logs and index suggestions
- The skill correctly identifies the COLLSCAN queries and recommends appropriate indexes
- The skill prioritizes suggestions by impact (the status/region/createdAt query scans more data than the customerId query)
