---
title: Use Archive Pattern for Historical Data
impact: MEDIUM
impactDescription: "Reduces active collection size, improves query performance, lowers storage costs"
tags: schema, patterns, archive, data-lifecycle, merge, ttl, online-archive
---

## Use Archive Pattern for Historical Data

**Storing old data alongside recent data degrades performance.** As collections grow with historical data that's rarely accessed, queries slow down, indexes bloat, and working set exceeds RAM. The archive pattern moves old data to separate storage while keeping your active collection fast.

**Incorrect (all data in one collection):**

```javascript
// Sales collection with 5 years of data
// 50 million documents, only recent 6 months actively queried
db.sales.find({ date: { $gte: lastMonth } })

// Problems:
// 1. Index on date covers 50M docs, only 1M relevant
// 2. Working set includes old data pages
// 3. Backups include rarely-accessed historical data
// 4. Storage costs for hot tier when cold would suffice
```

**Correct (archive old data separately):**

```javascript
// Step 1: Define archive threshold
const fiveYearsAgo = new Date()
fiveYearsAgo.setFullYear(fiveYearsAgo.getFullYear() - 5)

// Step 2: Move old data to archive collection using $merge
db.sales.aggregate([
  { $match: { date: { $lt: fiveYearsAgo } } },
  { $merge: {
      into: "sales_archive",
      on: "_id",
      whenMatched: "keepExisting",  // Don't overwrite if re-run
      whenNotMatched: "insert"
    }
  }
])

// Step 3: Delete archived data from active collection
db.sales.deleteMany({ date: { $lt: fiveYearsAgo } })

// Result:
// - sales: Recent data, fast queries, small indexes
// - sales_archive: Historical data, rarely queried
```

**Archive storage options (best to worst for cost/performance):**

```javascript
// Option 1: External file storage (S3, cloud object storage)
// Best for: Compliance, long-term retention, lowest cost
// Export to JSON/BSON, store in S3
// Use Atlas Data Federation to query when needed

// Option 2: Separate, cheaper cluster
// Best for: Occasional historical queries
// Replicate to lower-tier Atlas cluster
// Different performance tier = lower cost

// Option 3: Separate collection on same cluster
// Best for: Simple implementation, frequent historical access
// As shown above with sales_archive
// Still uses same storage tier

// Option 4: Atlas Online Archive (Atlas only)
// Best for: Automatic tiering without code changes
// MongoDB manages movement to cloud object storage
// Query via Federated Database Instance
```

**Design tips for archivable schemas:**

```javascript
// TIP 1: Use embedded data model for archives
// Archived data must be self-contained

// BAD: References that may be deleted
{
  _id: "order123",
  customerId: "cust456",  // Customer may be deleted
  productIds: ["prod1", "prod2"]  // Products may change
}

// GOOD: Embedded snapshot of related data
{
  _id: "order123",
  customer: {
    _id: "cust456",
    name: "Jane Doe",
    email: "jane@example.com"
  },
  products: [
    { _id: "prod1", name: "Widget", price: 29.99 },
    { _id: "prod2", name: "Gadget", price: 49.99 }
  ],
  date: ISODate("2020-01-15")
}

// TIP 2: Store age in a single, indexable field
// Makes archive queries efficient
{
  date: ISODate("2020-01-15"),  // Single field for age
  // NOT: { year: 2020, month: 1, day: 15 }
}

// TIP 3: Handle "never expire" documents
{
  date: ISODate("2025-01-15"),
  retentionPolicy: "permanent"  // Or use far-future date
}

// Archive query excludes permanent records:
db.sales.aggregate([
  { $match: {
      date: { $lt: fiveYearsAgo },
      retentionPolicy: { $ne: "permanent" }
    }
  },
  { $merge: { into: "sales_archive" } }
])
```

**Automated archival with scheduling:**

