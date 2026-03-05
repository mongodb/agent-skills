---
title: Embed vs Reference Decision Framework
impact: HIGH
impactDescription: "Determines long-term query and update paths in your application data model"
tags: schema, embedding, referencing, relationships, fundamentals
---

## Embed vs Reference Decision Framework

**This is one of the most important schema decisions you'll make.** Choose embedding or referencing based on access patterns, not just entity relationships.

**Embed when:**
- Data is always accessed together (1:1 or 1:few relationships)
- Child data doesn't make sense without parent
- Updates to both happen atomically
- Child array is clearly bounded by product constraints

**Reference when:**
- Data is accessed independently
- Many-to-many relationships exist
- Child data is large relative to the parent or array growth is unbounded
- Different update frequencies

**Incorrect (reference when should embed):**

```javascript
// Separate collections for 1:1 data - always accessed together
// users: { _id, email }
// profiles: { userId, name, avatar, bio }

// Every user fetch requires two queries
const user = await db.users.findOne({ _id: userId })      // Query 1
const profile = await db.profiles.findOne({ userId })    // Query 2
// Extra round-trips and index lookups on the read path
// No atomicity - what if profile insert fails after user insert?
// Orphaned profiles when user deleted - referential integrity issues
```

**Correct (embed 1:1 data):**

```javascript
// User with embedded profile - single document
// Always consistent, always atomic
{
  _id: "user123",
  email: "alice@example.com",
  profile: {
    name: "Alice Smith",
    avatar: "https://cdn.example.com/alice.jpg",
    bio: "Software developer"
  },
  createdAt: ISODate("2024-01-01")
}

// Single query returns everything
const user = await db.users.findOne({ _id: userId })
// Atomic updates - profile can't exist without user
db.users.updateOne(
  { _id: userId },
  { $set: { "profile.name": "Alice Johnson" } }
)
```

**Incorrect (embed when should reference):**

```javascript
// Blog post with ALL comments embedded - unbounded!
{
  _id: "post123",
  title: "Popular Post",
  comments: [
    // 50,000 comments × 500 bytes = 25MB document
    // Exceeds 16MB BSON limit -> writes fail for oversized documents
    { author: "user1", text: "...", ts: ISODate("...") },
    // ... grows forever
  ]
}
```

**Correct (reference unbounded data):**

```javascript
// Post with comment summary embedded
{
  _id: "post123",
  title: "Popular Post",
  commentCount: 50000,
  recentComments: [/* last 5 only - bounded */]
}

// Comments in separate collection - no limit
{
  _id: ObjectId("..."),
  postId: "post123",
  author: "user1",
  text: "Great post!",
  ts: ISODate("2024-01-15")
}
// Index on postId for efficient lookups
```

**Decision Matrix:**

| Relationship | Read Pattern | Write Pattern | Bounded? | Decision |
|--------------|--------------|---------------|----------|----------|
| User → Profile | Always together | Together | Yes | **Embed** |
| Order → Items | Usually together | Together | Yes (bounded) | **Embed** |
| Post → Comments | Together on load | Separate adds | No (unbounded) | **Reference** |
| Author → Books | Separately | Separate | Can grow large | **Reference** |
| Product ↔ Category | Either way | Either | N/A (many-to-many) | **Reference both ways** |

**When NOT to use embedding:**

- **Data grows unbounded**: Comments, logs, events—separate collection.
- **Large child documents**: If each child is large relative to the parent, references are usually safer.
- **Independent access**: If you ever query child without parent, reference.
- **Different lifecycles**: If child data is archived/deleted separately.

## Verify with

```javascript
// Check document sizes for embedded collections
db.posts.aggregate([
  { $project: {
    size: { $bsonSize: "$$ROOT" },
    commentCount: { $size: { $ifNull: ["$comments", []] } }
  }},
  { $match: { size: { $gt: 1000000 } } }  // example threshold, tune per workload
])
// Investigate large documents and growth trend before deciding to refactor

// Check for orphaned references
db.profiles.aggregate([
  { $lookup: {
    from: "users",
    localField: "userId",
    foreignField: "_id",
    as: "user"
  }},
  { $match: { user: { $size: 0 } } }
])
// Orphans suggest 1:1 should be embedded
```

Reference: [Embedding vs Referencing](https://mongodb.com/docs/manual/data-modeling/concepts/embedding-vs-references/)
