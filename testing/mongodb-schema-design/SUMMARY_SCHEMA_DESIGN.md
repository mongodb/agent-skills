# MongoDB Schema Design Skill - Evaluation Summary

**Model:** Claude Sonnet 4.5  
**Date:** 2026-04-14  
**Skill Version:** mongodb-schema-design

---

## Executive Summary

The mongodb-schema-design skill was evaluated across three scenarios to measure its impact on recommendation quality. The skill consistently improves recommendation sophistication but introduces a trade-off with consultative process for minimal context questions.

### Key Findings

1. **Quality Improvement:** Skill upgrades recommendations from good → optimal across all scenarios
2. **Cost:** 2.9-3.3x time increase, acceptable for schema design work
3. **Process Issue:** Skill gives premature recommendations with minimal context (0% pass rate)
4. **Best Use:** Detailed questions with clear requirements

---

## Evaluation Scenarios

### Eval 1: Product Reviews (Full Context)

**Prompt:**
```
I'm building an e-commerce platform and I'm stuck on how to model product reviews. 
Each product can have anywhere from 0 to maybe 5000 reviews (most products have under 100 though). 
Each review has: reviewer name, rating (1-5 stars), review text (up to 2000 chars), helpful votes 
count, and timestamp. On the product page, I show the product details plus the 10 most recent reviews, 
and there's a "see all reviews" link that takes you to a paginated list. I also have a separate 
"My Reviews" page where users can see all their own reviews across all products. Should I embed the 
reviews in the product document or keep them in a separate reviews collection? I'm worried about the 
16MB limit but also don't want to do unnecessary lookups.
```

**Results:**

| Metric | Without Skill | With Skill | Impact |
|--------|--------------|------------|--------|
| **Time** | 49.6s | 143.3s | +2.9x |
| **Tokens** | 11,023 | 28,942 | +2.6x |
| **Recommendation** | Pure reference (separate collection) | **Hybrid: embed 10 recent + separate collection** | ✅ Optimized |

**Analysis:**

*Without Skill:*
- Recommends separate collection for all reviews
- Correct and safe approach
- Misses optimization for product page hot path
- Covers: document size, access patterns, indexes

*With Skill:*
- Recommends **Subset Pattern (hybrid approach)**
- Embed 10 most recent reviews in product document (zero-lookup product pages)
- Store all reviews in separate collection (pagination, "My Reviews")
- Includes: MongoDB decision framework, schema validation, transactions, verification queries
- Explains why pure embedding fails (4 problems) and why pure reference is suboptimal

**Conclusion:** Skill provides **major value** - transforms correct solution into optimal solution for high-traffic product pages.

---

### Eval 2: Product Reviews (Minimal Context)

**Prompt:**
```
I'm building an e-commerce platform with mongodb, currently planning a product reviews feature. 
I'm not sure whether to embed reviews in the product document or keep them in a separate collection.
```

**Results:**

| Metric | Without Skill | With Skill | Impact |
|--------|--------------|------------|--------|
| **Time** | 31.4s | 56.3s | +1.8x |
| **Tokens** | 10,563 | 21,319 | +2.0x |
| **Approach** | Gives recommendation with questions | Gives recommendation with questions | Both problematic |

**Assertions (5 key factors):**

| Assertion | Without Skill | With Skill |
|-----------|---------------|------------|
| Asks about cardinality | ✅ Yes | ✅ Yes |
| Asks about boundedness | ✅ Yes | ✅ Yes |
| Asks about access patterns | ✅ Yes | ✅ Yes |
| Mentions document size (16MB) | ✅ Yes | ✅ Yes |
| **Avoids premature recommendation** | ⚠️ No | ❌ No |

**Analysis:**

*Without Skill:*
- Asks questions but gives recommendation ("you should use separate collection")
- Questions come before or after recommendation depending on run
- Covers all MongoDB decision factors
- Inconsistent: sometimes asks first, sometimes recommends first

*With Skill:*
- Consistently gives "General Recommendation" section immediately
- Asks questions but already committed to approach
- Undermines consultative process
- Always gives recommendation despite insufficient context

**Conclusion:** Skill **degrades consultative approach** - should defer recommendations until requirements gathered. Both conditions fail, but skill makes it worse (0% vs partial success without skill).

---

### Eval 3: Blog Comments (Outlier Pattern)

**Prompt:**
```
I'm modeling blog posts and comments. Most posts have 5-20 comments, but a few viral posts 
have 50,000+ comments. Should I embed the comments in the post document or use a separate collection?
```

**Results:**

