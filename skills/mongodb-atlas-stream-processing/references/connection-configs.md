# Connection Configuration Reference

**Official examples repo**: https://github.com/mongodb/ASP_example — check quickstarts, example processors, and Terraform examples. Start with quickstarts.

## Connection Capabilities — Source/Sink Reference

Know what each connection type can do before creating pipelines:

| Connection Type | As Source ($source) | As Sink ($merge / $emit) | Mid-Pipeline | Notes |
|-----------------|---------------------|--------------------------|--------------|-------|
| **Cluster** | ✅ Change streams | ✅ $merge to collections; `$emit` (incl. timeseries) | ✅ $lookup | Change streams monitor insert/update/delete/replace operations |
| **Kafka** | ✅ Topic consumer | ✅ $emit to topics | ❌ | Source MUST include `topic` field |
| **Sample Stream** | ✅ Sample data | ❌ Not valid | ❌ | Testing/demo only |
| **S3** | ❌ Not valid | ✅ $emit to buckets; `$iceberg` (SP10+) | ❌ | Sink only - use `path` and `config.outputFormat` (no top-level `format`); `compression` under `config` |
| **Https** | ❌ Not valid | ✅ $https as sink | ✅ $https enrichment | Can be used mid-pipeline for enrichment OR as final sink stage |
| **AWSLambda** | ❌ Not valid | ✅ $externalFunction (sync or async) | ✅ $externalFunction (sync or async) | **Sink:** sync or async; async recommended, and `as` must be omitted whenever `execution: "async"`. **Sync mid-pipeline:** `as` required; a sync sink may omit it. |
| **AWS Kinesis** | ✅ Stream consumer | ✅ $emit to streams | ❌ | Similar to Kafka pattern |
| **GCPPubSub** | ❌ Not valid | ✅ $emit to topics | ❌ | Sink only. Needs `topic`, `projectId`, `region`; private networking uses `publicPrivateNetworking` |
| **SchemaRegistry** | ❌ Not valid | ❌ Not valid | ✅ Schema resolution | **Metadata only** - used by Kafka connections for Avro schemas |

**Common connection usage mistakes to avoid:**
- ❌ Using HTTPS connections as `$source` → HTTPS is for enrichment or sink only
- ❌ Setting `as` with `execution: "async"` → omit it whenever execution is async, sink or mid-pipeline; only sync stages take `as`
- ❌ Forgetting change streams exist → Atlas Cluster is a powerful source, not just a sink
- ❌ Using `$merge` with Kafka → Use `$emit` for Kafka sinks

**$externalFunction execution modes:**
- **`execution: "sync"`** — blocks until Lambda returns. Mid-pipeline it requires `as` to store the response; as a terminal sink the response has nowhere to go, so `as` may be omitted
- **`execution: "async"`** — non-blocking; **must omit `as`** (supplying both errors). Works as a sink or mid-pipeline.

## Connection Naming Best Practices

**CRITICAL**: Connection names should clearly indicate their actual targets to avoid confusion and prevent writing data to wrong destinations.

### Good Naming Patterns

**Match the actual target name:**
- Cluster connection to "ClusterRestoreTest" → name it `cluster-restore-test` or `ClusterRestoreTest`
- Cluster connection to "AtlasCluster" → name it `atlas-cluster` or `AtlasCluster`

**Use descriptive names with context:**
- `prod-kafka-orders` (indicates environment + service + purpose)
- `dev-atlas-main` (indicates environment + service + designation)
- `staging-s3-exports` (indicates environment + service + purpose)

### Bad Naming Patterns (AVOID)

❌ **Generic names that don't match targets:**
- Connection "atlascluster" pointing to "ClusterRestoreTest" ← CONFUSING!
- Connection "kafka" pointing to multiple different topics ← NOT SPECIFIC!

❌ **Reusing names across workspaces without context:**
- "myconnection" in workspace A and workspace B with different targets

❌ **Names that don't indicate connection type:**
- "connection1", "test", "temp" ← NO CONTEXT!

### Verification Workflow

**Before creating processors**, always inspect your connections to verify they point where you expect:
```
1. atlas-streams-discover → action: "list-connections"
2. atlas-streams-discover → action: "inspect-connection" for each
3. Verify connection name matches actual target (clusterName, bootstrapServers, url, etc.)
4. If mismatch exists, consider renaming or warn the user
```

See [development-workflow.md](development-workflow.md) "Pre-Deployment Connection Validation" section for the complete validation procedure.

