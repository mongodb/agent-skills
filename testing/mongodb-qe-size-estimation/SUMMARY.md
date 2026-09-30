# mongodb-qe-size-estimation — Eval Results (Iteration 6)

**Date:** 2026-09-30
**Model:** inherited session default (`glm-5p3[1m]`)
**Runs per configuration:** 1 (with_skill and without_skill) per iteration
**Grading:** LLM-graded assertions, including a golden-file match: the agent's
`qe-sizing-calculations.md` values must match `evals/expected/qe-sizing-calculations-<N>.md`.
The diff was performed by an ad-hoc grader script written during the runs. No 
MCP server, all evals are conversation-only with schema JSON as input.

Eval roster: 
1. manual-inputs (multi-turn interview, inputs gathered turn by turn), 
2. encryption-schema-input (schema + doc count up front), 
3. encryption-schema-input-2 (invalid schema, must validate and reject), 
4. csfle-collection (negative trigger), 
5. unencrypted-collection (negative trigger).

## Results (iteration 6)

| Eval                                   | with_skill   | without_skill | Differentiates?  |
| -------------------------------------- | ------------ | ------------- | ---------------- |
| 1. manual-inputs                       | 10/10 (100%) | 3/10 (30%)    | Yes              |
| 2. encryption-schema-input             | 9/10 (90%)   | 1/10 (10%)    | Yes              |
| 3. encryption-schema-input-2           | 8/9 (89%)    | 1/9 (11%)     | Yes              |
| 4. csfle-collection (negative)         | 1/1 (100%)   | 1/1 (100%)    | No (by construction) |
| 5. unencrypted-collection (negative)   | 1/1 (100%)   | 1/1 (100%)    | No (by construction) |

**Overall: with_skill 95.8% vs without_skill 50.2% (+46pp)**

| Metric     | with_skill | without_skill | Delta    |
| ---------- | ---------- | ------------- | -------- |
| Pass Rate  | 95.8%      | 50.2%         | +46pp    |
| Avg Time   | 162.3s     | 368.0s        | -205.7s  |
| Avg Tokens | 23,875     | 22,736        | +1,139   |

## Iteration history

| Iteration | with_skill | without_skill | What changed |
| --------- | ---------- | ------------- | ------------ |
| 1         | 97.4%      | 55.6%         | Initial suite; eval 1 with-skill lost 2/15 to the scripted user answering unasked questions |
| 2         | 100%       | 61.9%         | New General Instructions bullet (acknowledge input, ask next question) fixed both eval-1 turn-flow failures; advice math wrong-but-uncaught ('~9', correct 5) |
| 3         | 98.8%      | 62.2%         | New advice-prose assertion caught the advisory-math class (T quoted as 4, correct 5 — carryover from username's bounds); eval 1 tightened to 16 assertions |
| 4         | 100%       | 53.3%         | Eval 1 simplified to 7 outcome assertions; counterfactual advice math recomputed correctly |
| 5         | 100%       | 51.4%         | Prefix+suffix reworked to a distinct single formula requiring more inputs (single entry with `lb_prefix`/`ub_prefix`/`lb_suffix`/`ub_suffix`; `numIndexed`/`numEntries` no longer double-count) |
| 6         | 95.8%      | 50.2%         | Formula constant 110→122; golden files regenerated, matched bit-exact; eval-3 note (string+range) accepted as valid (SKILL.md ambiguity, since fixed in working tree); advice-prose assertion carried to eval 2 post-run |
| 7         | —          | —             | In progress: prefix-only username field added to schema, bound-leakage assertions moved to eval 2 (prefix only), golden file regenerated; eval 2 re-run fresh (with_skill 10/11, without_skill 2/11); suite rerun aborted, no suite-level results |

Per-eval with_skill stayed at 100% on evals 2–5 across iterations 1–5; eval 1
went 87% → 100% → 94% → 100% → 100% → 100% (iteration 6). Iteration 6: eval 2
90% (advice-prose assertion added post-run), eval 3 89% (note, string+range —
SKILL.md ambiguity, fixed in working tree). Iteration 7 in progress: eval 2
re-run fresh with_skill 10/11, without_skill 2/11. Baseline never passed a
formula-dependent assertion in any run of any iteration.

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
- **Advice-prose counterfactual math failed on eval 2 in both graded runs**
  (iteration 6 post-run and iteration 7 fresh): T = 106 quoted vs correct 46;
  T = 4 vs correct 5.
- **Negative triggers held:** correctly declined from the description alone.
- **Grader-flagged coverage gaps:** no assertion covers the Step 9 closing
  behavior (temp-file path notice, review-or-delete offer, sensitive-contents
  warning). It was performed correctly in every run but would pass silently if
  skipped. Eval 1's bound-leakage assertions (no `_prefix`/`_suffix` values on
  prefix-only or suffix-only fields) are vacuous on the current fixture, which
  has no such field; "top field by impact" passes on ranking alone; and nothing
  covers the substring field-count limit or the `mlen < v` queryability warning.
- **Cost of the skill:** +1.1k tokens mean (iteration 6); with_skill faster
  on multi-turn evals.

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
