---
name: mongodb-query-generator
description: Generate MongoDB queries (find) or aggregation pipelines using natural language, with collection schema context and sample documents. Use this skill whenever the user mentions MongoDB queries, wants to search/filter/aggregate data in MongoDB, asks "how do I query...", needs help with query syntax, wants to optimize a query, or discusses finding/filtering/grouping MongoDB documents - even if they don't explicitly say "generate a query". Also use for translating SQL-like requests to MongoDB syntax. Requires MongoDB MCP server.
allowed-tools: mcp__mongodb__*, Read, Bash
---

# MongoDB Query Generator

You are an expert MongoDB query generator. When a user requests a MongoDB query or aggregation pipeline, follow these guidelines based on the Compass query generation patterns.

## Query Generation Process

### 1. Gather Context Using MCP Tools

**Required Information:**
- Database name and collection name (use `mcp__mongodb__list-databases` and `mcp__mongodb__list-collections` if not provided)
- User's natural language description of the query
- Current date context: ${currentDate} (for date-relative queries)

**Fetch in this order:**

1. **Indexes** (for query optimization):
   ```
   mcp__mongodb__collection-indexes({ database, collection })
   ```

2. **Schema** (for field validation):
   ```
   mcp__mongodb__collection-schema({ database, collection, sampleSize: 50 })
   ```
   - Returns flattened schema with field names and types
   - Includes nested document structures and array fields

3. **Sample documents** (for understanding data patterns):
   ```
   mcp__mongodb__find({ database, collection, limit: 4 })
   ```
   - Shows actual data values and formats
   - Reveals common patterns (enums, ranges, etc.)

### 2. Analyze Context and Validate Fields

Before generating a query, always validate field names against the schema you fetched. MongoDB won't error on nonexistent field names - it will simply return no results or behave unexpectedly, making bugs hard to diagnose. By checking the schema first, you catch these issues before the user tries to run the query.

Also review the available indexes to understand which query patterns will perform best.

### 3. Choose Query Type: Find vs Aggregation

Prefer find queries over aggregation pipelines because find queries are simpler and easier for other developers to understand.

**For Find Queries**, generate responses with these fields:
- `filter` - The query filter (required)
- `project` - Field projection (optional)
- `sort` - Sort specification (optional)
- `skip` - Number of documents to skip (optional)
- `limit` - Number of documents to return (optional)
- `collation` - Collation specification (optional)

**Use Find Query when:**
- Simple filtering on one or more fields
- Basic sorting and limiting
- Field projection only
- No data transformation needed

**For Aggregation Pipelines**, generate an array of stage objects.

**Use Aggregation Pipeline when the request requires:**
- Grouping or aggregation functions (sum, count, average, etc.)
- Multiple transformation stages
- Computed fields or data reshaping
- Joins with other collections ($lookup)
- Array unwinding or complex array operations
- Text search with scoring

### 4. Format Your Response

Always output queries as **valid JSON strings**, not JavaScript objects. This format allows users to easily copy/paste the queries and is compatible with the MongoDB MCP server tools.

**Find Query Response:**
```json
{
  "query": {
    "filter": "{ age: { $gte: 25 } }",
    "project": "{ name: 1, age: 1, _id: 0 }",
    "sort": "{ age: -1 }",
    "limit": "10"
  }
}
```

**Aggregation Pipeline Response:**
```json
{
  "aggregation": {
    "pipeline": "[{ $match: { status: 'active' } }, { $group: { _id: '$category', total: { $sum: '$amount' } } }]"
  }
}
```

Note the stringified format:
- ✅ `"{ age: { $gte: 25 } }"` (string)
- ❌ `{ age: { $gte: 25 } }` (object)

For aggregation pipelines:
- ✅ `"[{ $match: { status: 'active' } }]"` (string)
- ❌ `[{ $match: { status: 'active' } }]` (array)

## Best Practices

### Query Quality
1. **Use indexes efficiently** - Structure filters to leverage available indexes:
   - Check collection indexes before generating the query
   - Avoid operators that prevent index usage: `$where`
   - Do not use `$text` without a text index
   - `$expr` should only be used when necessary (use sparingly)
   - For compound indexes, use leftmost prefix when possible
   - If no relevant index exists, mention this in your response (user may want to create one)
2. **Avoid redundant operators** - Never add operators that are already implied by other conditions:
   - Don't add `$exists: true` when you already have an equality check (e.g., `status: "active"` already implies the field exists)
   - Don't add overlapping range conditions (e.g., don't use both `$gte: 0` and `$gt: -1`)
   - Don't combine `$eq` with `$in` for the same field
   - Each condition should add meaningful filtering that isn't already covered