## Important Notes
- HTTPS connections are for `$https` enrichment or as a terminal `$https` sink — they are NOT valid as `$source` data sources
- Store API authentication in connection settings, never hardcode in processor pipelines
- AWS connections (S3, Kinesis, Lambda) require IAM role ARN registered via Atlas Cloud Provider Access first
- Supported `connectionType` values: `Kafka`, `Cluster`, `S3`, `Https`, `AWSKinesisDataStreams`, `AWSLambda`, `SchemaRegistry`, `Sample`, `GCPPubSub`

## AWS Cloud Provider Access Prerequisites

**For S3, Kinesis, and Lambda connections:**

AWS connections (S3, Kinesis, Lambda) require that the IAM role ARN be **registered in the Atlas project via Cloud Provider Access** before creating the connection. This is a prerequisite — the connection creation will fail without it.

**Always mention this prerequisite** in your response when the user wants to create AWS connections, even if the user says connections already exist. Confirm with language like:
- "IAM role ARNs are registered via Atlas Cloud Provider Access"
- "Ensure IAM role ARNs are registered via Atlas Cloud Provider Access before creating connections"

**Security best practice:** Use a dedicated IAM role per processor (or group of related processors) with least-privilege permissions scoped only to the specific S3 buckets, Kinesis streams, or Lambda functions that processor needs. Avoid sharing broad-access roles across unrelated processors.

## Region Mapping Reference

The `region` field for workspace creation uses Atlas-specific names that differ by cloud provider. Using the wrong format returns a cryptic `dataProcessRegion` error.

| Provider | Cloud Region | Streams `region` Value |
|----------|-------------|----------------------|
| **AWS** | us-east-1 | `VIRGINIA_USA` |
| **AWS** | us-east-2 | `OHIO_USA` |
| **AWS** | us-west-2 | `OREGON_USA` |
| **AWS** | ca-central-1 | `MONTREAL_CAN` |
| **AWS** | sa-east-1 | `SAOPAULO_BRA` |
| **AWS** | eu-west-1 | `DUBLIN_IRL` |
| **AWS** | ap-southeast-1 | `SINGAPORE_SGP` |
| **AWS** | ap-south-1 | `MUMBAI_IND` |
| **AWS** | ap-northeast-1 | `TOKYO_JPN` |
| **GCP** | us-central1 | `US_CENTRAL1` |
| **GCP** | europe-west1 | `EUROPE_WEST1` |
| **GCP** | us-east4 | `US_EAST4` |
| **Azure** | eastus | `eastus` |
| **Azure** | eastus2 | `eastus2` |
| **Azure** | westus | `westus` |
| **Azure** | westeurope | `westeurope` |

This is a partial list. If unsure, inspect an existing workspace with `atlas-streams-discover` → `inspect-workspace` and check `dataProcessRegion.region`.

## MCP Tool Behaviors for Connections

**Elicitation:** When required fields are missing, the build tool auto-prompts for them via an interactive form (MCP elicitation protocol). Do NOT manually ask the user for passwords or bootstrap servers — let the tool collect them.

**Auto-normalization:**
- `bootstrapServers` passed as array → auto-converted to comma-separated string
- `schemaRegistryUrls` passed as string → auto-wrapped in array
- Cluster `dbRoleToExecute` → auto-defaults to `{role: "readWriteAnyDatabase", type: "BUILT_IN"}` if omitted
- Networking → moved between `networking` and `publicPrivateNetworking` by connection type (Lambda and GCP Pub/Sub use `publicPrivateNetworking`); setting `connectionId` infers `access.type: "PRIVATE_LINK"`; setting both fields to conflicting values throws

## connectionConfig by type

### Kafka
```json
{
  "bootstrapServers": "broker1:9092,broker2:9092",
  "authentication": {
    "mechanism": "SCRAM-256",
    "username": "my-user",
    "password": "my-password"
  },
  "security": {
    "protocol": "SASL_SSL"
  }
}
```
**Important:** `bootstrapServers` is a **comma-separated string**, not an array.

All fields above are required. The tool will prompt the user for username/password via elicitation if not provided.

Through the MCP tool, `authentication.mechanism` accepts `PLAIN`, `SCRAM-256`, `SCRAM-512`, `OAUTHBEARER`, or `AWS_MSK_IAM`, and `security.protocol` accepts `SASL_SSL`, `SASL_PLAINTEXT`, or `SSL`. Those two fields are closed enums, so values outside them — mTLS's `mechanism: "NONE"` and a `plaintext` protocol — are rejected and need the Admin API or Atlas UI. Every other field under `authentication` and `security` is passed through untouched, so `security.brokerPublicCertificate` and additional OIDC fields **can** be set with the MCP tool. The tool also requires `bootstrapServers`, `authentication.mechanism`, `security.protocol`, and a username/password for every mechanism except `AWS_MSK_IAM`.

