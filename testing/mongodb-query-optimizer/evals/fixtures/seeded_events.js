// Seed fixture: `seeded_events` — sample.events with NO secondary index (query-optimizer
// functional case 37). Equality lookups on `userId` do a COLLSCAN until the agent creates
// an index; scorers.functional_db (type: index) then checks the index exists.
// Applied per-sample by solvers/seed_db.py.
const sample = db.getSiblingDB('sample')

sample.events.drop()
const docs = []
for (let i = 0; i < 2000; i++) {
  docs.push({
    userId: i % 100,
    type: i % 7 === 0 ? 'purchase' : 'view',
    ts: new Date(2024, 0, 1 + (i % 365)),
  })
}
sample.events.insertMany(docs)

// Intentionally leave only the default _id_ index — userId lookups are unindexed.
print(
  'seeded sample.events: ' +
    sample.events.countDocuments() +
    ' indexes=' +
    sample.events.getIndexes().length,
)
