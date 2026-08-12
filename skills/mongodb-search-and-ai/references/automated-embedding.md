# Automated Embedding

This guide covers how to configure MongoDB Vector Search to automatically generate and manage vector embeddings — no embedding code, no model infrastructure, no vector pipelines required.

Automated Embedding is available on all Atlas cluster tiers — M0 (free), Flex, and M10+ dedicated.

**Scope**: This guide covers the `autoEmbed` index type and text-query `$vectorSearch` syntax. For manual vector search (bring your own embeddings), see `vector-search.md`. For combining with lexical search, see `hybrid-search.md`.

---

## Table of Contents

- [When to Use Automated Embedding](#when-to-use-automated-embedding)
- [Prerequisites](#prerequisites)
- [Model Selection](#model-selection)
- [Index Definition](#index-definition)
- [Query Construction](#query-construction)
- [How It Works Internally](#how-it-works-internally)
- [Billing and Free Tokens](#billing-and-free-tokens)
- [Rate Limits](#rate-limits)
- [Management and Monitoring](#management-and-monitoring)
- [Troubleshooting](#troubleshooting)

---

## When to Use Automated Embedding

**Use Automated Embedding when:**
- The user wants semantic / vector search but doesn't want to write embedding code
- The user has no existing vector pipeline or embedding infrastructure
- The user is getting started quickly and wants a minimal-setup path
- The user's data is text stored in Atlas and they want to search it by meaning

**Use manual vector search (`vector-search.md`) when:**
- The user already generates their own embeddings
- The user needs a specific embedding model not offered by Voyage AI
- The user needs image, audio, or multimodal embeddings (Automated Embedding is text-only)
- The user is using self-managed MongoDB without Voyage AI API key access configured

**Decision shortcut:**
> "Do you have a vector embedding pipeline already, or do you want MongoDB to handle that for you?"
- **Already have one** → `vector-search.md`
- **Want MongoDB to handle it** → this guide

---

## Prerequisites

### Atlas Clusters

Automated Embedding is supported on **all Atlas cluster tiers**: M0 (free), Flex, and M10+ dedicated.

**M10+ dedicated clusters require auto-scaling to be enabled.** M0 and Flex clusters do not require auto-scaling.

| Current Tier | Required Maximum Tier |
|---|---|
| `M10` or `M20` (burstable CPU) | `M30` or higher |
| `M30` or higher | Any tier higher than current |
| NVMe storage | Enable "Scale NVMe cluster tier when storage is running low" |

Auto-scaling is required on M10+ so the cluster can scale up for the initial index build on large datasets, then scale back down automatically. M0 and Flex handle this differently and do not need it configured.

### Self-Managed Deployments

Requires:
1. MongoDB 8.3+ Community Edition with `mongot`
2. A Voyage AI API key for indexing
3. A Voyage AI API key for querying (recommended to use separate keys)
4. Keys configured in `mongot` during deployment

---

## Model Selection

All models use Voyage AI, hosted and managed by MongoDB (multi-tenant, US region, Google Cloud). Context window is **32,000 tokens** for all models. Text exceeding this is truncated at index time; queries exceeding it return a `context-limit-exceeded` error. (Pricing and rate limits can change—confirm current values in Atlas or official MongoDB documentation.)

| Model | Best For | Per 1K Tokens | Per 1M Tokens |
|---|---|---|---|
| `voyage-4-lite` | High-volume, cost-sensitive applications | $0.00002 | $0.02 |
| `voyage-4` | **(Recommended)** General text search, balanced performance | $0.00006 | $0.06 |
| `voyage-4-large` | Maximum accuracy, complex semantic relationships | $0.00012 | $0.12 |
| `voyage-code-3` | Code search, technical documentation | $0.00018 | $0.18 |

**Decision guide:**
- Default / unknown use case → `voyage-4`
- Large collection, cost is a concern → `voyage-4-lite`
- High-stakes retrieval where accuracy matters most → `voyage-4-large`
- Codebase or technical docs search → `voyage-code-3`

**Free tokens:** 200 million tokens per model, one-time, shared across the entire Atlas organization. Does not refresh. See [Billing and Free Tokens](#billing-and-free-tokens) below for how consumption and invoicing work.

---

## Index Definition

### Syntax

```javascript
{
  "fields": [
    {
      "type": "autoEmbed",
      "modality": "text",
      "path": "<text-field-to-embed>",
      "model": "<embedding-model>"
    },
    {
      "type": "filter",    // Optional: add one or more filter fields
      "path": "<field-to-filter-on>"
    }
  ]
}
```

### Fields

| Field | Required | Description |
|---|---|---|
| `type` | Yes | Must be `"autoEmbed"` |
| `modality` | Yes | Must be `"text"` (only text is supported currently) |
| `path` | Yes | The field in your documents containing the text to embed |
| `model` | Yes | The Voyage AI embedding model to use |

### Examples

**Minimal index (no filters):**
```javascript
{
  "fields": [
    {
      "type": "autoEmbed",
      "modality": "text",
      "path": "description",
      "model": "voyage-4"
    }
  ]
}
```

**With filter fields (recommended for scoped search):**
```javascript
{
  "fields": [
    {
      "type": "autoEmbed",
      "modality": "text",
      "path": "description",
      "model": "voyage-4"
    },
    {
      "type": "filter",
      "path": "category"
    },
    {
      "type": "filter",
      "path": "year"
    }
  ]
}
```

### Creating the Index via MCP

```javascript
db.collection.createSearchIndex(
  "<index-name>",
  "vectorSearch",
  {
    "fields": [
      {
        "type": "autoEmbed",
        "modality": "text",
        "path": "<text-field>",
        "model": "voyage-4"
      }
    ]
  }
)
```

**Note:** After creation, MongoDB performs an initial sync — generating embeddings for all existing documents. This can take several hours for large collections. Monitor progress via Atlas → Search & Vector Search.

---

## Query Construction

### Key Difference from Manual Vector Search

With Automated Embedding, you use **`query`** (a text string) instead of **`queryVector`** (an array of numbers). MongoDB generates the query embedding automatically.

### Basic Query Syntax

```javascript
db.collection.aggregate([
  {
    $vectorSearch: {
      index: "<index-name>",
      path: "<text-field>",
      query: "<your search text>",    // Plain text — no vector needed
      numCandidates: 100,
      limit: 10
    }
  },
  {
    $project: {
      _id: 0,
      description: 1,
      score: { $meta: "vectorSearchScore" }
    }
  }
])
```

### Query with Pre-filtering

```javascript
db.collection.aggregate([
  {
    $vectorSearch: {
      index: "<index-name>",
      path: "<text-field>",
      query: "your search text",
      filter: {
        $and: [
          { category: { $eq: "electronics" } },
          { year: { $gte: 2022 } }
        ]
      },
      numCandidates: 150,
      limit: 10
    }
  },
  {
    $project: {
      _id: 0,
      description: 1,
      category: 1,
      score: { $meta: "vectorSearchScore" }
    }
  }
])
```

### Optional: Override the Query Model

You can specify a different (but compatible) embedding model at query time:

```javascript
{
  $vectorSearch: {
    index: "<index-name>",
    path: "<text-field>",
    query: "your search text",
    model: "voyage-4-lite",    // Must be compatible with the index model
    numCandidates: 100,
    limit: 10
  }
}
```

### Query Parameters Reference

| Parameter | Required | Description |
|---|---|---|
| `index` | Yes | Name of the autoEmbed vector search index |
| `path` | Yes | The field indexed as `autoEmbed` |
| `query` | Yes (with autoEmbed) | Plain text query string |
| `numCandidates` | Yes (for ANN) | Candidates to evaluate; recommend 20x `limit` |
| `limit` | Yes | Number of results to return |
| `filter` | No | MQL pre-filter; field must be indexed as `filter` type |
| `model` | No | Override query embedding model (must be compatible) |
| `exact` | No | `true` for ENN (exact search), omit for ANN |

**Note:** Each query call counts against your Automated Embedding rate limits because it triggers an embedding API call.

---

## How It Works Internally

### Initial Sync
1. MongoDB scans all documents in the collection for the indexed text field
2. Sends text to the Voyage AI model in batches (uses Flex inference tier — no standard rate limits)
3. Stores embeddings in an internal reserved database: `__mdb_internal_search`
4. Builds the vector index from the stored embeddings

### Ongoing Updates (via Change Streams)
- **Insert**: New doc detected → embedding generated → stored → index updated
- **Update**: Changed field detected → new embedding generated → old one replaced → index updated
- **Delete**: Doc deleted → embeddings removed → index updated
- Updates to non-indexed fields do **not** trigger embedding regeneration

### Embeddings Storage
Stored in `__mdb_internal_search` (internal namespace — **do not modify this database**).

Each stored document has:
```javascript
{
  _id: <same as source document>,
  <filter-field>: <copied from source>,
  _autoEmbed: {
    "<fieldPath>": [<embedding vector>]
  }
}
```

---

## Billing and Free Tokens

**Token consumption occurs during:**
- Index creation (initial sync)
- Document inserts and updates
- Every query (embedding generated per query)

**Free allocation:** 200M tokens per model, per organization. One-time, does not refresh. Shared across all projects and clusters. See [Model Selection](#model-selection) above for per-model pricing after free tokens are used.

**View usage:** Atlas → Search & Vector Search → Automated Embedding → Usage

**View invoices:** Atlas → Billing → Invoices (broken down by model)

**M0 clusters:** When free tokens run out, MongoDB automatically invoices for additional usage — index builds and queries do not stop. M0 users can add a payment method without upgrading their cluster: Atlas → Billing → Payment Method. Charges are for embedding model usage only.

---

## Rate Limits

Rate limits are enforced at the **cluster level**, shared across all autoEmbed indexes on that cluster. They are applied **separately** for queries, index inserts/updates, and initial builds.

### Initial Index Build
No standard rate limits — uses a separate inference tier optimized for throughput, with dynamic scaling up to available GPU capacity, fair resource sharing between competing index builds, and safe ramp-up from low concurrency.

**Best practice:** create the index on a prepopulated collection rather than an empty one — the initial sync benefits from this unbounded throughput, while steady-state inserts/updates afterward are subject to the rate limits below.

### Index Insert/Update Rate Limits (all tiers)

| Model | RPM | TPM |
|---|---|---|
| `voyage-4-large` | 2,000 | 3,000,000 |
| `voyage-4` | 2,000 | 8,000,000 |
| `voyage-4-lite` | 2,000 | 16,000,000 |
| `voyage-code-3` | 2,000 | 3,000,000 |

**Best practice:** space out bulk insert/update operations rather than sending them all at once — batching avoids hitting these per-minute limits.

### Query Rate Limits

**Free cluster (M0 without a payment method) — all models:**

| Model | RPM | TPM |
|---|---|---|
| `voyage-4-large` | 3 | 2,000 |
| `voyage-4` | 3 | 2,000 |
| `voyage-4-lite` | 3 | 2,000 |
| `voyage-code-3` | 3 | 2,000 |

**Paid cluster (M0 with a payment method, Flex, or M10+ dedicated):**

| Model | RPM | TPM |
|---|---|---|
| `voyage-4-large` | 2,000 | 3,000,000 |
| `voyage-4` | 2,000 | 8,000,000 |
| `voyage-4-lite` | 2,000 | 16,000,000 |
| `voyage-code-3` | 2,000 | 3,000,000 |

Paid-tier limits increase automatically as usage grows over time — no action needed to benefit from that growth.

**If rate limits are hit:**
- Inserts/updates: queued and retried automatically with exponential backoff
- Queries: return an error — application must handle and retry
- Free cluster hitting the 3 RPM ceiling: add a payment method to upgrade to paid-tier limits (Atlas → Billing → Payment Method) — this alone unlocks up to 667x higher TPM
- Paid tier still hitting limits: contact MongoDB Support for a limit increase

---

## Management and Monitoring

### View Usage (Atlas)
Atlas → Search & Vector Search page → Automated Embedding → Usage

Shows:
- Total tokens used and remaining free tokens
- Usage breakdown by model
- Usage breakdown by operation (indexing vs querying)

### View Rate Limits (Atlas)
Atlas → Search & Vector Search page → Automated Embedding → Rate Limits

### View Organization-Level Usage
Atlas → Organization level → AI Models → Usage

### Disable Automated Embedding (Organization Policy)
Use Atlas Resource Policies with Cedar syntax.

**Disable entirely:**
```
forbid (
  principal,
  action == ResourcePolicy::Action::"search.index.modify",
  resource
) when {
  context.search.index.isAutoEmbed
};
```

**Disable with project-level exceptions** (replace `<project-id-1>`/`<project-id-2>` with actual project IDs):
```
forbid (
  principal,
  action == ResourcePolicy::Action::"search.index.modify",
  resource
) when {
  context.search.index.isAutoEmbed
} unless {
  resource in ResourcePolicy::Project::"<project-id-1>" ||
  resource in ResourcePolicy::Project::"<project-id-2>"
};
```

Apply at: Atlas → Organization Settings → Resource Policies → Create policy

**Note:** this policy blocks new `autoEmbed` indexes going forward. Existing `autoEmbed` indexes must be deleted manually to bring a project into compliance.

---

## Troubleshooting

**Index stuck in Building state / initial sync taking a long time**
- Normal for large collections — initial sync can take hours
- Monitor via Atlas → Search & Vector Search → index status
- Check token consumption hasn't exceeded rate limits

**Query returns `context-limit-exceeded` error**
- Your query text exceeds 32,000 tokens (the model context window)
- Truncate or shorten your query text before passing it to `$vectorSearch`

**Queries return rate limit error**
- You've exceeded your query RPM or TPM
- Free tier users: add a payment method to upgrade to paid limits
- Paid tier users: contact MongoDB Support for a limit increase
- Short term: implement retry with backoff in your application

**No results returned**
- Check the index status is `READY` (not `Building` or `Failed`)
- Verify the `path` in the query matches the `path` in the index definition
- Verify the `index` name matches exactly (typos return no results silently)

**Missing embeddings for some documents**
- Documents inserted before the index was created are synced during initial sync — check if sync is still in progress
- Documents without the indexed text field are skipped (no embedding generated)

**`__mdb_internal_search` database appearing in Data Explorer**
- This is normal — it's the internal storage for generated embeddings
- Do not modify or delete collections in this database
