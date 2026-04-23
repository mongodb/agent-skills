# System Profiler

## When to use

Collects detailed information about Database Commands executed against a running mongod instance, including CRUD operations and administration commands. Can significantly degrade production performance. Propose as an alternative when other sources are unavailable or insufficient, explain the impact.

## Requirements

The profiler is off by default. It can be enabled per-database or per-instance at one of several profiling levels. Before enabling, work with the user to determine the profiling level and duration to enable, balancing the need for detailed information with the impact on performance. For most cases, we recommend enabling at level 1 with a reasonable `slowms` threshold (e.g. 50ms), and disabling after the analysis is complete.

```javascript
// enable
db.setProfilingLevel(1, { slowms: <number> })

// ... do your analysis ...

// disable
db.setProfilingLevel(0)
```

## How to use

Example queries to identify access patterns:

**Example 1: Find collections always queried together (embedding candidates)**
```javascript
// Which collections are joined via $lookup?
db.system.profile.find({
  "command.aggregate": { $exists: true },
  "command.pipeline.$lookup": { $exists: true }
}).sort({ millis: -1 }).limit(20)

// Look at the results for:
// - "command.pipeline.$lookup.from": "<collection>"  ← Which collection is being joined
// - "command.pipeline.$lookup.localField" and "foreignField"  ← The relationship
// - "millis": <number>  ← Cost of the join
// If products always $lookup brands, consider embedding brand data in products
```

**Example 2: Find fields accessed together (co-location candidates)**
```javascript
// What fields are queried together?
db.system.profile.aggregate([
  { $match: { 
    ns: "<database>.<collection>",  // e.g., "myshop.products"
    op: "query"
  }},
  { $group: {
    _id: {
      filter: "$command.filter",
      projection: "$command.projection"
    },
    count: { $sum: 1 },
    avgMs: { $avg: "$millis" }
  }},
  { $sort: { count: -1 } },
  { $limit: 10 }
])

// Results show which fields are repeatedly accessed together:
// { _id: { filter: { userId: 1 }, projection: { name: 1, email: 1, avatar: 1 } }, count: <number> }
//   ↑ These fields are always accessed together → keep in same document
```

**Example 3: Find most frequent access patterns (optimize for hot paths)**
```javascript
// What operations run most often? (finds, aggregations, updates, etc.)
db.system.profile.aggregate([
  { $match: { 
    ns: "<database>.<collection>"
    // No op filter - captures all operation types
  }},
  { $group: {
    _id: {
      op: "$op",
      command: "$command"
    },
    count: { $sum: 1 },
    avgMs: { $avg: "$millis" }
  }},
  { $sort: { count: -1 } },
  { $limit: 10 }
])

// High count = hot path → design your schema for these operations first
// Look at both read patterns (find, aggregate) and write patterns (update, insert)
// Frequent updates to same fields might indicate they should be separated from rarely-updated data
```
