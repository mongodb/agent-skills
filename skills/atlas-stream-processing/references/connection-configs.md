# Connection Configuration Reference

**Official examples repo**: https://github.com/mongodb/ASP_example

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
- HTTPS connections are for `$https` enrichment ONLY — they are NOT valid as `$source` data sources
- Store API authentication in connection settings, never hardcode in processor pipelines
- AWS connections (S3, Kinesis, Lambda) require IAM role ARN registered via Atlas Cloud Provider Access first
- Supported `connectionType` values: `Kafka`, `Cluster`, `S3`, `Https`, `AWSKinesisDataStreams`, `AWSLambda`, `SchemaRegistry`, `Sample`

## MCP Tool Behaviors for Connections

**Elicitation:** When required fields are missing, the build tool auto-prompts for them via an interactive form (MCP elicitation protocol). Do NOT manually ask the user for passwords or bootstrap servers — let the tool collect them.

**Auto-normalization:**
- `bootstrapServers` passed as array → auto-converted to comma-separated string
- `schemaRegistryUrls` passed as string → auto-wrapped in array
- Cluster `dbRoleToExecute` → auto-defaults to `{role: "readWriteAnyDatabase", type: "BUILT_IN"}` if omitted

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

Authentication mechanisms: `PLAIN`, `SCRAM-256`, `SCRAM-512`, `OAUTHBEARER`
Security protocols: `SASL_SSL`, `SASL_PLAINTEXT`, `SSL`

For Confluent Cloud, use `mechanism: "PLAIN"` with your API key as `username` and API secret as `password`.

Kafka supports both **PrivateLink** and **VPC Peering** for private networking:

**PrivateLink:**
- Supported with Confluent Cloud on AWS (see Terraform examples in the ASP_example repo: `terraform/privatelinkConfluentAWS.tf`)
- Requires both the Stream Processing workspace and Kafka cluster to be on AWS
- Format: `"networking": {"access": {"type": "PRIVATE_LINK", "connectionId": "<Atlas PrivateLink ID>"}}`
- The `connectionId` is the Atlas PrivateLink `_id` (not the AWS service endpoint ID)

**VPC Peering:**
- Supported for outbound connections to Kafka brokers in your own VPC
- Requires `SASL_SSL` security protocol
- Use `atlas-streams-manage` with `accept-peering` action to complete the peering setup
- Requires AWS account ID, VPC ID, and region information

**Important: Networking cannot be modified after connection creation.** To add or change PrivateLink/VPC peering on an existing Kafka connection, you must delete it and recreate it with the networking config.

Use `atlas-streams-discover` → `action: "get-networking"` to list available PrivateLink endpoints and VPC peering connections.

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

Required IAM policy permissions: `s3:ListBucket`, `s3:GetObject`, `s3:PutObject`.

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

### SchemaRegistry
```json
{
  "connectionType": "SchemaRegistry",
  "connectionConfig": {
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
- `schemaRegistryUrls` is an **array** (not a string). The tool auto-wraps a string into an array if needed.
- `schemaRegistryAuthentication.type`: `"USER_INFO"` (explicit credentials) or `"SASL_INHERIT"` (inherit from Kafka connection)
- Tool elicitation will collect sensitive fields (password) — don't ask the user for these directly

### Sample
No connectionConfig required. Provides built-in test data. Useful for development and testing without external infrastructure.

Available sample formats: `sample_stream_solar` (default, auto-created when `includeSampleData: true` on workspace), `samplestock`, `sampleweather`, `sampleiot`, `samplelog`, `samplecommerce`.
