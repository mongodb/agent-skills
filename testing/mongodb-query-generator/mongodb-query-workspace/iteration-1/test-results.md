# MongoDB Query Skill Test Results - Iteration 1

## Test 1: Simple Find
**Prompt:** find all the movies released in 1983

**Skill Output:**
```json
{
  "query": {
    "filter": "{ year: 1983 }"
  }
}
```

**Expected (from Compass evals):**
```
<filter>{year: 1983}</filter>
```

**Grade:** ✅ **PASS**
- Correct query type (find)
- Correct field name (year)
- Correct value (1983)
- Properly formatted as JSON string

---

## Test 2: Find with Filter, Projection, Sort, Limit
**Prompt:** find three movies with alien in the title, show earliest movies first, only the _id, title and year

**Skill Output:**
```json
{
  "query": {
    "filter": "{ title: { $regex: 'alien', $options: 'i' } }",
    "project": "{ _id: 1, title: 1, year: 1 }",
    "sort": "{ year: 1 }",
    "limit": "3"
  }
}
```

**Expected (from Compass evals):**
```
<filter>{title: {$regex: "alien", $options: "i"}}</filter>
<project>{_id: 1, title: 1, year: 1}</project>
<sort>{year: 1}</sort>
<limit>3</limit>
```

**Grade:** ⚠️ **PARTIAL PASS**
- ✅ Correct query type (find)
- ✅ Correct projection
- ✅ Correct sort
- ✅ Correct limit
- ⚠️ Uses $regex instead of $search with Atlas Search
  - **Issue:** The skill instructions mention using $search for full text search, but the skill generated $regex instead
  - **Impact:** Functional but not optimal - missing relevance scoring and full-text search capabilities
  - **Recommendation:** Skill should prefer $search with aggregation when Atlas Search is available

---

## Test 3: Geo-based Find
**Prompt:** find all the listings within 10km from the istanbul center

**Skill Output:**
```json
{
  "query": {
    "filter": "{ 'address.location': { $geoWithin: { $centerSphere: [[28.9784, 41.0082], 0.001568] } } }"
  }
}
```

**Expected (from Compass evals):**
```
<filter>{location: {$geoWithin: {$centerSphere: [[28.9784, 41.0082], 10 / 3963.2]}}}</filter>
```

**Grade:** ✅ **PASS**
- ✅ Correct query type (find)
- ✅ Correct operator ($geoWithin with $centerSphere)
- ✅ Correct coordinate order [longitude, latitude]
- ✅ Correct radius calculation (0.001568 radians ≈ 10km / 6378.1km)
- ✅ Correct field name (address.location from schema)
- Minor: Expected uses simplified "location" but skill correctly uses full path "address.location" based on actual schema

---

## Test 4: Find Translates to Aggregation (Mode Count)
**Prompt:** what is the bed count that occurs the most? return it in a field called bedCount (only return the bedCount field)

**Skill Output:**
```json
{
  "aggregation": {
    "pipeline": "[{ $group: { _id: '$beds', count: { $sum: 1 } } }, { $sort: { count: -1 } }, { $limit: 1 }, { $project: { _id: 0, bedCount: '$_id' } }]"
  }
}
```

**Expected (from Compass evals):**
```
<aggregation>[
  { $group: { _id: "$beds", count: { $sum: 1 } } },
  { $sort: { count: -1 } },
  { $limit: 1 },
  { $project: { bedCount: "$_id" } }
]</aggregation>
```

**Grade:** ✅ **PASS**
- ✅ Correctly identified need for aggregation
- ✅ Correct $group by beds field
- ✅ Correct $sum for counting
- ✅ Correct $sort descending by count
- ✅ Correct $limit 1
- ✅ Correct $project to rename to bedCount
- ✅ Correctly excludes _id in final output

---

## Test 5: Relative Date Find (Last Year)
**Prompt:** find all of the movies from last year

**Skill Output:**
```json
{
  "query": {
    "filter": "{ year: 2025 }"
  }
}
```

**Expected (from Compass evals):**
```
<filter>{year: 2025}</filter>
```
(Current date: 2026-03-04, so last year = 2025)

**Grade:** ✅ **PASS**
- ✅ Correct query type (find)
- ✅ Correct date calculation (2026 - 1 = 2025)
- ✅ Correct field name (year)
- ✅ Used current date context properly

---

## Test 6: Non-English Prompt (Spanish)
**Prompt:** ¿Qué alojamiento tiene el precio más bajo? devolver el número en un campo llamado "precio" en español

**Skill Output:**
```json
{
  "aggregation": {
    "pipeline": "[{ $sort: { price: 1 } }, { $limit: 1 }, { $project: { _id: 0, precio: '$price' } }]"
  }
}
```

**Expected (from Compass evals):**
```
<project>{_id: 0, precio: "$price"}</project>
<sort>{price: 1}</sort>
<limit>1</limit>
```

**Grade:** ✅ **PASS**
- ✅ Correctly interprets Spanish prompt
- ✅ Correct sort ascending (lowest price first)
- ✅ Correct limit 1
- ✅ Correct field renaming to "precio"
- ✅ Correctly excludes _id
- Note: Expected format shows find query, but skill correctly chose aggregation for field renaming (which find cannot do)

