# Pipeline Patterns Reference

**Official examples repo**: https://github.com/mongodb/ASP_example (quickstarts, example processors, Terraform examples). Start with example_processors/README.md for the full pattern catalog.
Always consult the official repo for the latest validated patterns before creating processors.

## Stage Quick-Reference

| Stage | Purpose | Category |
|-------|---------|----------|
| `$source` | Data ingress (Kafka, Cluster, Kinesis, Sample) | Source (required, first) |
| `$match` | Filter documents | Stateless |
| `$project` | Select/reshape fields | Stateless |
| `$addFields` | Add computed fields | Stateless |
| `$unset` | Remove fields | Stateless |
| `$unwind` | Explode arrays into documents | Stateless |
| `$sort` | Order documents (only permitted inside windows) | Window-only |
| `$replaceRoot` | Promote nested document to root | Stateless |
| `$redact` | Field-level access control | Stateless |
| `$validate` | Schema enforcement (route invalid to DLQ) | Validation |
| `$lookup` | Enrich from Atlas collection | Enrichment |
| `$https` | Enrich from HTTP API | Enrichment |
| `$externalFunction` | Invoke Lambda (mid-pipeline or terminal sink) | Enrichment |
| `$tumblingWindow` | Fixed-size non-overlapping windows | Stateful |
| `$hoppingWindow` | Fixed-size overlapping windows | Stateful |
| `$sessionWindow` | Gap-based per-key windows | Stateful |
| `$function` | JavaScript UDF (requires the `enableFunctionExpression` flag, SP30+) | Custom Code |
| `$group` | Aggregate (inside windows) | Stateful |
| `$merge` | Write to Atlas collection | Output (exactly one, required, last) |
| `$emit` | Write to Kafka, Kinesis, S3, GCP Pub/Sub, or an Atlas collection | Output (exactly one, required, last) |
| `$iceberg` | Write to Apache Iceberg tables on an S3 connection (SP10+) | Output (exactly one, required, last) |

| Category | Stages | Rules |
|----------|--------|-------|
| **Source** (1, required) | `$source` | Must be first. One per pipeline. |
| **Stateless Processing** | `$match`, `$project`, `$addFields`, `$set`, `$unset`, `$unwind`, `$replaceRoot`, `$replaceWith`, `$redact` | No state or memory overhead. Place `$match` first to reduce volume. |
| **Enrichment** | `$lookup`, `$https`, `$externalFunction` (sync/async) | I/O-bound. `$lookup` and blob/time-series `$emit` support `parallelism`; `$https` and `$externalFunction` do not. `$https` and `$externalFunction` can be mid-pipeline enrichment OR terminal sink. For sinks: `$https` sends to webhooks/APIs; `$externalFunction` may be sync or async, and `as` must be omitted whenever execution is async. |
| **Validation** | `$validate` | Schema enforcement. Place early to catch bad data before expensive stages. |
| **Stateful/Window** | `$tumblingWindow`, `$hoppingWindow`, `$sessionWindow` | Accumulates state in memory. Monitor `memoryUsageBytes`. |
| **Custom Code** | `$function` | JavaScript UDFs. Requires the `enableFunctionExpression` feature flag (off by default); SP30+ enforced. |
| **Output** (exactly one, required) | `$merge`, `$emit`, `$iceberg`, `$https`, `$externalFunction` (sync or async; async recommended for sink) | Must be last. Required for deployed processors. |

## Invalid Constructs

**`$$ROOT` and `$$CURRENT`** — the ASP engine supports both (they reference the whole current document). MongoDB MCP Server versions through at least v3.3.0 reject any pipeline containing them when **creating a processor with `atlas-streams-build`** ("not available in streaming request"). If your server version does, use explicit field references, or deploy via `modify-processor` / `atlas api streams createStreamProcessor`, which do not run that validator.

Do NOT use these in streaming pipelines:
- `$$NOW`, `$$CLUSTER_TIME`, `$$USER_ROLES` — never seeded in ASP; using them throws "Builtin variable ... is not available"
- `$$SEARCH_META` — spelled with two `$$`; it does not throw, it silently evaluates to *missing* when unset. ASP has no `$search` stage, so guard with `$ifNull` or omit
- `$where` and `$accumulator` — always rejected by the engine
- `$$ROOT`/`$$CURRENT` when creating via `atlas-streams-build` on MCP server versions through at least v3.3.0 — blocked by the validator (see above)
- `$function` unless the `enableFunctionExpression` feature flag is enabled (off by default)
- HTTPS connections as `$source` — HTTPS is for `$https` enrichment or a terminal sink only
- Kafka `$source` without `topic` — topic field is required
- Pipelines without a sink — a terminal sink (`$merge`/`$emit`/`$iceberg`/`$https`/`$externalFunction`) is required for deployed processors (sinkless only works via `sp.process()`)
- Lambda connections with `$emit` — Lambda uses `$externalFunction` (mid-pipeline or terminal sink), not `$emit`

