// Seed fixture: `seeded_nlq_lift` — sample.listingsAndReviews + sample.movies.
//
// Backs the NLQ cases imported from Dachary Carey's routing-eval spike
// (grove-platform/research-scratch, agent-skill-routing-eval). Those were the prompts where a
// blind order-swapped judge preferred the skill's answer over an unaided one in BOTH
// independent passes — the "stable lift-positive" core, 11 of 37 declines.
//
// Why a purpose-built fixture rather than the real sample datasets the spike used: functional
// grading re-executes the agent's pipeline and compares to a KNOWN result, so the data has to
// be small and every answer has to be unambiguous. The real sample_airbnb is ~100MB and its
// answers depend on the dataset snapshot.
//
// Field names deliberately mirror sample_airbnb.listingsAndReviews (`beds`, `amenities`,
// `number_of_reviews`, `host.host_id`, `address.location`) and sample_mflix.movies (`year`),
// because the skill's value here is SCHEMA GROUNDING — discovering the real field names and
// shapes instead of guessing. A fixture with invented field names would not exercise that.
//
// Every query these cases ask has exactly ONE correct answer against this data; ties are
// avoided on purpose (see the notes per field). Expected values in the cases were captured by
// executing the canonical queries against this fixture, not computed by hand.
const sample = db.getSiblingDB('sample')

sample.listingsAndReviews.drop()
sample.listingsAndReviews.insertMany([
  // --- within 10km of Istanbul centre [28.9784, 41.0082] ---
  {
    _id: 'L1',
    name: 'Sultanahmet Flat',
    price: 90,
    beds: 2,
    amenities: ['Wifi', 'Washer', 'Kitchen'],
    number_of_reviews: 10,
    host: { host_id: 'H1' },
    address: { market: 'Istanbul', location: { type: 'Point', coordinates: [28.977, 41.0055] } },
  },
  {
    _id: 'L2',
    name: 'Galata Loft',
    price: 120,
    beds: 3,
    amenities: ['Wifi', 'Washer', 'Kitchen', 'Heating'],
    number_of_reviews: 20,
    host: { host_id: 'H1' },
    address: { market: 'Istanbul', location: { type: 'Point', coordinates: [28.974, 41.0256] } },
  },
  {
    _id: 'L3',
    name: 'Besiktas Studio',
    price: 75,
    // beds:2 (not 1) so the MODE of beds is unique: 2 occurs 3x, 3 occurs 2x, 4 and 5 once.
    // With beds:1 here, 2 and 3 both occurred twice and "the most common bed count" had two
    // equally defensible answers — an unusable case.
    beds: 2,
    amenities: ['Wifi'],
    number_of_reviews: 5,
    host: { host_id: 'H2' },
    address: { market: 'Istanbul', location: { type: 'Point', coordinates: [29.0, 41.043] } },
  },
  {
    _id: 'L6',
    name: 'Kadikoy Room',
    price: 55,
    beds: 2,
    amenities: ['Wifi', 'Kitchen'],
    number_of_reviews: 25,
    host: { host_id: 'H3' },
    address: { market: 'Istanbul', location: { type: 'Point', coordinates: [29.025, 40.99] } },
  },
  // --- far outside 10km, so the geo filter has something to exclude ---
  {
    // the ONLY listing with 'Step-free access', and the MOST amenities (6) — both unique
    _id: 'L4',
    name: 'Ankara House',
    price: 60,
    beds: 4,
    amenities: ['Wifi', 'Washer', 'Kitchen', 'Heating', 'Pool', 'Step-free access'],
    number_of_reviews: 40,
    host: { host_id: 'H2' },
    address: { market: 'Ankara', location: { type: 'Point', coordinates: [32.8597, 39.9334] } },
  },
  {
    _id: 'L5',
    name: 'Izmir Villa',
    price: 200,
    beds: 5,
    amenities: ['Wifi', 'Pool'],
    number_of_reviews: 15,
    host: { host_id: 'H3' },
    address: { market: 'Izmir', location: { type: 'Point', coordinates: [27.1428, 38.4237] } },
  },
  {
    // 4th listing with beds > 2 and NO Washer, so the Washer percentage lands on a clean 50%
    _id: 'L7',
    name: 'Bursa Cabin',
    price: 45,
    beds: 3,
    amenities: ['Wifi', 'Heating'],
    number_of_reviews: 8,
    host: { host_id: 'H4' },
    address: { market: 'Bursa', location: { type: 'Point', coordinates: [29.0611, 40.1826] } },
  },
])

// Required for $geoNear / $geoWithin on address.location. The agent has to discover that the
// geo query needs this index (or that one already exists) — part of what schema grounding buys.
sample.listingsAndReviews.createIndex({ 'address.location': '2dsphere' })

// beds:              [2, 3, 2, 2, 4, 5, 3] -> mode is 2, uniquely (3x vs 2x for beds:3)
// number_of_reviews: sums to a single total; per-host sums have a unique maximum
// amenities:         exactly one listing has 'Step-free access'; one has strictly the most
// beds > 2:          L2, L4, L5, L7 — exactly half of which have 'Washer'

sample.movies.drop()
sample.movies.insertMany([
  { title: 'Sunrise Over Kyoto', year: 1983, genre: 'drama', imdb: 7.4 },
  { title: 'The Long Signal', year: 1983, genre: 'sci-fi', imdb: 8.1 },
  { title: 'Paper Lanterns', year: 1983, genre: 'drama', imdb: 6.8 },
  // adjacent years, so "released in 1983" has to be an equality match rather than a range
  { title: 'Winter Harbour', year: 1982, genre: 'drama', imdb: 7.9 },
  { title: 'Copper Line', year: 1984, genre: 'action', imdb: 7.2 },
  { title: 'Glass Orchard', year: 1990, genre: 'comedy', imdb: 6.5 },
])

print('seeded sample.listingsAndReviews: ' + sample.listingsAndReviews.countDocuments())
print('seeded sample.movies: ' + sample.movies.countDocuments())
