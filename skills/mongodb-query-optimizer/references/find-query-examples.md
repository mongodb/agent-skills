## $exists on Regular Index vs. Sparse Index

**Before** — `$exists: true` on a regular index still requires a document fetch:

```javascript
db.collection.createIndex({ a: 1 })
db.collection.find({ a: { $exists: true } })
// Cannot efficiently answer — null semantics require checking each document
```

**After** — Use a sparse index, which only contains entries where the field exists:

```javascript
db.collection.createIndex({ a: 1 }, { sparse: true })
db.collection.find({ a: { $exists: true } })
// Answered directly from the index — no document fetch needed
```

**Why:** Regular indexes store `null` for both missing and explicitly-null fields, so `$exists` can't distinguish them without fetching. Sparse indexes only store entries for documents where the field exists.

## Unanchored $regex vs. Anchored $regex

**Before** — Unanchored case insensitive regex cannot use the index efficiently:

```javascript
db.collection.find({ name: { $regex: /smith/i } })
// Full index or collection scan — case-insensitive, not anchored
```

**After** — Anchored, case-sensitive regex uses the index as a range query:

```javascript
db.collection.find({ name: { $regex: /^Smith/ } })
// Efficient index range scan on the "Smi..." prefix
```

**Why:** Indexes store values in sorted order. Only a left-anchored, case-sensitive `$regex` can be converted into an efficient index range scan. For case-insensitive matching, use a collation index instead.

## $where / JavaScript vs. Native MQL Operators

**Before** — Server-side JavaScript execution:

```javascript
db.collection.find({
  $where: "this.price * this.quantity > 1000"
})
```

**After** — Native aggregation expression:

```javascript
db.collection.find({
  $expr: { $gt: [{ $multiply: ["$price", "$quantity"] }, 1000] }
})
```

**Why:** JavaScript executed on the server is always slower than native MQL. It's also a security risk and is deprecated. Use `$expr` with aggregation operators instead.

## In-Memory Sort vs. Index-Supported Sort

**Before** — Sort on an unindexed field triggers in-memory sort:

```javascript
db.orders.find({ status: "processing" }).sort({ createdAt: -1 })
// Index: { status: 1 } — sort is done in memory
```

**After** — Compound index supports both filter and sort:

```javascript
db.orders.createIndex({ status: 1, createdAt: -1 })
db.orders.find({ status: "processing" }).sort({ createdAt: -1 })
// No SORT stage in the plan — results come pre-sorted from the index
```