## Source Patterns

### MongoDB Change Stream
```json
{"$source": {"connectionName": "my-cluster", "db": "mydb", "coll": "mycoll"}}
```

With full document and pushdown pipeline:
```json
{"$source": {
  "connectionName": "my-cluster",
  "db": "mydb", "coll": "mycoll",
  "config": {
    "fullDocument": "updateLookup",
    "fullDocumentBeforeChange": "whenAvailable",
    "pipeline": [{"$match": {"operationType": "insert"}}]
  }
}}
```

### Kafka (topic is REQUIRED)
```json
{"$source": {
  "connectionName": "my-kafka",
  "topic": "my-topic",
  "config": {"auto_offset_reset": "earliest"},
  "partitionIdleTimeout": {"size": 30, "unit": "second"}
}}
```

### Kinesis
```json
{"$source": {
  "connectionName": "my-kinesis",
  "stream": "my-stream",
  "config": {
    "consumerARN": "arn:aws:kinesis:us-east-1:123456789:stream/my-stream/consumer/my-consumer:123",
    "initialPosition": "TRIM_HORIZON"
  },
  "shardIdleTimeout": {"size": 30, "unit": "second"}
}}
```

`stream` (required): Kinesis stream name. `config.initialPosition`: defaults to `LATEST`; also supports `TRIM_HORIZON` (oldest), `AT_TIMESTAMP` (requires `config.atTimestamp`), `AT_SEQUENCE_NUMBER`, and `AFTER_SEQUENCE_NUMBER`. `shardIdleTimeout`: unblocks windows when shards go idle (like Kafka `partitionIdleTimeout`). `config.consumerARN` (required): Enhanced Fan-Out consumer ARN; register the consumer (`aws kinesis register-stream-consumer`) before processor creation.

### Inline Documents (no external connection needed)
```json
{"$source": {"documents": [{"device_id": "sensor-1", "temp": 72.5}]}}
```
The fastest way to test a pipeline with zero external setup. Whether a **deployed** processor accepts an inline source depends on your Atlas deployment — confirm before promoting past local or `sp.process()` testing.

## Sink Patterns

### $merge to Atlas
```json
{"$merge": {"into": {"connectionName": "my-atlas", "db": "mydb", "coll": "mycoll"}}}
```

With match behavior and parallelism:
```json
{"$merge": {
  "into": {"connectionName": "my-atlas", "db": "mydb", "coll": "mycoll"},
  "on": "_id", "whenMatched": "replace", "whenNotMatched": "insert",
  "parallelism": 4
}}
```

`whenMatched`: `replace`, `keepExisting`, `merge`, `delete`, a pipeline, or an expression. `delete` is a direct literal value (no `$cond` needed). `whenNotMatched`: `insert`, `discard`, or an expression.

Additive merge (append to arrays):
```json
{"$merge": {
  "into": {"connectionName": "my-atlas", "db": "mydb", "coll": "mycoll"},
  "on": "device_id",
  "whenMatched": [{"$addFields": {"readings": {"$concatArrays": ["$readings", "$$new.readings"]}}}],
  "whenNotMatched": "insert"
}}
```

Dynamic routing:
```json
{"$merge": {"into": {
  "connectionName": "my-atlas", "db": "mydb",
  "coll": {"$cond": {"if": {"$eq": ["$priority", "high"]}, "then": "alerts", "else": "events"}}
}}}
```

### $emit to Atlas (collections, including time-series)
```json
{"$emit": {"connectionName": "my-atlas", "db": "mydb", "coll": "events"}}
```
`$emit` writes directly to an Atlas Cluster connection, and can create a time-series collection by adding `"timeseries": {"timeField": "timestamp"}`. Use `$merge` when you need `on`/`whenMatched`/`whenNotMatched` merge semantics; use `$emit` for plain ingest.

### $emit to GCP Pub/Sub
```json
{"$emit": {"connectionName": "my-pubsub", "topic": "events", "projectId": "my-project", "region": "us-central1"}}
```
Requires a `GCPPubSub` connection; `topic`, `projectId`, and `region` are all required.

### $emit to Kafka
```json
{"$emit": {
  "connectionName": "my-kafka", "topic": "output-topic",
  "config": {"key": "$device_id", "keyFormat": "string"}
}}
```

