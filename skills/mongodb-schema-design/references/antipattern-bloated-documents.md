---
title: Avoid Bloated Documents
impact: CRITICAL
impactDescription: "Improves working-set efficiency by separating hot and cold fields"
tags: schema, document-size, anti-pattern, working-set, memory, atlas-suggestion
---

## Avoid Bloated Documents

**Large documents can hurt working set efficiency.** MongoDB reads full documents, even when queries only need a few fields. When frequently queried documents carry large cold fields, cache pressure increases and hot-path queries may become slower and more disk-bound.

**Incorrect (everything in one document):**

```javascript
// Product with full history and all images embedded
// Problem: 665KB loaded into RAM just to show product name and price
{
  _id: "prod123",
  name: "Laptop",           // 10 bytes - what you need
  price: 999,               // 8 bytes - what you need
  description: "...",       // 5KB - rarely needed
  fullSpecs: {...},         // 10KB - rarely needed
  images: [...],            // 500KB base64 - almost never needed
  reviews: [...],           // 100KB - paginated separately
  priceHistory: [...]       // 50KB - analytics only
}
// Total: ~665KB per product
// Large cold fields reduce how many hot-path documents fit in cache
```

Queries that touch this collection still read large documents, even when projecting a small field set such as `db.products.find({}, {name: 1, price: 1})`.

**Correct (hot data only in main document):**

```javascript
// Product - hot data only (~500 bytes)
// This is what most product-list queries actually need
{
  _id: "prod123",
  name: "Laptop",
  price: 999,
  thumbnail: "https://cdn.example.com/prod123-thumb.jpg",
  avgRating: 4.5,
  reviewCount: 127,
  inStock: true
}
// Keeping only hot fields in the main document improves cache density

// Cold data in separate collections - loaded only when needed
// products_details: { productId, description, fullSpecs }
// products_images: { productId, images: [...] }
// products_reviews: { productId, reviews: [...] }  // paginated

// Product detail page: 2 targeted queries instead of 1 large-document query
const product = await db.products.findOne({ _id })           // 0.5KB from cache
const details = await db.products_details.findOne({ productId })  // 15KB
```

Two targeted queries can outperform one oversized-document query when hot-path reads are cache constrained.

**Alternative (projection when you can't refactor):**

```javascript
// If refactoring isn't possible, always use projection
// Only loads ~500 bytes instead of 665KB
db.products.find(
  { category: "electronics" },
  { name: 1, price: 1, thumbnail: 1 }  // Project only needed fields
)
```

Projection reduces network transfer but still loads full documents into memory.
Exception: index-covered queries (where all projected fields are served directly
from the index) never load the document from WiredTiger at all. For real working
set reduction, use the Subset Pattern — projection alone cannot help WiredTiger
cache pressure for uncovered queries.

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
    avgReviews: { $avg: "$reviewsSize" }
  }}
])
// Shows which fields are bloating documents
```

Atlas Schema Suggestions flags: "Document size exceeds recommended limit"

Reference: [Reduce Bloated Documents](https://mongodb.com/docs/manual/data-modeling/design-antipatterns/bloated-documents/)
