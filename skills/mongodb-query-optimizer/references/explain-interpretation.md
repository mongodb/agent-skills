# Understanding Explain Output

Use this when interpreting explain results to diagnose query performance.

## What explain shows

The `explain()` command reveals how MongoDB executes a query:

- Which index (if any) was used  
- How many documents/keys were examined  
- Execution time and stages  
- Alternative plans considered

## Verbosity levels

- `queryPlanner` (default) \- Shows winning plan only, no execution stats  
- `executionStats` \- Executes query and shows actual performance metrics  
- `allPlansExecution` \- Shows execution stats for all considered plans (verbose)

**For optimization:** Use `"executionStats"` to see real performance data.

## Key metrics to check

### Query targeting ratio

**Most important efficiency metric:**

```
Query Targeting = nReturned / totalKeysExamined
```

- **1.0 (perfect)**: Every index entry examined was a match  
- **0.5**: Half the index entries were matches  
- **\< 0.1**: Query scans many irrelevant index entries (poor selectivity)

**Low ratio indicates:**

- Index isn't selective for this query  
- May need different index  
- Range scan examining too many entries

### Documents examined

```
totalDocsExamined
```

- **0**: Covered query (best case)  
- **\= nReturned**: Reading only matching documents (good)  
- **\> nReturned**: Reading documents that don't match (needs investigation)

High `totalDocsExamined` relative to `nReturned`:

- Index doesn't fully qualify matches (must read docs to filter)  
- Consider more selective index or covered query

### Keys examined

```
totalKeysExamined
```

Number of index entries scanned.

- Should be close to `nReturned` for efficient queries  
- Much higher than `nReturned` indicates poor selectivity  
- For range scans, will typically be higher than exact matches

### Execution time

```
executionTimeMillis
```

Approximate query execution time.

**Contextualize this:**

- Compare to your latency requirements  
- Is it consistent across runs?  
- How does it scale with result set size?

## Plan stages to recognize

### IXSCAN (Index Scan)

**Good:** Using an index. Note that IXSCAN is not the only index-using stage — COUNT\_SCAN, DISTINCT\_SCAN, and IDHACK also use indexes. The key distinction is index usage vs. COLLSCAN.

```json
{
  "stage": "IXSCAN",
  "indexName": "category_1_price_1",
  "keysExamined": 42,
  "direction": "forward",
  "indexBounds": {
    "category": ["[\"electronics\", \"electronics\"]"],
    "price": ["[MinKey, MaxKey]"]
  }
}
```

**Check:**

- `indexName` \- Is this the right index?  
- `keysExamined` \- Reasonable relative to `nReturned`?  
- Bounds \- Are they tight or scanning large range?

### COLLSCAN (Collection Scan)

**Bad:** Full collection scan, no index used.

```json
{
  "stage": "COLLSCAN",
  "direction": "forward",
  "docsExamined": 100000
}
```

**Causes:**

- No suitable index exists for the query predicates

**Fix:** Create index matching query predicates (follow ESR).

### FETCH

Retrieving full documents after index scan.

```json
{
  "stage": "FETCH",
  "inputStage": {
    "stage": "IXSCAN",
    "keysExamined": 100
  }
}
```

**Normal** when query needs fields not in index.

**Optimization:** Make it a covered query if possible (eliminate FETCH).

### SORT (in-memory sort)

**Can be expensive** (without limit): Sorting results in memory after retrieval.

```json
{
  "stage": "SORT",
  "sortPattern": { "date": -1 },
  "memUsage": 1024000,
  "inputStage": { "stage": "IXSCAN", ... }
}
```

**Why this is costly:**

- Blocks until all results are buffered in memory before returning the first document (100MB memory limit for in-memory sorts in MongoDB)

**Fix:** Index to support sort order \- add sort fields to index following ESR rules.

### SORT\_KEY\_GENERATOR

Extracting sort key from documents before in-memory sort. Indicates sort is NOT using index.

**Fix:** Adjust index to include sort fields in correct order.

### Projection stages

**PROJECTION\_SIMPLE**: Basic field inclusion/exclusion. **PROJECTION\_DEFAULT**: More complex projection logic. **PROJECTION\_COVERED**: Covered query, no document read needed.

### SHARDING\_FILTER

In sharded clusters, filters out documents not owned by the shard. This stage appears when the shard key fields are not part of the index being used — it is avoidable by including shard key fields in the index.

## Reading executionStats

Example:

```json
{
  "executionStats": {
    "executionSuccess": true,
    "nReturned": 25,
    "executionTimeMillis": 12,
    "totalKeysExamined": 28,
    "totalDocsExamined": 25,
    "executionStages": {
      "stage": "FETCH",
      "nReturned": 25,
      "docsExamined": 25,
      "inputStage": {
        "stage": "IXSCAN",
        "indexName": "category_1_price_1",
        "keysExamined": 28
      }
    }
  }
}
```