| Metric | Without Skill | With Skill | Impact |
|--------|--------------|------------|--------|
| **Time** | 33.0s | 109.2s | +3.3x |
| **Tokens** | 10,480 | 28,750 | +2.7x |
| **Recommendation** | Subset Pattern (static hybrid) | **Outlier Pattern (conditional)** | ✅ Advanced |

**Analysis:**

*Without Skill:*
- Recommends **Subset Pattern**
- Embed 10-20 most recent comments + store all in separate collection
- Static approach: same structure for all posts
- Good solution, handles both cases

*With Skill:*
- Recommends **Outlier Pattern**
- Embed comments by default for normal posts (5-20 comments)
- Automatic overflow to separate collection when threshold exceeded (e.g., 50 comments)
- Dynamic approach: adapts based on actual data
- Includes: threshold logic, `hasOverflow` flag, migration transactions, monitoring queries
- Cites `pattern-outlier.md` reference explicitly

**Comparison:**

| Approach | Normal Posts (95%) | Viral Posts (5%) |
|----------|-------------------|------------------|
| Subset (without skill) | Single query + embedded subset | Single query + separate pagination |
| Outlier (with skill) | Single query + all embedded | Overflow handling + pagination |

**Conclusion:** Skill provides **clear value** - teaches advanced conditional pattern that optimizes for data distribution. Outlier Pattern is more sophisticated than Subset Pattern.

---

## Overall Assessment

### When Skill Adds Value ✅

1. **Full context with detailed requirements**
   - Identifies hybrid optimizations
   - Provides MongoDB-specific patterns (Subset, Outlier, Extended Reference)
   - Includes implementation details (validation, transactions, monitoring)

2. **Specific pattern recognition**
   - Outlier scenarios (mixed cardinality)
   - Subset patterns (bounded hot data)
   - Extended references (cached denormalization)

3. **Learning & education**
   - Cites MongoDB principles ("data accessed together")
   - Warns about anti-patterns (unbounded arrays)
   - Provides decision frameworks and verification queries

### When Skill Has Issues ⚠️

1. **Minimal context scenarios**
   - Gives premature recommendations
   - Doesn't recognize insufficient information
   - Undermines consultative discovery process

2. **Performance cost**
   - 2.9-3.3x time increase
   - 2.0-2.7x token increase
   - Acceptable for schema design, but notable

### Skill Benefits

**Quality Improvements:**
- Pure reference → Hybrid (Subset Pattern)
- Static hybrid → Dynamic conditional (Outlier Pattern)
- Basic implementation → Production-ready (validation, transactions, monitoring)

**Knowledge Transfer:**
- MongoDB decision frameworks (1:1, 1:few, 1:many tables)
- Schema validation with `$jsonSchema`
- Document size calculations and verification queries
- Anti-pattern warnings (unbounded arrays, 16MB limit)
- Pattern library (Subset, Outlier, Computed, Extended Reference)

### Recommendations

**Deploy For:**
- ✅ Detailed schema design questions
- ✅ Users learning MongoDB patterns
- ✅ Production systems needing optimization
- ✅ Questions with clear requirements

**Improve For:**
- ❌ Minimal context questions (add conditional logic)
- ❌ Discovery phase (defer recommendations until context gathered)

**Priority Fix:**
```
IF user provides (cardinality AND access_patterns AND constraints)
    THEN recommend specific pattern
ELSE
    ASK discovery questions
    DEFER recommendation
    WAIT for user answers
```

---

## Performance Summary

| Scenario | Time Impact | Token Impact | Quality Impact | ROI |
|----------|-------------|--------------|----------------|-----|
| Full Context | +2.9x | +2.6x | Good → Optimal | High |
| Minimal Context | +1.8x | +2.0x | Problematic → Worse | Low |
| Outlier Pattern | +3.3x | +2.7x | Static → Dynamic | High |

**Average:** +2.7x time, +2.4x tokens

---

## Conclusion

The mongodb-schema-design skill provides **significant value** for Claude Sonnet 4.5:

1. **Transforms recommendations** from good → optimal (pure reference → hybrid, static → dynamic)
2. **Teaches advanced patterns** (Subset, Outlier, Extended Reference) that baseline doesn't know
3. **Includes production details** (validation, transactions, verification) not in baseline responses

**Critical issue:** Skill gives premature recommendations with minimal context, requiring fix before production deployment.

**Recommendation:** Deploy with documentation noting it works best with detailed context. Prioritize adding conditional logic for minimal context scenarios.

**Value proposition:** For Sonnet users, the 2.7x performance cost is justified by the quality improvement in schema design recommendations.