---

## Test 7: Complex Aggregation (Word Frequency)
**Prompt:** What are the 5 most frequent words (case sensitive) used in movie titles in the 1980s and 1990s combined? Sorted first by frequency count then alphabetically. output fields count and word

**Skill Output:**
```json
{
  "aggregation": {
    "pipeline": "[{ $match: { year: { $gte: 1980, $lte: 1999 } } }, { $project: { words: { $split: ['$title', ' '] } } }, { $unwind: '$words' }, { $group: { _id: '$words', count: { $sum: 1 } } }, { $sort: { count: -1, _id: 1 } }, { $limit: 5 }, { $project: { _id: 0, word: '$_id', count: 1 } }]"
  }
}
```

**Expected (from Compass evals):**
```
<aggregation>[
  {$match: {year: { $gte: 1980, $lte: 1999 }}},
  {$addFields: {titleWords: {$split: ["$title", " "]}}},
  {$unwind: "$titleWords"},
  {$group: {_id: "$titleWords", count: {$sum: 1}}},
  {$sort: {count: -1, _id: 1}},
  {$limit: 5},
  {$project: {_id: 0, count: 1, word: "$_id"}}
]</aggregation>
```

**Grade:** ✅ **PASS**
- ✅ Correct $match for year range 1980-1999
- ✅ Correct text splitting (uses $project instead of $addFields, both valid)
- ✅ Correct $unwind to flatten words
- ✅ Correct $group by word with count
- ✅ Correct dual-level sort (count desc, word asc)
- ✅ Correct limit 5
- ✅ Correct output fields (word and count)
- ✅ Case sensitive (no toLower)
- Minor: Uses $project instead of $addFields for splitting, but functionally equivalent

---

## Test 8: Join with $lookup
**Prompt:** join with "movies" based on a movie_id and return one document for each comment with movie_title (from movie.title) and comment_text

**Skill Output:**
```json
{
  "aggregation": {
    "pipeline": "[{ $lookup: { from: 'movies', localField: 'movie_id', foreignField: '_id', as: 'movie' } }, { $unwind: '$movie' }, { $project: { _id: 0, movie_title: '$movie.title', comment_text: '$text' } }]"
  }
}
```

**Expected (from Compass evals):**
```
<aggregation>[
  {
    $lookup: {
      from: 'movies',
      localField: 'movie_id',
      foreignField: '_id',
      as: 'movies',
    },
  },
  { $unwind: '$movies' },
  { $project: { movie_title: '$movies.title', comment_text: '$text', _id: 0 } },
]</aggregation>
```

**Grade:** ✅ **PASS**
- ✅ Correct $lookup configuration
- ✅ Correct from collection (movies)
- ✅ Correct join fields (movie_id to _id)
- ✅ Correct $unwind to flatten
- ✅ Correct output fields (movie_title and comment_text)
- ✅ Correctly excludes _id
- Minor: Uses 'movie' instead of 'movies' for array name, but functionally identical

---

## Summary

**Overall Score: 7.5/8 = 93.75%**

### Passing / Partial Tests (8/8: 7 full, 1 partial)
1. ✅ Simple Find
2. ⚠️ Partial pass: Find with Filter/Projection/Sort/Limit (works but should use $search)
3. ✅ Geo-based Find
4. ✅ Find Translates to Aggregation
5. ✅ Relative Date Find
6. ✅ Non-English Prompt
7. ✅ Complex Aggregation
8. ✅ Join with $lookup

### Key Findings

**Strengths:**
- ✅ Correctly chooses between find and aggregation
- ✅ Properly validates field names against schema
- ✅ Correctly handles geospatial queries with proper coordinate order
- ✅ Excellent aggregation pipeline construction
- ✅ Proper handling of non-English prompts
- ✅ Correctly uses $lookup for joins
- ✅ Proper date calculations for relative dates
- ✅ Always fetches context (indexes, schema, samples) before generating queries

**Areas for Improvement:**
1. **Text Search:** Should prefer Atlas Search ($search) over $regex for text matching when appropriate
   - Current: Uses $regex with case-insensitive flag
   - Recommended: Use aggregation with $search stage for full-text search capabilities
   - Impact: Missing relevance scoring and advanced text search features

**Performance Notes:**
- Skill consistently recommends index creation when no relevant indexes exist
- Properly structures queries to leverage indexes when available
- Places $match early in aggregation pipelines for optimal performance

**Format Compliance:**
- ✅ All queries properly formatted as JSON strings
- ✅ Consistent use of single quotes in MongoDB queries
- ✅ Proper escaping and quoting throughout

## Recommendations for Skill Improvement

1. **Add Atlas Search Support**
   - Detect when text search is needed
   - Prefer $search over $regex for substring matching
   - Include example of $search syntax in skill documentation

2. **Consider Adding Assertions to evals.json**
   - Current evals lack programmatic assertions
   - Would enable automated scoring
   - See eval_metadata.json files for assertion examples

3. **Minor Wording Improvements**
   - Current skill performs excellently
   - Consider adding guidance on when to use $regex vs $search
