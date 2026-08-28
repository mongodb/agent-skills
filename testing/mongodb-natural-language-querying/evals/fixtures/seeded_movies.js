// Seed fixture: `seeded_movies` — sample.movies only (functional case 37).
// Applied per-sample by solvers/seed_db.py (not the mongo init dir), selected by a case's
// `seed: seeded_movies`. Deterministic so scorers.functional_db can compare to a known set.
const sample = db.getSiblingDB('sample')

sample.movies.drop()
sample.movies.insertMany([
  { title: 'Alpha', year: 1998, genre: 'drama', imdb: 7.1 },
  { title: 'Bravo', year: 2001, genre: 'action', imdb: 8.9 },
  { title: 'Charlie', year: 2004, genre: 'action', imdb: 8.2 },
  { title: 'Delta', year: 2009, genre: 'drama', imdb: 9.1 },
  { title: 'Echo', year: 2011, genre: 'comedy', imdb: 7.8 },
  { title: 'Foxtrot', year: 2015, genre: 'action', imdb: 8.5 },
  { title: 'Golf', year: 2018, genre: 'drama', imdb: 6.9 },
  { title: 'Hotel', year: 2020, genre: 'comedy', imdb: 8.7 },
  { title: 'India', year: 1999, genre: 'action', imdb: 9.4 }, // pre-2000: excluded
])

print('seeded sample.movies: ' + sample.movies.countDocuments())
