---
title: Use Subset Pattern for Hot/Cold Data
impact: MEDIUM
impactDescription: "Improves working-set efficiency by separating frequently-read hot data from rarely-read cold data"
tags: schema, patterns, subset, hot-data, cold-data, working-set, memory
---

## Use Subset Pattern for Hot/Cold Data

**Keep frequently-accessed (hot) data in the main document, store rarely-accessed (cold) data in a separate collection.** MongoDB reads full documents, so large cold sections can reduce cache efficiency for hot-path queries.

**Incorrect (all data in one document):**

A movie document with all 10,000 reviews embedded (~1MB of cold data alongside ~1KB of hot data like title, rating, plot) means every page load pulls ~1MB into RAM. Since most page views only need title + rating + plot, this reduces how many movies fit in cache (e.g. 1GB RAM ≈ 1,000 movies instead of ~1,000,000 if only hot data were loaded).

**Correct (subset pattern):**

The movie document (~2KB) contains only hot fields: `title`, `year`, `rating`, `plot`, `reviewStats` (count, avgRating, distribution), and a bounded `featuredReviews` array (top 5 only, ~500 bytes). Full reviews live in a separate `reviews` collection with `movieId` reference, loaded only when the user clicks “Show all reviews.” This dramatically improves cache density for hot-path queries.

**Access patterns:**

Movie page load: a single `findOne` against the movies collection returns the small hot-data document, typically from cache. When the user clicks “Show all reviews,” a separate paginated query (sorted by `helpful`, with skip/limit) runs against the reviews collection.

**Maintaining the subset:**

```javascript
// When new review is added:
// 1. Insert full review into reviews collection
db.reviews.insertOne({ movieId: "movie123", user: "newUser", rating: 5, text: "Amazing!", date: new Date(), helpful: 0 })

// 2. Update movie stats
db.movies.updateOne(
  { _id: "movie123" },
  { $inc: { "reviewStats.count": 1, "reviewStats.distribution.5": 1 } }
)

// 3. Periodically refresh featured reviews (background job)
const topReviews = db.reviews.find({ movieId: "movie123" }).sort({ helpful: -1 }).limit(5).toArray()
db.movies.updateOne({ _id: "movie123" }, { $set: { featuredReviews: topReviews } })
```

**How to identify hot vs cold data:**

| Hot Data (embed) | Cold Data (separate) |
|------------------|----------------------|
| Displayed on every page load | Only on user action (click, scroll) |
| Used for filtering/sorting | Historical/archival |
| Small relative size | Large relative size |
| Bounded small subsets | Large or unbounded sets |
| Changes rarely | Changes frequently |

**When NOT to use this pattern:**

- **Small documents**: If total document is <16KB, subset pattern adds complexity without benefit.
- **Always need all data**: If 90% of requests need full reviews, separation hurts.
- **Write-heavy cold data**: If reviews are written 100× more than read, keeping them embedded may simplify writes.

## Verify with

```javascript
// Find documents with hot/cold imbalance
db.movies.aggregate([
  { $project: {
    totalSize: { $bsonSize: "$$ROOT" },
    reviewsSize: { $bsonSize: { $ifNull: ["$reviews", []] } },
    hotSize: { $subtract: [
      { $bsonSize: "$$ROOT" },
      { $bsonSize: { $ifNull: ["$reviews", []] } }
    ]}
  }},
  { $match: {
    $expr: { $gt: ["$reviewsSize", { $multiply: ["$hotSize", 10] }] }
  }},  // Example ratio threshold; tune per workload
  { $limit: 10 }
])

// Check working set efficiency
db.serverStatus().wiredTiger.cache
// "bytes currently in the cache" vs "maximum bytes configured"
// If cache pressure is high, evaluate subset split candidates
```

Reference: [Reduce Bloated Documents](https://mongodb.com/docs/manual/data-modeling/design-antipatterns/bloated-documents/)