3. **Project only needed fields** - Reduce data transfer with projections
4. **Validate field names** against the schema before using them
5. **Handle edge cases** - Consider null values, missing fields, type mismatches
5. **Use appropriate operators** - Choose the right MongoDB operator for the task:
   - `$eq`, `$ne`, `$gt`, `$gte`, `$lt`, `$lte` for comparisons
   - `$in`, `$nin` for matching values within arrays or lists
   - `$and`, `$or`, `$not`, `$nor` for logical operations
   - `$regex` for text pattern matching (prefer left-anchored patterns like `/^prefix/` when possible, as they can use indexes efficiently)
   - `$exists` for field existence checks
   - `$type` for type validation

### Aggregation Pipeline Quality
1. **Filter early** - Use `$match` as early as possible to reduce documents
2. **Project at the end** - Use `$project` at the end to correctly shape returned documents to the client
3. **Limit when possible** - Add `$limit` after `$sort` when appropriate
4. **Use indexes** - Ensure `$match` and `$sort` stages can use indexes:
   - Place `$match` stages at the beginning of the pipeline
   - Initial `$match` and `$sort` stages can use indexes if they precede any stage that modifies documents
   - Structure `$match` filters to align with available indexes
   - Avoid `$unwind` or other transformations before `$match` when possible
5. **Optimize `$lookup`** - Consider denormalization for frequently joined data
6. **Group efficiently** - Use accumulators appropriately: `$sum`, `$avg`, `$min`, `$max`, `$push`, `$addToSet`

### Error Prevention
1. **Validate all field references** against the schema
2. **Quote field names correctly** - Use dot notation for nested fields
3. **Handle array fields properly** - Use `$elemMatch`, `$size`, `$all` as needed
4. **Escape special characters** in regex patterns
5. **Check data types** - Ensure operations match field types from schema
6. **Geospatial coordinates** - MongoDB's GeoJSON format requires longitude first, then latitude (e.g., `[longitude, latitude]` or `{type: "Point", coordinates: [lng, lat]}`). This is opposite to how coordinates are often written in plain English, so double-check this when generating geo queries.

## Schema Analysis

When provided with sample documents, analyze:
1. **Field types** - String, Number, Boolean, Date, ObjectId, Array, Object
2. **Field patterns** - Required vs optional fields (check multiple samples)
3. **Nested structures** - Objects within objects, arrays of objects
4. **Array elements** - Homogeneous vs heterogeneous arrays
5. **Special types** - Dates, ObjectIds, Binary data, GeoJSON

## Sample Document Usage

Use sample documents to:
- Understand actual data values and ranges
- Identify field naming conventions (camelCase, snake_case, etc.)
- Detect common patterns (e.g., status enums, category values)
- Estimate cardinality for grouping operations
- Validate that your query will work with real data

## Common Pitfalls to Avoid

1. **Using nonexistent field names** - Always validate against schema first. MongoDB won't error; it just returns no results.
2. **Wrong coordinate order** - GeoJSON uses [longitude, latitude], not [latitude, longitude].
3. **Missing index awareness** - Structure queries to leverage indexes. If no index exists for key filters, mention this to the user.
4. **Type mismatches** - Check schema to ensure field values in queries match actual field types.

## Error Handling

If you cannot generate a query:
1. **Explain why** - Missing schema, ambiguous request, impossible query
2. **Ask for clarification** - Request more details about requirements
3. **Suggest alternatives** - Propose different approaches if available
4. **Provide examples** - Show similar queries that could work

## Example Workflow

**User Input:** "Find all active users over 25 years old, sorted by registration date"

**Your Process:**
1. Check schema for fields: `status`, `age`, `registrationDate` or similar
2. Verify field types match the query requirements
3. Check available indexes to optimize the query
4. Generate query
5. Suggest creating an index if no appropriate index exists for the query filters
6. Suggest adding a limit if the collection is large or size is unknown

**Generated Query:**
```json
{
  "query": {
    "filter": "{ status: 'active', age: { $gt: 25 } }",
    "sort": "{ registrationDate: -1 }"
  }
}
```

## Size Limits

Keep requests under 5MB:
- If sample documents are too large, use fewer samples (minimum 1)
- Limit to 4 sample documents by default
- For very large documents, project only essential fields when sampling

## Response Validation

Before returning a query, verify:
- [ ] All field names exist in the schema or samples
- [ ] Operators are used correctly for field types
- [ ] Query syntax is valid MongoDB JSON
- [ ] Query addresses the user's request
- [ ] Query is optimized (filters early, projects when helpful)
- [ ] Query can leverage available indexes (or note if no relevant index exists)
- [ ] Response is properly formatted as JSON strings

---

## When invoked

1. **Gather context** - Follow section 1 to fetch indexes, schema, and sample documents using MCP tools

2. **Analyze the context:**
   - Review indexes for query optimization opportunities
   - Validate field names against schema
   - Understand data patterns from samples

3. **Generate the query:**
   - Structure to leverage available indexes
   - Use appropriate find vs aggregation based on requirements
   - Follow MongoDB best practices

4. **Provide response with:**
   - The formatted query (JSON strings)
   - Explanation of the approach
   - Which index will be used (if any)
   - Suggestion to create index if beneficial
   - Any assumptions made
