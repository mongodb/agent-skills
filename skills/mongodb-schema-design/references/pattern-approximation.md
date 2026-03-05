---
title: "Approximation Pattern"
impact: MEDIUM
tags: [pattern, approximation, computed, write-optimization]
---

# Approximation Pattern

Intentionally store approximate values to reduce write load when exact real-time counts are not required.

## When to Use

- Page views, trending scores, social media counters, ratings
- Counter changes by small increments (+1 per event)
- Exact real-time count is NOT required — approximate is acceptable
- High-write workloads where every +1 write to MongoDB is expensive

## When NOT to Use

- Financial amounts, inventory counts — exact values required
- Low-frequency updates where approximation adds no benefit
- When regulatory/audit requirements mandate exact counts

## Pattern Structure

```javascript
// Document stores approximate count + sync timestamp
{
  _id: "article_123",
  title: "MongoDB Best Practices",
  viewCount: 9847,          // approximate — may lag by up to threshold
  lastSyncedAt: ISODate("2024-01-15T10:30:00Z")
}
```

## Implementation

```javascript
// Application-side: only write to MongoDB when local counter crosses threshold
let localViewCount = 0
const WRITE_THRESHOLD = 100  // write to DB every 100 views

function recordPageView(articleId) {
  localViewCount++

  if (localViewCount % WRITE_THRESHOLD === 0) {
    // Write accumulated increment to MongoDB
    db.articles.updateOne(
      { _id: articleId },
      {
        $inc: { viewCount: WRITE_THRESHOLD },
        $set: { lastSyncedAt: new Date() }
      }
    )
  }
}
```

## Tradeoff

| Concern | Impact |
|---------|--------|
| Write reduction | ~100x fewer DB writes (at threshold=100) |
| Staleness | Up to `threshold` events behind |
| Accuracy | Approximate — never exact real-time |
| Crash safety | Unsynced local increments lost on restart |

## Difference from Computed Pattern

- **Computed Pattern**: pre-computes expensive aggregations, stores exact results
- **Approximation Pattern**: intentionally stores inexact values to reduce write frequency

Use Approximation when staleness is acceptable. Use Computed when exact values are needed but recalculating each time is too expensive.
