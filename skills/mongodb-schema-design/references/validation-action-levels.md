---
title: Choose Validation Level and Action Appropriately
impact: MEDIUM
impactDescription: "Enables safe schema migrations, prevents production outages during validation rollout"
tags: schema, validation, migration, validation-level, validation-action
---

## Choose Validation Level and Action Appropriately

**MongoDB's validation levels and actions let you roll out schema validation safely.** Using the wrong settings can either block legitimate operations or silently allow invalid data. Choose based on your migration state and data quality requirements.

**Incorrect (strict validation on existing data):**

```javascript
// Adding strict validation to collection with legacy data
db.runCommand({
  collMod: "users",
  validator: {
    $jsonSchema: {
      required: ["email", "name"],
      properties: {
        email: { bsonType: "string", pattern: "^.+@.+$" }
      }
    }
  },
  validationLevel: "strict",   // Validates ALL documents
  validationAction: "error"    // Rejects invalid
})
// Problem: 10,000 existing users without email field
// Result: All updates to those users fail!
// "Document failed validation" on every updateOne()
```

**Correct (gradual rollout with moderate level):**

```javascript
// Step 1: Start with warn + moderate to discover issues
db.runCommand({
  collMod: "users",
  validator: { $jsonSchema: { required: ["email", "name"] } },
  validationLevel: "moderate",  // Skip existing non-matching docs
  validationAction: "warn"      // Log but allow
})

// Step 2: Find and fix non-compliant documents
db.users.find({ email: { $exists: false } })
// Fix: Add missing emails

// Step 3: Only then switch to strict + error
db.runCommand({
  collMod: "users",
  validationLevel: "strict",
  validationAction: "error"
})
```

**Validation Levels:**

| Level | Behavior | Use When |
|-------|----------|----------|
| `strict` | Validate ALL inserts and updates | New collections, stable schemas |
| `moderate` | Only validate documents that already match | Adding validation to existing collections |

**Validation Actions:**

| Action | Behavior | Use When |
|--------|----------|----------|
| `error` | Reject invalid documents | Production, data integrity critical |
| `warn` | Allow but log warning | Discovery phase, monitoring |
| `errorAndLog` (v8.1+) | Reject AND log | Production with audit trail (plan downgrade path) |

**Migration workflow—adding validation to existing collection:**

```javascript
// Step 1: Start with warn to discover violations
db.runCommand({
  collMod: "users",
  validator: {
    $jsonSchema: {
      required: ["email", "name"],
      properties: {
        email: { bsonType: "string", pattern: "^.+@.+$" },
        name: { bsonType: "string", minLength: 1 }
      }
    }
  },
  validationLevel: "moderate",  // Don't fail existing invalid docs
  validationAction: "warn"      // Log but allow
})

// Step 2: Check logs for validation warnings
db.adminCommand({ getLog: "global" }).log.filter(
  l => l.includes("Document validation")
)

// Step 3: Query to find non-compliant documents
db.users.find({
  $or: [
    { email: { $not: { $type: "string" } } },
    { email: { $not: { $regex: /@/ } } },
    { name: { $exists: false } }
  ]
})

// Step 4: Fix non-compliant data
db.users.updateMany(
  { email: { $not: { $regex: /@/ } } },
  { $set: { email: "invalid@fixme.com", needsReview: true } }
)

// Step 5: Tighten to strict + error
db.runCommand({
  collMod: "users",
  validationLevel: "strict",
  validationAction: "error"
})
```

**When NOT to use strict + error:**

- **During active migration**: Use moderate + warn until data is cleaned.
- **Legacy systems integration**: External data may not conform.
- **Feature flag rollouts**: New fields may be optional initially.

## Verify with

```javascript
// Check current validation settings
const info = db.getCollectionInfos({ name: "users" })[0]
console.log("Level:", info.options.validationLevel)
console.log("Action:", info.options.validationAction)
console.log("Validator:", JSON.stringify(info.options.validator, null, 2))

// Count documents that would fail current validation
// (Run this BEFORE switching to strict)
const validator = info.options.validator
db.users.countDocuments({
  $nor: [validator]  // Documents NOT matching validator
})
// If count > 0, fix data before switching to strict
```

Reference: [Specify Validation Level](https://mongodb.com/docs/manual/core/schema-validation/specify-validation-level/)
