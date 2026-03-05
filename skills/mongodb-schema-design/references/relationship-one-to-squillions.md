---
title: Model One-to-Squillions with References and Summaries
impact: HIGH
impactDescription: "Prevents unbounded arrays and keeps parent documents small and fast"
tags: schema, relationships, one-to-many, references, unbounded, scalability
---

## Model One-to-Squillions with References and Summaries

**When a parent has millions of children, store children in a separate collection.** Embed only summary fields (counts, recent items) in the parent. This avoids unbounded arrays and keeps the parent document within the 16MB limit.

**Incorrect (embed massive child arrays):**

```javascript
// User document with millions of activity entries
{
  _id: "user123",
  name: "Ada",
  activities: [
    // Unbounded array - will exceed 16MB
    { ts: ISODate("2025-01-01"), action: "login" }
  ]
}
```

**Correct (reference children + summary in parent):**

```javascript
// Parent with summary only
{
  _id: "user123",
  name: "Ada",
  activityCount: 15000000,
  recentActivities: [
    { ts: ISODate("2025-01-15"), action: "login" }
  ]
}

// Child documents in separate collection
{
  _id: ObjectId("..."),
  userId: "user123",
  ts: ISODate("2025-01-01"),
  action: "login"
}

// Index for efficient fan-out queries

db.user_activities.createIndex({ userId: 1, ts: -1 })
```

**When NOT to use this pattern:**

- **Small, bounded child sets**: Embed for simplicity and atomic reads.
- **Always-accessed-together data**: Embedding may be faster.

## Verify with

```javascript
// Ensure parent doc stays small

db.users.aggregate([
  { $project: { size: { $bsonSize: "$$ROOT" } } },
  { $match: { size: { $gt: 1000000 } } }
])

// Ensure child lookups are indexed

db.user_activities.find({ userId: "user123" }).explain("executionStats")
```

Reference: [Referenced One-to-Many Relationships](https://mongodb.com/docs/manual/tutorial/model-referenced-one-to-many-relationships-between-documents/)
