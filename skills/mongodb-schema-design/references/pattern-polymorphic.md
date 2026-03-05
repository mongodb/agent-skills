---
title: Use Polymorphic Pattern for Heterogeneous Documents
impact: MEDIUM
impactDescription: "Keeps related entities in one collection while preserving type-specific fields"
tags: schema, patterns, polymorphic, discriminator, flexible-schema, indexing, single-collection
---

## Use Polymorphic Pattern for Heterogeneous Documents

**Store related but different document shapes in one collection with a type discriminator.** This keeps shared queries and indexes simple while allowing type-specific fields. Common use cases: product catalogs with different product types, content management systems, event stores, and any domain with inheritance.

**Incorrect (separate collections per subtype):**

```javascript
// Separate collections for each product type
db.products_books.find({})
db.products_electronics.find({})
db.products_clothing.find({})

// Problems:
// 1. Queries across all products need multiple calls or $unionWith
// 2. Shared indexes must be duplicated
// 3. Adding new types requires new collections
// 4. Application code branches on collection names

// Querying all products is painful:
const allProducts = [
  ...db.products_books.find({ price: { $lt: 50 } }).toArray(),
  ...db.products_electronics.find({ price: { $lt: 50 } }).toArray(),
  ...db.products_clothing.find({ price: { $lt: 50 } }).toArray()
]
```

**Correct (single collection with discriminator):**

```javascript
// Single collection with type field as discriminator
// All products share common fields, type-specific fields vary

// Book
{
  _id: ObjectId("..."),
  type: "book",
  name: "MongoDB: The Definitive Guide",
  price: 49.99,
  inStock: true,
  // Book-specific fields
  author: "Shannon Bradshaw",
  isbn: "978-1491954461",
  pages: 514
}

// Electronics
{
  _id: ObjectId("..."),
  type: "electronics",
  name: "Wireless Headphones",
  price: 79.99,
  inStock: true,
  // Electronics-specific fields
  brand: "Sony",
  wattage: 20,
  batteryHours: 30,
  warranty: "2 years"
}

// Clothing
{
  _id: ObjectId("..."),
  type: "clothing",
  name: "Running Shoes",
  price: 129.99,
  inStock: false,
  // Clothing-specific fields
  size: ["S", "M", "L", "XL"],
  color: "blue",
  material: "synthetic"
}

// Query all products easily:
db.products.find({ price: { $lt: 100 } })

// Query specific type:
db.products.find({ type: "book", author: "Shannon Bradshaw" })
```

**Design the discriminator field:**

```javascript
// TIP 1: Use a clear, consistent discriminator field name
// Common choices: type, kind, _type, docType, category

// GOOD: Clear discriminator
{ type: "book", ... }
{ type: "electronics", ... }

// BAD: Ambiguous or varying field
{ category: "book", ... }      // "category" might mean product category
{ productType: "electronic", ...}  // Different field name!

// TIP 2: Use lowercase, singular values
// GOOD
{ type: "book" }
{ type: "user" }

// AVOID
{ type: "BOOK" }      // Inconsistent casing
{ type: "books" }     // Plural
{ type: "Book" }      // Title case

// TIP 3: Store additional type metadata if needed
{
  type: "book",
  typeVersion: 2,     // Schema version for this type
  ...
}
```

**Index strategies for polymorphic collections:**

```javascript
// Strategy 1: Compound index with type first
// Best for: Queries that always filter by type
db.products.createIndex({ type: 1, price: 1 })
db.products.createIndex({ type: 1, name: 1 })

// Query uses index efficiently:
db.products.find({ type: "book", price: { $lt: 50 } })

// Strategy 2: Compound index with type second
// Best for: Queries that rarely filter by type
db.products.createIndex({ price: 1, type: 1 })

// Query across all types uses index:
db.products.find({ price: { $lt: 50 } })

// Strategy 3: Partial indexes for type-specific fields
// Best for: Fields that only exist on some types
db.products.createIndex(
  { author: 1 },
  { partialFilterExpression: { type: "book" } }
)

db.products.createIndex(
  { brand: 1, wattage: 1 },
  { partialFilterExpression: { type: "electronics" } }
)

// Strategy 4: Wildcard index for varying fields
// Best for: Many type-specific fields, ad-hoc queries
db.products.createIndex({ "specs.$**": 1 })

// Documents store type-specific data in specs:
{ type: "book", specs: { author: "...", isbn: "..." } }
{ type: "electronics", specs: { brand: "...", wattage: 20 } }
```

**Query patterns across types:**

