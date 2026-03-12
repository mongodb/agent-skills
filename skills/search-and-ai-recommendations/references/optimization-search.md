# Atlas Search Optimizations

This guide covers performance optimizations specific to MongoDB Atlas Search (lexical/full-text search).

## Table of Contents

- [storedSource and returnStoredSource](#storedsource-and-returnstoredsource)
- [Analyzer Selection](#analyzer-selection)
- [Dynamic vs Explicit Mappings](#dynamic-vs-explicit-mappings)
- [Query Optimization](#query-optimization)

---

## storedSource and returnStoredSource

Store frequently accessed fields directly in the search index (mongot) to avoid full document lookups from the database. This dramatically improves query performance, especially when filtering or sorting.

**Index configuration:**
```javascript
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "title": { "type": "string" },
      "genre": { "type": "string", "analyzer": "lucene.keyword" },
      "year": { "type": "number" },
      "rating": { "type": "number" }
    },
    "storedSource": {
      "include": ["title", "genre", "year", "rating"]  // Store these fields
    }
  }
}

// Or exclude specific fields
{
  "storedSource": {
    "exclude": ["largeTextField", "unusedField"]
  }
}

// Or store all fields (not available if vector index present)
{
  "storedSource": true
}
```

**Query with returnStoredSource:**
```javascript
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      text: { query: "detective", path: "plot" },
      returnStoredSource: true  // Retrieve from mongot, not DB
    }
  },
  { $limit: 20 },
  { $match: { rating: { $gte: 7 } } }  // Filter on stored fields
])
```

**When to use:**
- Fields used for filtering, sorting, or projection after $search
- Frequently accessed fields in search results
- When avoiding database lookups is critical for performance

**When NOT to use:**
- Very large text fields (increases index size significantly)
- Fields rarely used in queries
- When index size is a concern

---

## Analyzer Selection

The analyzer determines how text is processed for indexing and searching.

**Common analyzers:**

| Analyzer | Use Case | Example |
|----------|----------|---------|
| `lucene.standard` | General text search | "The quick brown fox" → ["quick", "brown", "fox"] |
| `lucene.simple` | Lowercase, no special chars | "Hello-World!" → ["hello", "world"] |
| `lucene.keyword` | Exact matching, facets | "Action" → ["Action"] |
| `lucene.whitespace` | Split on spaces only | "first-class" → ["first-class"] |
| Language-specific | Stemming, stop words | `lucene.english`, `lucene.spanish` |

**Configuration:**
```javascript
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "title": {
        "type": "string",
        "analyzer": "lucene.standard"  // General text
      },
      "category": {
        "type": "string",
        "analyzer": "lucene.keyword"   // Exact matching
      },
      "description": {
        "type": "string",
        "analyzer": "lucene.english"   // English-specific
      }
    }
  }
}
```

**Decision guide:**
- **lucene.standard**: Default for most text fields
- **lucene.keyword**: Categories, tags, exact values
- **Language-specific**: When you know the content language
- **lucene.simple**: When you want aggressive normalization

---

## Dynamic vs Explicit Mappings

**Dynamic mappings** automatically index all fields:
```javascript
{
  "mappings": {
    "dynamic": true  // Index everything
  }
}
```
- **Pros**: Quick setup, works immediately
- **Cons**: Larger index, slower queries, wastes resources on unused fields

**Explicit mappings** define exactly what to index:
```javascript
{
  "mappings": {
    "dynamic": false,  // Only index specified fields
    "fields": {
      "title": { "type": "string" },
      "genre": { "type": "string", "analyzer": "lucene.keyword" }
    }
  }
}
```
- **Pros**: Smaller index, faster queries, precise control
- **Cons**: Requires knowing your schema

**Recommendation:** Use `dynamic: false` in production for better performance.

---

## Query Optimization

**Compound queries** combine multiple operators efficiently:
```javascript
{
  $search: {
    compound: {
      must: [
        { text: { query: "detective", path: "plot" } }  // Required, affects score
      ],
      should: [
        { text: { query: "mystery", path: "genre" } }   // Optional, boosts score
      ],
      filter: [
        { range: { path: "year", gte: 2000 } }          // Required, no score impact
      ],
      mustNot: [
        { text: { query: "comedy", path: "genre" } }    // Excludes results
      ]
    }
  }
}
```

**Performance tips:**
- Use `filter` instead of `must` for criteria that shouldn't affect scoring (faster)
- Put most selective criteria in `must` or `filter` first
- Limit `should` clauses to 3-5 for best performance
