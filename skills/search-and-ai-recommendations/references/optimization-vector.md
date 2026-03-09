# Vector Search Optimizations

This guide covers performance optimizations specific to MongoDB Atlas Vector Search.

## Table of Contents

- [numCandidates Tuning](#numcandidates-tuning)
- [Quantization](#quantization)
- [Vector Search Filtering Options](#vector-search-filtering-options)
- [Embedding Dimensions](#embedding-dimensions)
- [Similarity Metrics](#similarity-metrics)
- [ENN vs ANN](#enn-vs-ann)

---

## numCandidates Tuning

The `numCandidates` parameter controls the trade-off between recall (finding relevant results) and performance.

**Rule of thumb:**
- `numCandidates = 10-20x limit` for good recall/performance balance
- Higher numCandidates = better recall but slower queries
- Lower numCandidates = faster queries but might miss relevant results

**Examples:**
```javascript
// Good balance for most use cases
{
  $vectorSearch: {
    queryVector: [...],
    numCandidates: 150,  // 15x the limit
    limit: 10
  }
}

// High recall (use when accuracy is critical)
{
  $vectorSearch: {
    queryVector: [...],
    numCandidates: 500,  // 50x the limit
    limit: 10
  }
}

// Fast queries (use when speed is more important)
{
  $vectorSearch: {
    queryVector: [...],
    numCandidates: 50,   // 5x the limit
    limit: 10
  }
}
```

**When to adjust:**
- **Increase** if search results seem to miss relevant documents
- **Decrease** if queries are too slow and results are already good
- Test different values with your actual data and queries

---

## Quantization

Quantization compresses vectors to reduce storage and improve query speed at the cost of some accuracy.

**Options:**

| Type | Compression | Accuracy | Use Case |
|------|-------------|----------|----------|
| `none` | 1x (no compression) | Highest | Maximum accuracy needed |
| `scalar` | 4x | High | Good balance for most cases |
| `binary` | 4-8x | Good | Large datasets, speed priority |

**Index configuration:**
```javascript
// No quantization (default)
{
  "type": "vector",
  "fields": [{
    "type": "vector",
    "path": "embedding",
    "numDimensions": 1024,
    "similarity": "cosine",
    "quantization": "none"
  }]
}

// Scalar quantization (4x compression)
{
  "type": "vector",
  "fields": [{
    "type": "vector",
    "path": "embedding",
    "numDimensions": 1024,
    "similarity": "cosine",
    "quantization": {
      "type": "scalar"
    }
  }]
}

// Binary quantization (maximum compression)
{
  "type": "vector",
  "fields": [{
    "type": "vector",
    "path": "embedding",
    "numDimensions": 1024,
    "similarity": "cosine",
    "quantization": {
      "type": "binary"
    }
  }]
}
```

**Decision guide:**
- **Use `none`** when:
  - Dataset is small (< 1M vectors)
  - Maximum accuracy is critical
  - Storage/memory is not a concern

- **Use `scalar`** when:
  - Dataset is medium-large (1M-10M+ vectors)
  - Need good balance of accuracy and performance
  - Want 4x storage savings

- **Use `binary`** when:
  - Dataset is very large (10M+ vectors)
  - Query speed is priority
  - Can tolerate slight accuracy loss
  - Need maximum compression (4-8x)

---

## Vector Search Filtering Options

There are three ways to filter vector search results, each with different performance characteristics:

### 1. Index Filter Fields (Fastest - Exact/Range Matches)

Pre-filtering with indexed filter fields happens before vector similarity computation.

**When to use:**
- Exact matching (category = "Action")
- Range matching (year >= 2020)
- Simple boolean logic ($and, $or, $in)

**Performance:** ⚡⚡⚡ Fastest - filters before computing similarity

**Example:**
```javascript
// Index configuration
{
  "type": "vector",
  "fields": [
    {
      "type": "vector",
      "path": "embedding",
      "numDimensions": 1024,
      "similarity": "cosine"
    },
    {
      "type": "filter",
      "path": "category"
    },
    {
      "type": "filter",
      "path": "year"
    }
  ]
}

// Query with filter fields
db.collection.aggregate([
  {
    $vectorSearch: {
      queryVector: [...],
      path: "embedding",
      filter: {
        $and: [
          { category: { $eq: "Electronics" } },
          { year: { $gte: 2020 } }
        ]
      }
    }
  }
])
```

### 2. Lexical Prefilters (Fast - Text Search Criteria)

Pre-filtering using full-text search before vector similarity computation.

**When to use:**
- Text search criteria ("documents that mention 'security'")
- Fuzzy text matching needed
- Complex text queries (phrase matching, wildcards)

**Performance:** ⚡⚡ Fast - filters before similarity, but text search has overhead

**Example:**
```javascript
db.collection.aggregate([
  {
    $vectorSearch: {
      queryVector: [...],
      path: "embedding",
      filter: {
        text: {
          query: "security",
          path: "description"
        }
      }
    }
  }
])
```

**Note:** Requires Atlas Search index on the text field being filtered.

### 3. Post-filtering with $match (Slowest - Maximum Flexibility)

Filtering happens after vector search computes all similarities.

**When to use:**
- Ad-hoc filters not worth indexing
- Complex aggregation logic
- Fields not in vector index
- Combining with other aggregation stages

**Performance:** ⚡ Slower - computes similarity for all candidates first

**Example:**
```javascript
db.collection.aggregate([
  {
    $vectorSearch: {
      queryVector: [...],
      path: "embedding",
      numCandidates: 150,
      limit: 50  // Get more candidates
    }
  },
  {
    $match: {
      category: "Electronics",
      year: { $gte: 2020 },
      "reviews.rating": { $gte: 4.5 }  // Complex nested field
    }
  },
  { $limit: 10 }
])
```

### Comparison Table

| Method | Speed | Use Case | Index Required |
|--------|-------|----------|----------------|
| Filter fields | ⚡⚡⚡ Fastest | Exact/range matches (category, year) | Yes - filter fields in vector index |
| Lexical prefilter | ⚡⚡ Fast | Text search criteria ("mentions X") | Yes - Atlas Search index on field |
| $match post-filter | ⚡ Slowest | Ad-hoc filters, complex logic | No |

**Recommendation:** Use filter fields for frequently-applied exact/range filters, lexical prefilters for text search requirements, and $match only for ad-hoc or complex filtering logic.

---

## Embedding Dimensions

Higher dimensions capture more semantic information but increase storage and query time.

**Common dimensions:**
- **256**: Fast queries, less storage, good for simple similarity
- **512**: Balanced for most use cases
- **1024**: Default for many models, good accuracy
- **1536**: OpenAI embeddings, high accuracy
- **2048+**: Maximum semantic capture, slower queries

**For auto-embed:**
Voyage models support multiple output dimensions via `outputDimension` parameter:
```javascript
{
  $vectorSearch: {
    query: "text query",
    path: "textField",
    embeddingParameters: {
      model: "voyage-4",
      outputDimension: 512  // 256, 512, 1024, 2048, 4096
    }
  }
}
```

**Decision guide:**
- Start with your model's default (usually 1024)
- Reduce if queries are slow and accuracy is acceptable
- Increase if semantic understanding is insufficient

---

## Similarity Metrics

Choose based on your embedding model and use case:

| Metric | Formula | Best For | Notes |
|--------|---------|----------|-------|
| `cosine` | `score = (1 + cosine) / 2` | Most embeddings, normalized vectors | Can't use zero-magnitude vectors |
| `dotProduct` | `score = (1 + dotProduct) / 2` | Fastest, angle + magnitude | Requires unit length normalization |
| `euclidean` | `score = 1 / (1 + distance)` | Spatial/geometric similarity | Only option for binary (int1) vectors |

**Recommendations:**
- **Most efficient**: Normalize vectors to unit length and use `dotProduct`
- **Most common**: `cosine` (works with most embedding models)
- **Binary quantization**: Must use `euclidean`

---

## ENN vs ANN

By default, vector search uses ANN (approximate nearest neighbor) for speed. Set `exact: true` for ENN (exact nearest neighbor).

**ENN search:**
```javascript
{
  $vectorSearch: {
    queryVector: [...],
    path: "embedding",
    exact: true,  // Exhaustive search
    limit: 10
  }
}
```

**When to use ENN:**
- Measuring accuracy baseline (ground truth)
- Collections with <10K documents
- Very selective filters (<5% of data)
- When you need guaranteed best matches

**When to use ANN:**
- Production queries (much faster)
- Large collections
- When 90-95% recall is acceptable

**Note:** ENN uses full-fidelity vectors even when quantization is enabled.
