# Aggregation Pipeline Optimization

Use this reference when optimizing aggregation pipelines.

## Core optimization strategy

Aggregation pipelines process documents through sequential stages. Performance depends on:
- Reducing documents early in the pipeline
- Minimizing data moved between stages
- Leveraging indexes where possible
- Managing memory usage

## Filter early with $match

Place `$match` stages as early as possible to reduce the working set immediately. The query optimizer can push `$match` to use indexes when it appears before transformations.

**Prefer:**
```javascript
db.orders.aggregate([
  { $match: { status: "shipped", region: "US" } },  // Uses index, reduces data early
  { $lookup: { ... } },
  { $group: { ... } }
])
```

**Avoid:**
```javascript
db.orders.aggregate([
  { $lookup: { ... } },  // Processes all documents first
  { $match: { status: "shipped" } }  // Too late, already did expensive work
])
```

## Minimize $unwind usage

`$unwind` explodes array elements into separate documents, multiplicatively increasing document count. This amplifies processing cost for subsequent stages.

**When $unwind is needed**, filter before unwinding:
```javascript
[
  { $match: { "items.category": "electronics" } },  // Reduce documents first
  { $unwind: "$items" },  // Then unwind
  { $match: { "items.category": "electronics" } }  // Filter unwound elements
]
```

**Consider alternatives:**
- `$filter` array operator to process arrays without unwinding
- Aggregation expressions that work on arrays directly (`$size`, `$arrayElemAt`, etc.)

## Optimize $lookup operations

`$lookup` performs collection joins and can be expensive. Strategies to improve performance:

1. **Filter before lookup** to reduce left-side documents
2. **Use indexed fields** in the lookup `localField`/`foreignField`
3. **Add $match in the lookup pipeline** to reduce right-side documents early
4. **Limit fields** with `$project` after lookup to avoid moving unnecessary data

```javascript
[
  { $match: { active: true } },  // Reduce left side
  { $lookup: {
      from: "inventory",
      localField: "product_id",  // Ensure this is indexed
      foreignField: "_id",  // _id is always indexed
      pipeline: [
        { $match: { inStock: true } },  // Reduce right side
        { $project: { name: 1, price: 1 } }  // Limit fields
      ],
      as: "product"
  }}
]
```

**Schema consideration:** Excessive `$lookup` usage may indicate over-normalization. Consider embedding frequently-joined data.

## $group efficiency

Group operations require accumulating data in memory. Keys to efficiency:

1. **Filter before grouping** to reduce input documents
2. **Use selective _id** for grouping to reduce number of groups
3. **Project only needed fields** before $group to reduce memory per document
4. **Be mindful of accumulators** - some (`$push`, `$addToSet`) grow unbounded with group size

```javascript
[
  { $match: { date: { $gte: ISODate("2024-01-01") } } },  // Reduce input
  { $project: { category: 1, amount: 1 } },  // Only needed fields
  { $group: {
      _id: "$category",  // Limited cardinality
      total: { $sum: "$amount" },  // Fixed-size accumulator
      count: { $sum: 1 }
  }}
]
```

## Memory limits and allowDiskUse

Aggregation stages have a 100MB memory limit per stage (MongoDB 4.2+, configurable with `internalQueryExecMaxBlockingSortBytes`). When exceeded:
- Without `allowDiskUse`: pipeline fails
- With `allowDiskUse: true`: spills to disk (slower but completes)

**Use allowDiskUse when:**
- Processing large datasets that exceed memory limits
- $group or $sort operations on high-cardinality data
- Acceptable to trade speed for completion

**Better solutions:**
- Filter more aggressively early in pipeline
- Add indexes to enable `$sort` to use index order
- Increase available memory (Atlas tier upgrade)
- Consider materialized views for repeated aggregations

## Index usage in aggregations

The query optimizer can use indexes for:
- `$match` at pipeline start (or after $project that doesn't exclude indexed fields)
- `$sort` immediately after `$match`, or at pipeline start
- `$lookup` foreign field lookups
- `$geoNear` (must be first stage)

**Check index usage:**
```javascript
db.collection.explain("executionStats").aggregate([...])
```

Look for `IXSCAN` stages. `COLLSCAN` indicates full collection scan.

## Sharded collections

On sharded clusters, understand which stages run on each shard versus the merge node:

**Shard-local** (parallel, efficient):
- `$match`, `$project`, `$limit`, `$skip`, `$unwind`, `$group` (sometimes)

**Requires merge** (sequential bottleneck):
- `$lookup`, `$sort`, `$group` (when grouping across shards), final `$group`

**Optimization:** Include shard key in `$match` early to target specific shards, avoiding scatter-gather.

## When to use aggregation vs. find()

Use `find()` when:
- Simple filtering and field projection
- No transformation or grouping needed
- Result documents have same structure as collection documents

Use aggregation when:
- Computing aggregates ($sum, $avg, etc.)
- Reshaping documents significantly
- Joining collections ($lookup)
- Complex multi-stage processing

Aggregation has overhead - don't use it for simple queries that `find()` handles efficiently.
