Aggregation pipelines process documents through sequential stages. Performance depends on:
Reducing documents early in the pipeline
Minimizing data moved between stages
Leveraging indexes where possible
Managing memory usage
Optimization Examples
Adding an Early $match the Optimizer Can't Infer
Before — All documents flow into $group; the post-group $match on computed totalSpent can't be pushed earlier by the optimizer:

db.orders.aggregate([
  { $group: { _id: "$customerId", totalSpent: { $sum: "$amount" } } },
  { $match: { totalSpent: { $gt: 10000 } } }
])

After — Manually add an early $match to reduce input before the blocking $group:

db.orders.aggregate([
  { $match: { createdAt: { $gte: ISODate("2025-01-01") } } },
  { $group: { _id: "$customerId", totalSpent: { $sum: "$amount" } } },
  { $match: { totalSpent: { $gt: 10000 } } }
])

Why: The optimizer can push $match through $unwind/$group when the field maps to a source field, but it can't infer domain-specific pre-filters. Add them yourself to reduce input to blocking stages.
Unindexed $lookup vs. Indexed $lookup
Before — No index on the foreign collection's join field:

db.orders.aggregate([
  { $lookup: {
      from: "products",
      localField: "productId",
      foreignField: "sku",   // no index on products.sku!
      as: "product"
  }}
])

After — Index on foreignField in the foreign collection:

db.products.createIndex({ sku: 1 })

db.orders.aggregate([
  { $lookup: {
      from: "products",
      localField: "productId",
      foreignField: "sku",
      as: "product"
  }}
])

Why: Each $lookup executes a find on the from collection. Without an index on foreignField, every join does a full collection scan. This is the single most critical $lookup optimization.

Early $project Defeating Optimization vs. Late $project
Before — Early $project prevents the optimizer from pruning unused fields, forgets to exclude _id which is unneeded, and includes name which is not used:

db.collection.aggregate([
  { $project: { name: 1, status: 1, amount: 1 } },
  { $match: { status: "active" } },
  { $group: { _id: "$status", total: { $sum: "$amount" } } }
])

After — Let the optimizer handle field pruning; use $project only at the end for reshaping:

db.collection.aggregate([
  { $match: { status: "active" } },
  { $group: { _id: "$status", total: { $sum: "$amount" } } },
  { $project: { _id: 0, status: "$_id", total: 1 } }  // reshape at the end
])

Why: MongoDB's pipeline optimizer automatically analyzes which fields are used and avoids fetching unused ones. An early $project defeats this optimization, and can inadvertently request the wrong fields.

$facet for Divergent Processing vs. $unionWith
Before — $facet sends all documents to every branch, even if branches need very different subsets:

db.collection.aggregate([
  { $facet: {
      "top10": [{ $sort: { score: -1 } }, { $limit: 10 }],
      "totalCount": [{ $count: "n" }]  // gets ALL docs even though it's just counting
  }}
])

After — Separate pipelines via $unionWith let each branch optimize independently:

db.collection.aggregate([
  { $sort: { score: -1 } }, { $limit: 10 },
  { $unionWith: {
      coll: "collection",
      pipeline: [{ $count: "n" }]
  }}
])

Why: $facet funnels every document into every branch. $unionWith runs independent pipelines that each benefit from their own index usage and optimization.



$sort + $limit as Separate Concerns vs. Top-N Sort
Before — Large sort, then limit (MongoDB may sort entire dataset):

db.collection.aggregate([
  { $group: { _id: "$category", total: { $sum: "$amount" } } },
  { $sort: { total: -1 } },
  // ... many stages later ...
  { $limit: 10 }
])

After — Place $limit immediately after $sort:

db.collection.aggregate([
  { $group: { _id: "$category", total: { $sum: "$amount" } } },
  { $sort: { total: -1 } },
  { $limit: 10 }
])

Why: When $sort is immediately followed by $limit, MongoDB performs a top-N sort — it only tracks the top N values instead of sorting the full dataset. Far less memory.