```javascript
// Pattern 1: Query all types with shared fields
db.products.find({ price: { $lt: 100 }, inStock: true })
  .sort({ price: 1 })

// Pattern 2: Query specific type with type-specific fields
db.products.find({
  type: "book",
  pages: { $gt: 300 },
  author: /bradshaw/i
})

// Pattern 3: Aggregation across types with type-specific handling
db.products.aggregate([
  { $match: { inStock: true } },
  { $group: {
      _id: "$type",
      count: { $sum: 1 },
      avgPrice: { $avg: "$price" }
    }
  }
])

// Pattern 4: Faceted search with type breakdown
db.products.aggregate([
  { $match: { price: { $lt: 100 } } },
  { $facet: {
      byType: [{ $group: { _id: "$type", count: { $sum: 1 } } }],
      priceRanges: [
        { $bucket: {
            groupBy: "$price",
            boundaries: [0, 25, 50, 100],
            default: "100+"
          }
        }
      ]
    }
  }
])
```

**Validation per type:**

```javascript
// Use JSON Schema with discriminator-based validation
db.runCommand({
  collMod: "products",
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["type", "name", "price"],
      properties: {
        type: { enum: ["book", "electronics", "clothing"] },
        name: { bsonType: "string" },
        price: { bsonType: "number", minimum: 0 }
      },
      oneOf: [
        {
          properties: { type: { enum: ["book"] } },
          required: ["author", "isbn"]
        },
        {
          properties: { type: { enum: ["electronics"] } },
          required: ["brand"]
        },
        {
          properties: { type: { enum: ["clothing"] } },
          required: ["size", "color"]
        }
      ]
    }
  },
  validationLevel: "moderate"
})
```

**Adding new types:**

```javascript
// Polymorphic pattern makes adding types easy
// No schema migration needed - just insert new documents

// Add a new "furniture" type
db.products.insertOne({
  type: "furniture",
  name: "Standing Desk",
  price: 599.99,
  inStock: true,
  // Furniture-specific fields
  dimensions: { width: 60, depth: 30, height: 48 },
  material: "bamboo",
  assemblyRequired: true
})

// Add partial index for furniture-specific queries
db.products.createIndex(
  { "dimensions.width": 1 },
  { partialFilterExpression: { type: "furniture" } }
)

// Update validation to include new type
// (if using strict validation)
```

**When NOT to use polymorphic pattern:**

- **Completely different access patterns**: If each type is queried independently with no cross-type queries, separate collections may be cleaner.
- **Conflicting index requirements**: If types need many different indexes, the index overhead may outweigh benefits.
- **Strict type separation required**: Regulatory or security requirements may mandate separate collections.
- **Vastly different document sizes**: If one type has 100-byte docs and another has 100KB docs, working set suffers.
- **Type-specific sharding needs**: Different types may need different shard keys.

## Verify with

```javascript
// Analyze polymorphic collection health
function analyzePolymorphicCollection(collectionName, typeField = "type") {
  const coll = db[collectionName]

  // Get type distribution
  const typeStats = coll.aggregate([
    { $group: {
        _id: `$${typeField}`,
        count: { $sum: 1 },
        avgSize: { $avg: { $bsonSize: "$$ROOT" } }
      }
    },
    { $sort: { count: -1 } }
  ]).toArray()

  print(`\n=== Polymorphic Analysis: ${collectionName} ===`)
  print(`Discriminator field: ${typeField}`)
  print(`\nType distribution:`)

  let totalDocs = 0
  typeStats.forEach(t => {
    totalDocs += t.count
    print(`  ${t._id || "(null)"}: ${t.count.toLocaleString()} docs, avg ${t.avgSize?.toFixed(0) || "?"} bytes`)
  })
  print(`  TOTAL: ${totalDocs.toLocaleString()} documents`)

  // Check for missing type field
  const missingType = coll.countDocuments({ [typeField]: { $exists: false } })
  if (missingType > 0) {
    print(`\nWARNING: ${missingType} documents missing '${typeField}' field`)
  }

  // Analyze indexes
  print(`\nIndexes:`)
  const indexes = coll.getIndexes()
  indexes.forEach(idx => {
    const hasType = Object.keys(idx.key).includes(typeField)
    const isPartial = !!idx.partialFilterExpression
    print(`  ${idx.name}: ${JSON.stringify(idx.key)}${hasType ? " [includes type]" : ""}${isPartial ? " [partial]" : ""}`)
  })

  // Suggest missing indexes
  const hasTypeIndex = indexes.some(idx => Object.keys(idx.key)[0] === typeField)
  if (!hasTypeIndex && typeStats.length > 3) {
    print(`\nSUGGESTION: Consider index on { ${typeField}: 1 } for type-filtered queries`)
  }
}

// Usage
analyzePolymorphicCollection("products", "type")
```

Reference: [Polymorphic Schema Pattern](https://mongodb.com/docs/manual/data-modeling/design-patterns/polymorphic-data/polymorphic-schema-pattern/)
