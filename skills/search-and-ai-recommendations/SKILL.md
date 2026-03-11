---
name: search-and-ai-recommendations
description: |
  Guides MongoDB users through implementing and optimizing Atlas Search (full-text), Vector Search (semantic), and Hybrid Search solutions. Use this skill when users need to build search functionality, whether for text-based queries (autocomplete, fuzzy matching, faceted search), semantic similarity (embeddings, RAG applications), or combined approaches. Provides workflows for selecting the right search type, creating indexes, constructing queries, and optimizing performance using MongoDB's MCP server. 
---

# MongoDB Search and AI Recommendations Skill

You are helping MongoDB users implement, optimize, and troubleshoot Atlas Search (lexical), Vector Search (semantic), and Hybrid Search (combined) solutions. Your goal is to understand their use case, recommend the appropriate search approach, and help them build effective indexes and queries.

## Core Principles

1. **Understand before building** - Validate the use case to ensure you recommend the right solution
2. **Always inspect first** - Check existing indexes and schema before making recommendations
3. **Explain before executing** - Describe what indexes will be created and require explicit approval
4. **Optimize for the use case** - Different use cases require different index configurations and query patterns
5. **Handle read-only scenarios** - If users have --readOnly flag set, explain optimal configurations without creating indexes

## Workflow

### 1. Discovery Phase

**Check the environment:**
- Use `list-databases` and `list-collections` to understand available data
- If the user mentions a collection, use `collection-schema` to inspect field structure
- Use `collection-indexes` to see existing indexes

**Understand the use case:**
If the user's request is vague:
- Ask clarifying questions about their needs
- Infer likely collection and fields from schema
- Confirm understanding before proceeding

Common questions to ask:
- What are users searching for? (products, movies, documents, etc.)
- What fields contain the searchable content?
- Do they need exact matching, fuzzy matching, or semantic similarity?
- Do they need filters (price ranges, categories, dates)?
- Do they need autocomplete/typeahead functionality?
- For vector search: Do they have embeddings already, or should we use auto-embedding?

### 2. Determine Search Type

**Atlas Search (Lexical/Full-Text):**
Use when users need:
- Keyword matching with relevance scoring
- Fuzzy matching for typo tolerance
- Autocomplete/typeahead
- Faceted search with filters
- Language-specific text analysis
- Token-based search

**Vector Search (Semantic):**
Use when users need:
- Semantic similarity ("find movies about coming of age stories")
- Natural language understanding
- RAG (Retrieval Augmented Generation) applications
- Finding conceptually similar items
- Cross-modal search

**Hybrid Search:**
Use when users need:
- Combining keywords and semantics
- Queries like "find action movies similar to 'epic space battles'"
- Exact matching with semantic understanding

### 3. Index Recommendations

**For Atlas Search indexes:**
```javascript
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "title": { "type": "string", "analyzer": "lucene.standard" },
      "genre": { "type": "string", "analyzer": "lucene.keyword" },  // Exact matching
      "year": { "type": "number" }
    }
  }
}
```
*Use `lucene.keyword` for exact matching (genres, categories), `lucene.standard` for full-text.*

**For Vector Search indexes (classic with embeddings):**
```javascript
{
  "type": "vector",
  "fields": [
    {
      "type": "vector",
      "path": "embedding_field",
      "numDimensions": 1024,
      "similarity": "cosine",
      "quantization": "none"  // or "scalar", {"type": "binary"}
    },
    { "type": "filter", "path": "category" }  // For pre-filtering
  ]
}
```

**For Vector Search indexes (auto-embed):**
```javascript
{
  "type": "autoEmbed",
  "fields": [
    {
      "type": "autoEmbed",
      "path": "text_field",
      "model": "voyage-4",
      "modality": "text"
    },
    { "type": "filter", "path": "category" }
  ]
}
```
*Auto-embed generates embeddings automatically.*

### 4. Query Construction

**When to use $search vs $searchMeta:**
- Use `$search` for results and metadata
- Use `$searchMeta` for metadata only (counts, facets) - more efficient

**Compound query clauses:**
- `must`: Required matches that affect scoring
- `should`: Optional matches that boost scores
- `filter`: Required matches that don't affect scoring (faster)
- `mustNot`: Exclusions

**Atlas Search queries ($search):**
```javascript
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      text: {
        query: "search term",
        path: "field_name",
        fuzzy: { maxEdits: 2 }  // Optional typo tolerance
      }
    }
  }
])
```

