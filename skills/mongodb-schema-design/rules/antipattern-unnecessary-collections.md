---
title: Reduce Unnecessary Collections
impact: CRITICAL
impactDescription: "Reduces avoidable joins when related data is repeatedly queried together"
tags: schema, collections, anti-pattern, embedding, normalization, atlas-suggestion
---

## Reduce Unnecessary Collections

**Collection count alone is not the anti-pattern.** The anti-pattern is splitting data across many collections when the same operation repeatedly re-joins it. MongoDB supports both embedding and references; choose based on access patterns, update patterns, and growth.

**Incorrect (SQL-style normalization):**

```javascript
// 5 collections for one order - relational thinking in MongoDB
// orders: { _id, customerId, date, status }
// order_items: { orderId, productId, quantity, price }
// products: { _id, name, sku }
// customers: { _id, name, email }
// addresses: { customerId, street, city }

// Displaying one order requires 5 queries or complex $lookup chain
db.orders.aggregate([
  { $match: { _id: orderId } },
  { $lookup: { from: "order_items", localField: "_id", foreignField: "orderId", as: "items" } },
  { $unwind: "$items" },
  { $lookup: { from: "products", localField: "items.productId", foreignField: "_id", as: "items.product" } },
  { $lookup: { from: "customers", localField: "customerId", foreignField: "_id", as: "customer" } },
  { $lookup: { from: "addresses", localField: "customerId", foreignField: "customerId", as: "address" } }
])
// Multiple joins increase query complexity and runtime variance
```

**Correct (embedded document model):**

```javascript
// Single document contains everything needed for order operations
{
  _id: "order123",
  date: ISODate("2024-01-15"),
  status: "shipped",
  // Customer snapshot at time of order (won't change)
  customer: {
    _id: "cust456",
    name: "Alice Smith",
    email: "alice@example.com"
  },
  // Address at time of order (historical accuracy)
  shippingAddress: {
    street: "123 Main St",
    city: "Boston",
    state: "MA",
    zip: "02101"
  },
  // Line items with product snapshot (price at time of order)
  items: [
    {
      sku: "LAPTOP-01",
      name: "Laptop Pro",  // Snapshot, won't change if product renamed
      quantity: 1,
      unitPrice: 999,
      lineTotal: 999
    },
    {
      sku: "MOUSE-02",
      name: "Wireless Mouse",
      quantity: 2,
      unitPrice: 29,
      lineTotal: 58
    }
  ],
  subtotal: 1057,
  tax: 84.56,
  total: 1141.56
}

// One query returns complete order - no joins needed
db.orders.findOne({ _id: "order123" })
```

This isn't denormalization—it's proper document modeling. Orders are self-contained entities; the embedded data is a snapshot that shouldn't change.

**Alternative (hybrid for reusable entities):**

```javascript
// Keep products as separate collection (catalog changes independently)
// But embed product snapshot in order (historical accuracy)
{
  _id: "order123",
  items: [{
    productId: "prod789",        // Reference for inventory updates
    productSnapshot: {           // Embedded for historical record
      name: "Laptop Pro",
      sku: "LAPTOP-01",
      priceAtPurchase: 999
    },
    quantity: 1
  }]
}

// Current product details from products collection
// Order history from embedded snapshot
```

**Incorrect (over-partitioned time-based collections):**

```javascript
// Creating one collection per time period — a common over-partitioning mistake
// orders_2024_01, orders_2024_02, orders_2024_03, ...

// Problems:
// 1. Each collection gets its own default _id index — N collections = N extra indexes
//    straining the storage engine with no query benefit
// 2. Queries spanning time periods require $unionWith across many collections
// 3. Atlas Performance Advisor flags this pattern as avoidable collection proliferation
// 4. Schema validation, indexes, and TTL must be maintained on every collection separately

// Correct: single orders collection with a date index and optional TTL
db.orders.createIndex({ createdAt: 1 })
// Optional TTL for automatic expiry:
db.orders.createIndex({ createdAt: 1 }, { expireAfterSeconds: 7776000 }) // 90 days

// Query a time range efficiently — single collection, single index
db.orders.find({ createdAt: { $gte: ISODate("2024-01-01"), $lt: ISODate("2024-02-01") } })
```

**When to use separate collections:**

| Scenario | Separate Collection | Why |
|----------|--------------------|----|
| Data accessed independently | Yes | User profiles vs. user orders |
| Different update frequencies | Yes | Product catalog vs. orders |
| Unbounded relationships | Yes | Comments on posts |
| Many-to-many | Yes | Students ↔ Courses |
| Shared across entities | Yes | Tags, categories |
| Historical snapshots | No (embed) | Order contains customer at time of purchase |
| 1:1 always together | No (embed) | User and profile |

**When NOT to use this pattern:**

- **Data is genuinely independent**: Products exist separately from orders; don't embed full product catalog in every order.
- **Frequent independent updates**: If customer email changes shouldn't update all historical orders (it shouldn't).
- **Data is accessed in different contexts**: Same address entity used for shipping, billing, user profile—keep it separate.
- **Regulatory requirements**: Some industries require normalized data for audit trails.

## Verify with

```javascript
// Count your collections
db.adminCommand({ listDatabases: 1 }).databases
  .forEach(d => {
    const colls = db.getSiblingDB(d.name).getCollectionNames().length
    print(`${d.name}: ${colls} collections`)
  })
// Count alone is not sufficient: combine with access and index/storage evidence

// Find $lookup-heavy aggregations
db.setProfilingLevel(1, { slowms: 20 })
db.system.profile.find({
  "command.pipeline.0.$lookup": { $exists: true }
}).count()
// Frequent repeated lookups on the same paths can indicate over-normalized hot paths

// Check if collections are always accessed together
// If orders always needs customer, items, addresses
// → they should be embedded
db.system.profile.aggregate([
  { $match: { op: "query" } },
  { $group: { _id: "$ns", count: { $sum: 1 } } },
  { $sort: { count: -1 } }
])
// Collections with similar access patterns should be combined
```

Atlas Schema Suggestions flags: "Reduce number of collections"

Reference: [Embedding vs Referencing](https://mongodb.com/docs/manual/data-modeling/concepts/embedding-vs-references/)
