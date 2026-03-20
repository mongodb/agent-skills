---
name: mongodb-query-optimizer
description: >-
  Help with MongoDB query optimization and indexing. Use only when the user asks for optimization or performance: "How do I optimize this query?", "How do I index this?", "Why is this query slow?", "Can you fix my slow queries?", "What are the slow queries on my cluster?", etc. Do not invoke for general MongoDB query writing unless user asks for performance or index help. Prefer indexing as optimization strategy. Use MongoDB MCP when available.
compatibility: >-
  Best with MongoDB MCP server. Uses collection-indexes and explain when the connection string works; uses Atlas Performance Advisor when Atlas API is configured. Without either, suggest indexes from query shape only. User creates indexes in Atlas or migrations unless tooling allows otherwise.
---

# MongoDB Query Optimizer

## When this skill is invoked

Invoke **only** when the user wants:

- Query/index **optimization** or **performance** help  
- **Why** a query is slow or **how to speed it up**  
- **Slow queries** on their cluster and/or **how to optimize them**

Do **not** invoke for routine query authoring unless the user has requested help with optimization, slow queries, or indexing.

## High Level Workflow

### General Performance Help

If the user wants to examine slow queries, or is looking for general performance suggestions (not regarding any particular query):

- Use MongoDB MCP server **atlas-get-performance-advisor** tool to fetch slow query logs and performance advisor output  
- Make suggestions based on this information

If Atlas MCP Server for Atlas is not configured or you don’t have enough information to run **atlas-get-performance-advisor** against the correct cluster, terminate early with explanation.

### Help with a Specific Query

If the user is asking about a particular query:

- Use **collection-indexes**, **explain**, and **find** MCP tools to get existing indexes on the collection, explain() output for the query, and a sample document from the collection  
- Use **atlas-get-performance-advisor MCP** tool to fetch slow query logs and performance advisor output

Then make an optimization suggestion based on collected information and MongoDB best practices and examples from reference files. Prefer creating an index that fully covers the query if possible. If you cannot use MongoDB MCP Server then still try to make a suggestion.

## MCP: available tools

