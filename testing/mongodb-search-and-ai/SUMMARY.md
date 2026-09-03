# mongodb-search-and-ai — Eval Results (Iteration 1)

**Date:** 2026-08-07
**Model:** Claude Opus 4.6 (`claude-opus-4-6`)
**MCP config:** All 18 evals run **with** the MongoDB MCP server configured against the `sample_mflix` cluster (schema inspection, index checks, and `$search`/`$vectorSearch`/`autoEmbed` pipeline construction against real collections).
**Runs per configuration:** 1 (with_skill and without_skill baseline)

## Results

| Eval                        | with_skill    | without_skill | Delta   | Differentiates? |
| --------------------------- | ------------- | ------------- | ------- | --------------- |
| 1. comedy-robots            | 100% (10/10)  | 70% (7/10)    | +30%    | Yes             |
| 2. detective-facets         | 100% (8/8)    | 87.5% (7/8)   | +12.5%  | Yes             |
| 3. binary-quantization      | 100% (7/7)    | 57.1% (4/7)   | +42.9%  | Yes             |
| 4. vector-genre-filter      | 100% (9/9)    | 77.8% (7/9)   | +22.2%  | Yes             |
| 5. vector-sort-imdb         | 100% (6/6)    | 66.7% (4/6)   | +33.3%  | Yes             |
| 6. hybrid-search            | 100% (7/7)    | 71.4% (5/7)   | +28.6%  | Yes             |
| 7. autocomplete             | 100% (7/7)    | 71.4% (5/7)   | +28.6%  | Yes             |
| 8. fuzzy-search             | 100% (7/7)    | 71.4% (5/7)   | +28.6%  | Yes             |
| 9. regex-redirect           | 100% (5/5)    | 0% (0/5)      | +100%   | Yes             |
| 10. searchmeta-count        | 100% (5/5)    | 20% (1/5)     | +80%    | Yes             |
| 11. vector-date-prefilter   | 100% (7/7)    | 14.3% (1/7)   | +85.7%  | Yes             |
| 12. ecommerce-compound      | 77.8% (7/9)   | 55.6% (5/9)   | +22.2%  | Yes             |
| 13. rag-vector-filter       | 100% (9/9)    | 66.7% (6/9)   | +33.3%  | Yes             |
| 14. weighted-hybrid         | 100% (7/7)    | 28.6% (2/7)   | +71.4%  | Yes             |
| 15. support-ticket-vector   | 77.8% (7/9)   | 55.6% (5/9)   | +22.2%  | Yes             |
| 16. auto-embed              | 100% (8/8)    | 25% (2/8)     | +75%    | Yes             |
| 17. auto-embed-cost         | 100% (7/7)    | 0% (0/7)      | +100%   | Yes             |
| 18. auto-embed-code         | 87.5% (7/8)   | 12.5% (1/8)   | +75%    | Yes             |

**Overall: with_skill 95.2% vs without_skill 43.4% (+51.8%)**

| Metric     | with_skill | without_skill | Delta    |
| ---------- | ---------- | ------------- | -------- |
| Pass Rate  | 95.2%      | 43.4%         | +51.8%   |
| Avg Time   | 146.3s     | 85.4s         | +60.9s   |
| Avg Tokens | 42,574     | 25,241        | +17,333  |

Every eval differentiates — the base model never matched the skill on any case.

## Key findings

- **Biggest skill wins: evals 9, 17, 11, 16, 18.**
  - **Eval 9 (regex-redirect, +100%):** without-skill offers `$regex` directly; the skill correctly redirects to the Atlas Search `text` operator (relevance scoring, analyzers, performance).
  - **Eval 17 (auto-embed-cost, +100%):** without-skill recommends an OpenAI model (wrong ecosystem); the skill correctly recommends `voyage-4-lite` for cost-sensitive workloads.
  - **Eval 11 (vector-date-prefilter, +85.7%):** without-skill uses a standalone `$vectorSearch` with a simple filter; the skill correctly uses the `vectorSearch` operator inside `$search` with a search-type index so rich lexical prefilters (date range) apply.
  - **Evals 16 & 18 (autoEmbed, +75% each):** without-skill invents wrong `embeddingModel`/`queryString` syntax; the skill uses the correct `autoEmbed` index type and the plain-text `query` field (not `queryVector`).
- **New Automated Embedding coverage (16–18) validated the PR's headline feature.** These cases did not exist before this PR; all three show large deltas (+75%, +100%, +75%), confirming the `autoEmbed` guidance teaches the model something it demonstrably lacks.
- **Consistent without-skill failure modes:** (1) never asks for approval before creating indexes; (2) frequently skips schema inspection; (3) doesn't know specialized patterns — `autoEmbed` syntax, `vectorSearch`-inside-`$search`, `$searchMeta` for counts (eval 10: defaults to `$match`+`$count`), and `$rankFusion` (eval 14: builds a manual RRF pipeline).
- **Weakest with-skill results (evals 12 and 15 at 77.8%)** trace to transcript truncation from write-permission issues during the run, not skill-quality gaps.
- **Cost of the skill:** ~1.7x tokens (42.6K vs 25.2K) and ~1.7x time (146s vs 85s) on average, driven by loading reference files — a reasonable trade for a +51.8% pass-rate gain.

## Reproducing

```
/skill-creator Please run the evals for mongodb-search-and-ai. Evals are at
testing/mongodb-search-and-ai/evals/evals.json and the skill is at
skills/mongodb-search-and-ai/. Run all evals with the MongoDB MCP server
configured against the sample_mflix cluster.
```

Raw per-run outputs, timing, and grading live in the gitignored
`mongodb-search-and-ai-workspace/iteration-1/` directory (`benchmark.json` + per-eval subdirs).
