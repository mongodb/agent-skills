---
title: Model One-to-Squillions with References and Summaries
impact: HIGH
impactDescription: "Prevents unbounded arrays and keeps parent documents small and fast"
tags: schema, relationships, one-to-many, references, unbounded, scalability
---

## Model One-to-Squillions with References and Summaries

**When a parent has millions of children, store children in a separate collection.** Embed only summary fields (counts, recent items) in the parent. This avoids unbounded arrays and keeps the parent document within the 16MB limit.

**Incorrect (embed massive child arrays):**

Embedding millions of activity entries directly in the user document creates an unbounded array that will exceed the 16MB BSON limit.

**Correct (reference children + summary in parent):**

Keep the parent document small with only summary fields: `activityCount` and a bounded `recentActivities` array. Store individual activity documents in a separate collection with a `userId` reference. Create a compound index `{ userId: 1, ts: -1 }` for efficient fan-out queries.

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