$unwind Best Practices
$unwind is not inherently expensive, but it multiplies the number of documents in the pipeline, which increases processing cost for all subsequent stages.

When $unwind is needed, filter before unwinding to reduce the number of documents being multiplied:

[
  { $match: { "items.category": "electronics" } },  // Reduce documents first
  { $unwind: "$items" },  // Then unwind
  { $match: { "items.category": "electronics" } }  // Filter unwound elements
]

Consider alternatives when unwinding and then re-grouping by _id: If you are using $unwind followed by $group with _id: "$_id" (i.e., grouping back to the original document), you can often replace the pattern with array operators instead:

$filter to select matching array elements without unwinding
$arrayElemAt to pick a single element from an array
Optimize $lookup operations
$lookup performs collection joins and can be expensive. Strategies to improve performance:

Filter before lookup to reduce left-side documents
Use indexed fields in the lookup localField/foreignField
Add $match in the lookup pipeline to reduce right-side documents early
Add $project last in the lookup pipeline only when and you need a small subset of fields
$unwind after lookup when you expect a single match, since $lookup always returns an array

[
  { $match: { active: true } },  // Reduce left side
  { $lookup: {
      from: "inventory",
      localField: "product_id",  // Ensure this is indexed
      foreignField: "_id",  // _id is always indexed
      pipeline: [
        { $match: { inStock: true } },  // Reduce right side
        { $project: { _id: 0, name: 1, price: 1 } }        ],
      as: "product"
  }},
  { $unwind: "$product" }  // Lookup returns array; unwind when expecting one match
]

Schema consideration: Excessive $lookup usage may indicate over-normalization. Consider embedding frequently-joined data.
$group efficiency
Group operations require accumulating result documents in memory. Keys to efficiency:

Include only needed fields within the $group stage - reference only the fields you need in accumulators
Be mindful of unbounded accumulators - $push and $addToSet grow without limit as group size increases and can cause memory issues

Correct approach - reference only needed fields directly in $group:

[
  { $match: { date: { $gte: ISODate("2024-01-01") } } },  // Reduce input
  { $group: {
      _id: "$category",
      total: { $sum: "$amount" },
      count: { $sum: 1 }
  }}
]

Anti-pattern - do not add $project before $group to "reduce fields":

// DON'T do this - the $project is unnecessary and wasteful
[
  { $match: { date: { $gte: ISODate("2024-01-01") } } },
  { $project: { category: 1, amount: 1 } },  // Unnecessary extra stage
  { $group: {
      _id: "$category",
      total: { $sum: "$amount" },
      count: { $sum: 1 }
  }}
]

The $group stage only processes the fields referenced in its expressions. Adding a $project before it does not save memory; it just adds an unnecessary pipeline stage.
Memory limits and disk spilling
Blocking stages (such as in-memory $sort and $group) have a 100MB memory limit per stage. Now, the default behavior when this limit is exceeded is to spill to disk automatically (allowDiskUse defaults to true).

Better solutions:

Filter more aggressively early in pipeline
Add indexes to enable $sort to use index order
Use $limit with $sort to reduce the amount of data the sort must process in memory for unindexed sorts
Consider materialized views for repeated aggregations
Checking index usage in aggregations
Multiple aggregation stages can take advantage of indexes. Use explain() to verify index usage in your pipeline:

Check index usage:

db.collection.explain("executionStats").aggregate([...])

Look for COLLSCAN in the explain output as the key indicator of a missing index. If you see COLLSCAN, consider adding an index to support the query pattern.
Sharded collections
On sharded clusters, some stages must run on the primary shard or a merge node, creating a sequential bottleneck. Watch for these stages that require merge:

$lookup (runs on primary shard)
$group when the group key does not align with the shard key
$sort when merging results across shards

Optimization: Include the shard key in $match early to target specific shards, avoiding scatter-gather queries.

