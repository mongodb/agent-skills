---
title: Rule Title Here
impact: CRITICAL|HIGH|MEDIUM
impactDescription: "Specific quantified impact: 10-100× improvement, 16MB limit avoided, 50ms→5ms"
tags: tag1, tag2, tag3
---

## Rule Title Here

**Impact: CRITICAL|HIGH|MEDIUM (specific quantified impact)**

Brief explanation of WHY this matters with specific impact metrics. Example: "This pattern prevents X which causes Y, improving performance by Z×."

**Incorrect (description of the problem):**

```javascript
// Bad code example with inline comments explaining the issue
// Metric: "Results in X behavior, Y impact"
db.collection.find({ field: "value" })
```

Brief explanation of what goes wrong with this approach and why.

**Correct (description of the solution):**

```javascript
// Good code example with inline comments explaining the fix
// Metric: "Results in X behavior, Y improvement"
db.collection.find({ field: "value" })
```

Brief explanation of why this solution works better.

**Alternative approach (when applicable):**

```javascript
// Alternative solution for specific use cases
db.collection.find({ field: "value" })
```

Explanation of when to use this alternative instead.

**When NOT to use this pattern:**

- Exception scenario 1 where this rule doesn't apply
- Exception scenario 2 where the trade-off isn't worth it
- Edge case that requires different handling

Reference: [MongoDB Documentation](https://mongodb.com/docs/manual/...)
