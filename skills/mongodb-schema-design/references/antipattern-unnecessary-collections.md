---
title: Reduce Unnecessary Collections
impact: CRITICAL
impactDescription: "Reduces avoidable joins when related data is repeatedly queried together"
tags: schema, collections, anti-pattern, embedding, normalization, atlas-suggestion
---

## Reduce Unnecessary Collections

**Collection count alone is not the anti-pattern.** The anti-pattern is using collections as a substitute for indexes — creating one collection per category, time period, or partition key instead of indexing a single collection. Every collection carries a default `_id` index that consumes storage and strains the replica set, and cross-collection queries require `$lookup` or `$unionWith`, adding complexity and overhead.

**Incorrect (one collection per day as partitioning strategy):**

```javascript
// temperature database — one collection per day
// temperatures_2024_05_10, temperatures_2024_05_11, ...

// temperatures_2024_05_10
{ _id: 1, timestamp: ISODate("2024-05-10T10:00:00Z"), temperature: 60 }
{ _id: 2, timestamp: ISODate("2024-05-10T11:00:00Z"), temperature: 61 }
{ _id: 3, timestamp: ISODate("2024-05-10T12:00:00Z"), temperature: 64 }

// temperatures_2024_05_11
{ _id: 1, timestamp: ISODate("2024-05-11T10:00:00Z"), temperature: 68 }
{ _id: 2, timestamp: ISODate("2024-05-11T11:00:00Z"), temperature: 72 }
{ _id: 3, timestamp: ISODate("2024-05-11T12:00:00Z"), temperature: 72 }

// Problems:
// 1. Each collection creates a default _id index — 365 collections/year = 365 extra indexes
// 2. Querying across days requires $unionWith across many collections
// 3. Schema validation, indexes, and TTL must be duplicated on every collection
// 4. Application code must dynamically resolve the collection name for each query
```

**Correct (single collection with an index):**

```javascript
// All readings in one collection — the index does the partitioning work
{ _id: ObjectId(), timestamp: ISODate("2024-05-10T10:00:00Z"), temperature: 60 }
{ _id: ObjectId(), timestamp: ISODate("2024-05-10T11:00:00Z"), temperature: 61 }
{ _id: ObjectId(), timestamp: ISODate("2024-05-11T10:00:00Z"), temperature: 68 }

db.temperatures.createIndex({ timestamp: 1 })

// Efficient range query — one collection, one index
db.temperatures.find({
  timestamp: { $gte: ISODate("2024-05-10"), $lt: ISODate("2024-05-11") }
})

// Optional TTL for automatic expiry (e.g. 90 days)
db.temperatures.createIndex({ timestamp: 1 }, { expireAfterSeconds: 7776000 })
```

**Even better (bucket pattern or time series collection):**

For high-volume time-stamped data, group readings into buckets or use a native time series collection, which is optimized for this workload:

```javascript
// Bucket pattern — one document per day
{
  _id: ISODate("2024-05-10T00:00:00Z"),
  readings: [
    { timestamp: ISODate("2024-05-10T10:00:00Z"), temperature: 60 },
    { timestamp: ISODate("2024-05-10T11:00:00Z"), temperature: 61 },
    { timestamp: ISODate("2024-05-10T12:00:00Z"), temperature: 64 }
  ]
}

// In this particular case, a native time series collection
// is also a good option to consider
db.createCollection("temperatures", {
  timeseries: { timeField: "timestamp", granularity: "hours" }
})
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

Reference: [Reduce the Number of Collections](https://mongodb.com/docs/manual/data-modeling/design-antipatterns/reduce-collections/)
