---
title: Avoid Unbounded Arrays
impact: CRITICAL
impactDescription: "Prevents unbounded growth that risks the 16MB limit and degrades update/index behavior"
tags: schema, arrays, anti-pattern, document-size, atlas-suggestion, 16mb-limit
---

## Avoid Unbounded Arrays

**Unbounded arrays are a common schema anti-pattern.** When arrays grow indefinitely, documents can approach the 16MB BSON size limit. Before that point, growing arrays can strain memory and index performance and make updates more expensive.

**Incorrect (array grows forever):**

```javascript
// User document with unbounded activity log
// Problem: After 1 year, this array has 100,000+ entries
// Impact: Document grows toward BSON size limit and becomes expensive to maintain
{
  _id: "user123",
  name: "Alice",
  activityLog: [
    { action: "login", ts: ISODate("2024-01-01") },
    { action: "purchase", ts: ISODate("2024-01-02") },
    // ... grows to 100,000+ entries over time
    // Each entry ~150 bytes × 100,000 = 15MB
  ]
}
```

As this document grows, updates and indexes can become increasingly expensive. When an update would push the document past 16MB, that write is rejected until the data model is corrected.

**Correct (separate collection with reference):**

```javascript
// User document (bounded, ~200 bytes)
{ _id: "user123", name: "Alice", lastActivity: ISODate("2024-01-02") }

// Activity in separate collection (one document per event)
// Each document is written independently, keeping the parent document bounded
{ userId: "user123", action: "login", ts: ISODate("2024-01-01") }
{ userId: "user123", action: "purchase", ts: ISODate("2024-01-02") }

// Query recent activity with index on {userId, ts}
db.activities.find({ userId: "user123" }).sort({ ts: -1 }).limit(10)
```

Each activity is an independent document. This keeps parent documents small and avoids unbounded growth on a single record.

**Alternative (bucket pattern for time-series):**

```javascript
// Activity bucket - one document per user per day
// Bounded to ~24 hours of activity, typically <100 entries
{
  userId: "user123",
  date: ISODate("2024-01-01"),
  activities: [
    { action: "login", ts: ISODate("2024-01-01T09:00:00Z") },
    { action: "purchase", ts: ISODate("2024-01-01T14:30:00Z") }
  ],
  count: 2  // Denormalized for efficient queries
}

// Query: find today's activity
db.activityBuckets.findOne({
  userId: "user123",
  date: ISODate("2024-01-01")
})
```

Bucketing can reduce document count while keeping arrays bounded by a time window.

**When NOT to use this pattern:**

- **Truly bounded arrays are fine**: Tags (max 20), roles (max 5), shipping addresses (max 10). If you can enforce a hard limit, embedding is appropriate.
- **Low-volume applications**: If a user generates <100 events total lifetime, an embedded array may be simpler than a separate collection.
- **Read-heavy with rare writes**: If you read the full array constantly but rarely add to it, embedding avoids $lookup overhead.

## Verify with

```javascript
// Check document sizes in collection
db.users.aggregate([
  { $project: {
    size: { $bsonSize: "$$ROOT" },
    arrayLength: { $size: { $ifNull: ["$activityLog", []] } }
  }},
  { $sort: { size: -1 } },
  { $limit: 10 }
])
// Example alert thresholds (tune per workload): size > 1MB or arrayLength > 1000

// Check for arrays that could grow unbounded
db.users.aggregate([
  { $match: { "activityLog.999": { $exists: true } } }, // Example cardinality checkpoint
  { $count: "documentsWithLargeArrays" }
])
// Investigate documents where cardinality continues to increase over time
```

Atlas Schema Suggestions flags: "Array field 'activityLog' may grow without bound"

Reference: [Avoid Unbounded Arrays](https://mongodb.com/docs/manual/data-modeling/design-antipatterns/unbounded-arrays/)
