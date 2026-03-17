---
title: Avoid Bloated Documents
impact: CRITICAL
impactDescription: "Improves working-set efficiency by separating hot and cold fields"
tags: schema, document-size, anti-pattern, working-set, memory, atlas-suggestion
---

## Avoid Bloated Documents

**Large documents can hurt working set efficiency.** MongoDB reads full documents, even when queries only need a few fields. When frequently queried documents carry large cold fields, cache pressure increases and hot-path queries may become slower and more disk-bound.

**Incorrect (everything in one document):**

A product document that includes all fields — name and price (~18 bytes, frequently needed) alongside description (~5KB), full specs (~10KB), base64 images (~500KB), reviews (~100KB), and price history (~50KB) — can reach ~665KB. Hot-path queries that only need a few small fields still load the entire document into cache, reducing working-set density. Even projecting a small field set (e.g. `db.products.find({}, {name: 1, price: 1})`) still reads the full document from storage.

**Correct (hot data only in main document):**

Keep only hot fields in the main document (~500 bytes): name, price, thumbnail URL, avgRating, reviewCount, inStock. Move cold data to separate collections — `products_details` (description, fullSpecs), `products_images` (images array), `products_reviews` (paginated reviews). A product detail page then issues two targeted queries instead of one oversized read: the hot-data document from cache plus a cold-data read on demand. Two small queries can outperform one oversized-document query when hot-path reads are cache constrained.

**Alternative (projection when you can't refactor):**

```javascript
// If refactoring isn't possible, always use projection
// Only loads ~500 bytes instead of 665KB
db.products.find(
  { category: "electronics" },
  { name: 1, price: 1, thumbnail: 1 }  // Project only needed fields
)
```

Projection reduces network transfer but still loads full documents into memory unless the query is fully covered by an index. For real working set reduction, use the Subset Pattern.

**When NOT to use this pattern:**

- **Small collections that fit in RAM**: If your entire collection is <1GB, document size matters less.
- **Always need all data**: If every access pattern truly needs the full document, splitting adds overhead.
- **Write-heavy with rare reads**: If you write once and rarely read, optimize for write simplicity.

## Verify with

```javascript
// Find your largest documents
db.products.aggregate([
  { $project: {
    size: { $bsonSize: "$$ROOT" },
    name: 1
  }},
  { $sort: { size: -1 } },
  { $limit: 10 }
])
// Investigate large documents in hot-path collections as split candidates

// Check working set vs RAM
db.serverStatus().wiredTiger.cache
// "bytes currently in the cache" vs "maximum bytes configured"
// Example alert threshold: sustained cache usage > 80% of max (tune per workload)

// Analyze field sizes
db.products.aggregate([
  { $project: {
    total: { $bsonSize: "$$ROOT" },
    imagesSize: { $bsonSize: { $ifNull: ["$images", {}] } },
    reviewsSize: { $bsonSize: { $ifNull: ["$reviews", {}] } }
  }},
  { $group: {
    _id: null,
    avgTotal: { $avg: "$total" },
    avgImages: { $avg: "$imagesSize" },
    avgReviews: { $avg: "$reviewsSize" },
    maxImages: { $max: "$imagesSize" },
    maxReviews: { $max: "$reviewsSize" }
  }}
])
// Shows which fields are bloating documents
```

Atlas Schema Suggestions flags: "Document size exceeds recommended limit"

Reference: [Reduce Bloated Documents](https://mongodb.com/docs/manual/data-modeling/design-antipatterns/bloated-documents/)
