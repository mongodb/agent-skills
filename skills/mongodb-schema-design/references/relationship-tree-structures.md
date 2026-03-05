---
title: Model Tree and Hierarchical Data
impact: HIGH
impactDescription: "Choose a tree pattern that matches query shape and update behavior"
tags: schema, relationships, tree, hierarchy, parent-child, categories
---

## Model Tree and Hierarchical Data

**Hierarchical data requires choosing a tree pattern based on your primary operations.** MongoDB offers multiple tree patterns, each with different tradeoffs for parent/child lookup, subtree traversal, and update cost.

**Incorrect (recursive queries for breadcrumbs):**

```javascript
// Using only parent references for breadcrumb navigation
{ _id: "MongoDB", parent: "Databases" }
{ _id: "Databases", parent: "Programming" }
{ _id: "Programming", parent: null }

// Building breadcrumb requires recursive queries
async function getBreadcrumb(categoryId) {
  const crumbs = []
  let current = await db.categories.findOne({ _id: categoryId })
  while (current && current.parent) {
    current = await db.categories.findOne({ _id: current.parent })
    crumbs.unshift(current)  // N queries for N-level hierarchy!
  }
  return crumbs
}
// 5-level deep category = 5 database round-trips per page view
```

**Correct (materialized path for breadcrumbs):**

```javascript
// Store full path for efficient ancestor/subtree traversal
{ _id: "MongoDB", path: ",Programming,Databases,MongoDB,", depth: 3 }

// Single query returns all ancestors
const category = db.categories.findOne({ _id: "MongoDB" })
const ancestors = category.path.split(",").filter(Boolean)
db.categories.find({ _id: { $in: ancestors } }).sort({ depth: 1 })
// Avoids iterative parent lookups across multiple round-trips
```

**Common hierarchical data:**
- Category trees (Electronics > Computers > Laptops)
- Organizational charts
- File/folder structures
- Comment threads
- Geographic hierarchies

### Pattern 1: Parent References

**Best for:** Finding parent, updating parent

```javascript
// Each node stores its parent's ID
{ _id: "MongoDB", parent: "Databases" }
{ _id: "Databases", parent: "Programming" }
{ _id: "Programming", parent: null }

// Index for efficient parent lookups
db.categories.createIndex({ parent: 1 })

// Find immediate children
db.categories.find({ parent: "Databases" })

// Find parent
db.categories.findOne({ _id: node.parent })

// Con: Finding all descendants requires recursive queries
```

### Pattern 2: Child References

**Best for:** Finding children, graph-like structures

```javascript
// Each node stores array of child IDs
{ _id: "Databases", children: ["MongoDB", "PostgreSQL", "MySQL"] }
{ _id: "MongoDB", children: ["Atlas", "Compass", "Shell"] }

// Find immediate children (embedded in document)
db.categories.findOne({ _id: "Databases" }).children

// Con: Finding all ancestors requires recursive queries
// Con: Array updates on every child add/remove
```

### Pattern 3: Array of Ancestors

**Best for:** Finding ancestors, breadcrumb navigation

```javascript
// Each node stores path from root
{ _id: "MongoDB", ancestors: ["Programming", "Databases"] }
{ _id: "Atlas", ancestors: ["Programming", "Databases", "MongoDB"] }

// Index for efficient ancestor queries
db.categories.createIndex({ ancestors: 1 })

// Find all ancestors (single query)
db.categories.findOne({ _id: "MongoDB" }).ancestors

// Find all descendants of "Databases"
db.categories.find({ ancestors: "Databases" })

// Build breadcrumb
db.categories.find({ _id: { $in: node.ancestors } })
```

Including a `parent` field alongside the ancestors array enables `$graphLookup` traversal without application-side recursion.

```javascript
// Include the parent field alongside ancestors for $graphLookup compatibility
{
  _id: "programming",
  name: "Programming",
  parent: "books",          // ← add this alongside ancestors array
  ancestors: ["books", "technology"]
}
// $graphLookup uses connectFromField/connectToField — requires a direct parent ref
db.categories.aggregate([
  { $match: { _id: "programming" } },
  { $graphLookup: {
    from: "categories",
    startWith: "$parent",
    connectFromField: "parent",
    connectToField: "_id",
    as: "ancestorDocs"
  }}
])
```

### Pattern 4: Materialized Paths

**Best for:** Finding subtrees, regex-based queries, sorting

