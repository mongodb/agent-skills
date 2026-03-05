---
title: "Avoid Unnecessary Indexes"
impact: CRITICAL
tags: [antipattern, indexes, performance, atlas-suggestion]
---

# Avoid Unnecessary Indexes

Every index has a write cost. On insert, update, and delete, MongoDB must update ALL indexes on the collection. Unused or redundant indexes slow down writes with no query benefit.

## Why It Matters

- Each index adds overhead to every write operation (insert/update/delete must update ALL indexes)
- Indexes consume RAM in the WiredTiger cache, competing with working set data
- Atlas Performance Advisor specifically flags "Redundant Index" and "Unused Index"

## Identify Unused Indexes

```javascript
// Find indexes with zero query usage since last restart
db.orders.aggregate([{ $indexStats: {} }])
// Look for: accesses.ops: 0
// Example output:
// { name: "status_1", accesses: { ops: 0, since: ISODate("...") }, ... }
```

An `accesses.ops: 0` after a representative workload period means the index is never used by any query.

## Safe Removal Process

Never drop an index directly. Use the hide → monitor → drop workflow:

```javascript
// Step 1: Hide the index (makes it invisible to query planner but keeps it on disk)
db.orders.hideIndex("status_1")

// Step 2: Monitor for a full workload cycle (days/weeks)
// If queries degrade, unhide immediately:
// db.orders.unhideIndex("status_1")

// Step 3: Once confident, permanently drop:
db.orders.dropIndexes(["status_1"])
```

## Identify Redundant Indexes

A compound index `{a: 1, b: 1}` makes a single-field index `{a: 1}` redundant — the compound index can serve all queries that `{a: 1}` alone serves (as long as `a` is the leading field).

```javascript
// REDUNDANT — {a: 1} is fully covered by {a: 1, b: 1}
db.col.createIndex({ a: 1 })         // ← drop this
db.col.createIndex({ a: 1, b: 1 })   // ← keep this

// NOT redundant — different leading field
db.col.createIndex({ a: 1, b: 1 })
db.col.createIndex({ b: 1 })         // ← NOT covered by above
```

## Atlas Performance Advisor

Atlas automatically flags:
- **"Redundant Index"** — a prefix of an existing compound index
- **"Unused Index"** — zero query usage in the observed window

Always review and act on these recommendations.

## Correct Pattern

```javascript
// ✅ Only create indexes that serve real query patterns
// Audit before adding new indexes:
db.orders.aggregate([{ $indexStats: {} }])

// ✅ Review index list regularly
db.orders.getIndexes()

// ✅ Hide before drop — never drop directly in production
db.orders.hideIndex("old_index_1")
// ... wait and monitor ...
db.orders.dropIndexes(["old_index_1"])
```

## Incorrect Pattern

```javascript
// ❌ Creating indexes "just in case"
db.orders.createIndex({ status: 1 })        // never queried by status alone
db.orders.createIndex({ status: 1, date: 1 }) // already have {status:1,date:1,amount:1}

// ❌ Keeping indexes that Atlas Performance Advisor flags as unused
// → Review Advisor recommendations weekly
```
