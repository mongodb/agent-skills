---
name: mongodb-query-optimizer
description: >-
  Help with MongoDB query optimization and indexing. Use only when the user explicitly
  asks for optimization or performance—e.g. "How do I optimize this query?", "How do I
  index this?", "Why is this query slow?", "Can you fix my slow queries?", "What are the
  slow queries on my cluster?", "Which indexes should I add?". Do not invoke for general
  MongoDB query writing unless they ask for performance/indexing. When invoked, prefer
  indexes—reuse existing indexes or suggest new ones—and use MCP when available (see body).
compatibility: >-
  Best with MongoDB MCP server. Uses collection-indexes and explain when the connection
  string works; uses Atlas Performance Advisor when Atlas API is configured. Without either,
  suggest indexes from query shape only. User creates indexes in Atlas or migrations unless
  tooling allows otherwise.
---

# MongoDB query optimizer

Focus: **optimize through indexes** (existing or new) and **cluster/collection performance**
(slow queries, index suggestions). Do not conflate with natural-language query generation;
that is a different skill.

## When this skill is invoked

Invoke **only** when the user clearly wants:

- Query/index **optimization** or **performance** help
- **Why** a query is slow or **how to speed it up**
- **Slow queries** on their cluster or **what to index**
- **Fix** slow queries or **review** index usage

Do **not** invoke for routine CRUD/query authoring without an optimization or slowness angle.

## MCP: what to call and when

Branch in this order:

### 1. Connection string works (driver/MCP can reach the DB)

- **`collection-indexes`** — List existing indexes on the target `database` + `collection`.
  Use this to see if a query can already use an index (left-prefix, ESR).
- **`explain`** — Run explain on the same find/aggregate/count shape the user cares about.
  Use to confirm the winning plan uses an index (`IXSCAN` etc.) or to spot full collection
  scans. Prefer `verbosity: "executionStats"` when they care about relative cost; otherwise
  `queryPlanner` or `queryPlannerExtended` is enough to see index usage.

If both are available, typical flow: indexes first, then explain to validate the plan.

### 2. Atlas API access works (MCP configured with Atlas; PA enabled)

Use **`atlas-get-performance-advisor`** with `projectId` and `clusterName` (resolve project
via `atlas-list-projects` if needed). Pass `operations` selectively:

| Operation | Use when |
|-----------|----------|
| `slowQueryLogs` | User asks what’s slow on the cluster, which queries to fix first—**prioritize by slowest and most frequent** when the response exposes those dimensions. Optional: `namespaces` to scope to a collection; `since` for a time window. |
| `suggestedIndexes` | PA index recommendations—**validate** they apply to the user’s query and will have good impact before recommending creation. |
| `dropIndexSuggestions` | User asks what to remove or reduce index overhead. |
| `schemaSuggestions` | User asks for schema/query-structure advice alongside indexes (PA schema suggestions). |

Default is to request only what you need to avoid noise.

### 3. Neither connection nor Atlas is available

- If they only need an index idea from a described filter/sort/pipeline, **suggest a concrete
  index key** (ESR: equality → sort → range) and note they should create it in Atlas or via
  migrations and re-check with explain when connected.

## Index matching (short)

- Compound indexes: prefer **equality → sort → range** (ESR); left-prefix still applies;
  range on a field can block later keys for sort.
- **Filter/predicate order in the query does not matter** to the planner.
- **Sort direction** should align with the index when the query uses the index for sort.

## Output

- Keep answers short: one or two sentences on index usage or the suggested index when
  appropriate; expand only when summarizing slow-query lists or PA tradeoffs.
- Do not create indexes directly via MCP unless the environment explicitly supports it;
  otherwise tell the user to create in Atlas or migrations.

## Out of scope

- Writing queries from natural language without an optimization ask (use the NLQ skill).
- Non-index optimizations (sharding, hardware) except where `schemaSuggestions` already
  surfaces PA advice—still frame around query/index impact.
- Running destructive operations without explicit user intent.
