---
title: Use Outlier Pattern for Exceptional Documents
impact: MEDIUM
impactDescription: "Isolates unusually large documents so hot-path queries stay optimized for typical cases"
tags: schema, patterns, outlier, arrays, performance, edge-cases
---

## Use Outlier Pattern for Exceptional Documents

**Isolate atypical documents with large arrays to prevent them from degrading performance for typical queries.** When a small subset of documents is much larger than the rest, those outliers can dominate memory, index, and query costs. Split overflow data into a separate collection and flag the document.

**Problem scenario:**

```javascript
// Typical book: 50 customers purchased
{ _id: "book1", title: "Normal Book", customers: [/* 50 items */] }

// Bestseller: 50,000 customers - outlier!
{
  _id: "book2",
  title: "Harry Potter",
  customers: [/* 50,000 items = ~2.5MB */]
}

// Query affects both equally
db.books.find({ title: /Potter/ })
// Returns 2.5MB document, killing memory and network
// Index on customers array has 50,000 entries for this one doc
```

**Correct (outlier pattern):**

```javascript
// Typical book - unchanged
{
  _id: "book1",
  title: "Normal Book",
  customers: ["cust1", "cust2", /* ... 50 items */],
  hasExtras: false  // Flag for application logic
}

// Bestseller - capped at threshold
{
  _id: "book2",
  title: "Harry Potter",
  customers: [/* first 50 items only */],
  hasExtras: true,  // Flag indicating overflow exists
  customerCount: 50000  // Denormalized count
}

// Overflow in separate collection
{
  _id: ObjectId("..."),
  bookId: "book2",
  customers: [/* items 51-1000 */],
  batch: 1
}
{
  _id: ObjectId("..."),
  bookId: "book2",
  customers: [/* items 1001-2000 */],
  batch: 2
}
// ...additional batches as needed
```

**Querying with outlier pattern:**

```javascript
// Most queries - fast, typical documents
const book = db.books.findOne({ _id: "book1" })
// Returns immediately, small document

// Outlier query - check flag first
const book = db.books.findOne({ _id: "book2" })
if (book.hasExtras) {
  // Load extras only when needed
  const extras = db.book_customers_extra.find({ bookId: "book2" }).toArray()
  book.allCustomers = [...book.customers, ...extras.flatMap(e => e.customers)]
}
```

**Implementation with threshold (example; tune per workload):**

```javascript
const CUSTOMER_THRESHOLD = 50

// Adding a customer to a book
async function addCustomer(bookId, customerId) {
  const book = await db.books.findOne({ _id: bookId })

  if (book.customers.length < CUSTOMER_THRESHOLD) {
    // Normal case - add to embedded array
    await db.books.updateOne(
      { _id: bookId },
      {
        $push: { customers: customerId },
        $inc: { customerCount: 1 }
      }
    )
  } else {
    // Outlier case - add to overflow collection
    await db.book_customers_extra.updateOne(
      { bookId: bookId, count: { $lt: 1000 } },  // Example batch limit
      {
        $push: { customers: customerId },
        $inc: { count: 1 },
        $setOnInsert: { bookId: bookId, batch: nextBatch }
      },
      { upsert: true }
    )
    await db.books.updateOne(
      { _id: bookId },
      {
        $set: { hasExtras: true },
        $inc: { customerCount: 1 }
      }
    )
  }
}
```

**Index strategy:**

```javascript
// Index on main collection - only 50 entries per outlier doc
db.books.createIndex({ "customers": 1 })

// Index on overflow collection
db.book_customers_extra.createIndex({ bookId: 1 })
db.book_customers_extra.createIndex({ customers: 1 })
```

**When to use outlier pattern:**

| Scenario | What to measure | Example |
|----------|-----------------|---------|
| Book customers | Array-size distribution and long tail | Bestsellers vs. typical books |
| Social followers | Growth rate and read-path impact | Celebrities vs. regular users |
| Product reviews | Index fan-out and read locality | Viral products vs. typical |
| Event attendees | Outlier frequency vs. implementation complexity | Major events vs. small meetups |

**When NOT to use this pattern:**

- **Uniform distribution**: If all documents have similar array sizes, no outliers to isolate.
- **Always need full data**: If you always display all 50,000 customers, pattern doesn't help.
- **Write-heavy outliers**: Complex update logic may not be worth the read optimization.
- **Small outliers**: If outliers are 200 vs typical 50, just use larger threshold.

## Verify with

```javascript
// Find outlier documents
db.books.aggregate([
  { $project: {
    title: 1,
    customerCount: { $size: { $ifNull: ["$customers", []] } }
  }},
  { $sort: { customerCount: -1 } },
  { $limit: 20 }
])

// Calculate distribution
db.books.aggregate([
  { $project: { count: { $size: { $ifNull: ["$customers", []] } } } },
  { $bucket: {
    groupBy: "$count",
    boundaries: [0, 50, 100, 500, 1000, 10000, 100000],
    default: "100000+",
    output: { count: { $sum: 1 } }
  }}
])
// Look for a long-tail distribution where a small subset is far above median/p95

// Check index sizes
db.books.stats().indexSizes
// Large multikey index suggests outliers are bloating it
```

Reference: [Outlier Pattern](https://mongodb.com/docs/manual/data-modeling/design-patterns/group-data/outlier-pattern/)
