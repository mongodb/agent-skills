// Seed fixture: `seeded_events` — sample.events with NO secondary index, used by
// query-optimizer eval case 20. The case's functional_check is `type: explain`: it re-runs
// filter {type: 'purchase'} with sort {ts: -1} and requires an IXSCAN, forbids an in-memory
// sort, and caps docsExamined at 1.1x the docs returned. So the graded behaviour is whether
// the agent builds a compound index that serves BOTH the equality filter and the sort — not
// merely whether some index exists.
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

// Intentionally leave only the default _id_ index, so {type} + sort {ts} starts as a
// COLLSCAN plus an in-memory sort — both of which the explain check above rejects.
print(
  'seeded sample.events: ' +
    sample.events.countDocuments() +
    ' indexes=' +
    sample.events.getIndexes().length,
)
