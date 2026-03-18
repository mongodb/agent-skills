# Lexical Search - Querying

This guide covers query patterns and optimization techniques for MongoDB Atlas Search.

## Table of Contents

- [$search vs $searchMeta](#search-vs-searchmeta)
- [Query Patterns](#query-patterns)
- [Query Optimization](#query-optimization)

---

## $search vs $searchMeta

Both stages must be the **first stage** in an aggregation pipeline.

| Stage | Use When |
|---|---|
| `$search` | You need matching documents, with or without facet metadata |
| `$searchMeta` | You only need metadata (count, facets) — no documents returned |

`$searchMeta` shares the following fields with `$search`: `index`, all operator names (e.g. `text`, `range`, `compound`), `concurrent`, and `returnStoredSource`.

`$searchMeta`-only fields:

| Field | Description |
|---|---|
| `count` | Returns total or lower-bound count of matching documents. `{ "type": "total \| lowerBound" }` |
| `facet` | Collector that returns facet bucket metadata instead of an operator |
| `returnScope` | Sets query context to an embedded document field. Requires `returnStoredSource: true` on MongoDB < 8.2 |

**Example: count documents matching a range**
```javascript
db.movies.aggregate([
  {
    $searchMeta: {
      range: { path: "year", gte: 1998, lt: 1999 },
      count: { "type": "total" }
    }
  }
])
// Returns: [ { count: { total: Long("552") } } ]
```

---

## Query Patterns

### Advanced Query Syntax (queryString)

**Use case:** Complex search with boolean operators, wildcards, and field-specific queries.

**Fields configuration:**
```javascript
// Add to mappings.fields in your index:
{
  "title": { "type": "string" },
  "director": { "type": "string" },
  "year": { "type": "number" }
}
```

**Query patterns:**
```javascript
// Boolean operators
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      queryString: {
        defaultPath: "title",
        query: "detective AND (noir OR thriller) NOT comedy"
      }
    }
  }
])

// Field-specific searches
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      queryString: {
        defaultPath: "title",
        query: "title:inception AND director:nolan"
      }
    }
  }
])

// Wildcards and ranges
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      queryString: {
        defaultPath: "title",
        query: "star* AND year:[2010 TO 2020]"
      }
    }
  }
])
```

**Supported syntax:**
- Boolean: `AND`, `OR`, `NOT`
- Grouping: `(term1 OR term2)`
- Wildcards: `*` (0+ chars), `?` (single char)
- Ranges: `[min TO max]` for numbers/dates
- Field-specific: `fieldName:value`

**Key considerations:**
- Great for building search UIs with advanced options
- Users can construct complex queries without API changes
- Validate/sanitize user input to prevent injection

---

### Searching Nested Arrays (embeddedDocument)

**Use case:** Search within arrays of objects where each element should be scored independently.

**Fields configuration:**
```javascript
// Add to mappings.fields in your index:
{
  "title": { "type": "string" },
  "reviews": {
    "type": "embeddedDocuments",  // Required for array search
    "fields": {
      "author": { "type": "string" },
      "text": { "type": "string" },
      "rating": { "type": "number" }
    }
  }
}
```

**Query pattern:**
```javascript
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      embeddedDocument: {
        path: "reviews",
        operator: {
          compound: {
            must: [
              { text: { query: "excellent", path: "reviews.text" } }
            ],
            filter: [
              { range: { path: "reviews.rating", gte: 4 } }
            ]
          }
        },
        score: { embedded: { aggregate: "maximum" } }  // or sum, minimum, mean
      }
    }
  }
])
```

**Score aggregation options:**
- `sum`: Add scores from all matching array elements
- `maximum`: Use highest score from array elements
- `minimum`: Use lowest score from array elements
- `mean`: Average scores from array elements

**Key considerations:**
- Each array element is indexed as a separate document
- Use `embeddedDocuments` field type, not regular `document`
- Score aggregation controls how array matches affect overall document score
- Performance can be degraded due to complexity of parent-child joins

---

### Search Highlighting

**Use case:** Show users which parts of documents matched their query.

**Fields configuration:**
```javascript
// Add to mappings.fields in your index:
{
  "title": { "type": "string" },
  "plot": { "type": "string" }
}
```

**Query pattern:**
```javascript
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      text: {
        query: "detective noir",
        path: "plot"
      },
      highlight: {
        path: "plot",
        maxCharsToExamine: 500000,  // Default
        maxNumPassages: 5            // Number of snippets
      }
    }
  },
  {
    $project: {
      title: 1,
      plot: 1,
      highlights: { $meta: "searchHighlights" },
      score: { $meta: "searchScore" }
    }
  }
])
```

**Highlight result structure:**
```javascript
{
  "highlights": [
    {
      "path": "plot",
      "texts": [
        { "value": "A ", "type": "text" },
        { "value": "detective", "type": "hit" },
        { "value": " investigates a murder in ", "type": "text" },
        { "value": "noir", "type": "hit" },
        { "value": " Los Angeles", "type": "text" }
      ],
      "score": 1.23
    }
  ]
}
```

**Key considerations:**
- `type: "hit"` indicates matched terms
- `type: "text"` is surrounding context
- Multiple passages returned for long documents
- Use in search results UI to show match context

---

## Query Optimization

### Compound Queries

**Compound queries** combine multiple operators efficiently:

```javascript
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
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
])
```

**Clause types:**
- `must`: Required matches that affect scoring
- `should`: Optional matches that boost scores
- `filter`: Required matches that don't affect scoring (faster)
- `mustNot`: Exclusions

**Performance tips:**
- Use `filter` instead of `must` for criteria that shouldn't affect scoring (faster)
- Put most selective criteria in `must` or `filter` first
- Limit `should` clauses to 3-5 for best performance

---

### Using Stored Source

Retrieve frequently accessed fields directly from the search index instead of the database:

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

**Requirements:**
- Fields must be configured in `storedSource` in your index definition
- Dramatically improves performance by avoiding database lookups
- Especially beneficial when filtering or sorting after $search

---

### Query with Synonyms

When your index is configured with synonyms, specify the synonym mapping name in your query:

```javascript
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      text: {
        query: "car chase",
        path: "description",
        synonyms: "synonym-mapping-name"  // Reference the mapping from your index
      }
    }
  }
])
```

**Note:** When you specify a synonym mapping name, MongoDB Search automatically searches for the query terms AND all their synonyms (e.g., "car" also matches "automobile", "vehicle").

---

### Using Multi Analyzers

Query specific analyzer variants of a field:

```javascript
// Standard fuzzy search
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      text: {
        query: "Action",
        path: "title"  // Uses default analyzer
      }
    }
  }
])

// Exact match using keyword analyzer
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      text: {
        query: "Action",
        path: "title.keywordAnalyzer"  // Uses alternate analyzer
      }
    }
  }
])
```

**Use case:** Support both fuzzy and exact matching on the same field without duplicating data.

---

## Query Performance Analysis

Use `explain` to analyze query performance:

```javascript
db.collection.explain("executionStats").aggregate([
  { $search: { /* ... */ } }
])
```

**Important:** Atlas Search explain output differs from standard MongoDB explain. It shows execution on the search engine (mongot) side with Lucene-specific statistics, not standard MongoDB execution plans.