`config.keyFormat` values: `string`, `json`, `int`, `long`, `double`, `binData`. Tombstone support: `config.tombstoneWhen`, e.g. `{"$expr": {"$eq": ["$status", "deleted"]}}`.

### $emit to Kafka with Schema Registry (Avro)
```json
{"$emit": {
  "connectionName": "my-kafka", "topic": "output-topic",
  "schemaRegistry": {
    "connectionName": "my-schema-registry",
    "valueSchema": {
      "type": "avro",
      "schema": {
        "type": "record", "name": "SensorReading",
        "fields": [
          {"name": "device_id", "type": "string"},
          {"name": "temp", "type": "double"},
          {"name": "timestamp", "type": "long"}
        ]
      },
      "options": {
        "subjectNameStrategy": "TopicNameStrategy",
        "autoRegisterSchemas": true
      }
    }
  }
}}
```
Requires a `SchemaRegistry` connection (see [connection-configs.md](connection-configs.md#schemaregistry)). `valueSchema.type` must be lowercase `avro` (case-sensitive). `valueSchema.schema` is always required, even with `autoRegisterSchemas: true`. When emitting to an existing topic, verify the schema is registered and compatible with the subject's latest version (`TopicNameStrategy` uses `<topic>-value`) before deploying.

### $emit to Kinesis
```json
{"$emit": {"connectionName": "my-kinesis", "stream": "out", "partitionKey": "$device_id"}}
```

### $emit to S3
```json
{"$emit": {
  "connectionName": "my-s3", "bucket": "my-bucket",
  "path": {"$concat": ["data/", {"$dateToString": {"format": "%Y/%m/%d", "date": "$timestamp"}}]},
  "config": {"outputFormat": "relaxedJson"}
}}
```
Fields: `connectionName` (required), `bucket` (required), `path` (required — key prefix string or expression), `region` (optional), `config` (optional — `outputFormat`, `writeOptions`, `delimiter`, `compression`).

### $iceberg (Iceberg tables on S3)
```json
{"$iceberg": {
  "connectionName": "my-s3", "bucket": "my-bucket",
  "databaseName": "mydb", "tableName": "events",
  "path": "warehouse/events"
}}
```
Must be the last stage. Requires SP10+. `path` must not end with `/`; non-AWS workspaces also require `region`. `mode` defaults to `cdc` (change-data-capture semantics, reading `{ $meta: "stream.source.operationType" }`) — pass `mode` explicitly if you want plain inserts. `idFieldName` defaults to `_id`. An optional `catalog` selects `hadoop` (default) or `glue`. A dynamic `tableName` expression is allowed but forbids `partitionedBy`.

### $https as Sink (webhook/API)
```json
{"$https": {
  "connectionName": "my-webhook",
  "path": "/events",
  "method": "POST",
  "onError": "dlq"
}}
```

When used as a **final sink stage**, `$https` sends processed documents to an external HTTP endpoint. Unlike mid-pipeline usage (which enriches documents with API responses), sink usage doesn't expect a response to merge back into the document. Useful for:
- Sending data to webhooks
- Posting to external APIs
- Triggering external systems

### $externalFunction as Sink (Lambda)
```json
{"$externalFunction": {
  "connectionName": "my-lambda",
  "functionName": "arn:aws:lambda:us-west-1:123456789:function:my-function",
  "execution": "async",
  "onError": "dlq"
}}
```

**Important**: When used as a **final sink stage**, `$externalFunction` may use `execution: "sync"` or `"async"`; `async` is recommended for fire-and-forget. An async sink must **omit `as`**. Useful for:
- Triggering downstream AWS applications or analytics
- Notifying external systems
- Firing off alerts or billing logic
- Propagating data to external workflows

For sync mid-pipeline enrichment, include `as` to store the Lambda response. The pipeline still needs this as the terminal stage — you cannot use `$emit` to invoke Lambda.

## Window Patterns

### Tumbling
```json
{"$tumblingWindow": {
  "interval": {"size": 5, "unit": "minute"},
  "pipeline": [{"$group": {"_id": "$deviceId", "avg": {"$avg": "$temp"}, "count": {"$sum": 1}}}]
}}
```

### Hopping (with allowedLateness)
```json
{"$hoppingWindow": {
  "interval": {"size": 5, "unit": "minute"},
  "hopSize": {"size": 1, "unit": "minute"},
  "allowedLateness": {"size": 15, "unit": "second"},
  "pipeline": [{"$group": {"_id": "$region", "total": {"$sum": "$amount"}}}]
}}
```

### Session
```json
{"$sessionWindow": {
  "gap": {"size": 5, "unit": "minute"}, "partitionBy": "$userId",
  "pipeline": [{"$group": {"_id": "$userId", "actions": {"$push": "$action"}, "count": {"$sum": 1}}}]
}}
```

### Late data
```json
{"$tumblingWindow": {
  "interval": {"size": 1, "unit": "minute"},
  "allowedLateness": {"size": 30, "unit": "second"},
  "boundary": "eventTime",
  "pipeline": [{"$group": {"_id": "$sensorId", "max": {"$max": "$value"}}}]
}}
```

`boundary`: `eventTime` (default) or `processingTime` (wall clock).

## Windowing Rules
- Window pipelines are required; `$group` is the usual aggregation
- `$group`, `$count`, `$limit`, and `$sort` are supported **only** inside a window — never in the main pipeline
- Windows also accept stateless stages (`$match`, `$project`, `$addFields`, `$set`, `$unset`, `$unwind`, `$replaceRoot`/`$replaceWith`, `$redact`, `$validate`) plus `$lookup`, `$https`, and `$externalFunction`
- A pipeline can contain only one window stage
- Idle Kafka partitions block windows — use `partitionIdleTimeout`
- `allowedLateness` keeps windows open for late docs; docs arriving after it are sent to the DLQ

## Enrichment Patterns

### $https
```json
{"$https": {
  "connectionName": "my-api",
  "path": {"$concat": ["/users/", "$userId"]},
  "method": "GET", "as": "userInfo", "onError": "dlq"
}}
```

`onError`: `dlq` (recommended), `ignore`, `fail`. Store auth in connection settings, not pipeline. Place `$https` after windows to batch requests.

### $lookup
```json
{"$lookup": {
  "connectionName": "my-atlas",
  "from": {"db": "mydb", "coll": "users"},
  "localField": "userId", "foreignField": "_id", "as": "user",
  "parallelism": 2
}}
```

### $externalFunction (Lambda - Mid-Pipeline Enrichment)
```json
{"$externalFunction": {
  "connectionName": "my-lambda",
  "functionName": "my-function-name",
  "execution": "sync",
  "as": "lambdaResult",
  "onError": "dlq",
  "payload": [
    {"$project": {"userId": 1, "data": 1}}
  ]
}}
```

**Mid-pipeline usage:**
- `execution`: `sync` (waits for Lambda result, stores in `as` field) or `async` (non-blocking)
- `as`: Field name to store the Lambda response. Required for `sync`; **must be omitted whenever `execution: "async"`** — supplying it errors, sink or mid-pipeline.
- `payload`: Optional inner pipeline to customize request body sent to Lambda
- Use for enriching/transforming documents before downstream stages

**Sink usage:** See the Sink Patterns section. Sink may use `sync` or `async`; async is recommended and must omit `as`; sync mid-pipeline requires `as`.

### $validate (Schema Validation)
```json
{"$validate": {
  "validator": {"$jsonSchema": {
    "required": ["device_id", "timestamp", "reading"],
    "properties": {
      "device_id": {"bsonType": "string"},
      "reading": {"bsonType": "double"}
    }
  }},
  "validationAction": "dlq"
}}
```

`validationAction`: `"discard"` (default) or `"dlq"` (recommended). `"error"` is not supported. `validator` accepts **any match expression** — `$jsonSchema` is one convenient option, not a requirement (`{"$expr": ...}` works too). Place early to catch bad data before expensive stages.

### $function (JavaScript UDF)
```json
{"$addFields": {
  "boostedWatts": {"$function": {
    "body": "function(watts) { return watts * 1.2; }",
    "args": ["$watts"],
    "lang": "js"
  }}
}}
```

**Feature-flagged and SP30+ enforced.** `$function` is rejected unless the `enableFunctionExpression` feature flag is on — it is **off by default**, so confirm with the user (or the deployment's flags) before building a pipeline that depends on it. The engine also requires SP30 or higher and rejects a lower tier. `body`: JavaScript function as string. `args`: array of field references. `lang`: always `"js"`.

## Common Pipeline Patterns

### Array Normalization
```json
[
  {"$source": {"connectionName": "my-kafka", "topic": "orders"}},
  {"$unwind": "$items"},
  {"$replaceRoot": {"newRoot": {"$mergeObjects": ["$items", {"orderId": "$orderId", "ts": "$timestamp"}]}}},
  {"$merge": {"into": {"connectionName": "my-atlas", "db": "mydb", "coll": "line_items"}}}
]
```

### Dynamic Kafka Topic Routing
```json
{"$emit": {
  "connectionName": "my-kafka",
  "topic": {"$switch": {
    "branches": [
      {"case": {"$eq": ["$severity", "critical"]}, "then": "alerts-critical"},
      {"case": {"$eq": ["$severity", "warning"]}, "then": "alerts-warning"}
    ],
    "default": "alerts-info"
  }}
}}
```

### Complex Event Processing (Fraud Detection)
```json
[
  {"$source": {"connectionName": "my-kafka", "topic": "transactions"}},
  {"$tumblingWindow": {
    "interval": {"size": 5, "unit": "minute"},
    "pipeline": [
      {"$group": {
        "_id": "$userId",
        "txnCount": {"$sum": 1},
        "totalAmount": {"$sum": "$amount"},
        "uniqueLocations": {"$addToSet": "$location"}
      }},
      {"$addFields": {
        "suspiciousLocations": {"$gt": [{"$size": "$uniqueLocations"}, 3]},
        "highVelocity": {"$gt": ["$txnCount", 10]}
      }},
      {"$match": {"$or": [{"suspiciousLocations": true}, {"highVelocity": true}]}}
    ]
  }},
  {"$merge": {"into": {"connectionName": "my-atlas", "db": "fraud", "coll": "alerts"}}}
]
```

### Graceful Degradation with $ifNull
```json
{"$addFields": {
  "userName": {"$ifNull": ["$userInfo.name", "unknown"]},
  "userTier": {"$ifNull": ["$userInfo.tier", "standard"]},
  "enrichmentSucceeded": {"$ne": [{"$type": "$userInfo"}, "missing"]}
}}
```

## Window Metadata

After a window stage, the `$meta` expression exposes window boundary timestamps (`stream.window.start`, `stream.window.end`) and source metadata such as `stream.source.ts`:
```json
{"$addFields": {
  "windowStart": {"$meta": "stream.window.start"},
  "windowEnd": {"$meta": "stream.window.end"}
}}
```

## Checkpoint Resume Constraints

With `resumeFromCheckpoint: true` (default), you CANNOT change: window type, interval, remove windows, or modify `$source`. Set `false` to make these changes (restarts from beginning).

## DLQ Configuration
```json
{"dlq": {"connectionName": "my-atlas", "db": "streams_dlq", "coll": "failed_documents"}}
```
DLQ documents include: original document, error message, stage info, timestamp.

## Sample Stream Formats

| Format | Data type |
|--------|-----------|
| `sample_stream_solar` | Solar panel IoT readings (default; the only sample format documented by Atlas and used by the MCP server) |

## Chained Processors (Multi-Sink Pattern)

**CRITICAL: A single pipeline can only have ONE terminal sink** (`$merge`, `$emit`, `$iceberg`, `$https`, or `$externalFunction`). You CANNOT have both `$merge` and `$emit` as terminal stages. When a user requests multiple output destinations (e.g., "write to Atlas AND emit to Kafka" or "archive to S3 AND send to Lambda"), you MUST:

1. **Acknowledge** the single-sink constraint explicitly in your response
2. **Propose chained processors**: Processor A reads source → enriches → writes to intermediate via `$merge` (Atlas) or `$emit` (Kafka). Processor B reads from that intermediate (change stream or Kafka topic) → emits to second destination. Kafka-as-intermediate is lower latency; Atlas-as-intermediate is simpler to inspect.
3. **Show both processor pipelines** including any `$lookup` enrichment stages with `parallelism` settings.

Note: `$externalFunction` (Lambda) can be used mid-pipeline OR as a terminal sink. Async is recommended for a sink and must omit `as`; sync mid-pipeline requires `as`. A pipeline with mid-pipeline `$externalFunction` AND a terminal `$merge`/`$emit` is a valid single-sink pattern (Lambda enriches, then the result is written to the sink).

## Required Field Examples by Stage

### $source (Kinesis)
Use `stream` (NOT `streamName` or `topic`) for the Kinesis stream name.
```json
{"$source": {"connectionName": "my-kinesis", "stream": "my-stream"}}
```

### $source (change stream)
Include `config: { fullDocument: "updateLookup" }` to get the full document content.

### $emit (Kinesis)
MUST include `partitionKey`.
```json
{"$emit": {"connectionName": "my-kinesis", "stream": "my-stream", "partitionKey": "$fieldName"}}
```

### $emit (S3)
Use `path` (NOT `prefix`).
```json
{"$emit": {"connectionName": "my-s3", "bucket": "my-bucket", "path": {"$concat": ["data/", {"$dateToString": {"format": "%Y/%m/%d", "date": "$timestamp"}}]}, "config": {"outputFormat": "relaxedJson"}}}
```
