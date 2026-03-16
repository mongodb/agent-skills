---
title: Respect the 16MB Document Limit
impact: CRITICAL
impactDescription: "Hard BSON limit; oversized documents fail writes and force schema refactoring"
tags: schema, fundamentals, document-size, 16mb, bson-limit, atlas-suggestion
---

## Respect the 16MB Document Limit

**MongoDB documents cannot exceed 16 megabytes (16,777,216 bytes).** This is a hard BSON limit, not a guideline. When documents approach the limit, writes can fail and schema refactoring becomes urgent.

**How documents hit 16MB:**

Three common scenarios push documents toward the 16MB BSON limit:

1. **Unbounded arrays** — e.g. an `activityLog` array with 100,000 events × ~150 bytes = ~15MB, growing until writes are rejected.
2. **Large embedded binary** — e.g. a `BinData` PDF attachment of 10MB+; additional attachments push the document past the limit.
3. **Deeply nested objects** — e.g. a configuration document with 100+ nesting levels where metadata and keys alone approach 16MB.

**Correct (design for size constraints):**

Instead of unbounded arrays, use a separate collection. Keep the parent document small (e.g. user with `activityCount` and `lastActivity` fields only). Store individual activity entries in their own collection with a reference field (`userId`). For large binary data, use GridFS or external object storage instead of embedding.

**Size estimation:**

```javascript
// Check current document size
db.users.aggregate([
  { $match: { _id: "user1" } },
  { $project: { size: { $bsonSize: "$$ROOT" } } }
])

// Find largest documents in collection
db.users.aggregate([
  { $project: { size: { $bsonSize: "$$ROOT" } } },
  { $sort: { size: -1 } },
  { $limit: 10 }
])

// Size of specific fields
db.users.aggregate([
  { $project: {
    total: { $bsonSize: "$$ROOT" },
    activitySize: { $bsonSize: { $ifNull: ["$activityLog", []] } },
    profileSize: { $bsonSize: { $ifNull: ["$profile", {}] } }
  }}
])
```


**Prevention strategies:**

```javascript
// 1. Schema validation with array limits
db.createCollection("users", {
  validator: {
    $jsonSchema: {
      properties: {
        addresses: { maxItems: 10 },
        tags: { maxItems: 100 }
      }
    }
  }
})

// 2. Application-level checks before write
const doc = await db.users.findOne({ _id: userId })
const currentSize = BSON.calculateObjectSize(doc)
if (currentSize > 10 * 1024 * 1024) {  // 10MB warning
  throw new Error("Document approaching size limit")
}

// 3. Use $slice to cap arrays
db.users.updateOne(
  { _id: userId },
  {
    $push: {
      activityLog: {
        $each: [newActivity],
        $slice: -1000  // Keep only last 1000
      }
    }
  }
)
```

For storing large binary blobs, MongoDB provides in-database storage called GridFS, but often it will be most efficient to store them outside of the database and in an external file storage solution.

## Verify with

```javascript
// Find largest documents in collection
db.users.aggregate([
  { $project: { size: { $bsonSize: "$$ROOT" } } },
  { $sort: { size: -1 } },
  { $limit: 10 }
])

// Check specific field sizes
db.users.aggregate([
  { $project: {
    total: { $bsonSize: "$$ROOT" },
    activitySize: { $bsonSize: { $ifNull: ["$activityLog", []] } }
  }}
])
```

Reference: [BSON Document Size Limit](https://mongodb.com/docs/manual/reference/limits/#std-label-limit-bson-document-size)
