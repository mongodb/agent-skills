# mongodb-qe-size-estimation — Eval Results (Iteration 4)

**Date:** 2026-09-25 (all four iterations run same day)
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

## Results (iteration 4)

| Eval                                   | with_skill   | without_skill | Differentiates?  |
| -------------------------------------- | ------------ | ------------- | ---------------- |
| 1. manual-inputs                       | 7/7 (100%)   | 1/7 (14%)     | Yes              |
| 2. encryption-schema-input             | 10/10 (100%) | 4/10 (40%)    | Yes              |
| 3. encryption-schema-input-2           | 8/8 (100%)   | 1/8 (13%)     | Yes              |
| 4. csfle-collection (negative)         | 1/1 (100%)   | 1/1 (100%)    | No (by construction) |
| 5. unencrypted-collection (negative)   | 1/1 (100%)   | 1/1 (100%)    | No (by construction) |

**Overall: with_skill 100% vs without_skill 53% (+47pp)**

| Metric     | with_skill | without_skill | Delta    |
| ---------- | ---------- | ------------- | -------- |
| Pass Rate  | 100%       | 53%           | +47pp    |
| Avg Time   | 78.4s      | 84.3s         | -5.9s    |
| Avg Tokens | 21,491     | 19,262        | +2,229   |

## Iteration history

| Iteration | with_skill | without_skill | What changed |
| --------- | ---------- | ------------- | ------------ |
| 1         | 97.4%      | 55.6%         | Initial suite; eval 1 with-skill lost 2/15 to the scripted user answering unasked questions |
| 2         | 100%       | 61.9%         | New General Instructions bullet (acknowledge input, ask next question) fixed both eval-1 turn-flow failures; advice math wrong-but-uncaught ('~9', correct 5) |
| 3         | 98.8%      | 62.2%         | New advice-prose assertion caught the advisory-math class (T quoted as 4, correct 5 — carryover from username's bounds); eval 1 tightened to 16 assertions |
| 4         | 100%       | 53.3%         | Eval 1 simplified to 7 outcome assertions; counterfactual advice math recomputed correctly |

Per-eval with_skill stayed at 100% on evals 2–5 across all four iterations; eval 1 went 87% → 100% → 94% → 100%. Baseline never passed a formula-dependent assertion in any run of any iteration.

## Key findings

- **Every formula-dependent assertion failed in every baseline run of every iteration.** 
  The baseline's disk estimates run 4–5x low in iteration 4 (~27–35 GB vs 
  137.34 GB; ~26 GB vs 309.72 GB) and 15–30x low in iteration 1. The 
  255-byte-per-token index entries exist only in the skill's formulas. No 
  baseline run produces a Required Memory figure.
- **All with-skill quantitative runs were bit-exact across all four iterations:** 
  both golden-file checks at zero differences and all headline
  totals exact every time, guarding against an LLM grader that only approximates 
  correctness.
- **Iteration 4's eval tightening worked as intended.** The baseline's eval-1 
  score dropped from 9/16 to 1/7 — its eight process assertions were passable by
  a competent generic agent just walking the conversation path. Its 
  single remaining point is the substring-dominance call, guessable from raw
  inputs. The aggregate baseline drop from 62.2% to 53.3% is attributable 
  to the eval change, not run variance.
- **Baseline failure modes are consistent:** no bookkeeping state 
  (no numIndexed/numEntries tallies), no memory estimate, arithmetic errors in 
  derived values (substring token sum computed as 78 where its own stated
  formula gives 66), and on invalid schemas it hedges but sizes anyway 
  (eval 3: 1/8). The skill rejects invalid schemas outright, including preview
  query types (`substringPreview`).
- **The advice-prose arc shows the loop working:** iteration 1 caught the 
  scripted-harness artifact, iteration 2's fix introduced an unchecked
  advisory-math error, iteration 3's new assertion caught it, iteration 4's 
  runs recomputed counterfactuals correctly with grader verification 
  (lb 3→5 drops T 107→52; T 187→92).
- **Negative triggers held:** correctly declined from the description alone.
- **Grader-flagged coverage gaps:** no assertion covers the Step 9 closing
  behavior (temp-file path notice, review-or-delete offer, sensitive-contents
  warning). It was performed correctly in every run but would pass silently if
  skipped.
- **Cost of the skill:** +2.2k tokens mean; time roughly equal.

## What's different about this skill and evals

This skill is an outlier in the repo's testing setup on two axes:

- **First to use turn-based (multi-turn) evals.** Evals 1–3 are scripted 
  conversations where inputs arrive across user turns, exercising the skill's
  interview workflow: asking for `v` once per field, declining to ask 
  for range-query fields, incrementing counts when a prefix+suffix field is
  revealed.
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