```javascript
// Each node stores full path as string
{ _id: "MongoDB", path: ",Programming,Databases,MongoDB," }
{ _id: "Atlas", path: ",Programming,Databases,MongoDB,Atlas," }

// Index for path prefix queries
db.categories.createIndex({ path: 1 })

// Find all descendants (regex prefix match)
db.categories.find({ path: /^,Programming,Databases,MongoDB,/ })

// Find all ancestors (single query)
const pathParts = node.path.split(",").filter(Boolean)
db.categories.find({ _id: { $in: pathParts } })

// Sort by path for hierarchy display
db.categories.find({}).sort({ path: 1 })
```

### Pattern 5: Nested Sets

**Best for:** Fast subtree queries, rarely-changing trees

```javascript
// Each node stores left/right boundaries
{ _id: "Databases", left: 2, right: 7 }
{ _id: "MongoDB", left: 3, right: 4 }
{ _id: "PostgreSQL", left: 5, right: 6 }

// Find all descendants (single range query)
db.categories.find({
  left: { $gt: parent.left },
  right: { $lt: parent.right }
})

// Con: Insert/move requires updating many documents
// Best for read-heavy, rarely-modified hierarchies
```

### Pattern Comparison

| Pattern | Parent Lookup | Child Lookup | Descendant Queries | Ancestor Queries | Update Cost |
|---------|---------------|--------------|--------------------|------------------|-------------|
| Parent References | Direct | Indexed by `parent` | Recursive / `$graphLookup` | Recursive | Low |
| Child References | Via `children` membership query | Direct from `children` array | Recursive / `$graphLookup` | Recursive | Low to moderate (array maintenance) |
| Array of Ancestors | Optional via `parent` | Via `parent` or reverse query | Fast with `ancestors` index | Direct from stored array | Moderate (update ancestor arrays) |
| Materialized Paths | Via path parsing or `parent` field | Prefix path query | Flexible regex/prefix path queries (shape-dependent index efficiency) | From stored path | Moderate (path rewrites on moves) |
| Nested Sets | Via `parent` | Range boundaries | Fast range scans for subtrees | Range/predicate based | High for frequent tree mutations |

**Recommended patterns by use case:**

| Use Case | Best Pattern | Why |
|----------|--------------|-----|
| Category breadcrumbs | Array of Ancestors | Fast ancestor lookup |
| File browser | Parent References | Simple, fast child listing |
| Org chart reporting | Materialized Paths | Subtree queries + sorting |
| Static taxonomy | Nested Sets | Fastest reads, rare changes |
| Comment threads | Parent References | Comments change frequently |

**Example: E-commerce category tree**

```javascript
// Using Materialized Paths for category navigation
{
  _id: "laptop-gaming",
  name: "Gaming Laptops",
  path: ",electronics,computers,laptops,laptop-gaming,",
  parent: "laptops",
  depth: 4,
  productCount: 234  // Denormalized for display
}

// Create indexes
db.categories.createIndex({ path: 1 })
db.categories.createIndex({ parent: 1 })

// Get full category tree under "computers"
db.categories.find({ path: /^,electronics,computers,/ }).sort({ path: 1 })

// Get breadcrumb for product page
const category = db.categories.findOne({ _id: "laptop-gaming" })
const breadcrumb = category.path.split(",").filter(Boolean)
db.categories.find({ _id: { $in: breadcrumb } }).sort({ depth: 1 })
```

**When NOT to use tree patterns:**

- **Graph-like data**: If nodes can have multiple parents, use graph database or $graphLookup.
- **Flat structure**: If depth is always 1-2, simple parent reference is sufficient.
- **Extremely deep trees**: 100+ levels may need specialized approaches.

## Verify with

```javascript
// Check tree consistency (no orphans)
db.categories.aggregate([
  { $match: { parent: { $ne: null } } },
  { $lookup: {
    from: "categories",
    localField: "parent",
    foreignField: "_id",
    as: "parentDoc"
  }},
  { $match: { parentDoc: { $size: 0 } } },
  { $count: "orphanedNodes" }
])

// Check path consistency (materialized paths)
db.categories.find({
  $expr: {
    $ne: [
      { $size: { $split: ["$path", ","] } },
      { $add: ["$depth", 2] }  // +2 for leading/trailing commas
    ]
  }
})
```

Reference: [Model Tree Structures](https://mongodb.com/docs/manual/applications/data-models-tree-structures/)
