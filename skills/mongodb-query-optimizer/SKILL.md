---
name: mongodb-query-optimizer
description: Ensure MongoDB queries have good performance and are indexed. Use this skill whenever the user is writing or modifying MongoDB queries (find, aggregate, count), adding new query fields or filters, debugging slow queries, or changing application code that hits MongoDB — even if they don't mention "index" or "performance". Check existing indexes via MongoDB MCP and suggest or reuse an index so queries are not unoptimized.
compatibility: Requires MongoDB MCP server with collection-indexes tool. Connection to the target cluster must be available.
---

# MongoDB query index optimization

When you write or change a MongoDB query (in code or from a direct prompt), ensure it can use an index. Use the MongoDB MCP to inspect indexes and either align the query with an existing index or recommend creating one.

## Workflow

1. **Identify** the operation's target: database, collection, and which fields are used in:
   - filter / predicate
   - sort
   - aggregation `$match`, `$group`, `$sort`, etc.

2. **Inspect existing indexes**  
   Call the MCP tool `collection-indexes` (server `user-MongoDB`) with the `database` and `collection` for that query. You get `classicIndexes` (each has `name` and `key`). Use this to see what's already there.

3. **Match or suggest an index**
   - **If an existing index can support the query**  
     - Prefer equality on indexed fields, then range, then sort; compound indexes follow left-prefix.  
     - Shape the query so the planner can use that index (e.g. filter/sort order consistent with the index key).  
     - In your reply, state briefly that the query is covered by an existing index (e.g. "Query uses index `idx_serialCode`").
   - **If no suitable index exists**  
     - Propose a concrete index key, e.g. `{ serialCode: 1 }` or compound `{ status: 1, createdAt: -1 }`.  
     - If the codebase has an index/migration pattern (e.g. migrations folder, schema file that defines indexes), add the new index there.  
     - If there is no such pattern, clearly tell the user the query is unoptimized and that they should create the index (e.g. "Create index `{ serialCode: 1 }` on `db.collection`"), and optionally note they can create it in Atlas or via the driver.

4. **Keep output short**  
   One or two sentences on index usage or the suggested index; no long essays. Rely on standard MongoDB index behavior (left-prefix, equality before range, sort order).

## MCP usage

- **Tool**: `collection-indexes`  
- **Server**: `user-MongoDB`  
- **Arguments**: `database` (string), `collection` (string)  
- **Use**: Call after you know the target db and collection from the user's query or code. Use the returned `classicIndexes[].key` to see index key patterns; ignore search indexes unless the query is a search query.

## Out of scope (for this skill)

- Performance Advisor / slow query logs
- Suggesting or applying non-index optimizations (e.g. schema design, sharding)
- Creating indexes directly via MCP (only suggest; user creates in Atlas or via migrations)
