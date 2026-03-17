---
title: Model One-to-Many Relationships with References
impact: HIGH
impactDescription: "Handles unbounded growth, avoids 16MB document-limit write failures, and enables independent queries"
tags: schema, relationships, one-to-many, referencing, scalability
---

## Model One-to-Many Relationships with References

**Use references when the "many" side is unbounded or frequently accessed independently.** Store the parent's ID in each child document. This pattern prevents documents from exceeding 16MB and allows efficient queries from either direction.

**Incorrect (embedding unbounded arrays):**

Embedding all books inside a publisher document (e.g. 10,000+ books × ~1KB each = 10MB+) means adding one book rewrites the entire large document, and the document eventually exceeds the 16MB limit.

**Correct (reference in child documents):**

Keep the publisher document simple and fixed-size (name, founded, location, plus a denormalized `bookCount` for display). Each book document stores a `publisherId` reference. Create an index on `{ publisherId: 1 }` for efficient lookups. Query books by publisher with a simple `find` on the indexed field.

**Querying referenced data:**

```javascript
// Get publisher with book count (no join needed)
db.publishers.findOne({ _id: "oreilly" })

// Get all books for publisher (indexed query)
db.books.find({ publisherId: "oreilly" })

// Get books with publisher details ($lookup when needed)
db.books.aggregate([
  { $match: { publisherId: "oreilly" } },
  { $lookup: {
    from: "publishers",
    localField: "publisherId",
    foreignField: "_id",
    as: "publisher"
  }},
  { $unwind: "$publisher" }
])
```

**Alternative (hybrid with subset):**

Embed a bounded subset (e.g. top 5 featured books with `_id`, `title`, `isbn`) directly in the publisher document for display without `$lookup`. Provide a “View all books” path that queries the books collection separately.

**Updating denormalized counts:**

```javascript
// When adding a new book
db.books.insertOne({
  title: "New MongoDB Book",
  publisherId: "oreilly"
})

// Update publisher's count
db.publishers.updateOne(
  { _id: "oreilly" },
  { $inc: { bookCount: 1 } }
)

// Or use Change Streams for async updates
```

**When to use One-to-Many references:**

| Scenario | Example | Why Reference |
|----------|---------|---------------|
| Unbounded children | Publisher → Books | Could have 100,000+ books |
| Large child documents | User → Orders | Orders have line items, addresses |
| Independent queries | Department → Employees | Query employees directly |
| Different lifecycles | Author → Articles | Archive articles separately |

**When NOT to use this pattern:**

- **Bounded small arrays**: User's 3 addresses should be embedded, not referenced.
- **Always accessed together**: Order line items should be embedded in order.
- **No independent queries**: If you never query children without parent, consider embedding.

## Verify with

```javascript
// Check for missing indexes on reference fields
db.books.getIndexes()
// Must have index on publisherId for efficient lookups

// Find reference fields without indexes
db.books.aggregate([
  { $sample: { size: 1000 } },
  { $project: { publisherId: 1 } }
])
// If this is slow, index is missing

// Check for orphaned references
db.books.aggregate([
  { $lookup: {
    from: "publishers",
    localField: "publisherId",
    foreignField: "_id",
    as: "pub"
  }},
  { $match: { pub: { $size: 0 } } },
  { $count: "orphanedBooks" }
])
// Orphans indicate data integrity issues
```

Reference: [Model One-to-Many Relationships with Document References](https://mongodb.com/docs/manual/tutorial/model-referenced-one-to-many-relationships-between-documents/)
