# Advanced Search Features

This guide covers specialized search operators and features for advanced use cases.

## Table of Contents

- [Advanced Query Syntax (queryString)](#advanced-query-syntax-querystring)
- [Similar Items (moreLikeThis)](#similar-items-morelikethis)
- [Searching Nested Arrays (embeddedDocument)](#searching-nested-arrays-embeddeddocument)
- [Search Highlighting](#search-highlighting)
- [Synonyms](#synonyms)

---

## Advanced Query Syntax (queryString)

**Use case:** Complex search with boolean operators, wildcards, and field-specific queries.

**Index configuration:**
```javascript
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "title": { "type": "string" },
      "director": { "type": "string" },
      "year": { "type": "number" }
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

## Similar Items (moreLikeThis)

**Use case:** "More like this" features, related content recommendations.

**Index configuration:**
```javascript
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "title": { "type": "string" },
      "plot": { "type": "string" }
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
      moreLikeThis: {
        like: [
          { title: "The Matrix", plot: "A hacker discovers reality is a simulation..." }
        ]
      }
    }
  },
  {
    $match: { _id: { $ne: originalDocId } }  // Exclude the source document
  },
  { $limit: 10 }
])

// Using compound to exclude original
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      compound: {
        must: [{
          moreLikeThis: {
            like: [{ plot: "A hacker discovers..." }]
          }
        }],
        mustNot: [{
          equals: { path: "_id", value: originalDocId }
        }]
      }
    }
  }
])
```

**How it works:**
- Extracts representative terms from input documents
- Creates an OR query from those terms
- Returns documents with similar term distributions

**Key considerations:**
- Works well for content recommendation
- Combine with filters for category-specific recommendations
- Can accept multiple input documents

---

## Searching Nested Arrays (embeddedDocument)

**Use case:** Search within arrays of objects where each element should be scored independently.

**Index configuration:**
```javascript
{
  "mappings": {
    "dynamic": false,
    "fields": {
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

---

## Search Highlighting

**Use case:** Show users which parts of documents matched their query.

**Index configuration:**
```javascript
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "title": { "type": "string" },
      "plot": { "type": "string" }
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

## Synonyms

**Use case:** Expand queries with equivalent terms (e.g., "car" → "automobile", "vehicle").

**Synonym collection setup:**
```javascript
// Create a collection for synonyms
db.synonyms.insertMany([
  {
    mappingType: "equivalent",
    synonyms: ["car", "automobile", "vehicle"]
  },
  {
    mappingType: "explicit",
    input: ["pants"],
    synonyms: ["trousers", "slacks"]
  }
])
```

**Index configuration with synonyms:**
```javascript
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "description": {
        "type": "string",
        "analyzer": "lucene.standard",
        "searchAnalyzer": "synonymAnalyzer"
      }
    }
  },
  "synonyms": [
    {
      "name": "synonymAnalyzer",
      "analyzer": "lucene.standard",
      "source": {
        "collection": "synonyms"
      }
    }
  ]
}
```

**Query (automatically applies synonyms):**
```javascript
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      text: {
        query: "car chase",  // Automatically searches: car OR automobile OR vehicle
        path: "description"
      }
    }
  }
])
```

**Mapping types:**
- `equivalent`: All terms are interchangeable
- `explicit`: Input term expands to synonym list (one-way)

**Key considerations:**
- Synonyms applied at query time
- Use `searchAnalyzer` to apply only to queries, not indexing
- Maintain synonym collection separately for easy updates
