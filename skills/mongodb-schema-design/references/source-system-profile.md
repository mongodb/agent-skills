# System Profiler

## When to use

Important: Can significantly degrade production performance. Only use when other sources are unavailable or insufficient. Explain the impact. Use with caution, limit time and scope.

Collects detailed information about Database Commands executed against a running mongod instance, including CRUD operations and administration commands.

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

**Example 1: Find pipelines with $lookup stages (embedding candidates)**
```javascript
db.setProfilingLevel(1, { slowms: 50 }) // Disable afterwards
db.system.profile.find({
  "command.aggregate": { $exists: true },
  "command.pipeline.$lookup": {
    $exists: true
  }
}).sort({ millis: -1 })
```

**Example 2: Check if collections are always accessed together (embedding candidates)**
```javascript
// If orders always needs customer, items, addresses
// → they should be embedded
db.system.profile.aggregate([
  { $match: { op: "query" } },
  { $group: { _id: "$ns", count: { $sum: 1 } } },
  { $sort: { count: -1 } }
])
```

**Example 3: Check write frequency on counter fields (approximation candidates)**
```javascript
db.setProfilingLevel(1, { slowms: 0 })
db.system.profile.find({
  "command.update": "articles",
  "command.updates.u.$inc.viewCount": { $exists: true }
}).count()
```

**Example 4: Find expensive aggregations that should be pre-computed**
```javascript
db.setProfilingLevel(1, { slowms: 100 }) // Disable afterwards
db.system.profile.find({
  "command.aggregate": { $exists: true },
  millis: { $gt: 100 }
}).sort({ millis: -1 })
```

**Example 5: Check if same aggregation runs repeatedly**
```javascript
db.system.profile.aggregate([
  { $match: { "command.aggregate": { $exists: true } } },
  { $group: {
    _id: "$command.pipeline",
    count: { $sum: 1 },
    avgMs: { $avg: "$millis" }
  }},
  { $match: { count: { $gt: 100 } } }  // Repeated 100+ times
])
```

**Example 6: Check how often lookups hit same collections**
```javascript
// Check how often lookups hit same collections
db.system.profile.aggregate([
  { $match: { "command.pipeline.$lookup": { $exists: true } } },
  { $project: { pipeline: "$command.pipeline" } },
  { $unwind: "$pipeline" },
  { $project: { lookup: { $getField: { field: { $literal: '$lookup' }, input: '$pipeline' } } } },
  { $match: { "lookup": { $exists: true } } },
  { $group: { _id: "$lookup.from", count: { $sum: 1 } } }
])
```
