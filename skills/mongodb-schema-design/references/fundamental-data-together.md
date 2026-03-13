---
title: Store Data That's Accessed Together
impact: HIGH
impactDescription: "Reduces application-side joins by aligning document shape to common access patterns"
tags: schema, embedding, access-patterns, fundamentals, mongodb-philosophy
---

## Store Data That's Accessed Together

**MongoDB's core principle: data that is accessed together should be stored together.** Design schemas around queries, not entities. In many workloads this reduces cross-collection joins and simplifies common reads.

**Incorrect (entity-based design):**

```javascript
// Designed like SQL tables - 3 queries for one page
// articles: { _id, title, content, authorId }
// authors: { _id, name, bio }
// article_tags: { articleId, tag }

// Display article page requires 3 separate queries
const article = await db.articles.findOne({ _id: articleId })  // Query 1
const author = await db.authors.findOne({ _id: article.authorId })  // Query 2
const tags = await db.article_tags.find({ articleId }).toArray()  // Query 3
// 3 round-trips, 3 index lookups, application joins
// If author query fails, you still show partial page? Complexity grows.
```

**Correct (query-based design):**

```javascript
// Everything needed for article page in one document
// Schema matches the API response shape
{
  _id: "article123",
  title: "MongoDB Best Practices",
  content: "...",
  author: {
    _id: "auth456",           // Keep reference for author profile link
    name: "Jane Developer",    // Embedded for display
    avatar: "https://..."      // Embedded for display
  },
  tags: ["mongodb", "database", "performance"],  // Embedded array
  publishedAt: ISODate("2024-01-15"),
  readingTime: 8
}

// Single query returns complete article view
const article = await db.articles.findOne({ _id: articleId })
// API response can return document directly - no transformation
```

**How to identify access patterns:**

```javascript
// Step 1: List your API endpoints/pages
// GET /article/:id - article page
// GET /articles - article list
// GET /author/:id - author profile

// Step 2: For each endpoint, list what data is returned
// /article/:id needs: title, content, author.name, author.avatar, tags
// /articles needs: title, author.name, publishedAt (no content)
// /author/:id needs: full author bio, their articles list

// Step 3: Design documents to match those queries
// Result: Embed author summary in articles, keep full author separate
```

**Common embedding patterns:**

```javascript
// E-commerce: Product with review summary (not all reviews)
{
  _id: "prod123",
  name: "Widget",
  price: 29.99,
  reviewSummary: {
    avgRating: 4.5,
    count: 127,
    distribution: { 5: 80, 4: 30, 3: 10, 2: 5, 1: 2 }
  },
  topReviews: [/* top 3 reviews for product page */]
}

// User dashboard: Embed counts, reference details
{
  _id: "user123",
  name: "Alice",
  stats: {
    orderCount: 42,
    totalSpent: 1234.56,
    lastOrderDate: ISODate("...")
  }
  // Don't embed 42 order documents - reference them
}
```

**When NOT to use this pattern:**

- **Data accessed independently**: Author profile page exists separately from articles—keep full author data in authors collection.
- **Different update frequencies**: If author avatar changes daily but articles never change, embedding creates update overhead.
- **Unbounded growth**: Don't embed all 10,000 comments in a popular post.

## Verify with

```javascript
// Profile your actual queries
db.setProfilingLevel(1, { slowms: 10 })

// Find queries that always happen together
db.system.profile.aggregate([
  { $match: { op: "query" } },
  { $group: {
    _id: {
      minute: { $dateToString: { format: "%Y-%m-%d %H:%M", date: "$ts" } }
    },
    collections: { $addToSet: "$ns" },
    count: { $sum: 1 }
  }},
  { $match: { "collections.1": { $exists: true } } }  // Multiple collections
])
// Collections queried in same minute = candidates for embedding
```

Reference: [Data Modeling Introduction](https://mongodb.com/docs/manual/data-modeling/)
