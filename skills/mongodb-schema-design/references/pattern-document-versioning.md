---
title: "Document Versioning Pattern"
impact: MEDIUM
tags: [pattern, versioning, audit, compliance]
---

# Document Versioning Pattern

Store full document history in a separate `revisions` collection to enable reproducing historical state. Different from schema-versioning (which handles field migration) — this stores complete snapshots.

## When to Use

- Insurance policies, legal documents, compliance audit trails
- Regulatory requirement to reproduce exact historical state
- Infrequent document updates (not high-frequency event streams)
- Only a subset of documents need version tracking

## When NOT to Use

- High-frequency updates — use event sourcing instead
- When approximate history is sufficient
- When the revision collection would grow unboundedly without a retention policy

## Pattern Structure

```javascript
// currentPolicies collection — current state only (fast reads)
{
  _id: "POL-001",
  holder: "Jane Smith",
  premium: 450,
  coverage: "comprehensive",
  v: 3,
  updatedAt: ISODate("2024-06-01")
}

// policyRevisions collection — full history snapshots
{
  policyId: "POL-001",
  v: 2,
  snapshot: {
    holder: "Jane Smith",
    premium: 425,
    coverage: "basic",
    v: 2
  },
  changedAt: ISODate("2024-03-15")
}
```

## Implementation

```javascript
async function updatePolicy(policyId, newData, session) {
  const current = await db.currentPolicies.findOne({ _id: policyId }, { session })

  await db.policyRevisions.insertOne({
    policyId: current._id,
    v: current.v,
    snapshot: { ...current },
    changedAt: new Date()
  }, { session })

  await db.currentPolicies.updateOne(
    { _id: policyId },
    { $set: { ...newData, v: current.v + 1, updatedAt: new Date() } },
    { session }
  )
}

async function getPolicyAtVersion(policyId, version) {
  if (version === 'current') {
    return db.currentPolicies.findOne({ _id: policyId })
  }
  const rev = await db.policyRevisions.findOne({ policyId, v: version })
  return rev?.snapshot
}
```

## Indexes

```javascript
db.policyRevisions.createIndex({ policyId: 1, v: -1 })
// Optional TTL for retention (e.g., 7 years)
db.policyRevisions.createIndex({ changedAt: 1 }, { expireAfterSeconds: 220752000 })
```

## Difference from Schema Versioning

| Pattern | Purpose | Stores |
|---------|---------|--------|
| Schema Versioning | Handle field structure migration | `schemaVersion` field on each doc |
| Document Versioning | Reproduce complete historical state | Full snapshots in revisions collection |
