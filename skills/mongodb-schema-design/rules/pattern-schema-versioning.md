---
title: Use Schema Versioning for Safe Evolution
impact: MEDIUM
impactDescription: "Avoids breaking reads/writes during migrations and enables online backfills"
tags: schema, patterns, versioning, migration, evolution, backward-compatibility, backfill
---

## Use Schema Versioning for Safe Evolution

**Schema changes are inevitable.** Add a `schemaVersion` field so your application can read old and new documents simultaneously while you migrate data in-place. This prevents production outages caused by suddenly missing, renamed, or restructured fields. Online migrations keep your application running during schema evolution.

**Incorrect (breaking change without versioning):**

```javascript
// Version 1: address is a string
{ _id: 1, name: "Ada", address: "12 Main St, NYC 10001" }

// Developer changes schema: address becomes an object
// New code expects:
{ _id: 1, name: "Ada", address: { street: "12 Main St", city: "NYC", zip: "10001" } }

// PROBLEMS:
// 1. Old documents break: address.city returns undefined
// 2. Application crashes or returns wrong data
// 3. Can't deploy gradually - all-or-nothing
// 4. Rollback is dangerous if new docs were written
```

**Correct (versioned documents with migration path):**

```javascript
// Version 1 documents (existing)
{ _id: 1, name: "Ada", schemaVersion: 1, address: "12 Main St, NYC 10001" }

// Version 2 documents (new structure)
{ _id: 2, name: "Bob", schemaVersion: 2,
  address: { street: "45 Oak Ave", city: "Boston", zip: "02101" } }

// Application code handles both versions:
function getCity(user) {
  if (user.schemaVersion >= 2) {
    return user.address.city
  }
  // Parse city from v1 string format
  return parseAddressString(user.address).city
}

// Benefits:
// 1. Old and new documents coexist
// 2. Deploy new code before migrating data
// 3. Gradual migration during low-traffic periods
// 4. Easy rollback - old code still works
```

**Online migration strategies:**

```javascript
// Strategy 1: Background batch migration
// Best for: Large collections, can tolerate mixed versions temporarily

function migrateToV2(batchSize = 1000) {
  let migrated = 0
  let cursor = db.users.find({ schemaVersion: { $lt: 2 } }).limit(batchSize)

  while (cursor.hasNext()) {
    const doc = cursor.next()

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

```javascript
// These changes DON'T require schemaVersion increment:

// 1. Adding new optional fields
// Old: { name: "Ada" }
// New: { name: "Ada", nickname: "A" }
// Old code ignores nickname, new code uses it if present

// 2. Adding new indexes
db.users.createIndex({ email: 1 })
// Transparent to application code

// 3. Relaxing validation (removing required fields)
// If "phone" was required, making it optional is backward-compatible

// These changes DO require schemaVersion:

// 1. Renaming fields
// address → shippingAddress

// 2. Changing field types
// price: "19.99" → price: 19.99

// 3. Restructuring (flat to nested, or vice versa)
// firstName, lastName → name: { first, last }

// 4. Removing fields that old code expects
// Removing "legacyId" that old code reads
```

**Version field conventions:**

```javascript
// Option 1: Integer version (recommended)
{ schemaVersion: 1 }
{ schemaVersion: 2 }
// Simple, easy to compare, clear progression

// Option 2: Semantic version string
{ schemaVersion: "1.0.0" }
{ schemaVersion: "1.1.0" }
// More expressive but harder to query

// Option 3: Date-based version
{ schemaVersion: "2025-01-15" }
// Ties to deployment dates

// Option 4: No explicit version (implicit v1)
// Treat missing schemaVersion as version 1
function getVersion(doc) {
  return doc.schemaVersion || 1
}
```

**Monitoring migration progress:**

```javascript
// Track version distribution
db.users.aggregate([
  { $group: {
      _id: "$schemaVersion",
      count: { $sum: 1 }
    }
  },
  { $sort: { _id: 1 } }
])

// Example output during migration:
// { _id: 1, count: 45000 }   // 45% still on v1
// { _id: 2, count: 55000 }   // 55% migrated to v2

// Set up alerts when migration stalls
// Monitor for: v1 count not decreasing over time
```

**Cleanup after migration:**

```javascript
// After all documents migrated and old code retired:

// 1. Verify no old versions remain
const oldCount = db.users.countDocuments({ schemaVersion: { $lt: 2 } })
if (oldCount > 0) {
  print(`WARNING: ${oldCount} documents still on old schema`)
  // Don't proceed with cleanup
}

// 2. Remove old field handling from application code
// Delete migration functions, version checks

// 3. Optionally remove schemaVersion field
// (Keep it for future migrations)
db.users.updateMany(
  {},
  { $unset: { schemaVersion: "" } }
)

// 4. Update validation to require new structure only
db.runCommand({
  collMod: "users",
  validator: {
    $jsonSchema: {
      required: ["address"],
      properties: {
        address: {
          bsonType: "object",
          required: ["street", "city", "postalCode"]
        }
      }
    }
  }
})
```

**When NOT to use schema versioning:**

- **Small datasets with downtime window**: If you can migrate all data in minutes during maintenance.
- **Truly stable schemas**: If the schema is mature and changes are rare.
- **Additive-only changes**: If you only add optional fields, versioning is overkill.
- **Event sourcing**: If using event sourcing, version the events instead.

## Verify with

```javascript
// Schema version health check
function analyzeSchemaVersions(collectionName, versionField = "schemaVersion") {
  const coll = db[collectionName]

  // Get version distribution
  const versions = coll.aggregate([
    { $group: {
        _id: `$${versionField}`,
        count: { $sum: 1 },
        oldestDoc: { $min: "$_id" },
        newestDoc: { $max: "$_id" }
      }
    },
    { $sort: { _id: 1 } }
  ]).toArray()

  print(`\n=== Schema Version Analysis: ${collectionName} ===`)

  let total = 0
  let latestVersion = 0
  versions.forEach(v => {
    total += v.count
    const ver = v._id || "(missing)"
    if (typeof v._id === "number" && v._id > latestVersion) {
      latestVersion = v._id
    }
    print(`  Version ${ver}: ${v.count.toLocaleString()} documents`)
  })

  print(`\nTotal: ${total.toLocaleString()} documents`)

  // Check for missing version field
  const missingVersion = coll.countDocuments({ [versionField]: { $exists: false } })
  if (missingVersion > 0) {
    print(`\nWARNING: ${missingVersion.toLocaleString()} documents missing '${versionField}'`)
    print(`  These may be v1 documents (implicit version)`)
  }

  // Check for old versions
  const oldVersions = versions.filter(v => v._id !== null && v._id < latestVersion)
  if (oldVersions.length > 0) {
    const oldCount = oldVersions.reduce((sum, v) => sum + v.count, 0)
    const pct = ((oldCount / total) * 100).toFixed(1)
    print(`\nMIGRATION STATUS: ${oldCount.toLocaleString()} documents (${pct}%) on old versions`)

    if (oldCount > 0) {
      print(`  Run migration to upgrade to version ${latestVersion}`)
    }
  } else {
    print(`\nMIGRATION STATUS: Complete - all documents on latest version`)
  }
}

// Usage
analyzeSchemaVersions("users", "schemaVersion")
```

Reference: [Schema Versioning Pattern](https://mongodb.com/docs/manual/data-modeling/design-patterns/data-versioning/schema-versioning/)
