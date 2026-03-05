---
title: Use Attribute Pattern for Sparse or Variable Fields
impact: MEDIUM
impactDescription: "Reduces sparse indexes and enables efficient search across many optional fields"
tags: schema, patterns, attribute, sparse-fields, indexing, flexible-schema
---

## Use Attribute Pattern for Sparse or Variable Fields

**If documents have many optional fields, move them into a key-value array.** This avoids dozens of sparse indexes and lets you query across attributes with a single multikey index.

**Incorrect (many optional fields and indexes):**

```javascript
// Many optional fields - most are null or missing
{
  _id: 1,
  name: "Bottle",
  color: "red",
  size: "M",
  material: "glass",
  // 20+ other optional fields
}

// Index explosion
// db.items.createIndex({ color: 1 })
// db.items.createIndex({ size: 1 })
// db.items.createIndex({ material: 1 })
```

**Correct (attribute pattern):**

```javascript
// Store optional fields as key-value pairs
{
  _id: 1,
  name: "Bottle",
  attributes: [
    { k: "color", v: "red" },
    { k: "size", v: "M" },
    { k: "material", v: "glass" }
  ]
}

// Single multikey index for all attributes

db.items.createIndex({ "attributes.k": 1, "attributes.v": 1 })

// Query for color = red

db.items.find({
  attributes: { $elemMatch: { k: "color", v: "red" } }
})
```

**When NOT to use this pattern:**

- **Fixed schema**: If fields are stable and always present.
- **Type-specific validation**: If each field needs strict schema rules.
- **Single-field queries only**: A normal field may be simpler and faster.
- **Atlas Search workloads**: The `{ k, v }` key-value structure cannot be mapped as
  named fields in Atlas Search indexes. If you need full-text search on attribute
  values by key name, use static named fields instead.

## Verify with

```javascript
// Ensure queries use the multikey index

db.items.find({
  attributes: { $elemMatch: { k: "material", v: "glass" } }
}).explain("executionStats")
```

Reference: [Attribute Pattern](https://mongodb.com/docs/manual/data-modeling/design-patterns/group-data/attribute-pattern/)
