---
title: Use Subset Pattern for Hot/Cold Data
impact: MEDIUM
impactDescription: "Improves working-set efficiency by separating frequently-read hot data from rarely-read cold data"
tags: schema, patterns, subset, hot-data, cold-data, working-set, memory
---

## Use Subset Pattern for Hot/Cold Data

**Keep frequently-accessed (hot) data in the main document, store rarely-accessed (cold) data in a separate collection.** MongoDB reads full documents, so large cold sections can reduce cache efficiency for hot-path queries.

**Incorrect (all data in one document):**

```javascript
// Movie with ALL reviews embedded
// Hot data: title, rating, plot (~1KB)
// Cold data: 10,000 reviews (~1MB)
{
  _id: "movie123",
  title: "The Matrix",
  year: 1999,
  rating: 8.7,
  plot: "A computer hacker learns about the true nature...",
  reviews: [
    // 10,000 reviews × 100 bytes each = 1MB cold data
    { user: "critic1", rating: 5, text: "Masterpiece...", date: "..." },
    { user: "user42", rating: 4, text: "Great effects...", date: "..." },
    // ... 9,998 more reviews, 95% never read
  ]
}

// Every movie page load pulls 1MB into RAM
// 1GB RAM = 1,000 movies cached
// Most page views only need title + rating + plot
```

**Correct (subset pattern):**

```javascript
// Movie with only hot data (~2KB)
{
  _id: "movie123",
  title: "The Matrix",
  year: 1999,
  rating: 8.7,
  plot: "A computer hacker learns about the true nature...",
  // Summary stats - no full reviews
  reviewStats: {
    count: 10000,
    avgRating: 4.2,
    distribution: { 5: 4000, 4: 3000, 3: 2000, 2: 700, 1: 300 }
  },
  // Only top 5 featured reviews (~500 bytes)
  featuredReviews: [
    { user: "critic1", rating: 5, text: "Masterpiece", featured: true },
    { user: "critic2", rating: 5, text: "Revolutionary", featured: true }
  ]
}
// Depending on size reduction, significantly more hot-path documents may fit in cache

// Cold data: Full reviews in separate collection
{
  _id: ObjectId("..."),
  movieId: "movie123",
  user: "user456",
  rating: 4,
  text: "Great visual effects and deep storyline...",
  date: ISODate("2024-01-15"),
  helpful: 42
}
// Only loaded when user clicks "Show all reviews"
```

**Access patterns:**

```javascript
// Movie page load: single query, small document, likely cached
const movie = db.movies.findOne({ _id: "movie123" })
// Hot-path query is typically faster and more cache-friendly

// User clicks "Show all reviews": separate query, paginated
const reviews = db.reviews
  .find({ movieId: "movie123" })
  .sort({ helpful: -1 })
  .skip(0)
  .limit(20)
// Cold-path query is loaded separately and can be paginated
```

**Maintaining the subset:**

```javascript
// When new review is added
// 1. Insert full review into reviews collection
db.reviews.insertOne({
  movieId: "movie123",
  user: "newUser",
  rating: 5,
  text: "Amazing!",
  date: new Date(),
  helpful: 0
})

// 2. Update movie stats and maybe featured reviews
db.movies.updateOne(
  { _id: "movie123" },
  {
    $inc: { "reviewStats.count": 1, "reviewStats.distribution.5": 1 },
    // Recalculate avgRating
    $set: { "reviewStats.avgRating": newAvg }
  }
)

// 3. Periodically refresh featured reviews (background job)
const topReviews = db.reviews
  .find({ movieId: "movie123" })
  .sort({ helpful: -1 })
  .limit(5)
  .toArray()

db.movies.updateOne(
  { _id: "movie123" },
  { $set: { featuredReviews: topReviews } }
)
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

Reference: [Building with Patterns - Subset Pattern](https://mongodb.com/blog/post/building-with-patterns-the-subset-pattern)
