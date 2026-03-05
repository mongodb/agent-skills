---
title: Use Time Series Collections for Time Series Data
impact: MEDIUM
impactDescription: "10-100× lower storage and index overhead with automatic bucketing and compression"
tags: schema, patterns, time-series, collections, bucketing, ttl, granularity, compression
---

## Use Time Series Collections for Time Series Data

**Time series collections are purpose-built for append-only measurements.** MongoDB automatically buckets, compresses, and indexes time series data so you get high ingest rates with far less storage and index overhead than a standard collection. Use them for IoT sensor data, application metrics, financial data, and event logs.

**MongoDB 8.0 Performance:** Block processing introduced in MongoDB 8.0 can significantly improve eligible analytical pipelines (for example, `$match` + `$sort` on the time field + `$group`). In some cases, throughput improves by more than 200%. This is automatic for eligible queries.

**Incorrect (regular collection for measurements):**

```javascript
// Regular collection: one document per reading
// Creates huge collections and indexes at scale
{
  sensorId: "temp-01",
  ts: ISODate("2025-01-15T10:00:00Z"),
  value: 22.5
}

// Problems:
// 1. Each measurement is a separate document
// 2. Index overhead per document
// 3. No automatic compression
// 4. Working set grows linearly

// Standard index (large and grows fast)
db.sensor_data.createIndex({ sensorId: 1, ts: 1 })
```

**Correct (time series collection with optimized settings):**

```javascript
// Create time series collection with careful configuration
db.createCollection("sensor_data", {
  timeseries: {
    timeField: "ts",           // Required: timestamp field
    metaField: "metadata",     // Recommended: grouping field
    granularity: "minutes"     // Match your data rate
  },
  expireAfterSeconds: 60 * 60 * 24 * 90  // 90-day retention
})

// Insert documents - MongoDB buckets automatically
db.sensor_data.insertOne({
  metadata: { sensorId: "temp-01", location: "building-A" },
  ts: new Date(),
  value: 22.5,
  unit: "celsius"
})

// Benefits:
// - Automatic bucketing (many measurements per internal doc)
// - Column compression (40-60% disk reduction)
// - MongoDB 6.3+: auto-created compound index on metaField + timeField for new collections
// - Optimized for time-range queries
```

**Choose the right metaField:**

```javascript
// metaField groups measurements into buckets
// Choose fields that:
// 1. Are queried together with time ranges
// 2. Have moderate cardinality (not too unique, not too few)
// 3. Don't change for a given time series

// GOOD: Sensor/device identifier as metaField
{
  metadata: { sensorId: "temp-01", region: "us-east" },
  ts: new Date(),
  value: 22.5
}
// Queries like: "All readings from temp-01 in last hour"

// BAD: High-cardinality field as metaField
{
  metadata: { requestId: "uuid-123..." },  // Unique per doc!
  ts: new Date()
}
// Creates one bucket per requestId - no compression benefit

// BAD: Frequently changing field in metaField
{
  metadata: { sensorId: "temp-01", currentValue: 22.5 },  // Changes!
  ts: new Date()
}
// metaField should be static for the time series
```

**Select appropriate granularity:**

```javascript
// Granularity determines bucket time span
// Match it to your data ingestion rate

// "seconds" - DEFAULT. High-frequency ingestion. Bucket spans ~1 hour.
db.createCollection("high_freq_metrics", {
  timeseries: { timeField: "ts", metaField: "host", granularity: "seconds" }
})

// "minutes" - Data every few seconds to minutes. Bucket spans ~24 hours.
db.createCollection("app_metrics", {
  timeseries: { timeField: "ts", metaField: "service", granularity: "minutes" }
})

// "hours"   - Data every few hours. Bucket spans ~30 days.
db.createCollection("daily_reports", {
  timeseries: { timeField: "ts", metaField: "reportType", granularity: "hours" }
})

// Custom bucketing (MongoDB 6.3+) for precise control
db.createCollection("custom_metrics", {
  timeseries: {
    timeField: "ts",
    metaField: "device",
    bucketMaxSpanSeconds: 3600,      // Max 1 hour per bucket
    bucketRoundingSeconds: 3600      // Align to hour boundaries
  }
})
```

**Optimize insert performance:**

```javascript
// TIP 1: Batch inserts with insertMany
// Group documents with same metaField value together
const batch = [
  { metadata: { sensorId: "temp-01" }, ts: new Date(), value: 22.5 },
  { metadata: { sensorId: "temp-01" }, ts: new Date(), value: 22.6 },
  { metadata: { sensorId: "temp-01" }, ts: new Date(), value: 22.4 },
  // ... more temp-01 readings
  { metadata: { sensorId: "temp-02" }, ts: new Date(), value: 19.2 },
  // ... more temp-02 readings
]

db.sensor_data.insertMany(batch, { ordered: false })
// ordered: false allows parallel processing

// TIP 2: Use consistent field order
// Column compression works better with consistent structure
// GOOD: Same field order in every document
{ metadata: {...}, ts: new Date(), value: 22.5, unit: "C" }
{ metadata: {...}, ts: new Date(), value: 22.6, unit: "C" }

// BAD: Varying field order
{ metadata: {...}, ts: new Date(), value: 22.5, unit: "C" }
{ unit: "C", value: 22.6, metadata: {...}, ts: new Date() }

// TIP 3: Omit empty values for better compression
// GOOD: Omit field entirely if no value
{ metadata: {...}, ts: new Date(), value: 22.5 }

// BAD: Include empty/null values
{ metadata: {...}, ts: new Date(), value: 22.5, error: null, note: "" }
```

