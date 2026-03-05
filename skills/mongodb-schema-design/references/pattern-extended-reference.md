---
title: Use Extended Reference Pattern
impact: MEDIUM
impactDescription: "Reduces repeated `$lookup` on hot paths by caching selected referenced fields"
tags: schema, patterns, extended-reference, denormalization, caching
---

## Use Extended Reference Pattern

**Copy frequently-accessed fields from referenced documents into the parent.** If you always display author name with articles, embed it. This eliminates $lookup for common queries while keeping the full data normalized—best of both worlds.

**Incorrect (always $lookup for display data):**

```javascript
// Order references customer by ID only
{
  _id: "order123",
  customerId: "cust456",  // Just an ObjectId
  items: [...],
  total: 299.99
}

// Every order list/display requires $lookup
db.orders.aggregate([
  { $match: { status: "pending" } },
  { $lookup: {
    from: "customers",
    localField: "customerId",
    foreignField: "_id",
    as: "customer"
  }},
  { $unwind: "$customer" }
])
// Repeated joins add avoidable work for a common list view
```

**Correct (extended reference):**

```javascript
// Order contains frequently-needed customer fields
// Full customer data still in customers collection
{
  _id: "order123",
  customer: {
    _id: "cust456",         // Keep reference for full lookup
    name: "Alice Smith",    // Cached for display
    email: "alice@ex.com"   // Cached for notifications
  },
  items: [...],
  total: 299.99,
  createdAt: ISODate("2024-01-15")
}

// Order list without $lookup - single query
db.orders.find({ status: "pending" })
// Returns customer.name directly - no join needed

// Full customer data available when needed
const fullCustomer = db.customers.findOne({ _id: order.customer._id })
```

**Keeping cached data in sync:**

```javascript
// When customer name changes (rare event)
// 1. Update source of truth
db.customers.updateOne(
  { _id: "cust456" },
  { $set: { name: "Alice Johnson" } }
)

// 2. Update cached copies
// Can be async via Change Streams or background job
db.orders.updateMany(
  { "customer._id": "cust456" },
  { $set: { "customer.name": "Alice Johnson" } }
)

// For frequently-changing data, add timestamp
{
  customer: {
    _id: "cust456",
    name: "Alice Smith",
    cachedAt: ISODate("2024-01-15")
  }
}
// Application can refresh if cachedAt > threshold
```

**What to cache (extend):**

| Cache | Don't Cache |
|-------|-------------|
| Display name, avatar | Full bio, description |
| Status, type | Sensitive PII |
| Slowly-changing data | Real-time values (balance, inventory) |
| Fields used in sorting/filtering | Large binary data |

**Alternative: Hybrid pattern with cache expiry:**

```javascript
// For data that changes occasionally
{
  _id: "order123",
  customerId: "cust456",        // Always have reference
  customerCache: {              // Optional cache
    name: "Alice Smith",
    email: "alice@ex.com",
    cachedAt: ISODate("2024-01-15")
  }
}

// Application logic
if (!order.customerCache ||
    order.customerCache.cachedAt < oneDayAgo) {
  // Refresh cache from customers collection
  const customer = db.customers.findOne({ _id: order.customerId })
  db.orders.updateOne(
    { _id: order._id },
    { $set: { customerCache: { ...customer, cachedAt: new Date() } } }
  )
}
```

**When NOT to use this pattern:**

- **Frequently-changing data**: If customer name changes daily, update overhead exceeds $lookup cost.
- **Large cached payloads**: Don't embed 50KB of author bio in every article.
- **Sensitive data segregation**: Don't copy PII into collections with different access controls.
- **Writes >> Reads**: If writes greatly outnumber reads, caching adds overhead.

## Verify with

```javascript
// Find $lookup-heavy aggregations in profile
db.setProfilingLevel(1, { slowms: 20 })
db.system.profile.find({
  "command.pipeline": { $elemMatch: { "$lookup": { $exists: true } } }
}).sort({ millis: -1 }).limit(10)

// Check how often lookups hit same collections
db.system.profile.aggregate([
  { $match: { "command.pipeline.$lookup": { $exists: true } } },
  { $unwind: "$command.pipeline" },
  { $match: { "$lookup": { $exists: true } } },
  { $group: { _id: "$command.pipeline.$lookup.from", count: { $sum: 1 } } }
])
// High count = candidate for extended reference
```

Reference: [Building with Patterns - Extended Reference](https://mongodb.com/blog/post/building-with-patterns-the-extended-reference-pattern)
