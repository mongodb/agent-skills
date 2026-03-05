---
title: Model Many-to-Many Relationships
impact: HIGH
impactDescription: "Choose embedding or referencing based on query direction and growth patterns"
tags: schema, relationships, many-to-many, referencing, embedding
---

## Model Many-to-Many Relationships

**Many-to-many relationships require choosing a primary query direction.** Unlike SQL's join tables, MongoDB favors denormalization toward your most common query pattern. Embed references in the collection you query most, and consider duplicating summary data for display efficiency.

**Common many-to-many examples:**
- Students ↔ Classes
- Books ↔ Authors
- Products ↔ Categories
- Users ↔ Roles
- Doctors ↔ Patients

**Incorrect (SQL-style junction table):**

```javascript
// SQL thinking: 3 collections, always need joins
// students: { _id, name }
// classes: { _id, name }
// enrollments: { studentId, classId }

// Get student with classes: 2 joins required
db.enrollments.aggregate([
  { $match: { studentId: "student1" } },
  { $lookup: { from: "classes", localField: "classId", foreignField: "_id", as: "class" } }
])
// Slow, complex, every query needs aggregation
```

**Correct (embed in primary query direction):**

```javascript
// If you query "which classes is this student in" most often:
// Embed class references in student
{
  _id: "student1",
  name: "Alice Smith",
  classes: [
    { classId: "class101", name: "Database Systems", instructor: "Dr. Smith" },
    { classId: "class102", name: "Web Development", instructor: "Dr. Jones" }
  ]
}

// If you query "which students are in this class" most often:
// Embed student references in class
{
  _id: "class101",
  name: "Database Systems",
  instructor: "Dr. Smith",
  students: [
    { studentId: "student1", name: "Alice Smith" },
    { studentId: "student2", name: "Bob Jones" }
  ]
}
```

**Bidirectional embedding (when both directions are common):**

```javascript
// Book with author summaries embedded
{
  _id: "book001",
  title: "Cell Biology",
  authors: [
    { authorId: "author124", name: "Ellie Smith" },
    { authorId: "author381", name: "John Palmer" }
  ]
}

// Author with book summaries embedded
{
  _id: "author124",
  name: "Ellie Smith",
  books: [
    { bookId: "book001", title: "Cell Biology" },
    { bookId: "book042", title: "Molecular Biology" }
  ]
}

// Trade-off: Data duplication, but fast queries in both directions
// Requires updating both documents when relationship changes
```

**Reference-only pattern (for large cardinality):**

```javascript
// When arrays would be too large, use reference arrays
// Product with category IDs only
{
  _id: "prod123",
  name: "Laptop",
  categoryIds: ["cat1", "cat2", "cat3"]  // Just IDs, small array
}

// Category with product IDs only
{
  _id: "cat1",
  name: "Electronics",
  productIds: ["prod123", "prod456", ...]  // Could be large
}

// Query with $lookup when needed
db.products.aggregate([
  { $match: { _id: "prod123" } },
  { $lookup: {
    from: "categories",
    localField: "categoryIds",
    foreignField: "_id",
    as: "categories"
  }}
])
```

**Choosing your strategy:**

| Query Pattern | Cardinality | Strategy |
|---------------|-------------|----------|
| Students → Classes | Few classes per student | Embed in student |
| Classes → Students | Many students per class | Reference only in class |
| Both directions common | Moderate both sides | Bidirectional embed |
| High cardinality both | Large and growing on both sides | Reference-only, use $lookup |

**Maintaining bidirectional data:**

```javascript
// Adding a student to a class requires 2 updates
// 1. Add class to student
db.students.updateOne(
  { _id: "student1" },
  { $push: { classes: { classId: "class101", name: "Database Systems" } } }
)

// 2. Add student to class
db.classes.updateOne(
  { _id: "class101" },
  { $push: { students: { studentId: "student1", name: "Alice Smith" } } }
)

// Use transactions for atomicity in critical applications
const session = client.startSession()
session.withTransaction(async () => {
  await db.students.updateOne({ _id: "student1" }, { $push: {...} }, { session })
  await db.classes.updateOne({ _id: "class101" }, { $push: {...} }, { session })
})
```

**When NOT to use this pattern:**

- **Extremely high cardinality**: If connections per entity grow without clear bounds, use reference-only with pagination (or evaluate graph-style approaches).
- **Frequently changing relationships**: If students change classes hourly, overhead of updating both sides is high.
- **No primary query direction**: If truly 50/50 query split, consider hybrid approach.

## Verify with

```javascript
// Check array sizes in many-to-many relationships
db.students.aggregate([
  { $project: { classCount: { $size: { $ifNull: ["$classes", []] } } } },
  { $group: {
    _id: null,
    avg: { $avg: "$classCount" },
    max: { $max: "$classCount" }
  }}
])
// If cardinality is high and growing toward unbounded arrays, consider reference-only pattern

// Verify bidirectional consistency
db.students.aggregate([
  { $unwind: "$classes" },
  { $lookup: {
    from: "classes",
    let: { sid: "$_id", cid: "$classes.classId" },
    pipeline: [
      { $match: { $expr: { $eq: ["$_id", "$$cid"] } } },
      { $match: { $expr: { $in: ["$$sid", "$students.studentId"] } } }
    ],
    as: "match"
  }},
  { $match: { match: { $size: 0 } } }  // Find inconsistencies
])
```

Reference: [Model Many-to-Many Relationships](https://mongodb.com/docs/manual/tutorial/model-embedded-many-to-many-relationships-between-documents/)