**Optimize compression:**

```javascript
// Time series collections use column compression
// Optimize data for maximum compression:

// TIP 1: Round numeric values to needed precision
// BAD: Excessive precision
{ value: 22.5123456789 }

// GOOD: Round to needed decimals
{ value: 22.5 }

// TIP 2: Use consistent nested field order
// Compression is per-field, nested fields need consistency
// GOOD
{ metadata: { sensorId: "a", location: "b" } }
{ metadata: { sensorId: "c", location: "d" } }

// BAD
{ metadata: { sensorId: "a", location: "b" } }
{ metadata: { location: "d", sensorId: "c" } }

// TIP 3: Consider flattening for high-cardinality metadata
// If metadata has many unique combinations, flatten may help
{ sensorId: "temp-01", location: "building-A", ts: new Date(), value: 22.5 }
```

**Secondary indexes on time series:**

```javascript
// MongoDB 6.3+: time series auto-creates index on { metaField, timeField } for new collections
// Add secondary indexes for other query patterns

// Index on measurement values for threshold queries
db.sensor_data.createIndex({ "value": 1 })
// Query: "All readings where value > 100"

// Compound index for filtered time queries
db.sensor_data.createIndex({ "metadata.location": 1, "ts": 1 })
// Query: "Readings from building-A in last hour"

// Partial index for specific conditions
db.sensor_data.createIndex(
  { "metadata.alertLevel": 1 },
  { partialFilterExpression: { "metadata.alertLevel": { $exists: true } } }
)
```

**Sharding time series collections:**

```javascript
// For very high volume, shard on metaField
// MongoDB 8.0+: timeField sharding is deprecated

// Create sharded time series collection
sh.shardCollection("mydb.sensor_data", { "metadata.region": 1 })

// Good shard keys for time series:
// - metadata.sensorId (if many sensors)
// - metadata.region (geographic distribution)
// - metadata.customerId (multi-tenant)

// BAD: Sharding on timeField alone
// Creates hot spots on recent time ranges
```

**When NOT to use time series collections:**

- **Not time-based data**: Primary access isn't time range queries.
- **Frequent updates/deletes**: Time series optimized for append-only; updates to old data are slow.
- **Very low volume**: A few hundred events don't benefit from bucketing.
- **Need transactional writes**: Time series collections don't support writes in transactions (reads are supported).
- **Complex queries on measurements**: If you mostly query by non-time fields, regular collections may be better.

## Verify with

```javascript
// Analyze time series collection efficiency
function analyzeTimeSeries(collectionName) {
  // Get collection info
  const info = db.getCollectionInfos({ name: collectionName })[0]

  if (!info?.options?.timeseries) {
    print(`${collectionName} is not a time series collection`)
    return
  }

  const ts = info.options.timeseries
  print(`\n=== Time Series: ${collectionName} ===`)
  print(`Time field: ${ts.timeField}`)
  print(`Meta field: ${ts.metaField || "(none)"}`)
  print(`Granularity: ${ts.granularity || "default"}`)

  if (info.options.expireAfterSeconds) {
    const days = info.options.expireAfterSeconds / 86400
    print(`TTL: ${days} days`)
  }

  // Get stats
  const stats = db[collectionName].stats()
  print(`\nStorage:`)
  print(`  Documents: ${stats.count?.toLocaleString() || "N/A"}`)
  print(`  Size: ${(stats.size / 1024 / 1024).toFixed(2)} MB`)
  print(`  Avg doc size: ${stats.avgObjSize?.toFixed(0) || "N/A"} bytes`)

  // Check bucket efficiency (via system.buckets)
  const bucketColl = `system.buckets.${collectionName}`
  const bucketCount = db[bucketColl].countDocuments({})
  if (bucketCount > 0 && stats.count) {
    const docsPerBucket = stats.count / bucketCount
    print(`\nBucketing efficiency:`)
    print(`  Buckets: ${bucketCount.toLocaleString()}`)
    print(`  Docs per bucket: ${docsPerBucket.toFixed(1)}`)

    if (docsPerBucket < 10) {
      print(`  WARNING: Low docs/bucket - consider adjusting granularity or metaField`)
    }
  }

  // Show indexes
  print(`\nIndexes:`)
  db[collectionName].getIndexes().forEach(idx => {
    print(`  ${idx.name}: ${JSON.stringify(idx.key)}`)
  })
}

// Usage
analyzeTimeSeries("sensor_data")
```

Reference: [Time Series Collections](https://mongodb.com/docs/manual/core/timeseries-collections/)
