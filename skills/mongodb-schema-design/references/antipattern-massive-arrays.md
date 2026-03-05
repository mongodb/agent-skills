---
title: Limit Array Size
impact: CRITICAL
impactDescription: "Keeps high-cardinality arrays from degrading update and index performance"
tags: schema, arrays, anti-pattern, performance, indexing, subset-pattern
---

## Limit Array Size

**Large arrays can become expensive even when bounded.** As arrays grow, document size, multikey index fan-out, and update costs can increase. This is different from unbounded arrays: a bounded array can still be too large for your workload.

**Incorrect (large embedded arrays):**

```javascript
// Blog post with all comments embedded
// Problem: frequent updates on a very large embedded array
{
  _id: "post123",
  title: "Popular Post",
  comments: [
    // 5,000 comments, each ~500 bytes = 2.5MB
    { author: "user1", text: "Great post!", ts: ISODate("...") },
    // ... 4,999 more
  ]
}

// Adding one comment grows an already large document
// If you index comments.author, index fan-out grows with array size
db.posts.updateOne(
  { _id: "post123" },
  { $push: { comments: newComment } }
)
```

**Correct (bounded array + overflow collection):**

```javascript
// Post with only recent comments (hard limit: 20)
{
  _id: "post123",
  title: "Popular Post",
  recentComments: [/* last 20 comments only, ~10KB */],
  commentCount: 5000
}

// All comments in separate collection
// Each comment is an independent document
{
  _id: ObjectId("..."),
  postId: "post123",
  author: "user1",
  text: "Great post!",
  ts: ISODate("2024-01-15")
}

// Add comment: atomic update with $slice keeps array bounded
db.posts.updateOne(
  { _id: "post123" },
  {
    $push: {
      recentComments: {
        $each: [newComment],
        $slice: -20,        // Keep only last 20
        $sort: { ts: -1 }   // Most recent first
      }
    },
    $inc: { commentCount: 1 }
  }
)
// Simultaneously insert into comments collection
db.comments.insertOne({ postId: "post123", ...newComment })
```

**Alternative ($slice without separate collection):**

```javascript
// For simpler cases where you only ever need recent items
// Keep last 100 items, discard older automatically
db.posts.updateOne(
  { _id: "post123" },
  {
    $push: {
      activityLog: {
        $each: [newActivity],
        $slice: -100  // Hard cap at 100 elements
      }
    }
  }
)
```

**Workload signals:**

| Signal | Recommendation | Rationale |
|--------|----------------|-----------|
| Array cardinality keeps growing | Cap with `$slice` or split to separate collection | Keeps document growth bounded |
| Array field is heavily indexed | Review multikey index fan-out and move cold history out | Reduces index/storage overhead |
| Hot-path reads only need recent subset | Keep recent N embedded, archive full history elsewhere | Preserves locality for common queries |
| Frequent updates become slower as array grows | Compare embedded vs referenced/write-path design | Avoids accumulating write amplification |

**When NOT to use this pattern:**

- **Write-once arrays**: If you build the array once and never modify, size matters less (still affects working set).
- **Arrays of primitives**: `tags: ["a", "b", "c"]` is much cheaper than array of objects.
- **Infrequent writes**: If array is updated once per day, 200ms writes may be acceptable.

## Verify with

```javascript
// Find documents with large arrays
db.posts.aggregate([
  { $project: {
    title: 1,
    commentsCount: { $size: { $ifNull: ["$comments", []] } }
  }},
  { $match: { commentsCount: { $gt: 100 } } }, // Example threshold; tune per workload
  { $sort: { commentsCount: -1 } },
  { $limit: 10 }
])
// Inspect high-cardinality arrays against your read/write patterns

// Check multikey index size vs document count
db.posts.stats().indexSizes
// Large array-index footprint can signal fan-out pressure

// Profile write times for array updates
db.setProfilingLevel(1, { slowms: 100 })
// Then check db.system.profile for slow $push operations
```

Reference: [Building with Patterns - Subset Pattern](https://mongodb.com/blog/post/building-with-patterns-the-subset-pattern)
