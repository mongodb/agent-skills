# Covered Queries

Use this when a query can be answered entirely from an index without reading documents.

## What is a covered query?

A covered query retrieves all requested data directly from the index, never accessing the actual documents. This is extremely fast because:
- Index data is more compact than documents
- Indexes are often cached in memory
- Eliminates disk I/O for document reads

## Requirements for a covered query

All of the following must be true:

1. **All query fields** are in the index
2. **All returned fields** are in the index (includes sort fields)
3. **No fields excluded from result** are in index (can't use `{field: 0}` projection)
4. **No array fields** are indexed (multikey indexes prevent covering)
5. **No sub-document fields** unless the exact sub-document path is indexed

## Building a covered query

**Step 1:** Identify your query pattern
```javascript
db.products.find(
  { category: "electronics", inStock: true },
  { category: 1, inStock: 1, price: 1, _id: 0 }
).sort({ price: 1 })
```

**Step 2:** Create index with all accessed fields

Following ESR (Equality-Sort-Range):
```javascript
db.products.createIndex({
  category: 1,    // Equality
  inStock: 1,     // Equality
  price: 1        // Sort
})
```

**Step 3:** Project only indexed fields
- Include indexed fields in projection
- **Must exclude _id** unless _id is in the index (use `_id: 0`)
- Don't request any fields not in the index

**Step 4:** Verify with explain
```javascript
db.products.find(...).explain("executionStats")
```

Look for:
- `"stage": "IXSCAN"`
- `"totalDocsExamined": 0` ← **This confirms covering**
- `"totalKeysExamined": <n>` (should be close to `nReturned`)

## Common mistakes that break covering

### Including _id without indexing it
```javascript
// NOT COVERED - _id not in index but included in result
db.products.find(
  { category: "electronics" },
  { category: 1, price: 1 }  // _id included by default!
).hint({ category: 1, price: 1 })
```

**Fix:** Explicitly exclude _id
```javascript
db.products.find(
  { category: "electronics" },
  { category: 1, price: 1, _id: 0 }  // Now covered
)
```

### Requesting non-indexed fields
```javascript
// NOT COVERED - description not in index
db.products.find(
  { category: "electronics" },
  { category: 1, price: 1, description: 1, _id: 0 }
)
```

**Fix:** Only project indexed fields, or add description to index

### Array fields (multikey indexes)
```javascript
// NOT COVERED - tags is an array, creating multikey index
db.products.createIndex({ tags: 1, price: 1 })
db.products.find(
  { tags: "sale" },
  { tags: 1, price: 1, _id: 0 }
)
```

Multikey indexes cannot cover queries. **No fix** - this is a MongoDB limitation. Must read documents.

### Querying embedded documents without exact path
```javascript
// Index on embedded field
db.products.createIndex({ "specs.weight": 1, price: 1 })

// NOT COVERED - asking for entire specs object
db.products.find(
  { "specs.weight": { $lt: 10 } },
  { specs: 1, price: 1, _id: 0 }
)
```

**Fix:** Project only the specific embedded field
```javascript
db.products.find(
  { "specs.weight": { $lt: 10 } },
  { "specs.weight": 1, price: 1, _id: 0 }  // Now covered
)
```

## When covering is most valuable

- **High-traffic queries** that run frequently
- **Queries on large documents** where reading full document is expensive
- **Queries with selective indexes** that return small result sets
- **Analytical queries** that aggregate over many documents

## When covering doesn't help much

- **Query returns most/all documents** - will read them anyway
- **Documents are small** - reading from pages is already fast
- **Index is not selective** - `totalKeysExamined >> nReturned` means scanning many index entries
- **Working set fits in cache** - documents already in memory, no disk I/O saved

## Covered queries with compound indexes

The same index can cover multiple query patterns:

```javascript
db.orders.createIndex({ status: 1, region: 1, date: 1, amount: 1 })
```

**Covered patterns:**
```javascript
// 1. Equality on status, project status + region
db.orders.find({ status: "shipped" }, { status: 1, region: 1, _id: 0 })

// 2. Equality on status + region, sort by date
db.orders.find(
  { status: "shipped", region: "US" },
  { status: 1, region: 1, date: 1, _id: 0 }
).sort({ date: 1 })

// 3. Equality + range, project all indexed fields
db.orders.find(
  { status: "shipped", date: { $gte: ISODate("2024-01-01") } },
  { status: 1, region: 1, date: 1, amount: 1, _id: 0 }
)
```

**Not covered** (requires fields not in index):
```javascript
// Requests customer_id - not in index
db.orders.find(
  { status: "shipped" },
  { status: 1, customer_id: 1, _id: 0 }
)
```

## Verification checklist

When aiming for covered query:

- [ ] All filter fields are in the index
- [ ] All projected fields are in the index
- [ ] `_id: 0` in projection (unless _id is in index)
- [ ] No array fields in index
- [ ] Embedded document projections use exact paths from index
- [ ] `explain()` shows `totalDocsExamined: 0`

**Remember:** Covered queries are an optimization, not a requirement. Focus on covering your hottest, most frequent query patterns.
