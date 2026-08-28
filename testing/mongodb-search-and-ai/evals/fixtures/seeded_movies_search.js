// Seed fixture: `seeded_movies_search` — a small deterministic `sample.movies` collection
// plus an Atlas Search index, for the mongodb-search-and-ai functional task (Tier 2).
// Requires the mongodb/mongodb-atlas-local image (bundles the search process); plain mongo:8
// does NOT support $search / createSearchIndex.
//
// Applied per-case by solvers/seed_db.py. Deterministic membership so functional_db can
// compare: exactly two plots contain the token "robot" (Metro, Nexus); the others don't.
const sample = db.getSiblingDB('sample')

sample.movies.drop()
sample.movies.insertMany([
  { title: 'Metro', genre: 'comedy', plot: 'a lonely robot finds friendship in a big city' },
  { title: 'Nexus', genre: 'scifi', plot: 'a robot uprising threatens the megacity' },
  { title: 'Harbor', genre: 'drama', plot: 'a fisherman battles a relentless winter storm' },
  { title: 'Circuit', genre: 'comedy', plot: 'two hackers pull off a daring bank heist' },
])

// Create an Atlas Search index and WAIT until it is queryable. Two async hazards on
// mongodb-atlas-local:
//   1. mongot (the Search Index Management service) starts AFTER mongod, and the compose
//      healthcheck only gates on mongod — so createSearchIndex can transiently fail with
//      "Error connecting to Search Index Management service". Retry until it accepts.
//   2. createSearchIndex itself is async — the index isn't queryable immediately.
// English analyzer so the query is robust to stemming (e.g. "robots" matches "robot") —
// otherwise full-text membership would hinge on the agent guessing singular vs. plural.
const indexDef = {
  mappings: { dynamic: false, fields: { plot: { type: 'string', analyzer: 'lucene.english' } } },
}

let created = false
for (let i = 0; i < 60 && !created; i++) {
  try {
    sample.movies.createSearchIndex('default', indexDef)
    created = true
  } catch (e) {
    if (String(e).indexOf('already exists') >= 0) {
      created = true
    } else {
      sleep(2000) // mongot not ready yet
    }
  }
}
if (!created) {
  throw new Error('createSearchIndex failed: Search Index Management service (mongot) not ready')
}

let ready = false
for (let i = 0; i < 90; i++) {
  try {
    const idx = sample.movies.getSearchIndexes('default')
    if (idx.length && (idx[0].queryable === true || idx[0].status === 'READY')) {
      ready = true
      break
    }
  } catch (e) {
    /* transient while the service settles */
  }
  sleep(1000)
}
print('seeded sample.movies=' + sample.movies.countDocuments() + ' searchIndexReady=' + ready)
if (!ready) {
  throw new Error('Atlas Search index "default" did not become queryable in time')
}
