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

## Example workflow

Complete end-to-end optimization example:

**User:** "Why is this query slow? `db.orders.find({status: 'shipped', region: 'US'}).sort({date: -1})`"

1. **Check existing indexes:**
   - Call `collection-indexes` with database=`store`, collection=`orders`
   - Result shows: `{_id: 1}`, `{status: 1}`, `{date: -1}`

2. **Run explain:**
   - Call `explain` with method=`find`, filter=`{status: 'shipped', region: 'US'}`, sort=`{date: -1}`, verbosity=`executionStats`
   - Load `references/explain-interpretation.md` to interpret output
   - Result: Uses `{status: 1}` index, then in-memory SORT, `totalKeysExamined: 50000`, `nReturned: 100`

3. **Diagnose:** Query targets 100 docs but scans 50K index entries (poor selectivity: 0.002). In-memory sort adds overhead. Index doesn't support both filter fields or sort.

4. **Recommend:** Create compound index `{status: 1, region: 1, date: -1}` following ESR (two equality fields, then sort). This eliminates in-memory sort and improves selectivity by filtering on both status and region.

## Determine query type first

Before starting optimization work, load the appropriate reference:

- **Running explain()** → **Always** load `references/explain-interpretation.md` when calling the explain MCP tool
- **Aggregation pipelines** → Load `references/aggregation-optimization.md` **first** when dealing with aggregate pipelines
- **Queries on array fields** → Load `references/multikey-arrays.md` when fields have array values
- **Covered query optimization** → Load `references/covered-queries.md` when the query is able to have all fields fully covered

These references provide detailed guidance for specific scenarios. Load them **before** applying general index principles.

## MCP: what to call and when

