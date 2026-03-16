---
name: mongodb-schema-design
description: MongoDB schema design patterns and anti-patterns. Use when designing data models, reviewing schemas, migrating from SQL, or troubleshooting performance issues caused by schema problems. Triggers on "design schema", "embed vs reference", "MongoDB data model", "schema review", "unbounded arrays", "one-to-many", "tree structure", "16MB limit", "schema validation", "JSON Schema", "time series", "schema migration", "polymorphic", "TTL", "data lifecycle", "archive", "index explosion", "unnecessary indexes", "approximation pattern", "document versioning".
license: Apache-2.0
---

# MongoDB Schema Design

Data modeling patterns and anti-patterns for MongoDB, maintained by MongoDB. Contains **30 rules across 5 categories**, prioritized by impact. Bad schema is the root cause of most MongoDB performance and cost issues—queries and indexes cannot fix a fundamentally wrong model.

## When to Apply

Reference these guidelines when:
- Designing a new MongoDB schema from scratch
- Migrating from SQL/relational databases to MongoDB
- Reviewing existing data models for performance issues
- Troubleshooting slow queries or growing document sizes
- Deciding between embedding and referencing
- Modeling relationships (one-to-one, one-to-many, many-to-many)
- Implementing tree/hierarchical structures
- Seeing Atlas Schema Suggestions or Performance Advisor warnings
- Hitting the 16MB document limit
- Adding schema validation to existing collections

## Rule Categories by Priority

| Priority | Category | Impact | Prefix | Rules |
|----------|----------|--------|--------|-------|
| 1 | Schema Anti-Patterns | CRITICAL | `antipattern-` | 6 |
| 2 | Schema Fundamentals | HIGH | `fundamental-` | 4 |
| 3 | Relationship Patterns | HIGH | `relationship-` | 6 |
| 4 | Design Patterns | MEDIUM | `pattern-` | 12 |
| 5 | Schema Validation | MEDIUM | `validation-` | 2 |

## Quick Reference

### 1. Schema Anti-Patterns (CRITICAL) - 6 rules

- [antipattern-unbounded-arrays](references/antipattern-unbounded-arrays.md) - Avoid large and unbounded arrays
- [antipattern-bloated-documents](references/antipattern-bloated-documents.md) - Keep hot-path documents small; split hot vs cold fields
- [antipattern-unnecessary-collections](references/antipattern-unnecessary-collections.md) - Fewer collections, more embedding
- [antipattern-excessive-lookups](references/antipattern-excessive-lookups.md) - Reduce $lookup by denormalizing
- [antipattern-schema-drift](references/antipattern-schema-drift.md) - Enforce consistent structure across documents
- [antipattern-unnecessary-indexes](references/antipattern-unnecessary-indexes.md) - Audit and remove unused or redundant indexes

### 2. Schema Fundamentals (HIGH) - 4 rules

- [fundamental-embed-vs-reference](references/fundamental-embed-vs-reference.md) - Decision framework for relationships
- [fundamental-document-model](references/fundamental-document-model.md) - Embrace documents, avoid SQL patterns
- [fundamental-schema-validation](references/fundamental-schema-validation.md) - Enforce structure with JSON Schema
- [fundamental-16mb-awareness](references/fundamental-16mb-awareness.md) - Design around BSON document limit

### 3. Relationship Patterns (HIGH) - 6 rules

- [relationship-one-to-one](references/relationship-one-to-one.md) - Embed for simplicity, reference for independence
- [relationship-one-to-few](references/relationship-one-to-few.md) - Embed bounded arrays (addresses, phone numbers)
- [relationship-one-to-many](references/relationship-one-to-many.md) - Reference for large/unbounded relationships
- [relationship-one-to-squillions](references/relationship-one-to-squillions.md) - Reference massive child sets, store summaries
- [relationship-many-to-many](references/relationship-many-to-many.md) - Choose primary query direction; mix references with embedded summaries
- [relationship-tree-structures](references/relationship-tree-structures.md) - Parent/child/materialized path patterns

### 4. Design Patterns (MEDIUM) - 12 rules

- [pattern-approximation](references/pattern-approximation.md) - Use approximate values for high-frequency counters
- [pattern-archive](references/pattern-archive.md) - Move historical data to separate storage for performance
- [pattern-attribute](references/pattern-attribute.md) - Collapse many optional fields into key-value attributes
- [pattern-bucket](references/pattern-bucket.md) - Group time-series or IoT data into buckets
- [pattern-computed](references/pattern-computed.md) - Pre-calculate expensive aggregations
- [pattern-document-versioning](references/pattern-document-versioning.md) - Track document change history
- [pattern-extended-reference](references/pattern-extended-reference.md) - Cache frequently-accessed related data
- [pattern-outlier](references/pattern-outlier.md) - Handle documents with exceptional array sizes
- [pattern-polymorphic](references/pattern-polymorphic.md) - Store heterogeneous documents with a type discriminator
- [pattern-schema-versioning](references/pattern-schema-versioning.md) - Evolve schemas safely with version fields
- [pattern-subset](references/pattern-subset.md) - Store hot data in main doc, cold data elsewhere
- [pattern-time-series-collections](references/pattern-time-series-collections.md) - Use native time series collections when available

### 5. Schema Validation (MEDIUM) - 2 rules

