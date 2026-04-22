# Skill Boundary Testing

This directory contains evaluation tests to validate that skills are invoked at the correct times based on user prompts.

## Purpose

These tests do NOT execute the skills - they only validate which skill gets triggered by the agent's skill selection mechanism. This ensures:
1. Clear cases trigger the correct skill
2. Ambiguous cases have predictable behavior
3. Skills don't conflict or trigger when they shouldn't

## Test Files

### natural-language-querying-vs-search-ai.json

Tests the boundary between:
- **mongodb-natural-language-querying**: Standard queries, filtering, aggregation, basic data retrieval
- **search-and-ai**: Atlas Search, vector search, fuzzy matching, semantic similarity, full-text search

**25 test cases covering:**
- 5 clear mongodb-natural-language-querying cases (basic filtering, aggregation, SQL translation)
- 8 clear search-and-ai cases (fuzzy matching, semantic search, full-text search, autocomplete)
- 8 ambiguous cases (the critical gray zone)
- 4 edge cases (optimization, exact match, case-insensitive, SQL translation)

## Running Tests

### Manual Testing

```bash
# For each test case in the JSON:
# 1. Present the prompt to your agent
# 2. Record which skill(s) get invoked
# 3. Compare against expected_skill
# 4. Mark as pass/fail
```

## Test Case Structure

```json
{
  "id": 1,
  "category": "clear_natural_language_querying",
  "prompt": "Find all users with age greater than 25",
  "expected_skill": "mongodb-natural-language-querying",
  "should_not_trigger": "search-and-ai",
  "reasoning": "Simple filtering with 'find' keyword",
  "trigger_keywords": ["find", "filter"],
  "ambiguity_level": "low"
}
```

## Interpreting Results

### Success Criteria

**Clear Cases (13 tests):**
- ✅ **>=95% accuracy**: Expected skill invoked, should_not_trigger skill not invoked
- 5 mongodb-natural-language-querying tests (basic filtering, aggregation)
- 8 search-and-ai tests (fuzzy matching, semantic search, full-text search)

**Ambiguous Cases (8 tests):**
- ✅ **>=70% expected behavior**: Expected skill invoked
- ⚠️ **Acceptable**: If test has `acceptable_alternative`, either skill is valid
- Includes cases where text search could use either regex or Atlas Search

**Edge Cases (4 tests):**
- ✅ **100% accuracy**: These test exclusions (e.g., optimization shouldn't trigger either skill)

### High-Priority Failure Cases

If these tests fail, descriptions need immediate revision:

1. **Test #13**: "I need to search my products database"
   - HIGH AMBIGUITY - monitor which skill wins
   - Should default to mongodb-natural-language-querying but search-and-ai is acceptable

2. **Test #20**: "I want users to be able to search products on my website"
   - HIGH AMBIGUITY - "build search" context
   - Preference: search-and-ai (building a feature) but ambiguous

3. **Test #25**: "can you find all movies about batman"
   - HIGH AMBIGUITY - content search scenario
   - Preference: search-and-ai (hybrid search captures semantic matches)
   - Acceptable: mongodb-natural-language-querying (regex pattern matching)
   - Tests whether agent recognizes content search benefits from full-text/semantic search

4. **Test #11-12**: Simple text pattern matching
   - "Find products where name contains 'laptop'"
   - "Query users where email includes '@gmail.com'"
   - Expected: search-and-ai (full-text search and custom analyzers)
   - Tests whether agent prefers Atlas Search for text operations

5. **Test #6-10**: Clear Atlas Search features
   - MUST trigger search-and-ai, never mongodb-natural-language-querying

6. **Test #1-5**: Clear basic queries
   - MUST trigger mongodb-natural-language-querying, never search-and-ai

## Ambiguity Levels

| Level | Meaning | Threshold |
|-------|---------|-----------|
| **low** | Clear boundary, expected skill should win 95%+ | Fail if wrong skill triggers |
| **medium** | Some overlap, expected skill should win 80%+ | Monitor if alternative triggers often |
| **high** | Genuine ambiguity, either skill acceptable | Track which wins, adjust if user confusion |

## Common Failure Patterns

### Pattern 1: "Search" Keyword Conflict
**Symptom:** Generic "search" prompts trigger wrong skill

**Fix:** Remove "search" from mongodb-natural-language-querying description, emphasize "explicitly need search features" in search-and-ai

### Pattern 2: Text Search Defaults to Regex Instead of Atlas Search
**Symptom:** "Find products with 'laptop' in name" triggers mongodb-natural-language-querying instead of search-and-ai

**Fix:** Emphasize that text search operations (contains, includes, pattern matching) benefit from Atlas Search's full-text capabilities

**Philosophy:** Atlas Search should be preferred for text search scenarios because:
- Full-text search with analyzers is more powerful than regex
- Better support for multi-language text
- Built-in relevance scoring
- Better performance on large text fields

### Pattern 3: Build vs Query Confusion
**Symptom:** "Build autocomplete" triggers mongodb-natural-language-querying

**Fix:** search-and-ai should emphasize "build", "create index", "implement" keywords

### Pattern 4: Content Search Ambiguity
**Symptom:** "Find movies about batman" could trigger either skill

**Philosophy:** Content search scenarios are HIGH AMBIGUITY - both approaches are valid:
- **search-and-ai**: Better results with semantic/full-text search (captures "The Dark Knight" without "batman" in title)
- **mongodb-natural-language-querying**: Simpler, faster with regex (only finds exact word matches)

Default to search-and-ai for better user experience, but mongodb-natural-language-querying is acceptable

## Test Maintenance

### When to Add Tests

Add new tests when you discover:
1. User confusion about which skill to use
2. Unexpected skill invocations
3. New features that might overlap boundaries

### When to Update Tests

Update tests when:
1. Skill descriptions change
2. New skills are added that overlap with these
3. Success criteria show consistent failures

## Results Template

```markdown
# Skill Boundary Test Results - [Date]

## Summary
- Total Tests: 25
- Passed: X/25
- Failed: Y/25
- Success Rate: Z%

## Clear Cases (13 tests)
- mongodb-natural-language-querying: X/5 correct
- search-and-ai: X/8 correct

## Ambiguous Cases (8 tests)
- Expected behavior: X/8
- Acceptable alternative: Y/8
- Unexpected: Z/8

## Edge Cases (4 tests)
- Passed: X/4

## Failures
[List any failed tests with details]

## Recommendations
[Suggested description updates based on results]
```

## Related Documentation

- `/tmp/conflict-analysis.md` - Detailed analysis of skill conflicts
- `/tmp/skill-boundary-analysis.md` - Comprehensive boundary strategy
- Skills under test:
  - `/skills/mongodb-natural-language-querying/SKILL.md`
  - `/skills/search-and-ai/SKILL.md`
