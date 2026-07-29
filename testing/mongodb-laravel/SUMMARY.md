# mongodb-laravel — Skill Evaluation Summary

## Iteration 1

- Date: 2026-07-29
- Model: `claude-opus-4-7` (with-skill runs load `skills/mongodb-laravel/SKILL.md` and follow its routing directives; baseline runs answer from general knowledge only)
- Scope: all 13 evals from `evals/evals.json` (P1 through P13)
- No live MongoDB connection required for any of these evals

## Aggregate results

| Configuration | Passed | Total | Pass rate |
|---|---|---|---|
| With skill | 60 | 60 | 100 % |
| Baseline (no skill) | 36 | 60 | 60 % |
| Delta | +24 | — | +40 pts |

## Per-eval breakdown

| # | Topic | With-skill | Baseline | Delta |
|---|---|---|---|---|
| P1  | Eloquent model for `posts` collection | 5/5 | 4/5 | +1 |
| P2  | Distinct field values (`distinct()->pluck` trap) | 5/5 | 2/5 | +3 |
| P3  | Count comments per post (`withCount` trap) | 4/4 | 1/4 | +3 |
| P4  | Random documents (`inRandomOrder` trap) | 4/4 | 2/4 | +2 |
| P5  | `belongsTo` returns null (BSON type mismatch) | 4/4 | 2/4 | +2 |
| P6  | Debug a MongoDB query (`toSql` trap) | 4/4 | 3/4 | +1 |
| P7  | `DatabaseTransactions` in Pest with MongoDB | 5/5 | 3/5 | +2 |
| P8  | MongoDB cache store with TTL | 5/5 | 5/5 | 0 |
| P9  | Scout price range filter (equality-only trap) | 4/4 | 0/4 | +4 |
| P10 | MySQL User ↔ MongoDB Post (`HybridRelations`) | 5/5 | 3/5 | +2 |
| P11 | Full-text search without Scout | 5/5 | 3/5 | +2 |
| P12 | Semantic search with manual embeddings | 5/5 | 5/5 | 0 |
| P13 | Semantic search via auto-embedding | 5/5 | 3/5 | +2 |

## Key findings

- **Every with-skill run scored 100 %.** No corrections to the skill were required from this iteration.
- **Highest differentiators (delta ≥ +3):**
  - **P9 (+4):** baseline confidently recommends `->where('price', '>=', 50)` and `->whereBetween` on Scout `search()` — the MongoDB Scout engine only supports equality, so the query silently returns unfiltered results. Skill's warning is critical.
  - **P2 (+3):** baseline recommends `Movie::distinct('genre')->get()->toArray()` as if it returned scalar strings; it actually returns a Collection of model objects. Skill flips this to `->distinct()->pluck('genre')`.
  - **P3 (+3):** baseline recommends `Post::withCount('comments')`, which is silently wrong on the MongoDB engine. Skill replaces with `$lookup + $size` aggregation.
- **P7 baseline claim to verify:** baseline states `DatabaseTransactions` "can work" with a replica set. The skill contradicts this and recommends manual truncation. The package's own docs list `DatabaseTransactions` and `RefreshDatabase` as unsupported testing traits, so the skill's position is the correct one — this is a MongoDB-specific correction the base model does not know.
- **Baseline API hallucinations on P13:** baseline invents `type: 'text'` in the vector index and `'query'` instead of `queryText` in the `$vectorSearch` stage. The skill's `references/vector-search.md` teaches the correct current API.
- **Non-discriminating evals (delta = 0):**
  - **P8 (cache):** both configs correctly configure the built-in `mongodb` cache driver, create a TTL index on `expires_at`, and use the `$c->expire(...)` / `expireAfterSeconds: 0` pattern. Cache/TTL is well-documented publicly.
  - **P12 (manual vector search):** both configs correctly build the vector index, generate embeddings via OpenAI, and query with `$vectorSearch`. The auto-embedding path (P13) remains the differentiator; manual embedding is now generic knowledge.
- **P1 baseline gets 4/5** (still uses the removed `protected $collection` field) — a small correction that reflects the skill catching a recently-changed package convention.

## Related validation

- Structural validation (`skill-validator validate structure` + `validate links`): **passed** (no errors, no warnings)
- LLM scoring (`skill-validator score evaluate --provider claude-cli`):
  - SKILL.md overall: **4.50 / 5** (Clarity 4, Actionability 5, Token Efficiency 4, Scope Discipline 5, Directive Precision 5, Novelty 4)
  - References overall: **4.40 / 5** (Clarity 5, Instructional Value 5, Token Efficiency 5, Novelty 3, Skill Relevance 4)

## Notes

- Subagent runs initially failed to write to disk due to a permission-prompt loop. Directories were pre-created and, for the first six evals, some responses were captured from inline text returned by the subagents. This is a harness quirk, not a skill defect.
- Workspace directory (`skills/mongodb-laravel-workspace/`) is gitignored per repo `.gitignore` (`*-workspace/`) and is intentionally not committed.
- Two evals (P8, P12) show no delta — worth considering whether to drop them or refine their assertions in a future iteration to focus on MongoDB-Laravel-specific gotchas rather than generic Laravel+MongoDB knowledge.
