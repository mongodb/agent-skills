---
title: Reduce Excessive $lookup Usage
impact: CRITICAL
impactDescription: "Can reduce query cost on hot paths by avoiding repeated cross-collection joins"
tags: schema, lookup, anti-pattern, joins, denormalization, atlas-suggestion
---

## Reduce Excessive $lookup Usage

**Frequent $lookup operations on hot paths can indicate over-normalization.** `$lookup` is useful, but repeated joins can be slower and more resource-intensive than querying a single collection, especially when supporting indexes or match selectivity are weak. If the same related fields are read together often, consider embedding or extended references.

**Incorrect (constant $lookup for common operations):**

```javascript
// Every product page requires repeated joins across collections
db.products.aggregate([
  { $match: { _id: productId } },
  { $lookup: {
      from: "categories",          // Collection scan #2
      localField: "categoryId",
      foreignField: "_id",
      as: "category"
  }},
  { $lookup: {
      from: "brands",              // Collection scan #3
      localField: "brandId",
      foreignField: "_id",
      as: "brand"
  }},
  { $unwind: "$category" },
  { $unwind: "$brand" }
])
// Multiple join stages add planning/execution overhead on hot paths
```

Join cost depends on cardinality, stage order, index support, and result size. Measure before deciding to embed.

**Correct (denormalize frequently-joined data):**

```javascript
// Embed data that's always displayed with product
{
  _id: "prod123",
  name: "Laptop Pro",
  price: 1299,
  // Denormalized from categories collection
  category: {
    _id: "cat-electronics",
    name: "Electronics",
    path: "Electronics > Computers > Laptops"
  },
  // Denormalized from brands collection
  brand: {
    _id: "brand-acme",
    name: "Acme Corp",
    logo: "https://cdn.example.com/acme.png"
  }
}

// Single indexed query, no $lookup needed
db.products.findOne({ _id: "prod123" })
// Or listing: one query against a single collection
db.products.find({ "category._id": "cat-electronics" }).limit(50)
```

**Managing denormalized data updates:**

```javascript
// When category name changes (rare), update all products
// Use bulkWrite for efficiency on large updates
db.products.updateMany(
  { "category._id": "cat-electronics" },
  { $set: {
    "category.name": "Consumer Electronics",
    "category.path": "Consumer Electronics > Computers > Laptops"
  }}
)

// For frequently-changing data, keep reference + cache summary
{
  _id: "prod123",
  brandId: "brand-acme",          // Reference for updates
  brandCache: {                    // Denormalized for reads
    name: "Acme Corp",
    cachedAt: ISODate("...")
  }
}
```

**Alternative ($lookup with index for rare joins):**

```javascript
// When you must $lookup, ensure foreign field is indexed
db.categories.createIndex({ _id: 1 })  // Already exists
db.brands.createIndex({ _id: 1 })       // Already exists

// For non-_id lookups, create explicit index
db.reviews.createIndex({ productId: 1 })  // Critical for $lookup

// Use pipeline $lookup for filtered joins
db.products.aggregate([
  { $match: { _id: productId } },
  { $lookup: {
      from: "reviews",
      let: { pid: "$_id" },
      pipeline: [
        { $match: { $expr: { $eq: ["$productId", "$$pid"] } } },
        { $sort: { rating: -1 } },
        { $limit: 5 }  // Only top 5 reviews
      ],
      as: "topReviews"
  }}
])
```

**When NOT to use this pattern:**

- **Data changes frequently and independently**: If brand logos change daily, denormalization creates update overhead.
- **Rarely-accessed data**: Don't embed review details if only a small fraction of product views load reviews.
- **Many-to-many with high cardinality**: Avoid embedding large or fast-growing relationship sets.
- **Analytics queries**: Batch jobs can afford $lookup latency; real-time queries cannot.

## Verify with

```javascript
// Find pipelines with multiple $lookup stages
// Check slow query log for aggregations
db.setProfilingLevel(1, { slowms: 50 })
db.system.profile.find({
  "command.aggregate": { $exists: true },
  "command.pipeline": {
    $elemMatch: { "$lookup": { $exists: true } }
  }
}).sort({ millis: -1 })

// Check if $lookup foreign fields are indexed
db.reviews.aggregate([
  { $indexStats: {} }
])
// Look for "productId_1" with high ops - good
// Missing index = every $lookup is a collection scan

// Measure $lookup impact
db.products.aggregate([
  { $match: { category: "electronics" } },
  { $lookup: { from: "brands", localField: "brandId", foreignField: "_id", as: "brand" } }
]).explain("executionStats")
// Check totalDocsExamined in $lookup stage
```

Atlas Schema Suggestions flags: "Reduce $lookup operations"

Reference: [Reduce Lookup Operations](https://mongodb.com/docs/manual/data-modeling/design-antipatterns/reduce-lookup-operations/)
