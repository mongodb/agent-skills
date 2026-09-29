# mongodb-qe-size-estimation — Eval Results (Iteration 5)

**Date:** 2026-09-29
**Model:** inherited session default (`glm-5p3[1m]`)
**Runs per configuration:** 1 (with_skill and without_skill) per iteration
**Grading:** LLM-graded assertions, including a golden-file match: the agent's
`qe-sizing-calculations.md` values must match `evals/expected/qe-sizing-calculations-<N>.md`.
The diff was performed by an ad-hoc grader script written during the runs (a run
artifact, not checked-in tooling). No MCP server, all evals are conversation-only
with schema JSON as input.

Eval roster: 
1. manual-inputs (multi-turn interview, inputs gathered turn by turn), 
2. encryption-schema-input (schema + doc count up front), 
3. encryption-schema-input-2 (invalid schema, must validate and reject), 
4. csfle-collection (negative trigger), 
5. unencrypted-collection (negative trigger).

## Results (iteration 5)

| Eval                                   | with_skill   | without_skill | Differentiates?  |
| -------------------------------------- | ------------ | ------------- | ---------------- |
| 1. manual-inputs                       | 10/10 (100%) | 1/10 (10%)    | Yes              |
| 2. encryption-schema-input             | 9/9 (100%)   | 2/9 (22%)     | Yes              |
| 3. encryption-schema-input-2           | 8/8 (100%)   | 2/8 (25%)     | Yes              |
| 4. csfle-collection (negative)         | 1/1 (100%)   | 1/1 (100%)    | No (by construction) |
| 5. unencrypted-collection (negative)   | 1/1 (100%)   | 1/1 (100%)    | No (by construction) |

**Overall: with_skill 100% vs without_skill 51% (+49pp)**

| Metric     | with_skill | without_skill | Delta    |
| ---------- | ---------- | ------------- | -------- |
| Pass Rate  | 100%       | 51%           | +49pp    |
| Avg Time   | 104.9s     | 132.8s        | -27.9s   |
| Avg Tokens | 23,066     | 19,821        | +3,245   |

## Iteration history

| Iteration | with_skill | without_skill | What changed |
| --------- | ---------- | ------------- | ------------ |
| 1         | 97.4%      | 55.6%         | Initial suite; eval 1 with-skill lost 2/15 to the scripted user answering unasked questions |
| 2         | 100%       | 61.9%         | New General Instructions bullet (acknowledge input, ask next question) fixed both eval-1 turn-flow failures; advice math wrong-but-uncaught ('~9', correct 5) |
| 3         | 98.8%      | 62.2%         | New advice-prose assertion caught the advisory-math class (T quoted as 4, correct 5 — carryover from username's bounds); eval 1 tightened to 16 assertions |
| 4         | 100%       | 53.3%         | Eval 1 simplified to 7 outcome assertions; counterfactual advice math recomputed correctly |
| 5         | 100%       | 51.4%         | Prefix+suffix reworked to a distinct single formula requiring more inputs (single entry with `lb_prefix`/`ub_prefix`/`lb_suffix`/`ub_suffix`; `numIndexed`/`numEntries` no longer double-count) |

Per-eval with_skill stayed at 100% on evals 2–5 across all five iterations; eval 1 went 87% → 100% → 94% → 100% → 100%. Baseline never passed a formula-dependent assertion in any run of any iteration.

## Key findings

- **The prefix+suffix rework regressed nothing.** with_skill stayed at 100%
  with both golden-file checks bit-exact, on both the schema-derived path and
  the manual path's single-lb/ub fallback.
- **Every formula-dependent assertion failed in every baseline run of every iteration.** 
  The 255-byte-per-token index entries exist only in the skill's formulas, and no
  baseline run produces a Required Memory figure.
- **All with-skill quantitative runs were bit-exact:** 
  both golden-file checks at zero differences and all headline
  totals exact every time, guarding against an LLM grader that only approximates 
  correctness.
- **Eval 1's assertions are outcome-focused by design.** Process assertions were
  passable by a competent generic agent just walking the conversation path, so
  they were cut; what remains is formula-dependent, plus the
  substring-dominance call, guessable from raw inputs.
- **Baseline failure modes are consistent:** no bookkeeping state 
  (no numIndexed/numEntries tallies), no memory estimate, arithmetic errors in 
  derived values, and on invalid schemas it hedges but sizes anyway. The skill
  rejects invalid schemas outright, including preview
  query types (`substringPreview`).
- **Advice prose derives its counterfactuals correctly:** suggested value
  changes recompute the corresponding formula, grader-verified against the
  skill's formulas.
- **Negative triggers held:** correctly declined from the description alone.
- **Grader-flagged coverage gaps:** no assertion covers the Step 9 closing
  behavior (temp-file path notice, review-or-delete offer, sensitive-contents
  warning). It was performed correctly in every run but would pass silently if
  skipped. Eval 1's bound-leakage assertions (no `_prefix`/`_suffix` values on
  prefix-only or suffix-only fields) are vacuous on the current fixture, which
  has no such field; "top field by impact" passes on ranking alone; and nothing
  covers the substring field-count limit or the `mlen < v` queryability warning.
- **Cost of the skill:** +3.2k tokens mean; time roughly equal.

## What's different about this skill and evals

This skill is an outlier in the repo's testing setup on two axes:

- **First to use turn-based (multi-turn) evals.** Evals 1–3 are scripted 
  conversations where inputs arrive across user turns, exercising the skill's
  interview workflow: asking for `v` once per field, declining to ask 
  for range-query fields, mapping a single lower/upper bound pair onto both
  the prefix and suffix configuration of a combined field.
- **First to grade against golden output files.** The domain is math-heavy, so
  beyond LLM-graded prose assertions, each quantitative eval checks the agent's
  recorded calculations file against a golden file
  (`evals/expected/qe-sizing-calculations-<N>.md`). The match is itself an
  assertion in `evals.json`. This turned the headline totals into
  deterministic pass/fail checks rather than grader judgment.

## Reproducing

```
/skill-creator Please run the evals for mongodb-qe-size-estimation. Evals are at
testing/mongodb-qe-size-estimation/evals/evals.json and the skill is at
skills/mongodb-qe-size-estimation/.
```
