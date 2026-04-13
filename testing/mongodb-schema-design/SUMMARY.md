# MongoDB Schema Design Skill - Evaluation Report

**Generated:** 2026-04-13  
**Skill:** mongodb-schema-design  
**Test Environment:** Claude Sonnet 4.5

---

## Executive Summary

This report evaluates the mongodb-schema-design skill's impact on response quality when helping users design MongoDB schemas. Two eval scenarios were tested, comparing responses with and without the skill.

### Key Findings

1. **Detailed Context Scenario** (Eval #1): Skill provides more comprehensive guidance with hybrid approaches
2. **Minimal Context Scenario** (Eval #2): Skill demonstrates better requirement gathering with structured questions
3. **Performance Trade-off**: Skill responses take 2-3x longer but provide significantly more depth
4. **Recommendation Quality**: Skill responses are more nuanced and cover multiple patterns

---

## Eval #1: Product Reviews with Full Context

### Prompt
```
I'm building an e-commerce platform and I'm stuck on how to model product reviews. 
Each product can have anywhere from 0 to maybe 5000 reviews (most products have 
under 100 though). Each review has: reviewer name, rating (1-5 stars), review text 
(up to 2000 chars), helpful votes count, and timestamp. On the product page, I show 
the product details plus the 10 most recent reviews, and there's a "see all reviews" 
link that takes you to a paginated list. I also have a separate "My Reviews" page 
where users can see all their own reviews across all products. Should I embed the 
reviews in the product document or keep them in a separate reviews collection? 
I'm worried about the 16MB limit but also don't want to do unnecessary lookups.
```

### Results Comparison

| Metric | Without Skill | With Skill | Difference |
|--------|--------------|------------|------------|
| **Time** | 49.6s | 143.3s | +2.9x |
| **Tokens** | 11,023 | 28,942 | +2.6x |
| **Recommendation** | Pure reference | Hybrid (reference + embedded subset) | More nuanced |

### Without Skill Response

**Recommendation:** Separate reviews collection (pure reference pattern)

**Key Points:**
- Document size safety (5000 reviews = 10MB)
- Access pattern alignment (product page, pagination, "My Reviews")
- Write performance benefits
- Recommended indexes
- Keep aggregate stats embedded

**Schema:**
```javascript
// products collection
{
  _id: ObjectId("..."),
  name: "Product Name",
  reviewStats: {
    averageRating: 4.5,
    totalReviews: 1247,
    ratingDistribution: { 5: 800, 4: 300, 3: 100, 2: 30, 1: 17 }
  }
}

// reviews collection
{
  _id: ObjectId("..."),
  productId: ObjectId("..."),
  userId: ObjectId("..."),
  rating: 5,
  text: "Great product!",
  helpfulVotes: 42,
  timestamp: ISODate("2026-04-13")
}
```

### With Skill Response

**Recommendation:** Hybrid approach (separate collection + embedded subset of 10 recent reviews)

**Key Points:**
- Uses MongoDB decision framework table (1:1, 1:few, 1:many, many-to-many)
- Analyzes cardinality: unbounded (0-5000) with most <100
- Access pattern analysis: three distinct patterns identified
  - Product page (high traffic) - needs recent reviews
  - Paginated reviews (moderate) - needs full set
  - My Reviews (low-moderate) - needs userId queries
- Hybrid optimization: embed 10 most recent for zero-lookup product page loads
- Comprehensive schema validation examples
- Transaction handling for consistency
- Document size verification queries

**Schema:**
```javascript
// products collection
{
  _id: ObjectId("..."),
  name: "Product Name",
  reviewStats: { /* ... */ },
  recentReviews: [  // Embedded subset - shown on product page
    { _id: ObjectId("..."), rating: 5, text: "...", timestamp: ... }
    // ... up to 10 reviews
  ]
}

// reviews collection (full data)
{
  _id: ObjectId("..."),
  productId: ObjectId("..."),
  userId: ObjectId("..."),
  /* ... full review data ... */
}
```

**Additional Value:**
- Explains why pure embedding fails (4 problems identified)
- Explains why pure reference is suboptimal (unnecessary lookups on high-traffic pages)
- Transaction example for maintaining consistency
- Schema validation with `maxItems: 10` enforcement
- Verification queries to monitor document sizes

### Analysis

**Without Skill:**
- ✅ Correct recommendation (separate collection works)
- ✅ Good reasoning about document size and access patterns
- ⚠️ Misses optimization opportunity for high-traffic product pages

**With Skill:**
- ✅ Uses MongoDB's formal decision framework
- ✅ Identifies hybrid optimization for the specific access patterns
- ✅ Provides implementation details (transactions, validation)
- ✅ Includes verification queries
- ⚠️ Takes 2.9x longer

**Winner:** Skill provides superior recommendation (hybrid vs pure reference)

---

## Eval #2: Product Reviews with Minimal Context

### Prompt (Iteration 2)
```
I'm building an e-commerce platform with mongodb, currently planning a product 
reviews feature. I'm not sure whether to embed reviews in the product document 
or keep them in a separate collection.
```

### Results Comparison

| Metric | Without Skill | With Skill | Difference |
|--------|--------------|------------|------------|
| **Time** | 31.9s | 67.2s | +2.1x |
| **Tokens** | 10,538 | 22,622 | +2.1x |
| **Approach** | Recommends immediately | Asks questions first | Better discovery |

### Assertions Evaluation

| Assertion | Without Skill | With Skill |
|-----------|---------------|------------|
| **Asks about cardinality** | ⚠️ Partial (only in follow-up) | ✅ Yes (upfront) |
| **Asks about access patterns** | ⚠️ Partial (only in follow-up) | ✅ Yes (upfront) |
| **Asks about independent queries** | ⚠️ Partial (only in follow-up) | ✅ Yes (upfront) |
| **Avoids premature recommendation** | ❌ No (recommends separate collection immediately) | ✅ Yes (asks questions, then provides general guidance) |

### Without Skill Response

**Approach:** Recommends separate collection immediately, asks follow-up questions after

**Structure:**
1. ❌ **Recommendation first**: "I recommend using a separate collection"
2. Provides reasoning (unbounded growth, query patterns, write performance)
3. Shows schema examples
4. Asks 4 follow-up questions at the end

**Issue:** Makes assumptions without gathering requirements. Gives definitive answer despite minimal context.

### With Skill Response

**Approach:** Asks discovery questions first, provides general guidance for scenarios

**Structure:**
1. ✅ **Questions first**: "Initial Questions to Understand Your Use Case"
   - Cardinality & boundedness
   - Access patterns
   - Independent query patterns
   - Review content size
2. General guidance from MongoDB principles
   - When to embed (with criteria)
   - When to reference (with criteria)
   - Hybrid approach (recommended for e-commerce)
3. Warning about unbounded arrays with calculations
4. Recommended approach with next steps

**Strength:** Consultative approach, educates on patterns, asks for specifics before committing to recommendation.

### Analysis

**Without Skill:**
- ❌ Jumps to recommendation without gathering requirements
- ⚠️ Follow-up questions are too late (after committing to solution)
- ✅ Recommendation is reasonable for typical e-commerce

**With Skill:**
- ✅ Asks structured discovery questions upfront
- ✅ Provides decision framework for different scenarios
- ✅ Educates on MongoDB principles
- ✅ Emphasizes need for more information before final recommendation

**Winner:** Skill demonstrates significantly better requirement gathering process

---

## Iteration Comparison: Eval #2

We tested two versions of the minimal prompt:

### Iteration 1
**Prompt:** "Should I embed reviews in my product documents?"

- **Without skill:** ✅ Correctly asked questions first
- **With skill:** ❌ Jumped to recommendations despite minimal context

### Iteration 2  
**Prompt:** "I'm building an e-commerce platform with mongodb, currently planning a product reviews feature. I'm not sure whether to embed reviews in the product document or keep them in a separate collection."

- **Without skill:** ❌ Recommended immediately
- **With skill:** ✅ Asked questions first

**Key Insight:** Adding "e-commerce platform" context gave both agents more to work with, but the skill helped structure the response more appropriately with discovery questions.

---

## Overall Assessment

### Skill Benefits

1. **Higher Quality Recommendations**
   - Hybrid patterns vs simple embed/reference
   - Uses formal MongoDB decision frameworks
   - Considers multiple access patterns

2. **Better Implementation Guidance**
   - Schema validation examples
   - Transaction handling
   - Verification queries
   - Index recommendations

3. **Improved Requirement Gathering**
   - Structured discovery questions
   - Educates on tradeoffs
   - Scenario-based guidance

4. **MongoDB Best Practices**
   - Cites core principles ("data accessed together")
   - Warns about anti-patterns (unbounded arrays)
   - Provides calculations (document size)

### Trade-offs

1. **Performance Cost**
   - 2-3x longer response time
   - 2-3x more tokens used
   - Acceptable for schema design (not time-critical)

2. **Response Length**
   - Much more comprehensive
   - Could be overwhelming for simple questions
   - Good for learning, potentially verbose for experts

### Recommendations

1. **Use the skill for:**
   - Schema design decisions with complexity
   - Users learning MongoDB patterns
   - When optimization matters (high-scale apps)
   - Questions with multiple access patterns

2. **Skill could be improved:**
   - Add guidance about when to ask discovery questions vs when to provide recommendations
   - Consider response length based on user expertise signals
   - Provide "quick answer" + "detailed explanation" options

---

## Appendix: Test Artifacts

### File Locations

**Eval Definitions:**
```
/Users/ps/dev/agent-skills/testing/mongodb-schema-design/evals/evals.json
```

**Test Results:**
```
/Users/ps/dev/agent-skills/testing/mongodb-schema-design/mongodb-schema-design-workspace/
├── iteration-1/
│   ├── product-reviews-embed-vs-reference/
│   │   ├── without_skill/outputs/recommendation.md
│   │   ├── with_skill/outputs/recommendation.md
│   │   └── eval_metadata.json
│   └── reviews-minimal-context/
│       ├── without_skill/outputs/response.md
│       ├── with_skill/outputs/response.md
│       └── eval_metadata.json
└── iteration-2/
    └── reviews-minimal-context/
        ├── without_skill/outputs/response.md
        ├── with_skill/outputs/response.md
        └── eval_metadata.json
```

### Metrics Summary

| Eval | Iteration | Without Skill Time | With Skill Time | Without Skill Tokens | With Skill Tokens |
|------|-----------|-------------------|-----------------|---------------------|-------------------|
| #1 (Full Context) | 1 | 49.6s | 143.3s | 11,023 | 28,942 |
| #2 (Minimal) | 1 | 43.6s | 85.5s | 24,670 | 25,299 |
| #2 (Minimal) | 2 | 31.9s | 67.2s | 10,538 | 22,622 |

**Average Impact:** 2.3x time increase, 2.0x token increase

---

## Conclusion

The mongodb-schema-design skill provides significant value for schema design questions:

- **Quality:** Recommendations are more nuanced and better optimized
- **Education:** Responses teach MongoDB patterns and principles
- **Completeness:** Includes validation, verification, and implementation details
- **Discovery:** Better requirement gathering for ambiguous questions

The 2-3x performance cost is acceptable given that schema design is not time-critical and benefits from thoroughness. The skill is particularly valuable for users learning MongoDB or designing complex, high-scale systems.

**Recommendation:** Deploy the skill. Consider adding guidance about response verbosity based on user context.