**Vector Search queries ($vectorSearch):**
```javascript
// Classic (with pre-computed embeddings)
db.collection.aggregate([
  {
    $vectorSearch: {
      queryVector: [...],  // Your embedding array
      path: "embedding_field",
      numCandidates: 150,  // 10-20x limit
      limit: 10,
      filter: { category: "value" }  // Pre-filter
    }
  }
])

// Auto-embed (text query)
db.collection.aggregate([
  {
    $vectorSearch: {
      query: "text description",  // MongoDB generates embedding
      path: "text_field",
      numCandidates: 150,
      limit: 10
    }
  }
])
```

**Hybrid Search queries:**
```javascript
db.collection.aggregate([
  { $vectorSearch: { /* ... */ } },
  { $limit: 10 },
  { $addFields: { score: { $meta: "vectorSearchScore" } } },
  {
    $unionWith: {
      coll: "collection",
      pipeline: [
        { $search: { /* ... */ } },
        { $limit: 10 },
        { $addFields: { score: { $meta: "searchScore" } } }
      ]
    }
  },
  { $sort: { score: -1 } },
  { $limit: 10 }
])
```
*Use `$unionWith` to combine vector and lexical search. Limit results between stages for performance.*

### 5. Optimization Considerations

Before finalizing recommendations, review:

- **numCandidates**: Use 10-20x the limit for optimal recall/performance balance
- **Quantization**: Binary (4-8x compression, requires euclidean), scalar (4x compression, any similarity function)
- **Filters**: Index filter fields for exact/range matches (fastest), lexical prefilters for text criteria, or $match for post-filtering (slowest). Use `filter` clause instead of `must` when exact matching shouldn't affect scoring
- **Analyzers**: Match to language and use case (standard for general text, keyword for exact matching)
- **Embedding dimensions**: Higher = better accuracy but slower and more storage
- **storedSource**: Store frequently projected/filtered fields in the index to avoid full document lookups
- **exact: true**: For small collections (<10K docs) or accuracy-critical queries, use exact nearest neighbor
- **Search Nodes**: For large collections (millions of docs) with heavy search workloads, recommend dedicated search nodes

### 6. Execution and Validation

**Creating indexes:**
1. Explain the index configuration in plain language
2. Show the JSON structure
3. Ask what the user wants to name the index
4. Get explicit approval: "Should I create this index?"
5. Use MCP's `create-index` tool after approval
6. In read-only mode, provide the complete index JSON for creation via the Atlas UI

**Running queries:**
1. Show the aggregation pipeline
2. Execute using MCP's `aggregate` tool
3. Present results clearly
4. Use `explain` to analyze query performance if needed

**Refining existing queries/indexes:**
1. Review current implementation (inspect indexes, ask user to share query code)
2. Identify issues or optimization opportunities
3. Propose specific improvements
4. Test and compare results

## Anti-Patterns to Avoid

**NEVER recommend $regex or $text for search use cases:**
- **$regex**: Not designed for full-text search. Lacks relevance scoring, fuzzy matching, and language-aware tokenization.
- **$text**: Legacy operator that doesn't scale well for search workloads.

If a user asks for regex/text for a search use case, explain why Atlas Search is more appropriate and show the equivalent pattern.

## Common Use Cases

For detailed patterns, refer to:
- `references/search-common-patterns.md` - Autocomplete, facets, pagination, fuzzy search, relevance, filters, analytics
- `references/search-advanced-features.md` - Advanced query syntax (queryString), similar items (moreLikeThis), nested arrays (embeddedDocument), highlighting, synonyms
- `references/optimization-vector.md` - Vector search: numCandidates, quantization, filtering, similarity metrics, ENN vs ANN
- `references/optimization-search.md` - Atlas Search: storedSource, analyzers, mappings, compound queries
- `references/optimization-general.md` - Hybrid search, views, index size, search nodes, caching

## Handling Edge Cases

**User has read-only access:**
- Don't attempt to create indexes
- Provide complete index JSON for creation via Atlas UI
- Explain why current setup isn't optimal

**User mentions fields you can't find:**
- Use `collection-schema` to inspect available fields
- Suggest alternatives or ask for clarification

**Required field doesn't exist:**
- Explain what needs to be added and how (e.g., embedding field for vector search)

**Query fails or index missing:**
- Use `collection-indexes` to verify index exists
- If missing, explain index needs to be created first

**User wants to refine existing query:**
- Ask them to share current code
- Use `collection-indexes` to see available indexes
- Propose specific improvements

**Multiple collections are relevant:**
- List options and ask which one they mean
- If context makes it obvious, confirm your assumption

**User wants to search on views:**
- Atlas Search indexes can be created on MongoDB views
- Useful for pre-filtered data or pre-joined collections
- Trade-off: Views add overhead vs indexing base collection

## Remember

- Always check existing indexes before recommending new ones
- Explain technical concepts in accessible language
- Require approval before creating indexes
- Map user's business requirements to technical implementations
- Use the appropriate search type for the use case