```javascript
// Create an archive script to run periodically
function archiveOldSales(yearsToKeep = 5) {
  const cutoffDate = new Date()
  cutoffDate.setFullYear(cutoffDate.getFullYear() - yearsToKeep)

  print(`Archiving sales before ${cutoffDate.toISOString()}`)

  // Count documents to archive
  const toArchive = db.sales.countDocuments({
    date: { $lt: cutoffDate },
    retentionPolicy: { $ne: "permanent" }
  })
  print(`Documents to archive: ${toArchive}`)

  if (toArchive === 0) {
    print("Nothing to archive")
    return
  }

  // Archive in batches to avoid long-running operations
  const batchSize = 10000
  let archived = 0

  while (archived < toArchive) {
    // Get batch of IDs
    const batch = db.sales.find(
      { date: { $lt: cutoffDate }, retentionPolicy: { $ne: "permanent" } },
      { _id: 1 }
    ).limit(batchSize).toArray()

    if (batch.length === 0) break

    const ids = batch.map(d => d._id)

    // Move to archive
    db.sales.aggregate([
      { $match: { _id: { $in: ids } } },
      { $merge: { into: "sales_archive", on: "_id" } }
    ])

    // Delete from active
    db.sales.deleteMany({ _id: { $in: ids } })

    archived += batch.length
    print(`Archived ${archived}/${toArchive}`)
  }

  print("Archive complete")
}

// Run monthly via cron, Atlas Triggers, or application scheduler
// archiveOldSales(5)
```

**Atlas Online Archive (Atlas only):**

```javascript
// Atlas Online Archive automatically tiers data
// Configure via Atlas UI or API:

// 1. Set archive rule based on date field
// archiveAfter: 365 days on "date" field

// 2. Data moves to MongoDB-managed cloud object storage
// Transparent to application - appears as same collection

// 3. Query via Federated Database Instance
// Slightly slower but much cheaper storage

// Benefits:
// - No code changes
// - Automatic data movement
// - Unified query interface
// - Pay cloud storage rates for cold data
```

**When NOT to use archive pattern:**

- **Small datasets**: If total data fits comfortably in RAM, archiving adds complexity without benefit.
- **Uniform access patterns**: If old and new data are queried equally.
- **Compliance requires instant access**: If regulations require sub-second queries on all historical data.
- **Already using TTL**: If data should be deleted, not archived, use TTL indexes.

## Verify with

```javascript
// Analyze archive candidates
function analyzeArchiveCandidates(collection, dateField, yearsThreshold) {
  const cutoff = new Date()
  cutoff.setFullYear(cutoff.getFullYear() - yearsThreshold)

  const stats = db[collection].aggregate([
    { $facet: {
        total: [{ $count: "count" }],
        old: [
          { $match: { [dateField]: { $lt: cutoff } } },
          { $count: "count" }
        ],
        recent: [
          { $match: { [dateField]: { $gte: cutoff } } },
          { $count: "count" }
        ],
        oldestDoc: [
          { $sort: { [dateField]: 1 } },
          { $limit: 1 },
          { $project: { [dateField]: 1 } }
        ],
        newestDoc: [
          { $sort: { [dateField]: -1 } },
          { $limit: 1 },
          { $project: { [dateField]: 1 } }
        ]
      }
    }
  ]).toArray()[0]

  const total = stats.total[0]?.count || 0
  const old = stats.old[0]?.count || 0
  const recent = stats.recent[0]?.count || 0

  print(`\n=== Archive Analysis for ${collection} ===`)
  print(`Date field: ${dateField}`)
  print(`Threshold: ${yearsThreshold} years (before ${cutoff.toISOString().split('T')[0]})`)
  print(`\nDocument counts:`)
  print(`  Total: ${total.toLocaleString()}`)
  print(`  Archivable (>${yearsThreshold}yr): ${old.toLocaleString()} (${((old/total)*100).toFixed(1)}%)`)
  print(`  Keep active: ${recent.toLocaleString()} (${((recent/total)*100).toFixed(1)}%)`)

  if (stats.oldestDoc[0]) {
    print(`\nDate range:`)
    print(`  Oldest: ${stats.oldestDoc[0][dateField]}`)
    print(`  Newest: ${stats.newestDoc[0][dateField]}`)
  }

  if (old > 0 && old / total > 0.3) {
    print(`\nRECOMMENDATION: Archive ${old.toLocaleString()} documents to improve performance`)
  }
}

// Usage
analyzeArchiveCandidates("sales", "date", 5)
```

Reference: [Archive Pattern](https://mongodb.com/docs/manual/data-modeling/design-patterns/archive/)
