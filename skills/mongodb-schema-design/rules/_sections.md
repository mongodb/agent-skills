# Sections

This file defines all sections, their ordering, impact levels, and descriptions.
The section ID (in parentheses) is the filename prefix used to group rules.

---

## 1. Schema Anti-Patterns (antipattern)

**Impact:** CRITICAL
**Description:** Anti-patterns are the #1 cause of MongoDB production outages. A single unbounded array will crash your application when documents hit the 16MB BSON limit—we've seen this take down production systems handling millions of users at 3 AM. Bloated documents exhaust RAM, forcing MongoDB to page to disk and turning 5ms queries into 500ms nightmares. Atlas Performance Advisor and Compass flag these automatically, but catching them during development saves painful zero-downtime migrations. Every pattern in this section represents real production incidents we've seen repeatedly.

## 2. Schema Fundamentals (fundamental)

**Impact:** HIGH
**Description:** Get fundamentals wrong, and you'll spend months planning a migration. Get them right, and your schema scales from prototype to production without changes. The document model is fundamentally different from relational—"data that is accessed together should be stored together" means you can eliminate joins entirely and return complete objects in single reads. But embed vs. reference decisions are permanent: embedded documents can't be queried independently, and references require additional round-trips. These rules determine whether your application needs 1 query or 10 to render a page.

## 3. Relationship Patterns (relationship)

**Impact:** HIGH
**Description:** Every relationship in your application needs a modeling decision: embed or reference? One-to-one is almost always embedded. One-to-few (comments on a post, addresses for a user) benefits from embedding with bounded arrays. One-to-many (orders for a customer), one-to-squillions (activity logs, events), and many-to-many (students/courses) require references. Tree structures need special patterns (parent reference, child reference, materialized path). Wrong decisions create either bloated documents that hit the 16MB limit, or chatty applications that make 50 round-trips to load a single page. These patterns give you the decision framework.

## 4. Design Patterns (pattern)

**Impact:** MEDIUM
**Description:** MongoDB's document model enables patterns impossible in relational databases. Time series collections and the Bucket pattern reduce document count 10-100× for IoT and analytics workloads. The Attribute and Polymorphic patterns tame variable schemas and keep queries indexable. The Schema Versioning pattern keeps applications online during migrations. The Computed pattern pre-calculates expensive aggregations, trading write complexity for read performance. The Subset pattern keeps hot data embedded while archiving cold data, keeping working sets small. The Outlier pattern handles the viral post with 1M comments without penalizing the 99.9% with normal engagement. Apply these patterns when your use case matches—don't over-engineer simple schemas.

## 5. Schema Validation (validation)

**Impact:** MEDIUM
**Description:** Schema validation catches bad data before it corrupts your database. Without validation, one malformed document can break your entire application—a string where a number is expected, a missing required field, an array that should be an object. MongoDB's JSON Schema validation runs on every insert and update, enforcing data contracts at the database level. You can choose warn mode during development (logs violations but allows writes) or error mode in production (rejects invalid documents). Validation doesn't replace application logic, but it's your last line of defense against data corruption.