For Amazon MSK IAM auth, use `mechanism: "AWS_MSK_IAM"` with `authentication: { aws: { roleArn: "<arn>" } }` — do not send a username/password.

For Confluent Cloud, use `mechanism: "PLAIN"` with your API key as `username` and API secret as `password`.

Kafka supports both **PrivateLink** and **VPC Peering** for private networking. See the [PrivateLink Reference](#privatelink-reference-all-vendors) section below for all supported vendors and providers.

**VPC Peering:**
- Supported for connections to Kafka brokers in your own VPC
- **The security protocol must be `SASL_SSL`** for a VPC-peered Kafka connection
- Use `atlas-streams-manage` with `accept-peering` action to complete the peering setup
- Requires AWS account ID, VPC ID, and region information

**Important: Networking, the connection type, and the connection's region cannot be modified after connection creation.** The API enforces the networking restriction (`STREAM_NETWORKING_CANNOT_BE_MODIFIED`) and the region restriction (`STREAM_CONNECTION_REGION_CANNOT_BE_MODIFIED`). To add or change PrivateLink/VPC peering on an existing Kafka connection, change its `connectionType`, or move its region, you must delete it and recreate it. Auth/credential fields are updatable in place via `update-connection`.

Use `atlas-streams-discover` → `action: "get-networking"` to list project-level PrivateLink endpoints (and Atlas account details for a provider/region). It does **not** list VPC peerings — peerings are managed with `accept-peering`/`reject-peering` and `teardown`.

### Cluster (Atlas)
```json
{
  "clusterName": "my-atlas-cluster",
  "dbRoleToExecute": {
    "role": "readWriteAnyDatabase",
    "type": "BUILT_IN"
  }
}
```
`clusterName` is **required** — must be a cluster in the same project (use `atlas-list-clusters` to verify).

`dbRoleToExecute` defaults to `{role: "readWriteAnyDatabase", type: "BUILT_IN"}` if not provided.

Optional: `clusterGroupId` (if cluster is in a different project — requires cross-project access to be enabled at the org level).

### S3
```json
{
  "aws": {
    "roleArn": "arn:aws:iam::123456789:role/streams-s3-role",
    "testBucket": "my-test-bucket"
  }
}
```
**Prerequisite:** The IAM role ARN must be registered in the Atlas project via Cloud Provider Access before creating the connection.

Required IAM policy permissions: `s3:ListBucket`, `s3:GetObject`, `s3:PutObject`, `s3:GetObjectVersion`, `s3:GetBucketLocation`.

### Https
```json
{
  "url": "https://api.example.com/webhook",
  "headers": {
    "Authorization": "Bearer token123"
  }
}
```
**IMPORTANT:** HTTPS connections are for `$https` enrichment stages ONLY. They are NOT valid data sources — do not use them in `$source`.

Store all API authentication in the connection config headers, not in the processor pipeline.

#### HTTPS Auth Patterns

**API Key:**
```json
{"url": "https://api.example.com", "headers": {"X-API-Key": "your-api-key"}}
```

**Bearer Token:**
```json
{"url": "https://api.example.com", "headers": {"Authorization": "Bearer your-token"}}
```

**Basic Auth:**
```json
{"url": "https://api.example.com", "headers": {"Authorization": "Basic base64-encoded-credentials"}}
```

**OAuth 2.0 (pre-obtained token):**
```json
{"url": "https://api.example.com", "headers": {"Authorization": "Bearer oauth-access-token"}}
```

### AWSKinesisDataStreams
```json
{
  "aws": {
    "roleArn": "arn:aws:iam::123456789:role/streams-kinesis-role"
  }
}
```
**Prerequisite:** The IAM role ARN must be registered in the Atlas project via Cloud Provider Access before creating the connection.

Required IAM policy permissions: `kinesis:ListShards`, `kinesis:SubscribeToShard`, `kinesis:PutRecords`, `kinesis:DescribeStreamSummary`.

### AWSLambda
```json
{
  "aws": {
    "roleArn": "arn:aws:iam::123456789:role/streams-lambda-role"
  }
}
```
**Prerequisite:** The IAM role ARN must be registered in the Atlas project via Cloud Provider Access before creating the connection.

Lambda's private networking goes in `connectionConfig.publicPrivateNetworking` (not `networking`).

### GCPPubSub
```json
{
  "gcp": {
    "serviceAccountId": "streams-writer@my-project.iam.gserviceaccount.com"
  }
}
```
Sink only — `$emit` supplies `topic`, `projectId`, and `region` on the stage. Private networking goes in `connectionConfig.publicPrivateNetworking`, not `networking`.

### SchemaRegistry
```json
{
  "connectionType": "SchemaRegistry",
  "connectionConfig": {
    "provider": "CONFLUENT",
    "schemaRegistryUrls": ["https://schema-registry.example.com"],
    "schemaRegistryAuthentication": {
      "type": "USER_INFO",
      "username": "...",
      "password": "..."
    }
  }
}
```
- `connectionType` MUST be `"SchemaRegistry"` (not `"Kafka"` or `"Https"`)
- `provider` is optional and defaults to `"CONFLUENT"`, the only supported value
- `schemaRegistryUrls` is an **array** (not a string). The tool auto-wraps a string into an array if needed.
- `schemaRegistryAuthentication.type`: `"USER_INFO"` (explicit credentials) or `"SASL_INHERIT"` (inherit from Kafka connection)
- Tool elicitation will collect sensitive fields (password) — don't ask the user for these directly

### Sample
No connectionConfig required. Provides built-in test data. Useful for development and testing without external infrastructure.

Available sample format: `sample_stream_solar` (default, auto-created when `includeSampleData: true` on workspace).

### PrivateLink Reference (All Vendors)

Via the MCP tool, PrivateLink vendors are: AWS `CONFLUENT`/`MSK`/`S3`/`KINESIS`/`LAMBDA`, Azure `EVENTHUB`/`CONFLUENT`, GCP `CONFLUENT`/`PUBSUB`, and `GENERIC`. Omitting `vendor` defaults to `GENERIC`; the value is normalized to uppercase, and `PUBSUB` also requires `region`. Create a project-level PrivateLink first, then reference it in the connection's `networking.access` config.

**Step 1: Create project-level PrivateLink** via `atlas-streams-build` resource='privatelink'. The field is `provider`; there is no `privateLinkProvider`. Supply `dnsDomain` whenever the Confluent cluster requires it. If your Confluent cluster's setup instead calls for setting it after creation, the Atlas CLI (`atlas api streams updatePrivateLinkConnection`) and the Admin API PATCH endpoint accept it while the endpoint's `dnsDomain` is unset or the endpoint is `IDLE`.

| Provider | Vendor | Required privateLinkConfig fields |
|----------|--------|----------------------------------|
| AWS | CONFLUENT | provider, vendor, region, serviceEndpointId, dnsDomain (supply when required, or set after creation while unset/`IDLE`), dnsSubDomain (array, [] if none) |
| AWS | MSK | provider, vendor, arn, authenticationScheme (`TLS`/`SASL_SCRAM`/`IAM`) |
| AWS | S3 | provider, vendor, region, serviceEndpointId (`com.amazonaws.<region>.s3`) |
| AWS | KINESIS | provider, vendor, region, serviceEndpointId (`com.amazonaws.<region>.kinesis-streams`) |
| AWS | LAMBDA | provider, vendor, region, serviceEndpointId (`com.amazonaws.<region>.lambda`) |
| AZURE | EVENTHUB | provider, vendor, region, dnsDomain, serviceEndpointId (full Azure Resource ID) |
| AZURE | CONFLUENT | provider, vendor, region, dnsDomain, azureResourceIds |
| GCP | CONFLUENT | provider, vendor, region, dnsDomain, gcpServiceAttachmentUris |
| GCP | PUBSUB | provider, vendor, region (required) — omit `dnsDomain` (Atlas derives it), `serviceEndpointId`, and `gcpServiceAttachmentUris` |
| GCP/AZURE | GENERIC (default) | provider (`GCP`/`AZURE`), vendor, region, serviceEndpointId. AWS rejects vendor `GENERIC`; name a specific AWS vendor. |

**Step 2: Reference in connection networking config:**
```json
{
  "networking": {
    "access": {
      "type": "PRIVATE_LINK",
      "connectionId": "<PrivateLink _id from Step 1>"
    }
  }
}
```

Use `atlas-streams-discover` action='get-networking' to find the PrivateLink `_id`.

**Note:** Networking config cannot be modified after connection creation (`STREAM_NETWORKING_CANNOT_BE_MODIFIED`) — delete and recreate to change.
