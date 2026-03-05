---
title: Use Computed Pattern for Expensive Calculations
impact: MEDIUM
impactDescription: "Improves read latency by pre-computing frequently-requested aggregations"
tags: schema, patterns, computed, aggregation, performance, denormalization
---

## Use Computed Pattern for Expensive Calculations

**Pre-calculate and store frequently-accessed computed values.** If you're running the same aggregation on every page load, you're wasting CPU cycles. Store the result in the document and update it on write or via background job—trades write complexity for read speed.

**Incorrect (calculate on every read):**

```javascript
// Movie with all screenings in separate collection
{ _id: "movie1", title: "The Matrix" }

// Screenings collection - thousands of records
{ movieId: "movie1", date: ISODate("..."), viewers: 344, revenue: 3440 }
{ movieId: "movie1", date: ISODate("..."), viewers: 256, revenue: 2560 }
// ... 10,000 screenings

// Movie page aggregates every time
db.screenings.aggregate([
  { $match: { movieId: "movie1" } },
  { $group: {
    _id: "$movieId",
    totalViewers: { $sum: "$viewers" },
    totalRevenue: { $sum: "$revenue" },
    screeningCount: { $sum: 1 }
  }}
])
// Repeated scans can add substantial read latency and CPU overhead
// 1M page views/day = 1M expensive aggregations
```

**Correct (pre-computed values):**

```javascript
// Movie with computed stats stored directly
{
  _id: "movie1",
  title: "The Matrix",
  stats: {
    totalViewers: 1840000,
    totalRevenue: 25880000,
    screeningCount: 8500,
    avgViewersPerScreening: 216,
    computedAt: ISODate("2024-01-15T00:00:00Z")
  }
}

// Movie page: instant read, no aggregation
db.movies.findOne({ _id: "movie1" })
// Single-document read on the hot path
```

**Update strategies:**

```javascript
// Strategy 1: Update on write (low write volume)
// When new screening is added
db.screenings.insertOne({
  movieId: "movie1",
  viewers: 400,
  revenue: 4000
})

// Immediately update computed values
db.movies.updateOne(
  { _id: "movie1" },
  {
    $inc: {
      "stats.totalViewers": 400,
      "stats.totalRevenue": 4000,
      "stats.screeningCount": 1
    },
    $set: { "stats.computedAt": new Date() }
  }
)

// Strategy 2: Background job (high write volume)
// Run hourly/daily aggregation job
db.screenings.aggregate([
  { $group: {
    _id: "$movieId",
    totalViewers: { $sum: "$viewers" },
    totalRevenue: { $sum: "$revenue" },
    count: { $sum: 1 }
  }},
  { $merge: {
    into: "movies",
    on: "_id",
    whenMatched: [{
      $set: {
        "stats.totalViewers": "$$new.totalViewers",
        "stats.totalRevenue": "$$new.totalRevenue",
        "stats.screeningCount": "$$new.count",
        "stats.computedAt": new Date()
      }
    }]
  }}
])
```

**Common computed values:**

| Source Data | Computed Value | Update Strategy |
|-------------|----------------|-----------------|
| Order line items | Order total | On write (single doc) |
| Product reviews | Avg rating, review count | Background job |
| User activity | Engagement score | Background job |
| Transaction history | Account balance | On write |
| Page views | View count, trending score | Batched updates |

**Handling staleness:**

```javascript
// Include timestamp for freshness checks
{
  _id: "movie1",
  stats: {
    totalViewers: 1840000,
    computedAt: ISODate("2024-01-15T00:00:00Z")
  }
}

// Application can check freshness
if (movie.stats.computedAt < oneHourAgo) {
  // Refresh computed values
  await refreshMovieStats(movie._id)
}

// Or show "as of" timestamp to users
// "1,840,000 viewers (updated 1 hour ago)"
```

**Windowed computations:**

```javascript
// Compute for time windows (rolling 30 days)
{
  _id: "movie1",
  stats: {
    allTime: { viewers: 1840000, revenue: 25880000 },
    last30Days: { viewers: 45000, revenue: 630000 },
    last7Days: { viewers: 12000, revenue: 168000 }
  }
}

// Background job updates rolling windows
db.screenings.aggregate([
  { $match: {
    movieId: "movie1",
    date: { $gte: thirtyDaysAgo }
  }},
  { $group: {
    _id: null,
    viewers: { $sum: "$viewers" },
    revenue: { $sum: "$revenue" }
  }}
])
// Then update movie.stats.last30Days
```

**When NOT to use this pattern:**

- **Rarely accessed calculations**: If stat is viewed once/day, compute on demand.
- **High write frequency**: If source data changes every second, update overhead may exceed read savings.
- **Complex multi-collection joins**: Some computations are too complex to maintain incrementally.
- **Strong consistency required**: Computed values may be slightly stale.

## Verify with

```javascript
// Find expensive aggregations that should be pre-computed
db.setProfilingLevel(1, { slowms: 100 })
db.system.profile.find({
  "command.aggregate": { $exists: true },
  millis: { $gt: 100 }
}).sort({ millis: -1 })

// Check if same aggregation runs repeatedly
db.system.profile.aggregate([
  { $match: { "command.aggregate": { $exists: true } } },
  { $group: {
    _id: "$command.pipeline",
    count: { $sum: 1 },
    avgMs: { $avg: "$millis" }
  }},
  { $match: { count: { $gt: 100 } } }  // Repeated 100+ times
])
// High count + high avgMs = candidate for computed pattern
```

Reference: [Computed Schema Pattern](https://mongodb.com/docs/manual/data-modeling/design-patterns/computed-values/computed-schema-pattern/)