**Analysis:**

- ✓ Using index (IXSCAN)  
- ✓ Keys examined (28) close to returned (25) \- good selectivity  
- ✓ Docs examined (25) \= returned (25) \- index fully qualifies matches  
- ✗ Has FETCH \- not covered (minor optimization opportunity)  
- ✓ Fast execution (12ms)

**Verdict:** Well-optimized query. Could eliminate FETCH for marginal improvement.

## Identifying problems

### Problem: High totalDocsExamined \>\> nReturned

```json
{
  "nReturned": 10,
  "totalKeysExamined": 100,
  "totalDocsExamined": 100
}
```

**Meaning:** Index narrows to 100 candidates, but only 10 match after reading docs.

**Causes:**

- Query has predicates not fully covered by index  
- Need compound index including all filter fields

**Example:**

```javascript
// Index: { category: 1 }
// Query: { category: "electronics", inStock: true }
```

Index finds 100 electronics items, must read docs to check `inStock`.

**Fix:** Compound index `{ category: 1, inStock: 1 }`

### Problem: In-memory SORT

```json
{
  "stage": "SORT",
  "sortPattern": { "date": -1 },
  "memUsage": 5000000,
  "inputStage": {
    "stage": "IXSCAN",
    "indexName": "category_1",
    "keysExamined": 1000
  }
}
```

**Meaning:** Using index for filter, but sorting 1000 results in memory.

**Fix:** Extend index to support sort: `{ category: 1, date: -1 }`

### Problem: High totalKeysExamined with low nReturned

```json
{
  "nReturned": 5,
  "totalKeysExamined": 10000,
  "totalDocsExamined": 5
}
```

**Meaning:** Scanned 10,000 index entries to find 5 matches.

**Causes:**

- Non-selective predicate (common value)  
- Range scan over large range  
- $in with many values

**Solutions:**

- Add more selective field to compound index  
- Partial index to index only relevant subset  
- Reconsider query approach

### Problem: COLLSCAN on small collection

**Not always a problem:** Collection scans can be faster than index for:

- Very small collections (\< 1000 docs, fits in few pages)  
- Queries returning most documents  
- Collection fits entirely in cache

**Optimizer willmay choose COLLSCAN in absence of an eligible index.f:**

- Index selectivity is poor for this query

## Compound index effectiveness

Check if compound index is being used optimally:

**Index:** `{ a: 1, b: 1, c: 1 }`

**Query 1:** `{ a: 1, b: 2 }`

```json
{
  "indexName": "a_1_b_1_c_1",
  "indexBounds": {
    "a": ["[1, 1]"],
    "b": ["[2, 2]"],
    "c": ["[MinKey, MaxKey]"]  // ← Not filtering on c
  }
}
```

**Good:** Using first two fields effectively.

**Query 2:** `{ b: 2, c: 3 }`

```json
{
  "stage": "COLLSCAN"  // ← Index not used!
}
```

**Problem:** Missing index prefix (a). Cannot use this index.

## Multi-plan execution

When `allPlansExecution` verbosity is used:

```json
{
  "allPlansExecution": [
    {
      "planName": "plan1",
      "executionStats": { ... }
    },
    {
      "planName": "plan2",
      "executionStats": { ... }
    }
  ]
}
```

Optimizer tests multiple plans and picks best. Usually not needed unless investigating why specific index wasn't chosen.

## Cached plans

MongoDB caches query plans. If explain shows unexpected behavior:

- Plan may be cached from different data distribution  
- Clear with `db.collection.getPlanCache().clear()`

Cached plans are evicted when:

- Index is created/dropped  
- Collection significantly changes size  
- Server restarts

## Aggregation explain

Aggregation pipelines show stages sequentially:

```json
{
  "stages": [
    {
      "$cursor": {
        "queryPlanner": {
          "winningPlan": {
            "stage": "IXSCAN",
            "inputStage": { ... }
          }
        }
      }
    },
    { "$group": { ... } },
    { "$sort": { ... } }
  ]
}
```

**Check:**

- Is `$cursor` (initial match) using index?  
- Are there in-memory sorts after $group?  
- High memory usage stages?  
- spilling to disk

## Quick diagnosis checklist

1. Is an index being used? Look for COLLSCAN  
2. **Is the right index being used?** Check indexName  
3. **Keys examined vs returned** \- Is selectivity good?  
4. **Docs examined vs returned** \- Are docs qualifying efficiently?  
5. **Is there a SORT stage?** Should sort use index  
6. **Is it covered?** Check for totalDocsExamined: 0  
7. **Execution time** \- Acceptable for your SLA?

Focus on the biggest problem first \- usually COLLSCAN or in-memory SORT.  