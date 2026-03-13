---
title: Define Validation Rules with JSON Schema
impact: MEDIUM
impactDescription: "Human-readable validation that prevents invalid writes at insert and update time"
tags: schema, validation, json-schema, data-integrity, data-quality
---

## Define Validation Rules with JSON Schema

**Use JSON Schema for document validation—it's readable, maintainable, and catches data quality issues before they corrupt your database.** JSON Schema provides clear syntax for types, required fields, patterns, and nested structures that both developers and tools can understand.

**Incorrect (no validation, data corruption):**

```javascript
// No schema validation - anything goes
db.products.insertOne({ price: "free" })      // String instead of number
db.products.insertOne({ price: -100 })        // Negative price
db.products.insertOne({ name: "" })           // Empty name
db.products.insertOne({ category: "xyz123" }) // Invalid category

// Later in your application:
const total = products.reduce((sum, p) => sum + p.price, 0)
// NaN! Because "free" + 100 = NaN
// Bug discovered months later, data already corrupted
```

**Correct (JSON Schema catches errors at insert):**

```javascript
db.createCollection("products", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["name", "price", "category"],
      properties: {
        name: { bsonType: "string", minLength: 1 },
        price: { bsonType: "double", minimum: 0 },
        category: { enum: ["electronics", "clothing", "food"] }
      }
    }
  }
})

db.products.insertOne({ price: "free" })
// Error: "price" must be double, got string
// Data quality enforced at database level!
```

**Basic JSON Schema structure:**

```javascript
db.createCollection("products", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      title: "Product Validation",
      description: "Enforces product data quality",
      required: ["name", "price", "category"],
      properties: {
        name: {
          bsonType: "string",
          minLength: 1,
          maxLength: 200,
          description: "Product name, 1-200 characters"
        },
        price: {
          bsonType: "double",
          minimum: 0,
          description: "Price must be non-negative"
        },
        category: {
          enum: ["electronics", "clothing", "food", "other"],
          description: "Must be valid category"
        },
        sku: {
          bsonType: "string",
          pattern: "^[A-Z]{3}-[0-9]{6}$",
          description: "Format: ABC-123456"
        }
      }
    }
  }
})
```

**BSON types available:**

| bsonType | JavaScript Equivalent | Example |
|----------|----------------------|---------|
| `"string"` | String | `"hello"` |
| `"int"` | 32-bit integer | `42` |
| `"long"` | 64-bit integer | `NumberLong(42)` |
| `"double"` | Floating point | `3.14` |
| `"decimal"` | 128-bit decimal | `NumberDecimal("3.14")` |
| `"bool"` | Boolean | `true` |
| `"date"` | Date | `ISODate("2024-01-15")` |
| `"objectId"` | ObjectId | `ObjectId("...")` |
| `"array"` | Array | `[1, 2, 3]` |
| `"object"` | Embedded document | `{ a: 1 }` |
| `"null"` | Null | `null` |

**Validating nested documents:**

```javascript
{
  $jsonSchema: {
    properties: {
      address: {
        bsonType: "object",
        required: ["city", "country"],
        properties: {
          street: { bsonType: "string" },
          city: { bsonType: "string", minLength: 1 },
          country: {
            bsonType: "string",
            enum: ["US", "CA", "UK", "DE", "FR"]
          },
          zip: {
            bsonType: "string",
            pattern: "^[0-9]{5}(-[0-9]{4})?$"
          }
        },
        additionalProperties: false  // Reject unknown fields
      }
    }
  }
}
```

**Validating arrays:**

```javascript
{
  $jsonSchema: {
    properties: {
      tags: {
        bsonType: "array",
        minItems: 1,
        maxItems: 20,
        uniqueItems: true,
        items: {
          bsonType: "string",
          minLength: 2,
          maxLength: 30
        },
        description: "1-20 unique tags"
      },
      variants: {
        bsonType: "array",
        items: {
          bsonType: "object",
          required: ["size", "color"],
          properties: {
            size: { enum: ["XS", "S", "M", "L", "XL"] },
            color: { bsonType: "string" },
            stock: { bsonType: "int", minimum: 0 }
          }
        }
      }
    }
  }
}
```

**Conditional validation:**

```javascript
// Different rules based on document type
{
  $jsonSchema: {
    properties: {
      type: { enum: ["physical", "digital"] }
    },
    oneOf: [
      {
        properties: {
          type: { enum: ["physical"] },
          weight: { bsonType: "double", minimum: 0 },
          dimensions: { bsonType: "object" }
        },
        required: ["weight", "dimensions"]
      },
      {
        properties: {
          type: { enum: ["digital"] },
          downloadUrl: { bsonType: "string" },
          fileSize: { bsonType: "int" }
        },
        required: ["downloadUrl"]
      }
    ]
  }
}
```

**Combining with query operators:**

```javascript
// JSON Schema + MongoDB query operators
{
  validator: {
    $and: [
      { $jsonSchema: {
        required: ["price"],
        properties: {
          price: { bsonType: "double" }
        }
      }},
      // Query operator validation
      { price: { $gte: 0 } },
      { $expr: { $lte: ["$salePrice", "$price"] } }
    ]
  }
}
```

**Error messages:**

```javascript
// Insert invalid document
db.products.insertOne({ name: "", price: -5 })

// Error shows which validation failed:
// WriteError: Document failed validation
// - name: minLength 1, actual 0
// - price: minimum 0, actual -5
```

**When NOT to use JSON Schema:**

- **Polymorphic collections**: Event logs with varied structures may need looser validation.
- **Schema-less by design**: Some applications intentionally allow arbitrary fields.
- **Very complex cross-field logic**: Use query operators or application validation instead.

## Verify with

```javascript
// View existing validation rules
db.getCollectionInfos({ name: "products" })[0].options.validator

// Test validation without inserting
db.runCommand({
  insert: "products",
  documents: [{ name: "Test", price: -1 }],
  bypassDocumentValidation: false
})
// Returns error without modifying collection

// Find documents that would fail validation
// (useful when adding validation to existing collection)
db.products.find({
  $nor: [{
    $and: [
      { name: { $type: "string" } },
      { price: { $type: "number", $gte: 0 } }
    ]
  }]
})
```

Reference: [JSON Schema Validation](https://mongodb.com/docs/manual/core/schema-validation/specify-json-schema/)
