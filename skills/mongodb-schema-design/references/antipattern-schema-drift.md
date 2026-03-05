---
title: Prevent Schema Drift
impact: CRITICAL
impactDescription: "Prevents application errors and query failures from inconsistent schemas"
tags: schema, anti-pattern, validation, consistency, data-quality, atlas-suggestion
---

## Prevent Schema Drift

**Schema drift—when documents in the same collection have inconsistent structures—causes application errors and query inconsistencies.** MongoDB's flexibility is a feature, but undisciplined field additions lead to code that must handle many shapes. Use schema validation to prevent drift before it happens.

**Incorrect (uncontrolled schema drift):**

```javascript
// Over time, different versions of "user" documents accumulate
// Version 1 (2020)
{ _id: 1, name: "Alice", email: "alice@ex.com" }

// Version 2 (2021) - added phone
{ _id: 2, name: "Bob", email: "bob@ex.com", phone: "555-1234" }

// Version 3 (2022) - restructured name
{ _id: 3, firstName: "Carol", lastName: "Smith", email: "carol@ex.com" }

// Version 4 (2023) - email is now array
{ _id: 4, firstName: "Dave", lastName: "Jones", emails: ["dave@ex.com", "d@work.com"] }

// Application code becomes defensive nightmare
function getUserEmail(user) {
  if (user.email) return user.email
  if (user.emails) return user.emails[0]
  throw new Error("No email found")  // Crashes on some documents
}

// Queries fail silently
db.users.find({ email: "test@ex.com" })  // Misses users with emails[] array
```

**Correct (controlled schema with validation):**

```javascript
// Define and enforce consistent schema
db.createCollection("users", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["email", "profile"],
      properties: {
        email: {
          bsonType: "string",
          pattern: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
        },
        profile: {
          bsonType: "object",
          required: ["firstName", "lastName"],
          properties: {
            firstName: { bsonType: "string", minLength: 1 },
            lastName: { bsonType: "string", minLength: 1 }
          }
        },
        phones: {
          bsonType: "array",
          items: { bsonType: "string" }
        },
        schemaVersion: {
          bsonType: "int",
          enum: [1]  // Current version
        }
      }
    }
  },
  validationLevel: "strict",
  validationAction: "error"
})

// All documents now have consistent structure
{
  _id: 1,
  email: "alice@example.com",
  profile: { firstName: "Alice", lastName: "Smith" },
  phones: ["555-1234"],
  schemaVersion: 1
}
```

**Schema versioning for migrations:**

```javascript
// Include version in documents
{
  _id: 1,
  schemaVersion: 2,
  email: "alice@example.com",
  profile: { firstName: "Alice", lastName: "Smith" }
}

// Migration script for version upgrades
db.users.find({ schemaVersion: 1 }).forEach(user => {
  db.users.updateOne(
    { _id: user._id },
    {
      $set: {
        profile: {
          firstName: user.name.split(" ")[0],
          lastName: user.name.split(" ").slice(1).join(" ")
        },
        schemaVersion: 2
      },
      $unset: { name: "" }
    }
  )
})

// Validation accepts both during migration
db.runCommand({
  collMod: "users",
  validator: {
    $jsonSchema: {
      properties: {
        schemaVersion: { enum: [1, 2] }  // Accept both during migration
      }
    }
  },
  validationLevel: "moderate"  // Don't block existing invalid docs
})
```

**Detecting existing schema drift:**

```javascript
// Find all unique field combinations
db.users.aggregate([
  { $project: { fields: { $objectToArray: "$$ROOT" } } },
  { $project: { keys: "$fields.k" } },
  { $group: { _id: "$keys", count: { $sum: 1 } } },
  { $sort: { count: -1 } }
])
// Multiple results = schema drift exists

// Find documents missing required fields
db.users.find({
  $or: [
    { email: { $exists: false } },
    { profile: { $exists: false } },
    { "profile.firstName": { $exists: false } }
  ]
})

// Find documents with wrong types
db.users.find({
  $or: [
    { email: { $not: { $type: "string" } } },
    { phones: { $exists: true, $not: { $type: "array" } } }
  ]
})
```

**Common causes of schema drift:**

| Cause | Prevention |
|-------|------------|
| Feature additions without migration | Use schema validation, version fields |
| Multiple app versions writing | Coordinate deployments, use validation |
| Direct database edits | Restrict write access, audit logs |
| Import from external sources | Validate before insert, ETL pipeline |
| Optional fields proliferating | Define allowed fields in schema |

**When NOT to strictly enforce schema:**

- **Truly polymorphic data**: Event logs with different event types may need flexible schemas.
- **Early prototyping**: Skip validation during exploration, add before production.
- **User-defined fields**: Some applications allow custom metadata fields.

## Verify with

```javascript
// Check if validation exists
const collInfo = db.getCollectionInfos({ name: "users" })[0]
const validator = collInfo?.options?.validator
// Missing validator means schema drift risk is higher

// Primary check: find documents that do NOT match current validator
if (validator) {
  db.users.find({ $nor: [validator] }).limit(20)
  db.users.countDocuments({ $nor: [validator] })
}

// Optional heavy check for maintenance windows:
// validate can be slow and can take an exclusive lock on the collection.
db.runCommand({
  validate: "users",
  full: true
})
```

Reference: [Schema Validation](https://mongodb.com/docs/manual/core/schema-validation/)
