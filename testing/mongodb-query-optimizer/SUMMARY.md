# mongodb-query-optimizer — Eval Results (Iteration 4)

**Date:** 2026-03-25
**Model:** Claude Opus 4.6 (`us.anthropic.claude-opus-4-6-v1`)
**MCP config:** Evals 1–5 run **without** MCP server; evals 6–8 run **with** MCP server

## Results

| Eval                             | with_skill  | without_skill | Differentiates? |
| -------------------------------- | ----------- | ------------- | --------------- |
| 1. $in operator optimization     | 2/3 (67%)   | 2/3 (67%)     | No              |
| 2. $lookup aggregation           | 4/4 (100%)  | 2/4 (50%)     | Yes             |
| 3. replaceOne oplog              | 3/3 (100%)  | 2/3 (67%)     | Yes             |
| 4. Covered query                 | 3/3 (100%)  | 3/3 (100%)    | No              |
| 5. Negative test (query writing) | 2/2 (100%)  | 2/2 (100%)    | No              |
| 6. Atlas slow queries (MCP)      | 5/5 (100%)  | 5/5 (100%)    | No              |
| 7. Atlas perf summary (MCP)      | 5/5 (100%)  | 4/5 (80%)     | Yes             |
| 8. $facet aggregation (MCP)      | 4/5 (80%)   | 2/5 (40%)     | Yes             |

**Overall: with_skill 93% vs without_skill 76% (+17%)**

| Metric        | with_skill       | without_skill    | Delta    |
| ------------- | ---------------- | ---------------- | -------- |
| Pass Rate     | 93%              | 76%              | +17%     |
| Avg Time      | 76.0s            | 70.6s            | +5.4s    |
| Avg Tokens    | 19,687           | 14,988           | +4,699   |

## Key findings

- **Biggest skill wins: evals 2, 3, and 8.** The skill's reference files provide specialized MongoDB knowledge the base model lacks: top-N sort optimization and avoiding the `$project`-before-`$group` anti-pattern (eval 2), `$replaceWith` + `$literal` for oplog-efficient updates (eval 3), and the `$facet` → `$unionWith` rewrite pattern (eval 8).
- **Eval 1 tied at 67%.** Both versions missed the assertion about `{ status: 1, tags: 1, createdAt: -1 }` being suitable for small `$in` lists — both converged on the ESR-based `{ status: 1, createdAt: -1, tags: 1 }` index without presenting the alternative.
- **Eval 7 skill edge.** The skill correctly called all three Performance Advisor operations (suggestedIndexes, slowQueryLogs, dropIndexSuggestions) while the baseline missed slowQueryLogs.
- **Eval 8 strongest differentiator (+40%).** The skill recommended replacing `$facet` with `$unionWith` for independent pipeline optimization — knowledge from `aggregation-optimization.md`. The baseline only suggested generic improvements (pre-$match, $project, $limit) without the structural rewrite.
- **Eval 8 caveat.** Both versions couldn't find the actual `$facet` query in slow query logs (aged out of retention window), costing the skill one assertion.
- **Evals 4–5 and 6 remain non-differentiating.** Covered query `_id` issue and negative test are handled equally well. MCP-based slow query discovery (eval 6) works equally well with or without the skill.
- **Token cost of skill:** ~4,700 extra tokens per run on average, primarily from loading reference files. Time overhead is modest (+5.4s).
