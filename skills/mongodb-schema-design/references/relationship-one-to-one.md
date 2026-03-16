---
title: Model One-to-One Relationships with Embedding
impact: HIGH
impactDescription: "Can reduce read round-trips and simplify atomic updates when data is consistently accessed together"
tags: schema, relationships, one-to-one, embedding, fundamentals
---

## Model One-to-One Relationships with Embedding

**Embed one-to-one related data directly in the parent document when it is consistently co-accessed.** When two pieces of data always belong together and are typically read together, keeping them in one document can reduce read round-trips and simplify atomic updates.

**Incorrect (separate collections for one-to-one data):**

Storing user accounts and profiles in separate collections when they are always accessed together requires two queries per user lookup, two index lookups, and risks orphaned records if one insert/delete fails without the other.

**Correct (embedded one-to-one document):**

```javascript
// Single document contains user + profile
{
  _id: "user123",
  email: "alice@example.com",
  createdAt: ISODate("2024-01-01"),
  profile: {
    name: "Alice Smith",
    avatar: "https://cdn.example.com/alice.jpg",
    bio: "Developer building cool things"
  }
}

// Single query returns everything
db.users.findOne({ _id: "user123" })

// Atomic update - profile can't exist without user
db.users.updateOne(
  { _id: "user123" },
  { $set: { "profile.name": "Alice Johnson" } }
)

// Delete user, profile goes with it automatically
db.users.deleteOne({ _id: "user123" })
```

**Common 1:1 relationships to embed:**

| Parent | Embedded 1:1 | Why Embed |
|--------|--------------|-----------|
| User | Profile | Always displayed together |
| Country | Capital city | Geographic data accessed together |
| Building | Address | Physical entity needs location |
| Order | Shipping address | Address at time of order (immutable) |
| Product | Dimensions/weight | Shipping calculation needs both |

**Alternative (subdocument for organization):**

Use subdocuments to logically group related fields within a single document. For example, a user document can have `auth` (passwordHash, lastLogin, mfaEnabled), `profile` (name, avatar), and `settings` (theme, notifications) subdocuments — all 1:1 data, logically organized without separate collections.

**When NOT to use this pattern:**

- **Data accessed independently**: If profile page is separate from auth operations, consider separation.
- **Different security requirements**: If auth data needs stricter access controls than profile.
- **Extreme size difference**: If embedded doc is >10KB and parent is <1KB, consider separation.
- **Different update frequencies**: If profile changes hourly but auth rarely, separate may reduce write amplification.

## Verify with

```javascript
// Find collections that look like 1:1 splits
db.profiles.aggregate([
  { $lookup: {
    from: "users",
    localField: "userId",
    foreignField: "_id",
    as: "user"
  }},
  { $match: { user: { $size: 1 } } },  // Exactly 1 match = 1:1
  { $count: "oneToOneRelationships" }
])
// High count suggests profiles should be embedded in users

// Check for orphaned 1:1 documents
db.profiles.aggregate([
  { $lookup: { from: "users", localField: "userId", foreignField: "_id", as: "u" } },
  { $match: { u: { $size: 0 } } },
  { $count: "orphanedProfiles" }
])
// Any orphans = referential integrity problem, embedding solves this
```

Reference: [Model One-to-One Relationships with Embedded Documents](https://mongodb.com/docs/manual/tutorial/model-embedded-one-to-one-relationships-between-documents/)
