# mongodb-qe-size-estimation — Eval Results (Iteration 10)

**Date:** 2026-10-02
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
5. unencrypted-collection (negative trigger), 
6. sample-data (user offers a sample document; must be rejected for security reasons).

## Results (iteration 10)

| Eval                                   | with_skill   | without_skill | Differentiates?  |
| -------------------------------------- | ------------ | ------------- | ---------------- |
| 1. manual-inputs                       | 8/8 (100%)   | 3/8 (38%)     | Yes              |
| 2. encryption-schema-input             | 11/11 (100%) | 3/11 (27%)    | Yes              |
| 3. encryption-schema-input-2           | 9/9 (100%)   | 1/9 (11%)     | Yes              |
| 4. csfle-collection (negative)         | 1/1 (100%)   | 1/1 (100%)    | No (by construction) |
| 5. unencrypted-collection (negative)   | 1/1 (100%)   | 1/1 (100%)    | No (by construction) |
| 6. sample-data                         | 1/1 (100%)   | 0/1 (0%)      | Yes              |

**Overall (macro-average of per-eval percentages): with_skill 100% vs
without_skill 45.9% (+54pp). Aggregate assertion pass rate: with_skill 31/31
(100%) vs without_skill 9/31 (29.0%).**

| Metric               | with_skill | without_skill | Delta    |
| -------------------- | ---------- | ------------- | -------- |
| Pass Rate (macro-avg) | 100%       | 45.9%         | +54pp    |
| Avg Time             | 67.1s      | 67.3s         | -0.2s    |
| Avg Tokens            | 23,074     | 18,976        | +4,098   |

Pass Rate is the unweighted mean of the six per-eval percentages: the two
one-assertion negative evals (baseline 1/1 by construction) carry the same
weight as the 11-assertion eval, which is why the macro-average (45.9%) sits
well above the aggregate assertion rate (29.0%). with_skill is 100% by either
measure.

Avg Time is comparable this iteration (no permission-confirmation waits, see
run history): the two configurations are within 0.2s of each other.

## Iteration history

| Iteration | with_skill | without_skill | What changed |
| --------- | ---------- | ------------- | ------------ |
| 1         | 97.4%      | 55.6%         | Initial suite; eval 1 with-skill lost 2/15 to the scripted user answering unasked questions |
| 2         | 100%       | 61.9%         | New General Instructions bullet (acknowledge input, ask next question) fixed both eval-1 turn-flow failures; advice math wrong-but-uncaught ('~9', correct 5) |
| 3         | 98.8%      | 62.2%         | New advice-prose assertion caught the advisory-math class (T quoted as 4, correct 5 — carryover from username's bounds); eval 1 tightened to 16 assertions |
| 4         | 100%       | 53.3%         | Eval 1 simplified to 7 outcome assertions; counterfactual advice math recomputed correctly |
| 5         | 100%       | 51.4%         | Prefix+suffix reworked to a distinct single formula requiring more inputs (single entry with `lb_prefix`/`ub_prefix`/`lb_suffix`/`ub_suffix`; `numIndexed`/`numEntries` no longer double-count) |
| 6         | 95.8%      | 50.2%         | Formula constant 110→122; golden files regenerated, matched bit-exact; eval-3 note (string+range) accepted as valid (SKILL.md ambiguity, since fixed in working tree); advice-prose assertion carried to eval 2 post-run |
| 7         | —          | —             | Prefix-only username field added to schema, bound-leakage assertions moved to eval 2 (prefix only), golden file regenerated; eval 2 re-run fresh (with_skill 10/11, without_skill 2/11); suite rerun aborted, no suite-level results |
| 8         | —          | —             | All 12 runs completed (eval 6, sample-data, added) but grading aborted after eval-1 with_skill (8/8); superseded by a fresh iteration-9 rerun |
| 9         | 100%       | 41.8%         | Full suite re-run as a unit (12 runs, one pass); no skill or eval changes; eval 6 graded for the first time — with_skill rejects the offered sample document, baseline asks the user to paste it |
| 10        | 100%       | 45.9%         | Wording-only SKILL.md changes (quoted query-type names, "50m" → "50 million", quoted Step 2 template); full 12-run rerun, no eval changes; baseline eval 1 up 1/8 → 3/8 on weak passes (implicit helper-script evidence, vacuous no-record) |

Overall percentages in this table are macro-averages of per-eval percentages
(iteration 9's baseline aggregate: 7/31, 22.6%).

Per-eval with_skill stayed at 100% on evals 2–5 across iterations 1–5; eval 1
went 87% → 100% → 94% → 100% → 100% → 100% (iteration 6). Iteration 6: eval 2
90% (advice-prose assertion added post-run), eval 3 89% (note, string+range —
SKILL.md ambiguity, since fixed). Iteration 9: all six with_skill evals at
100%, and again at 100% in iteration 10. Baseline never passed a
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
- **Advice-prose math passed on evals 1 and 2:** every numeric claim in the
  suggestions recomputed from the skill's formulas and matched (eval 1: prefix
  alternative T = 5 and 1,714.8 bytes/doc; eval 2: ub 6→4 yields T = 96).
- **The sample-data eval is the starkest split:** the with-skill run rejects
  the offered sample document for security reasons and offers the encryption
  schema alternative; the baseline asks the user to paste the document.
- **Negative triggers held:** correctly declined from the description alone.
- **Grader-flagged coverage gaps:** no assertion covers the Step 9 closing
  behavior (temp-file path notice, review-or-delete offer, sensitive-contents
  warning). It was performed correctly in every run but would pass silently if
  skipped. The bound-leakage assertion now lives on eval 2's prefix-only
  username field and is non-vacuous; "top field by impact" passes on ranking
  alone; and nothing covers the substring field-count limit or the `mlen < v`
  queryability warning.
- **Cost of the skill:** +4.1k tokens mean (iteration 10); timing is
  comparable this iteration — means within 0.2s (67.1s with skill vs 67.3s
  without).

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
skills/mongodb-qe-size-estimation/. Set a separate $TMPDIR for each agent to 
avoid collision.
```
