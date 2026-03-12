# Common Search Patterns

This guide provides index configurations and query patterns for the most frequently used search features.

## Table of Contents

- [Autocomplete / Search-as-you-type](#autocomplete--search-as-you-type)
- [Faceted Search](#faceted-search)
- [Paginated Results](#paginated-results)
- [Fuzzy Search (Typo Tolerance)](#fuzzy-search-typo-tolerance)
- [Relevance-Based Search](#relevance-based-search)
- [Filters](#filters)
- [Analytics (Counts and Aggregations)](#analytics-counts-and-aggregations)

---

## Autocomplete / Search-as-you-type

**Use case:** Users typing in a search bar should see suggestions as they type.

**Index configuration:**
```javascript
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "title": {
        "type": "autocomplete",
        "tokenization": "edgeGram",
        "minGrams": 3,
        "maxGrams": 15,
        "foldDiacritics": true
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
      index: "autocomplete_index",
      autocomplete: {
        query: "sta",  // User typed "sta"
        path: "title",
        tokenOrder: "sequential",  // Matches word order
        fuzzy: {
          maxEdits: 1  // Allow 1 typo
        }
      }
    }
  },
  { $limit: 10 },
  { $project: { title: 1, _id: 0 } }
])
```

**Key considerations:**
- `minGrams: 3` means indexing starts at 3 characters (prevents indexing very short strings)
- `tokenOrder: "sequential"` ensures "star wars" matches but "wars star" doesn't
- Use `tokenOrder: "any"` for more flexible matching

---

## Faceted Search

**Use case:** Filter search results by categories, price ranges, dates, etc., with counts for each facet.

**Index configuration:**
```javascript
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "description": {
        "type": "string",
        "analyzer": "lucene.standard"
      },
      "genre": {
        "type": "string",
        "analyzer": "lucene.keyword"  // Exact matching for facets
      },
      "year": {
        "type": "number"
      },
      "rating": {
        "type": "number"
      }
    }
  }
}
```

**Query pattern:**
```javascript
db.collection.aggregate([
  {
    $searchMeta: {
      index: "search_index",
      facet: {
        operator: {
          text: {
            query: "action",
            path: "description"
          }
        },
        facets: {
          genreFacet: {
            type: "string",
            path: "genre"
          },
          yearFacet: {
            type: "number",
            path: "year",
            boundaries: [1990, 2000, 2010, 2020, 2030]
          },
          ratingFacet: {
            type: "number",
            path: "rating",
            boundaries: [0, 5, 7, 9, 10]
          }
        }
      }
    }
  }
])
```

**Result structure:**
```javascript
{
  "count": { "lowerBound": 42 },
  "facet": {
    "genreFacet": {
      "buckets": [
        { "_id": "Action", "count": 15 },
        { "_id": "Thriller", "count": 8 }
      ]
    },
    "yearFacet": {
      "buckets": [
        { "_id": 1990, "count": 5 },
        { "_id": 2000, "count": 12 }
      ]
    }
  }
}
```

**Key considerations:**
- Use `$searchMeta` to get only facet counts (no documents) - more efficient
- Use `$search` with facets if you need both results and counts in one query
- Use `lucene.keyword` analyzer for exact category matching

---

## Paginated Results

**Use case:** Display search results across multiple pages efficiently.

**Query pattern:**
```javascript
// Page 1
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      text: {
        query: "detective",
        path: "plot"
      }
    }
  },
  { $skip: 0 },
  { $limit: 20 },
  {
    $project: {
      title: 1,
      plot: 1,
      score: { $meta: "searchScore" }
    }
  }
])

// Page 2
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      text: {
        query: "detective",
        path: "plot"
      }
    }
  },
  { $skip: 20 },  // pageNumber * pageSize
  { $limit: 20 },
  {
    $project: {
      title: 1,
      plot: 1,
      score: { $meta: "searchScore" }
    }
  }
])
```

**For total count (use $searchMeta):**
```javascript
db.collection.aggregate([
  {
    $searchMeta: {
      index: "search_index",
      text: {
        query: "detective",
        path: "plot"
      },
      count: { type: "total" }
    }
  }
])
```

**Note:** `$searchMeta` returns only metadata (counts, facets) without documents - more efficient than `$search` when you only need counts.

**Key considerations:**
- Use `$searchMeta` with `count: { type: "total" }` for accurate total counts
- For vector search pagination, keep `numCandidates` consistent across pages
- Consider caching counts for performance

---

## Fuzzy Search (Typo Tolerance)

**Use case:** Handle misspellings and typos in user queries.

**Index configuration:**
```javascript
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "title": {
        "type": "string",
        "analyzer": "lucene.standard"
      },
      "description": {
        "type": "string",
        "analyzer": "lucene.standard"
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
      text: {
        query: "detectiv",  // User meant "detective"
        path: ["title", "description"],
        fuzzy: {
          maxEdits: 2,        // Maximum Levenshtein distance (1 or 2)
          prefixLength: 0,    // No prefix required to match exactly
          maxExpansions: 50   // Max number of variations to try
        }
      }
    }
  },
  { $limit: 10 }
])
```

**Fuzzy parameters:**
- `maxEdits: 1` - Allows 1 character difference (good for small typos)
- `maxEdits: 2` - Allows 2 character differences (more lenient)
- `prefixLength: 3` - First 3 characters must match exactly (improves performance)
- `maxExpansions: 50` - Limits internal query expansion (performance vs recall trade-off)

**Key considerations:**
- `maxEdits: 2` is usually sufficient for most typos
- Use `prefixLength` to improve performance for long queries
- Combine with relevance scoring to rank exact matches higher

---

## Relevance-Based Search

**Use case:** Rank results by relevance, boosting certain fields or recency.

**Index configuration:**
```javascript
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "title": {
        "type": "string",
        "analyzer": "lucene.standard"
      },
      "description": {
        "type": "string",
        "analyzer": "lucene.standard"
      },
      "popularity": {
        "type": "number"
      },
      "releaseDate": {
        "type": "date"
      }
    }
  }
}
```

**Query pattern with boosting:**
```javascript
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      compound: {
        should: [
          {
            text: {
              query: "space adventure",
              path: "title",
              score: { boost: { value: 3 } }  // Title matches worth 3x
            }
          },
          {
            text: {
              query: "space adventure",
              path: "description",
              score: { boost: { value: 1 } }  // Description matches worth 1x
            }
          },
          {
            near: {
              path: "releaseDate",
              origin: new Date(),
              pivot: 31536000000,  // 1 year in milliseconds
              score: { boost: { value: 2 } }
            }
          }
        ],
        score: {
          function: {
            multiply: [
              { $meta: "searchScore" },
              { path: { value: "popularity" } }
            ]
          }
        }
      }
    }
  },
  {
    $project: {
      title: 1,
      description: 1,
      popularity: 1,
      releaseDate: 1,
      score: { $meta: "searchScore" }
    }
  }
])
```

**Key considerations:**
- Boost important fields (title > description)
- Use `compound.should` for multiple scoring signals
- Multiply search score by business metrics (popularity, ratings)
- Use `near` operator for recency decay

---

## Filters

**Use case:** Filter results by exact values, ranges, or combinations.

**Index configuration:**
```javascript
{
  "mappings": {
    "dynamic": false,
    "fields": {
      "plot": {
        "type": "string",
        "analyzer": "lucene.standard"
      },
      "genre": {
        "type": "string",
        "analyzer": "lucene.keyword"
      },
      "year": {
        "type": "number"
      },
      "rating": {
        "type": "number"
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
      compound: {
        must: [
          {
            text: {
              query: "detective",
              path: "plot"
            }
          }
        ],
        filter: [
          {
            text: {
              query: ["Action", "Thriller"],
              path: "genre"
            }
          },
          {
            range: {
              path: "year",
              gte: 2000,
              lte: 2020
            }
          },
          {
            range: {
              path: "rating",
              gte: 7
            }
          }
        ]
      }
    }
  }
])
```

**Key considerations:**
- Use `compound.filter` for criteria that don't affect scoring
- Use `compound.must` for criteria that should affect scoring
- Filters are faster than `$match` after `$search`
- For vector search, use index filter fields for pre-filtering

---

## Analytics (Counts and Aggregations)

**Use case:** Count documents by category, analyze search patterns.

**Query pattern for counts:**
```javascript
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      text: {
        query: "detective",
        path: "plot"
      }
    }
  },
  {
    $group: {
      _id: "$genre",
      count: { $sum: 1 },
      avgRating: { $avg: "$rating" }
    }
  },
  { $sort: { count: -1 } }
])
```

**With facets:**
```javascript
db.collection.aggregate([
  {
    $search: {
      index: "search_index",
      text: {
        query: "detective",
        path: "plot"
      }
    }
  },
  {
    $facet: {
      genres: [
        { $group: { _id: "$genre", count: { $sum: 1 } } },
        { $sort: { count: -1 } }
      ],
      decades: [
        {
          $bucket: {
            groupBy: "$year",
            boundaries: [1980, 1990, 2000, 2010, 2020, 2030],
            default: "Other",
            output: { count: { $sum: 1 } }
          }
        }
      ],
      results: [
        { $limit: 20 },
        { $project: { title: 1, genre: 1, year: 1 } }
      ]
    }
  }
])
```

**Key considerations:**
- Use `$facet` to get multiple aggregations in one query
- Combine `$search` with standard aggregation stages
- Use `$bucket` for range-based grouping
