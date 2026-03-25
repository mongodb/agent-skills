# mongodb-query-optimizer — Eval Results

**Date:** 2026-03-24
**Model:** Claude Opus 4.6 (`us.anthropic.claude-opus-4-6-v1`)
**Iteration:** 1 (baseline)

## Results


| Eval                             | with_skill | without_skill | Differentiates? |
| -------------------------------- | ---------- | ------------- | --------------- |
| 1. $in operator optimization     | 3/3 (100%) | 2/3 (67%)     | Yes             |
| 2. $lookup aggregation           | 4/4 (100%) | 3/4 (75%)     | Yes             |
| 3. replaceOne oplog              | 3/3 (100%) | 2/3 (67%)     | Yes             |
| 4. Covered query                 | 3/3 (100%) | 3/3 (100%)    | No              |
| 5. Negative test (query writing) | 2/2 (100%) | 2/2 (100%)    | No              |
| 6. Atlas slow queries (MCP)      | 5/5 (100%) | 5/5 (100%)    | No              |
| 7. Atlas perf summary (MCP)      | 5/5 (100%) | 5/5 (100%)    | No              |
| 8. $facet aggregation (MCP)      | 5/5 (100%) | 4/5 (80%)     | Yes             |


**Overall: with_skill 100% vs without_skill 88% (+12%)**

## Key findings

- **Evals 1–3 differentiate well.** The skill's reference files provide specialized knowledge the model lacks: the ~200-element `$in` threshold (eval 1), top-N sort optimization (eval 2), and `$replaceWith` + `$literal` for oplog-efficient updates (eval 3).
- **Eval 4–5 don't differentiate.** The covered query `_id` issue and the negative test case are handled equally well with or without the skill.
- **MCP evals 6–7 don't differentiate.** When Atlas Performance Advisor provides index suggestions via API, both runs surface them equally. Consider adding assertions for skill-specific reasoning (e.g., ESR analysis) to better measure value-add.

---

## Iteration 2

**Date:** 2026-03-24
**Model:** Claude Sonnet 4.6 (`us.anthropic.claude-sonnet-4-6`)
**MCP config:** Evals 1–5 run **without** MCP server; evals 6–7 run **with** MCP server

## Results

| Eval                             | with_skill | without_skill | Differentiates? |
| -------------------------------- | ---------- | ------------- | --------------- |
| 1. $in operator optimization     | 2/3 (67%)  | 3/3 (100%)    | Inverted        |
| 2. $lookup aggregation           | 4/4 (100%) | 2/4 (50%)     | Yes             |
| 3. replaceOne oplog              | 3/3 (100%) | 2/3 (67%)     | Yes             |
| 4. Covered query                 | 3/3 (100%) | 3/3 (100%)    | No              |
| 5. Negative test (query writing) | 2/2 (100%) | 2/2 (100%)    | No              |
| 6. Atlas slow queries (MCP)      | 5/5 (100%) | 5/5 (100%)    | No              |
| 7. Atlas perf summary (MCP)      | 5/5 (100%) | 5/5 (100%)    | No              |

**Overall: with_skill 95% vs without_skill 88% (+7%)**

| Metric        | with_skill       | without_skill    | Delta   |
| ------------- | ---------------- | ---------------- | ------- |
| Pass Rate     | 95% ± 12%        | 88% ± 21%        | +7%     |
| Time          | 52.2s ± 26.0s    | 48.1s ± 26.4s    | +4.1s   |
| Tokens        | 18,252 ± 6,460   | 10,728 ± 5,929   | +7,524  |

## Key findings

- **Eval 1 inverted (with_skill 67% < without_skill 100%).** The skill agent converged on the single "safe" ESR index `{ status: 1, createdAt: -1, tags: 1 }` and didn't present `{ status: 1, tags: 1, createdAt: -1 }` as the better option for small `$in` lists. The baseline correctly surfaced both options with a size-based recommendation. The skill's ESR guidance may be too prescriptive for this nuanced case.
- **Evals 2–3 still differentiate well.** Skill prevents the `$project`-before-`$group` anti-pattern (eval 2) and surfaces `$replaceWith` + `$literal` for oplog-efficient syncs (eval 3) — both require reference file knowledge.
- **Evals 4–5 and MCP evals 6–7 remain non-differentiating**, same as iteration 1.
- **Token cost of skill:** ~7,500 extra tokens per run on average, primarily from loading reference files.
