# Multikey Indexes and Array Queries

Use this when optimizing queries on array fields or dealing with multikey indexes.

### Array fields and multikey indexes

When you index a field containing arrays, MongoDB creates a **multikey index** (one entry per array element).

**Limitations:**

- Cannot cover queries in most cases (must read documents), though coverage is possible when the array field is excluded from the projection and $elemMatch is not used  
- Compound multikey restriction: at most **one** array field per compound index  
- Large arrays create many index entries (impacts write performance and index size)

**Use $elemMatch** for compound array queries to ensure conditions match the same array element.

## What are multikey indexes?

When you create an index on a field that contains an array value in any document, MongoDB creates a **multikey index**. One index entry is created for each array element.

```javascript
// Document
{ _id: 1, tags: ["mongodb", "database", "nosql"] }

// Index on tags creates 3 entries:
// "mongodb" → doc 1
// "database" → doc 1
// "nosql" → doc 1
```

## Querying arrays efficiently

### Equality match on array element

```javascript
// Find documents where tags contains "mongodb"
db.posts.find({ tags: "mongodb" })
```

**Index:** `{ tags: 1 }` enables IXSCAN

**Performance:** Efficient if tag is selective (few documents match)

### $in with arrays

```javascript
// Match any of several tags
db.posts.find({ tags: { $in: ["mongodb", "database"] } })
```

**Index:** `{ tags: 1 }` scans multiple index ranges efficiently

### $all (must contain all values)

```javascript
// Must have ALL specified tags
db.posts.find({ tags: { $all: ["mongodb", "database"] } })
```

**Index:** `{ tags: 1 }` scans for first tag, then filters results for second tag

**Performance note:** Still requires checking documents. Less efficient than single equality.

### Range queries on arrays

```javascript
// Array of numbers
db.sensors.find({ readings: { $gt: 100 } })
```

**Behavior:** Returns document if **any** array element satisfies condition

**Index:** `{ readings: 1 }` enables IXSCAN but may return more docs than expected

### $elemMatch for complex array conditions

```javascript
// items is array of objects
db.orders.find({
  items: {
    $elemMatch: { sku: "ABC123", quantity: { $gte: 5 } }
  }
})
```

**Index needed:** `{ "items.sku": 1, "items.quantity": 1 }`

**Behavior:** Ensures **same array element** satisfies all conditions (not just any element)

**Without $elemMatch:**

```javascript
// This matches different array elements!
db.orders.find({
  "items.sku": "ABC123",
  "items.quantity": { $gte: 5 }
})
```

May return documents where one item has sku="ABC123" and a *different* item has quantity\>=5.

## Compound multikey index restrictions

**Rule:** At most ONE array field per compound index.

**Allowed:**

```javascript
// tags is array, category is scalar
db.posts.createIndex({ tags: 1, category: 1 })  // Valid

// Neither field is array
db.posts.createIndex({ author: 1, category: 1 })  // Valid
```

**Not allowed:**

```javascript
// BOTH tags and keywords are arrays
db.posts.createIndex({ tags: 1, keywords: 1 })  // Error!
```

**Why:** MongoDB cannot determine which array element combinations to index.

**Workaround:** Create separate indexes:

- `{ tags: 1, category: 1 }` for queries filtering by tags  
- `{ keywords: 1, category: 1 }` for queries filtering by keywords

MongoDB will use the most appropriate index for each query.

## Array size considerations

Large arrays impact index size and write performance:

```javascript
// 1000-element array = 1000 index entries per document
{ _id: 1, tags: ["tag1", "tag2", ..., "tag1000"] }
```

**When arrays grow large:**

- Index size grows proportionally  
- Write operations update many index entries  
- Query selectivity decreases (many matches per tag)

**Strategies for large arrays:**

1. **Consider if you need to index it** \- Can you filter another way?  
2. **Partial index** \- Index only documents with reasonable array sizes:

```javascript
db.posts.createIndex(
  { tags: 1 },
  { partialFilterExpression: {
    $expr: { $lte: [{ $size: "$tags" }, 20] }
  }}
)
```

   Note: Use `$expr` with `$size` for range comparisons in partial filters.

   

3. **Separate collection** \- Move array to own collection with parent reference  
4. **Bucketing** \- Group related values instead of storing individually

## Multikey \+ compound index query patterns

### ESR still applies

For `{ tags: 1, date: 1 }` where tags is array:

**Efficient:**

```javascript
// Equality on array field first, then sort
db.posts.find({ tags: "mongodb" }).sort({ date: -1 })
```

**Less efficient:**

```javascript
// Range on array field first
db.posts.find({ tags: { $in: ["mongodb", "database"] } }).sort({ date: -1 })
```

May scan many index entries for tags before sorting by date.

### Prefix still matters

Index: `{ tags: 1, category: 1, date: 1 }`

**Can use index:**

- `{ tags: "X" }`  
- `{ tags: "X", category: "Y" }`  
- `{ tags: "X", category: "Y", date: {...} }`

**Cannot use index efficiently:**

- `{ category: "Y" }` \- missing prefix (tags)  
- `{ date: {...} }` \- missing prefix

## Avoiding unnecessary multikey indexes

**If you don't query array contents, don't index them:**

```javascript
// Document stores array but never queries it
{ _id: 1, history: [/* audit log, never queried */] }
```

Don't create index on `history` \- wastes space and slows writes.

**If you only query array existence/size:**

```javascript
// Only care if array exists and has elements
db.coll.find({ tags: { $exists: true, $ne: [] } })
```

May not benefit from multikey index. Consider partial index on specific values instead.

## Deduplication behavior

Multikey indexes automatically deduplicate results:

```javascript
{ _id: 1, tags: ["mongodb", "mongodb", "database"] }

// Query
db.posts.find({ tags: "mongodb" })

// Returns doc 1 only once, even though "mongodb" appears twice in array
```

MongoDB handles this automatically, but be aware it requires post-processing.

## Checking if index is multikey

```javascript
db.posts.getIndexes()
```

Look for `"multikey": true` in the index definition.

Alternatively:

```javascript
db.posts.find({ tags: "mongodb" }).explain("executionStats")
```

Check `"isMultiKey": true` in the winning plan.

## When to use multikey indexes

**Good use cases:**

- Small to moderate array sizes (\< 100 elements)  
- High query frequency on array contents  
- Selective array values (specific elements match few documents)  
- Tags, categories, multi-valued attributes

**Poor use cases:**

- Very large arrays (1000s of elements)  
- Low query frequency relative to write frequency  
- Non-selective values (most documents contain the value)  
- Arrays that grow unbounded

## Alternative: embedded document arrays

Instead of scalar array, use array of objects with specific fields:

```javascript
// Scalar array
{ tags: ["mongodb", "database", "nosql"] }

// Embedded documents
{ tags: [
    { name: "mongodb", category: "database" },
    { name: "nosql", category: "paradigm" }
]}
```

**Index:** `{ "tags.name": 1, "tags.category": 1 }`

**Benefit:** Can query multiple fields within same array element using $elemMatch

**Tradeoff:** More complex data model, but more expressive queries  