**How to invoke.** Your host provides a way to call MCP tools. You must call the **MongoDB MCP server** with the **exact tool name** as `toolName` and a single **arguments object** as `arguments`. Do not pass the tool name as an option, query param, or nested key; pass it as the MCP tool name and the parameters as the arguments object. Full MCP Server tool reference: [MongoDB MCP Server Tools](https://www.mongodb.com/docs/mcp-server/tools/).

**Database tools** (when the MCP cluster connection works):

| Tool name (exact) | Arguments object |
| :---- | :---- |
| `collection-indexes` | `{ "database": "<db>", "collection": "<coll>" }` — both required strings. |
| `explain` | `{ "database": "<db>", "collection": "<coll>", "method": [ { "name": "find", "arguments": { "filter": {...}, "sort": {...}, "limit": N } } ], "verbosity": "executionStats" }`. `method` is an array of one object: `name` is `"find"`, `"aggregate"`, or `"count"`; `arguments` holds that method's params (e.g. find: `filter`, `sort`, `limit`; aggregate: `pipeline`; count: `query`). Optional `verbosity`: `"queryPlanner"` (default), `"executionStats"`, `"queryPlannerExtended"`, `"allPlansExecution"`. |
| `find` |  `{ "database": "<db>", "collection": "<coll>", "filter": {...}, "projection": {...}, "sort": {...}, "limit": N }` — `database`, `collection`, and `filter` are required. Optional: `projection`, `sort`, `limit`. |

**Atlas tools** (when Atlas API credentials are configured):

| Tool name (exact) | Arguments object |
| :---- | :---- |
| `atlas-list-projects` | `{}` or `{ "orgId": "<24-char hex>" }`. Returns projects with their IDs; use to get `projectId` for Performance Advisor. |
| `atlas-get-performance-advisor` | **Required:** `"projectId"` (24-character hex string), `"clusterName"` (string, 1–64 chars, alphanumeric/underscore/dash). **Optional:** `"operations"` — array of strings from `"suggestedIndexes"`, `"dropIndexSuggestions"`, `"slowQueryLogs"`, `"schemaSuggestions"` (request only what you need); for slowQueryLogs only: `"since"` (ISO 8601 date-time), `"namespaces"` (array of `"db.coll"` strings). |

For a user question, try to fetch information from both the connection string and Atlas API related to the query you are optimizing.

### 1\. DB connection string works for MongoDB MCP

- **`collection-indexes`** — Invoke with server \= MongoDB MCP server, toolName \= `collection-indexes`, arguments \= `{ "database": "<db>", "collection": "<coll>" }`. Use the result's `classicIndexes` (each has `name`, `key`) to see if the query can use any index, or be modified to use an existing index.  
- **`explain`** — Invoke with server \= MongoDB MCP server, toolName \= `explain`, arguments \= object with `database`, `collection`, `method` (one find/aggregate/count shape), and `verbosity`.  
  - **Run explain in queryPlanner mode, then possibly in executionStats mode:**  
    - Use `"queryPlanner"` to check if query will be COLLSCAN and get other query planning information  
    - If query is not a COLLSCAN, or collection size is very small: use `"executionStats"` with timeout of 10 seconds to get detailed execution information such as docs scanned and docs returned   

Typical flow: call `collection-indexes` to get a list of existing indexes, then `explain` to get query plan and execution information.

### 2\. Atlas API access works for MongoDB MCP

If you need a project ID, invoke **`atlas-list-projects`**: server \= MongoDB MCP server, toolName \= `atlas-list-projects`, arguments \= `{}` (or `{ "orgId": "<24-char hex>" }`). Then invoke **`atlas-get-performance-advisor`**: toolName \= `atlas-get-performance-advisor`, arguments \= `{ "projectId": "<24-char hex>", "clusterName": "<name>", "operations": ["..."] }`. The `operations` array must contain only the string values below (not the tool name); choose only what you need:

| Operation value | Use when |
| :---- | :---- |
| `slowQueryLogs` | Fetching slow queries on cluster—**prioritize by slowest and most frequent** when the response exposes those dimensions. Optional: `namespaces` to scope to a collection if the user is asking about a query for a particular collection; `since` for a time window. |
| `suggestedIndexes` | Fetching cluster index recommendations |
| `dropIndexSuggestions` | User asks what to remove or reduce index overhead. |
| `schemaSuggestions` | User asks for schema/query-structure advice alongside indexes (PA schema suggestions). |

Do not pass the MCP tool name (e.g. `atlas-get-performance-advisor`) as an operation—the tool name is used when invoking the tool; `operations` is a separate argument for this tool only.

## Example workflow 1 (help with specific query)

**User:** "Why is this query slow? `db.orders.find({status: 'shipped', region: 'US'}).sort({date: -1})`"

1. **(**If MCP db connection configured and the collection+db name are known) **Check existing collection indexes:**  
   - Call `collection-indexes` with database=`store`, collection=`orders`  
   - Result shows: `{_id: 1}`, `{status: 1}`, `{date: -1}`

   

2. **(**If MCP db connection configured and the collection+db name are known) **Run explain:**  
   - Call `explain` with method=`find`, filter=`{status: 'shipped', region: 'US'}`, sort=`{date: -1}`, verbosity=`queryPlanner` and `executionStats`  
   - Load `references/explain-interpretation.md` to interpret output  
   - Result: Uses `{status: 1}` index, then in-memory SORT, `totalKeysExamined: 50000`, `nReturned: 100`

   

3. **(**If MCP db connection configured and the collection+db name are known) **Run find**:  
   - Call `find` with limit=1 to fetch a sample document to impute the schema.

4. **(**If MCP Atlas connection configured) **Run atlas-get-performance-advisor:**  
   - Try to get the target cluster id from the MCP connection string  
   - Use slowQueryLogs to fetch slow query logs from database=`store`, collection=`orders` in the past 24 hours  
   - Use suggestedIndexes to check for index suggestions for the query

5. **Diagnose:** Based on explain output and slow query logs, this query targets 100 docs but scans 50K index entries (poor selectivity: 0.002). In-memory sort adds overhead. Index doesn't support both filter fields or sort.  
     
6. **Recommend:** Create compound index `{status: 1, region: 1, date: -1}` following ESR (two equality fields, then sort). This eliminates in-memory sort and improves selectivity by filtering on both status and region.

If the MongoDB MCP server is not set up, follow best indexing practices.

## Example workflow 2 (general database performance help)

**User:** "Can you help with optimizing slow queries on my cluster?”

1. **Run atlas-get-performance-advisor:**  
   - Try to get the target cluster id from the MCP connection string  
   - Use slowQueryLogs to fetch slow query logs from the past 24 hours  
   - Use suggestedIndexes  
   - Use dropIndexSuggestions  
   - Use schemaSuggestions  
2. **Diagnose and Recommend:** Based on slow query logs and performance advisor advice, you can create the compound index `{status: 1, region: 1, date: -1}` on the `db.orders` collection to optimize queries such as `find({status: 'shipped', region: 'US'}).sort({date: -1})`

Examine all performance advisor output as well as slow query logs. Provide information on what is being improved and why, and focus on suggestions that have the potential for greatest impact (e.g., indexes that affect the most queries, or queries that have the worst performance).

## Load references

Before beginning diagnosis and recommendation, load reference files.

Always load:

- **Core Indexing Principles** → Load `references/core-indexing-principles.md` 

Conditionally load these files:

- **If running explain()** → `references/explain-interpretation.md` to interpret output from **explain** MCP tool  
- **If diagnosing aggregation pipelines** → `references/aggregation-pipeline-examples.md`  
- **If diagnosing find queries** → `references/find-query-examples.md`  
- **If query on array fields** → `references/multikey-arrays.md` only if you are **sure** that the query operates on array values (e.g. seeing array values in target fields of the sample document fetched with **find**, or the query uses array operators e.g. $elemMatch)

## Output

- Keep answers short and clear: a few sentences on index usage, optimization suggestions, or suggested index when appropriate; expand only when summarizing slow-query lists or PA suggestion tradeoffs.  
- Do not create indexes directly via MCP unless the environment explicitly supports it and the user gives approval; otherwise tell the user to create in Atlas or use application-specific migrations.