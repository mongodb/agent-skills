# Query Stats

## When to use

Analyzes query access patterns with minimal performance overhead. Use for identifying co-accessed fields, collection relationships, and query frequencies. Preferred over system.profile for production analysis. Only supports `find`, `aggregate`, and `distinct` operations.

## Requirements

Atlas M10+ tier.

## How to use

Aggregate on the admin database.

With mcp-server, use the `mcp__mongodb__aggregateDB` tool with database set to `admin`.

```javascript
db.getSiblingDB("admin").aggregate([{ $queryStats: {} }])
```

**Example 1: Find collections frequently queried together (embedding candidates)**
```javascript
db.getSiblingDB("admin").aggregate([
  { $queryStats: {} },
  {
    $match: {
      "key.queryShape.command": "aggregate",
      "key.queryShape.pipeline": {
        $elemMatch: { $lookup: { $exists: true } }
      }
    }
  },
  {
    $project: {
      collection: "$key.queryShape.cmdNs.coll",
      pipeline: "$key.queryShape.pipeline",
      execCount: "$metrics.execCount",
      avgMs: {
        $divide: [
          { $divide: ["$metrics.totalExecMicros.sum", 1000] },
          "$metrics.execCount"
        ]
      }
    }
  },
  { $sort: { execCount: -1 } }
])

// Check pipeline.$lookup.from for joined collections
// High execCount + high avgMs = consider embedding instead of $lookup
```

**Example 2: Identify co-accessed fields (co-location candidates)**
```javascript
db.getSiblingDB("admin").aggregate([
  { $queryStats: {} },
  {
    $match: {
      "key.queryShape.cmdNs.coll": "<collection>"  // e.g., "products"
    }
  },
  {
    $group: {
      _id: {
        filter: "$key.queryShape.filter",
        projection: "$key.queryShape.projection"
      },
      execCount: { $sum: "$metrics.execCount" }
    }
  },
  { $sort: { execCount: -1 } },
  { $limit: 5 }
])

// Fields in filter + projection accessed together should stay in same document
// queryShape normalizes values: {price: {$gte: "?number"}} groups all price range queries
```

**Example 3: Find most frequent access patterns (optimize hot paths)**
```javascript
db.getSiblingDB("admin").aggregate([
  { $queryStats: {} },
  { $sort: { "metrics.execCount": -1 } },
  { $limit: 10 },
  {
    $project: {
      collection: "$key.queryShape.cmdNs.coll",
      filter: "$key.queryShape.filter",
      projection: "$key.queryShape.projection",
      executions: "$metrics.execCount",
      avgMs: {
        $divide: [
          { $divide: ["$metrics.totalExecMicros.sum", 1000] },
          "$metrics.execCount"
        ]
      }
    }
  }
])

// High execCount = hot path → design your schema for these queries first
// Note: Does not include write patterns (update, insert)
// Filter + projection show which fields are accessed together
```