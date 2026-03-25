# mongodb-query-optimizer — Testing

Test data setup scripts, eval definitions, and configuration for testing the `mongodb-query-optimizer` skill.

## Directory Structure

```
testing/mongodb-query-optimizer/
├── README.md                  # This file
├── setup-slow-queries.ts      # Insert test data + run slow queries on Atlas
├── cleanup.ts                 # Drop the perftest database
├── package.json               # Dependencies (mongodb, tsx)
├── evals/
│   └── evals.json             # Eval prompts, assertions, and expected outputs
└── mongodb-query-optimizer-workspace/   # .gitignored — ephemeral eval output
    └── iteration-N/
```

## Running Evals

Use the `/skill-creator` skill to run and evaluate test cases. The evals are defined in `evals/evals.json`.

Each eval has:
- **prompt** — the simulated user input
- **expected_output** — human-readable description of a good response
- **expectations** — specific, verifiable assertions that get graded automatically

### MCP configuration for evals

Evals are split into two groups based on whether they need a live Atlas MCP connection:

| Evals | MCP server | What they test |
|-------|-----------|----------------|
| **1–5** | **Not configured** | Query optimization knowledge from skill references only. No MCP tools should be called. |
| **6–8** | **Configured** (connection string + Atlas API credentials) | Skill's ability to use `atlas-get-performance-advisor` to diagnose real cluster performance issues. |

**Both groups run with_skill and without_skill (baseline).** The skill-creator should spawn two subagents per eval — one with the skill, one without — so you can compare the skill's value-add against the model's base knowledge.

Eval 5 is a **negative test case** — the optimizer skill should NOT trigger for a routine query-writing prompt.

### Instructions for /skill-creator

**Important:** Evals 1–5 must run without the MCP server, and evals 6–8 must run with it. When invoking skill-creator, call it out explicitly, e.g.:

> `/skill-creator` can you please run the evals for mongodb-query-optimizer. run evals 1-5 without MCP server configured, run evals 6-8 with the MCP server configured

The steps are:

1. Run **evals 1–5 without the MCP server configured** (tell subagents not to use any MongoDB MCP tools). Run both with_skill and without_skill (baseline) for each.
2. Run **evals 6–8 with the MCP server configured** (subagents should use Atlas MCP tools). Run both with_skill and without_skill (baseline) for each.
3. Grade all runs against the assertions in `evals/evals.json`.
4. Generate the eval viewer with benchmark comparison (with_skill vs without_skill).

## Atlas Performance Test Setup (Evals 6–8)

Evals 6–8 require a live Atlas cluster with slow query data. Follow these steps before running them.

### Prerequisites

- An **Atlas replica set cluster** (M10+ recommended; M0/free tier does not support Performance Advisor)
- A database user with read/write access
- An Atlas API key (for the MCP server to call Performance Advisor)
- Node.js 18+

### 1. Install dependencies

```bash
cd testing/mongodb-query-optimizer
npm install
```

### 2. Configure MCP server

Configure both the connection string and Atlas API credentials in your MCP config. For Claude Code, this is either `~/.claude/mcp.json` (global) or `.mcp.json` in the project root:

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
npm run setup -- "mongodb+srv://<user>:<password>@<cluster>.mongodb.net/"
```

This will:
- Create a `perftest` database with `orders` (500K docs) and `customers` (50K docs) collections
- **No secondary indexes** are created — only the default `_id` index
- Run ~300 unindexed queries over 30 seconds to populate the slow query log

The script produces two slow query patterns:

| Query pattern | Plan | Expected index suggestion |
|---|---|---|
| `find({ status, region }).sort({ createdAt: -1 })` | COLLSCAN + in-memory SORT | `{ status: 1, region: 1, createdAt: -1 }` |
| `find({ customerId })` | COLLSCAN | `{ customerId: 1 }` |
| `aggregate([$facet: {...}])` | Full collection funneled into every branch | Replace `$facet` with `$unionWith`; index on `{ total: 1, createdAt: -1 }` |

### 4. Wait for Performance Advisor

After the script completes, **wait 5–15 minutes** for Atlas Performance Advisor to process the slow query logs and generate index suggestions. You can verify in the Atlas UI under Performance Advisor.

### 5. Allow MCP tools for subagents

If running evals via subagents (e.g., with skill-creator), pre-approve MCP tool permissions so subagents don't get blocked on interactive approval. Add the following to `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "mcp__mongodb__*"
    ]
  }
}
```

### 6. Run evals 6–8

The eval test cases (ids 6, 7, and 8 in `evals/evals.json`) ask the skill to:
- Discover and summarize slow queries on the connected cluster (eval 6)
- Provide a full performance summary including indexes to create and drop (eval 7)
- Identify and optimize a slow `$facet` aggregation from slow query logs (eval 8)

These evals require a live MCP server connection — they cannot be run in offline/mock mode.

## Cleanup

```bash
npm run cleanup -- "mongodb+srv://<user>:<password>@<cluster>.mongodb.net/"
```

This drops the `perftest` database.
