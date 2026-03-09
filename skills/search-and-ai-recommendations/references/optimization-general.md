# General Search Optimizations

This guide covers optimizations that apply across search types, including hybrid search and infrastructure considerations.

## Table of Contents

- [Hybrid Search Optimizations](#hybrid-search-optimizations)
- [Searching on Views](#searching-on-views)
- [Index Size Management](#index-size-management)
- [Query Performance Analysis](#query-performance-analysis)
- [Search Nodes](#search-nodes)
- [Caching Strategies](#caching-strategies)
- [Quick Reference](#quick-reference)

---

## Hybrid Search Optimizations

### Limiting Results Between Stages

In hybrid search, limit results from each pipeline before combining:

**Optimized pattern:**
```javascript
db.collection.aggregate([
  {
    $vectorSearch: {
      queryVector: [...],
      numCandidates: 150,
      limit: 50  // Get more candidates
    }
  },
  { $limit: 20 },  // But only keep top 20 for merging
  { $addFields: { score: { $meta: "vectorSearchScore" } } },
  {
    $unionWith: {
      coll: "collection",
      pipeline: [
        { $search: { /* ... */ } },
        { $limit: 20 }  // Also limit lexical results
      ]
    }
  },
  { $sort: { score: -1 } },
  { $limit: 10 }  // Final result count
])
```

**Why this matters:**
- Reducing intermediate results speeds up merging and sorting
- Typical pattern: Get 50 candidates, keep top 20 from each, merge to top 10
- Adjust based on how much diversity you want in final results

### Score Normalization

When combining vector and lexical scores, they have different scales. Normalize for fair comparison:

```javascript
db.collection.aggregate([
  {
    $vectorSearch: {
      queryVector: [...],
      numCandidates: 150,
      limit: 20
    }
  },
  { $limit: 10 },
  {
    $addFields: {
      vectorScore: { $meta: "vectorSearchScore" },
      // Normalize to [0, 1] range
      normalizedScore: {
        $divide: [
          { $meta: "vectorSearchScore" },
          { $max: "$vectorScore" }  // Divide by max score
        ]
      }
    }
  },
  // ... rest of hybrid query
])
```

**Or use MongoDB's built-in score fusion:**
```javascript
db.collection.aggregate([
  {
    $vectorSearch: { /* ... */ }
  },
  { $group: { _id: null, docs: { $push: "$$ROOT" } } },
  { $unwind: "$docs" },
  { $replaceRoot: { newRoot: "$docs" } },
  {
    $unionWith: {
      coll: "collection",
      pipeline: [{ $search: { /* ... */ } }]
    }
  },
  {
    $group: {
      _id: "$_id",
      maxScore: { $max: "$score" },
      doc: { $first: "$$ROOT" }
    }
  }
])
```

---

## Searching on Views

Atlas Search indexes can be created on MongoDB views, which can be useful for specific scenarios.

**When to use:**
- Pre-filtered data: View contains only recent documents (e.g., movies from last 5 years)
- Pre-joined data: View combines multiple collections that are frequently searched together
- Transformed data: View performs expensive transformations once rather than at query time

**Trade-offs:**
- Views add overhead since the aggregation pipeline runs on each access
- Generally slower than indexing the base collection directly
- Index maintenance happens on view results, not raw data

**Example use case:**
```javascript
// Create view of recent, highly-rated movies
db.createView("recent_popular_movies", "movies", [
  { $match: { year: { $gte: 2020 }, "imdb.rating": { $gte: 7 } } },
  { $project: { title: 1, plot: 1, genres: 1, year: 1, "imdb.rating": 1 } }
])

// Then create search index on the view
// Index only processes ~subset of documents instead of all movies
```

**Recommendation:** Only use views for search if the view significantly reduces data size or pre-computes expensive operations. Otherwise, index the base collection and use filters in queries.

---

## Index Size Management

**Monitor index sizes:**
```javascript
db.collection.aggregate([
  { $collStats: { storageStats: {} } }
])
```

**Reduce index size:**
1. Use explicit mappings (`dynamic: false`)
2. Only index fields you actually search
3. Use appropriate analyzers (keyword for exact, standard for text)
4. Use quantization for vector indexes

---

## Query Performance Analysis

Use `explain` to analyze query performance:
```javascript
db.collection.explain("executionStats").aggregate([
  { $search: { /* ... */ } }
])
```

Look for:
- `totalDocsExamined`: Lower is better
- `executionTimeMillis`: Query execution time
- `nReturned`: Number of results

---

## Search Nodes

**Only recommend for very large workloads:**
- Collections with millions of documents
- Heavy search query load
- When search performance impacts cluster operations

Available in M30+ clusters. Search nodes handle search queries separately from data nodes.

---

## Caching Strategies

**Application-level caching:**
- Cache facet counts (they change slowly)
- Cache autocomplete suggestions

**Index warming:**
- Run common queries after index creation to warm caches
- Schedule periodic queries for frequently-used patterns

---

## Quick Reference

### When to Use What

| Scenario | Recommendation |
|----------|---------------|
| Small dataset (< 100k docs) | No quantization, standard settings |
| Medium dataset (100k-1M docs) | Scalar quantization, explicit mappings |
| Large dataset (1M-10M docs) | Scalar quantization, search nodes, optimize numCandidates |
| Very large dataset (10M+ docs) | Binary quantization, search nodes, aggressive limiting |
| Queries are slow | Reduce numCandidates, add pre-filters, use explicit mappings |
| Results aren't relevant | Increase numCandidates, adjust analyzers, tune boosting |
| Index is too large | Use explicit mappings, quantization, remove unused fields |
| Need real-time updates | Standard indexing (no special config needed) |