**How to invoke.** Your host (e.g. Cursor) provides a way to call MCP tools—for example a tool that takes `server`, `toolName`, and `arguments`. You must call the **MongoDB MCP server** (the server name your host shows for MongoDB, e.g. `user-MongoDB` or `user-mongodb`) with the **exact tool name** as `toolName` and a single **arguments object** as `arguments`. Do not pass the tool name as an option, query param, or nested key; pass it as the MCP tool name and the parameters as the arguments object. If your host tells you to check the tool schema first, do that. Full reference: [MongoDB MCP Server Tools](https://www.mongodb.com/docs/mcp-server/tools/).

**Database tools** (when the MCP connection to the cluster works):

| Tool name (exact) | Arguments object |
|-------------------|------------------|
| `collection-indexes` | `{ "database": "<db>", "collection": "<coll>" }` — both required strings. |
| `explain` | `{ "database": "<db>", "collection": "<coll>", "method": [ { "name": "find", "arguments": { "filter": {...}, "sort": {...}, "limit": N } } ], "verbosity": "executionStats" }`. `method` is an array of one object: `name` is `"find"`, `"aggregate"`, or `"count"`; `arguments` holds that method's params (e.g. find: `filter`, `sort`, `limit`; aggregate: `pipeline`; count: `query`). Optional `verbosity`: `"queryPlanner"` (default), `"executionStats"`, `"queryPlannerExtended"`, `"allPlansExecution"`. |

**Atlas tools** (when Atlas API credentials are configured):

| Tool name (exact) | Arguments object |
|-------------------|------------------|
| `atlas-list-projects` | `{}` or `{ "orgId": "<24-char hex>" }`. Returns projects with their IDs; use to get `projectId` for Performance Advisor. |
| `atlas-get-performance-advisor` | **Required:** `"projectId"` (24-character hex string), `"clusterName"` (string, 1–64 chars, alphanumeric/underscore/dash). **Optional:** `"operations"` — array of strings from `"suggestedIndexes"`, `"dropIndexSuggestions"`, `"slowQueryLogs"`, `"schemaSuggestions"` (request only what you need); for slowQueryLogs only: `"since"` (ISO 8601 date-time), `"namespaces"` (array of `"db.coll"` strings). |

Branch in this order:

### 1. Connection string works (driver/MCP can reach the DB)

- **`collection-indexes`** — Invoke with server = MongoDB MCP server, toolName = `collection-indexes`, arguments = `{ "database": "<db>", "collection": "<coll>" }`. Use the result's `classicIndexes` (each has `name`, `key`) to see if the query can use an index (left-prefix, ESR).
- **`explain`** — Invoke with server = MongoDB MCP server, toolName = `explain`, arguments = object with `database`, `collection`, `method` (one find/aggregate/count shape), and `verbosity`.
  - **Always load `references/explain-interpretation.md`** when running explain to interpret output correctly
  - **Verbosity selection:**
    - Use `"executionStats"` when query likely completes in <10 seconds (small collections, simple queries, good indexes)
    - Use `"queryPlanner"` for potentially slow queries (large scans, complex aggregations) to avoid timeout
  - **When method is `aggregate`**: Also load `references/aggregation-optimization.md` before suggesting pipeline changes

If both are available, typical flow: call `collection-indexes` first, then `explain` to validate the plan.

### 2. Atlas API access works (MCP configured with Atlas; PA enabled)

If you need a project ID, invoke **`atlas-list-projects`**: server = MongoDB MCP server, toolName = `atlas-list-projects`, arguments = `{}` (or `{ "orgId": "<24-char hex>" }`). Then invoke **`atlas-get-performance-advisor`**: toolName = `atlas-get-performance-advisor`, arguments = `{ "projectId": "<24-char hex>", "clusterName": "<name>", "operations": ["..."] }`. The `operations` array must contain only the string values below (not the tool name); choose only what you need:

| Operation value | Use when |
|----------------|----------|
| `slowQueryLogs` | User asks what’s slow on the cluster, which queries to fix first—**prioritize by slowest and most frequent** when the response exposes those dimensions. Optional: `namespaces` to scope to a collection; `since` for a time window. |
| `suggestedIndexes` | PA index recommendations—**validate** they apply to the user’s query and will have good impact before recommending creation. |
| `dropIndexSuggestions` | User asks what to remove or reduce index overhead. |
| `schemaSuggestions` | User asks for schema/query-structure advice alongside indexes (PA schema suggestions). |

Do not pass the MCP tool name (e.g. `atlas-get-performance-advisor`) as an operation—the tool name is used when invoking the tool; `operations` is a separate argument for this tool only.

### 3. Neither connection nor Atlas is available

- If they only need an index idea from a described filter/sort/pipeline, **suggest a concrete
  index key** (ESR: equality → sort → range) and note they should create it in Atlas or via
  migrations and re-check with explain when connected.

## Index principles

### Compound index guidelines (ESR)

**Equality → Sort → Range** order:
- **Equality** fields first (`{field: value}`)
- **Sort** fields next
- **Range** fields last (`$gt`, `$lt`, `$gte`, `$lte`, `$in`, `$ne`)

Ranges scan multiple entries, blocking later fields from sorting efficiently. Index `{a:1, b:1, c:1}` supports queries on `{a}`, `{a,b}`, `{a,b,c}` but not `{b}` or `{c}` (prefix must match left-to-right). Filter order in query doesn't matter—optimizer reorders.

### Cardinality and selectivity

High-cardinality fields (many distinct values) are more selective—prefer for equality predicates. Low-cardinality fields (e.g., `status`) help in compound indexes. Good selectivity: `totalKeysExamined` ≈ `nReturned` in explain output.

### Sort direction

Index `{a:1, b:1}` supports `sort({a:1, b:1})` and reverse `sort({a:-1, b:-1})`, but NOT mixed directions like `sort({a:1, b:-1})`. For mixed sorts, create index matching exact pattern.

### Covered queries

**Highest performance tier:** Query answered entirely from index without reading documents.

**Requirements:**
- All queried fields are in the index
- All returned fields are in the index (or `_id` only)
- Projection must exclude `_id` unless `_id` is in the index
- No array fields indexed (multikey indexes cannot cover)

**Check:** `explain("executionStats")` shows `totalDocsExamined: 0`

### Array fields and multikey indexes

When you index a field containing arrays, MongoDB creates a **multikey index** (one entry per array element).

**Limitations:**
- Cannot cover queries (must read documents)
- Compound multikey restriction: at most **one** array field per compound index
- Large arrays create many index entries (impacts write performance and index size)

**Use $elemMatch** for complex array queries to ensure conditions match the same array element.

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