- [validation-json-schema](references/validation-json-schema.md) - Validate data types and structure at database level
- [validation-action-levels](references/validation-action-levels.md) - Choose warn vs error mode for validation

## Key Principle

> **"Data that is accessed together should be stored together."**

This is MongoDB's core philosophy. Embedding related data eliminates joins, reduces round trips, and enables atomic updates. Reference only when you must.

A core way to implement this philosophy is the fact that MongoDB exposes **flexible schemas**. This means you can have different fields in different documents, and even different structures. This allows you to model data in the way that best fits your access patterns, without being constrained by a rigid schema. For example, if different documents have different sets of fields, that is perfectly fine as long as it serves your application's needs. You can also use schema validation to enforce certain rules while still allowing for flexibility.

Another implication of the key principle is that information about the expected read and write workload becomes very relevant to schema design. If pieces of information from different entities are often queried or updated together, that means that prioritizing co-location of that data in the same document can lead to significant performance benefits. On the other hand, if certain pieces of information are rarely accessed together, it may make sense to store them separately to avoid loading more data than necessary.

#### Schema Fundamentals Summary

- **Embed vs Reference**: Choose embedding or referencing based on access patterns: embed when data is always accessed together (1:1, 1:few, bounded arrays, atomic updates needed); reference when data is accessed independently, relationships are many-to-many, or arrays can grow without bound.
- **Data accessed together stored together**: MongoDB's core principle: design schemas around queries, not entities. Embed related data to eliminate cross-collection joins and reduce round trips. Identify your API endpoints/pages, list the data each returns, then shape documents to match those queries.
- **Embrace the document model**: Don't recreate SQL tables 1:1 as MongoDB collections. Instead, denormalize joined tables into rich documents for single-query reads and atomic updates. When migrating from SQL, identify tables that are always joined together and merge them into single documents.
- **Schema validation**: Use MongoDB's built-in `$jsonSchema` validator to catch invalid data at the database level (type checks, required fields, enum constraints, array size limits). Start with `validationLevel: "moderate"` and `validationAction: "warn"` on existing collections, then tighten to `strict`/`error`.
- **16MB document limit**: MongoDB documents cannot exceed 16MB—this is a hard limit, not a guideline. Common causes: unbounded arrays, large embedded binaries, deeply nested objects. Mitigate by moving unbounded data to separate collections and monitoring document sizes with `$bsonSize`.

## Embed/Reference Decision Framework

| Relationship | Cardinality | Access Pattern | Recommendation |
|-------------|-------------|----------------|----------------|
| One-to-One | 1:1 | Always together | Embed |
| One-to-Few | 1:N (N < 100) | Usually together | Embed array |
| One-to-Many | 1:N (N > 100) | Often separate | Reference |
| Many-to-Many | M:N | Varies | Two-way reference |

This is a **rough** guideline, and whether to embed or reference depends on your specific access patterns, data size, and read/write frequencies. Always verify with your actual workload.

## How to Use

Read individual reference files for detailed explanations and code examples.

Each reference file contains:
- Brief explanation of why it matters
- Incorrect code example with explanation
- Correct code example with explanation
- "When NOT to use" exceptions
- Performance impact and metrics
- Verification diagnostics

---

## How These Rules Work

### Recommendations with Verification

Every rule in this skill provides:
1. **A recommendation** based on best practices
2. **A verification checklist** of things that should be confirmed
3. **Commands to verify** so you can check before implementing
4. **MCP integration** for automatic verification when connected

### Why Verification Matters

I analyze code patterns, but I can't see your actual data without a database connection.
This means I might suggest:
- Fixing an "unbounded array" that's actually small and bounded
- Restructuring a schema that works well for your access patterns
- Adding validation when documents already conform to the schema

**Always verify before implementing.** Each rule includes verification commands.

### MongoDB MCP Integration

For automatic verification, connect the [MongoDB MCP Server](https://github.com/mongodb-js/mongodb-mcp-server).

If the MCP server is running and connected, I can automatically run verification commands to check your actual schema, document sizes, array lengths, index usage, and more. This allows me to provide tailored recommendations based on your real data, not just code patterns.

**⚠️ Security**: Use `--readOnly` for safety. Remove only if you need write operations.

When connected, I can automatically:
- Infer schema via `mcp__mongodb__collection-schema`
- Measure document/array sizes via `mcp__mongodb__aggregate`
- Check collection statistics via `mcp__mongodb__db-stats`

### ⚠️ Action Policy

**I will NEVER execute write operations without your explicit approval.**

| Operation Type | MCP Tools | Action |
|---------------|-----------|--------|
| **Read (Safe)** | `find`, `aggregate`, `collection-schema`, `db-stats`, `count` | I may run automatically to verify |
| **Write (Requires Approval)** | `update-many`, `insert-many`, `create-collection` | I will show the command and wait for your "yes" |
| **Destructive (Requires Approval)** | `delete-many`, `drop-collection`, `drop-database` | I will warn you and require explicit confirmation |

When I recommend schema changes or data modifications:
1. I'll explain **what** I want to do and **why**
2. I'll show you the **exact command**
3. I'll **wait for your approval** before executing
4. If you say "go ahead" or "yes", only then will I run it

**Your database, your decision.** I'm here to advise, not to act unilaterally.

### Working Together

If you're not sure about a recommendation:
1. Run the verification commands I provide
2. Share the output with me
3. I'll adjust my recommendation based on your actual data

We're a team—let's get this right together.


