---
name: search-and-ai
description: |
  Guides MongoDB users through implementing and optimizing Atlas Search (full-text), Vector Search (semantic), and Hybrid Search solutions. Use this skill when users need to build search functionality, whether for text-based queries (autocomplete, fuzzy matching, faceted search), semantic similarity (embeddings, RAG applications), or combined approaches. Provides workflows for selecting the right search type, creating indexes, constructing queries, and optimizing performance using the MongoDB MCP server. 
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
- Combining multiple search approaches (e.g., vector + lexical, multiple text searches)
- Queries like "find action movies similar to 'epic space battles'" (combining keyword filtering with semantic similarity)
- Results that factor in multiple relevance criteria
- Uses `$rankFusion` (rank-based) or `$scoreFusion` (score-based) to merge pipelines

Once you have determined the search type, always consult the appropriate reference file(s) before recommending indexes or queries:
- **Lexical**: consult both `references/lexical-search-indexing.md` (index) and `references/lexical-search-querying.md` (query)
- **Vector**: consult `references/vector-search.md`
- **Hybrid**: consult `references/hybrid-search.md` (and the lexical/vector files for the individual pipeline stages within it)

### 3. Query Construction

Consult the appropriate reference file for full query syntax and examples. When constructing queries, keep in mind:

**Compound query clauses (Atlas Search):**
- `must`: Required matches that affect scoring
- `should`: Optional matches that boost scores
- `filter`: Required matches that don't affect scoring (faster)
- `mustNot`: Exclusions

### 5. Optimization Considerations

Before finalizing recommendations, review:

- **numCandidates**: Use 10-20x the limit for optimal recall/performance balance
- **Quantization**: Binary (4-8x compression, requires euclidean), scalar (4x compression, any similarity function)
- **Filters**: Index filter fields for exact/range matches (fastest), lexical prefilters for text criteria, or $match for post-filtering (slowest). Use `filter` clause instead of `must` when exact matching shouldn't affect scoring
- **Analyzers**: Match to language and use case (standard for general text, keyword for exact matching)
- **Embedding dimensions**: Higher = better accuracy but slower and more storage
- **storedSource**: Store frequently projected/filtered fields in the index to avoid full document lookups
- **exact: true**: For small collections (<10K docs) or accuracy-critical queries, use exact nearest neighbor

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

## Reference Files

- `references/lexical-search-indexing.md` — Creating or modifying an Atlas Search index: field types, analyzers, dynamic vs explicit vs typeSet mappings, storedSource configuration, synonym mapping setup, creating Search indexes on Views
- `references/lexical-search-querying.md` — Writing a $search or $searchMeta query: $search vs $searchMeta, compound operator, queryString, embeddedDocument, highlighting, returnStoredSource at query time, multi-analyzer path syntax, explain
- `references/vector-search.md` — Creating a Vector Search index or writing a $vectorSearch query: index definition, filter fields, numCandidates tuning, ANN vs ENN, pre/post filtering, creating Vector Search indexes on Views
- `references/hybrid-search.md` — Combining search methods: $rankFusion, $scoreFusion, lexical prefilters using the vectorSearch operator inside $search, required index setup for hybrid, choosing between $rankFusion/$scoreFusion/lexical prefilter

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
- Atlas Search and Vector Search indexes can be created on Views (requires MongoDB 8.0+)
- Programmatic index creation via mongosh/drivers requires 8.1+
- Supported view stages: `$addFields`, `$set`, `$match` with `$expr` only
- See `references/lexical-search-indexing.md` or `references/vector-search.md` for full details

## Remember

- Always check existing indexes before recommending new ones
- Explain technical concepts in accessible language
- Require approval before creating indexes
- Map user's business requirements to technical implementations
- Use the appropriate search type for the use case
