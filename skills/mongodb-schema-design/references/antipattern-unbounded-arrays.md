---
title: Avoid Large and Unbounded Arrays
impact: CRITICAL
impactDescription: "Prevents unbounded growth toward the 16MB limit and keeps update/index costs under control"
tags: schema, arrays, anti-pattern, document-size, atlas-suggestion, 16mb-limit, performance, indexing, subset-pattern
---

## Avoid Large and Unbounded Arrays

**Arrays that grow without limit risk the 16MB BSON size limit. Arrays that are large—even if bounded—can degrade update performance, multikey index fan-out, and working-set efficiency.** Both scenarios benefit from moving data into a separate collection.

**Incorrect (array grows forever):**

An `activityLog` array that receives a new entry on every user action can reach 100,000+ entries in a year (~15MB at ~150 bytes each). Writes are eventually rejected when the document exceeds 16MB.

**Also incorrect (large bounded array):**

Even a bounded comments array (e.g. 5,000 items × ~500 bytes = 2.5MB) is expensive: each `$push` rewrites the growing document, and a multikey index on an array field fans out to one index entry per element per document.

**Correct (separate collection with reference):**

Keep the parent document small (e.g. `{ _id: "user123", name: "Alice", lastActivity: ISODate(...) }`). Store children in their own collection with a reference field (`userId`). Create a compound index `{ userId: 1, ts: -1 }` for efficient queries like fetching the most recent 10 activities for a user.

**Alternative (bounded subset + overflow):**

```javascript
// Keep only the recent N embedded; full history in separate collection
{
  _id: "post123",
  title: "Popular Post",
  recentComments: [/* last 20 only */],
  commentCount: 5000
}

// Atomic $slice keeps the embedded array bounded
db.posts.updateOne(
  { _id: "post123" },
  {
    $push: {
      recentComments: {
        $each: [newComment],
        $slice: -20,
        $sort: { ts: -1 }
      }
    },
    $inc: { commentCount: 1 }
  }
)
// Also insert into overflow comments collection
db.comments.insertOne({ postId: "post123", ...newComment })
```

**Workload signals:**

| Signal | Action |
|--------|--------|
| Array cardinality keeps growing | Cap with `$slice` or move to separate collection |
| Array field is heavily indexed | Review multikey fan-out; move cold data out |
| Reads only need recent subset | Embed recent N, reference full history |
| Updates slow as array grows | Switch to referenced write path |

**When NOT to use this pattern:**

- **Small, bounded arrays**: Tags (max 20), roles (max 5), addresses (max 10)—embedding with a hard limit is fine.
- **Write-once arrays**: Built once and never modified—size matters less (still affects working set).
- **Arrays of primitives**: `tags: ["a", "b", "c"]` is much cheaper than arrays of objects.

## Verify with

```javascript
// Find documents with large arrays
db.collection.aggregate([
  { $project: {
    size: { $bsonSize: "$$ROOT" },
    arrayLen: { $size: { $ifNull: ["$myArray", []] } }
  }},
  { $match: { arrayLen: { $gt: 100 } } },
  { $sort: { arrayLen: -1 } },
  { $limit: 10 }
])
// Investigate documents where array cardinality continues to increase over time
```

Atlas Schema Suggestions flags: "Array field may grow without bound"

Reference: [Avoid Unbounded Arrays](https://mongodb.com/docs/manual/data-modeling/design-antipatterns/unbounded-arrays/)
