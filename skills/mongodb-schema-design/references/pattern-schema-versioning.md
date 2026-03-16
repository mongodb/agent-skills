---
title: Use Schema Versioning for Safe Evolution
impact: MEDIUM
impactDescription: "Avoids breaking reads/writes during migrations and enables online backfills"
tags: schema, patterns, versioning, migration, evolution, backward-compatibility, backfill
---

## Use Schema Versioning for Safe Evolution

**Schema changes are inevitable.** Add a `schemaVersion` field so your application can read old and new documents simultaneously while you migrate data in-place. This prevents production outages caused by suddenly missing, renamed, or restructured fields. Online migrations keep your application running during schema evolution.

**Incorrect (breaking change without versioning):**

Changing a field’s type without versioning (e.g. `address` from a string to an object) breaks old documents: code expecting `address.city` gets `undefined` on v1 documents, the application crashes or returns wrong data, deployment is all-or-nothing, and rollback is dangerous if new-shape documents have already been written.

**Correct (versioned documents with migration path):**

Add a `schemaVersion` field to every document. Version 1 documents keep the old shape (e.g. `address` as a string); version 2 documents use the new shape (e.g. `address` as an object with `street`, `city`, `zip`). Application code checks `schemaVersion` and handles both formats — for example, parsing the v1 string to extract city when needed. This allows old and new documents to coexist, new code to deploy before data migration, gradual migration during low-traffic periods, and easy rollback since old code still reads v1 documents.

**Online migration strategies:**

```javascript
// Strategy 1: Background batch migration
// Best for: Large collections, can tolerate mixed versions temporarily

function migrateToV2(batchSize = 1000) {
  let migrated = 0
  let cursor = db.users.find({ schemaVersion: { $lt: 2 } }).limit(batchSize)

  for (const doc of cursor) {
    // Transform v1 → v2
    const parsed = parseAddressString(doc.address)

    db.users.updateOne(
      { _id: doc._id, schemaVersion: { $lt: 2 } },  // Prevent double-migration
      {
        $set: {
          schemaVersion: 2,
          address: {
            street: parsed.street,
            city: parsed.city,
            zip: parsed.zip
          }
        }
      }
    )
    migrated++
  }

  print(`Migrated ${migrated} documents`)
  return migrated
}

// Run in batches during off-peak hours
while (migrateToV2(1000) > 0) {
  sleep(100)  // Throttle to reduce load
}


// Strategy 2: Aggregation pipeline update (MongoDB 4.2+)
// Best for: Simple transformations, moderate collection sizes

db.users.updateMany(
  { schemaVersion: { $lt: 2 } },
  [
    {
      $set: {
        schemaVersion: 2,
        address: {
          $cond: {
            if: { $eq: [{ $type: "$address" }, "string"] },
            then: {
              // Parse string address into object
              street: { $arrayElemAt: [{ $split: ["$address", ", "] }, 0] },
              city: { $arrayElemAt: [{ $split: ["$address", ", "] }, 1] },
              zip: { $arrayElemAt: [{ $split: ["$address", ", "] }, 2] }
            },
            else: "$address"  // Already an object
          }
        }
      }
    }
  ]
)


// Strategy 3: Read-time migration (lazy migration)
// Best for: Low-traffic documents, immediate consistency needed

function getUser(userId) {
  const user = db.users.findOne({ _id: userId })

  if (user && user.schemaVersion < 2) {
    // Migrate on read
    const migrated = migrateUserToV2(user)
    db.users.replaceOne({ _id: userId }, migrated)
    return migrated
  }

  return user
}
```

**Handling complex migrations:**

```javascript
// Multiple version jumps: v1 → v2 → v3
// Define transformation functions for each step

const migrations = {
  1: (doc) => {
    // v1 → v2: address string to object
    const parsed = parseAddressString(doc.address)
    return {
      ...doc,
      schemaVersion: 2,
      address: { street: parsed.street, city: parsed.city, zip: parsed.zip }
    }
  },
  2: (doc) => {
    // v2 → v3: add country, rename zip to postalCode
    return {
      ...doc,
      schemaVersion: 3,
      address: {
        street: doc.address.street,
        city: doc.address.city,
        postalCode: doc.address.zip,
        country: "USA"  // Default for existing data
      }
    }
  }
}

function migrateToLatest(doc, targetVersion = 3) {
  let current = doc
  while (current.schemaVersion < targetVersion) {
    const migrator = migrations[current.schemaVersion]
    if (!migrator) throw new Error(`No migration from v${current.schemaVersion}`)
    current = migrator(current)
  }
  return current
}
```

**Backward-compatible changes (no version bump needed):**

These changes do **not** require a `schemaVersion` increment:
- Adding new optional fields (old code ignores them, new code uses them if present)
- Adding new indexes (transparent to application code)
- Relaxing validation (making a required field optional)

These changes **do** require a `schemaVersion` increment:
- Renaming fields (e.g. `address` → `shippingAddress`)
- Changing field types (e.g. `price: "19.99"` → `price: 19.99`)
- Restructuring (e.g. flat `firstName`/`lastName` → nested `name: { first, last }`)
- Removing fields that old code reads

**When NOT to use schema versioning:**

- **Small datasets with downtime window**: If you can migrate all data in minutes during maintenance.
- **Truly stable schemas**: If the schema is mature and changes are rare.
- **Additive-only changes**: If you only add optional fields, versioning is overkill.
- **Event sourcing**: If using event sourcing, version the events instead.

## Verify with

```javascript
// Track version distribution
db.users.aggregate([
  { $group: { _id: "$schemaVersion", count: { $sum: 1 } } },
  { $sort: { _id: 1 } }
])

// Check for missing version field
db.users.countDocuments({ schemaVersion: { $exists: false } })
// Missing schemaVersion may indicate implicit v1 documents
```

Reference: [Schema Versioning Pattern](https://mongodb.com/docs/manual/data-modeling/design-patterns/data-versioning/schema-versioning/)
