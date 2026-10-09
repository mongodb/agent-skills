# mongodb — Eval Results

**Date:** 2026-09-30
**Model:** Claude Opus 5.5 for runs and grading
**Runs:** 3 per configuration
**Environment:** No live cluster and no MCP server. Every run used the eval sandbox (on the `mongodb-eval-sandbox` branch), with stubbed Atlas CLI, Ephemeral Cluster API, `mongosh`, Docker, Homebrew, and skills CLI. See `README.md` for the groups and setup.

## Behavior

| Eval | With skill | Without skill |
| --- | --- | --- |
| 1. handoff-schema-design | 100% (15/15) | single-arm |
| 2. handoff-natural-language-querying | 100% (15/15) | single-arm |
| 3. handoff-query-optimizer | 100% (15/15) | single-arm |
| 4. handoff-search-and-ai | 100% (12/12) | single-arm |
| 5. handoff-stream-processing | 100% (12/12) | single-arm |
| 6. handoff-connection | 100% (12/12) | single-arm |
| 7. handoff-mcp-setup | 100% (12/12) | single-arm |
| 8. deploy-app-to-keep | 100% (15/15) | 73% (11/15) |
| 9. deploy-production-paid | 100% (12/12) | 75% (9/12) |
| 10. deploy-offline-local | 100% (18/18) | 61% (11/18) |
| 11. deploy-self-hosted | 100% (12/12) | 50% (6/12) |
| 12. deploy-ephemeral-prototype | 100% (15/15) | 20% (3/15) |
| 13. deploy-cannot-sign-in | 100% (15/15) | 40% (6/15) |
| 14. deploy-streaming-not-local | 100% (9/9) | 33% (3/9) |
| 15. deploy-evaluation | 100% (9/9) | 67% (6/9) |
| 16. reuse-existing-uri | 100% (15/15) | 40% (6/15) |
| 17. paid-org-no-create | 100% (15/15) | 100% (15/15) |
| 18. explicit-new-skips-check | 100% (12/12) | 75% (9/12) |
| 19. ec-provision-handoff | 92% (33/36) | single-arm |
| 20. ec-hourly-cap | 100% (12/12) | single-arm |
| 21. ec-sensitive-data | 100% (15/15) | 80% (12/15) |
| 22. docs-supported-versions | 100% (9/9) | 100% (9/9) |
| 23. docs-client-bulkwrite | 100% (12/12) | 75% (9/12) |
| 24. fabricated-cli-command | 100% (12/12) | 100% (12/12) |
| 25. fabricated-aggregation-stage | 93% (14/15) | 80% (12/15) |
| 26. handoff-preapproved-fallback-schema | 100% (15/15) | single-arm |
| 27. handoff-preapproved-fallback-connection | 100% (15/15) | single-arm |
| 28. ec-retry-after | 100% (15/15) | single-arm |
| 29. cli-missing-asks-before-install | 100% (21/21) | 71% (15/21) |
| 30. personal-org-confirm | 100% (18/18) | 83% (15/18) |

| | With skill | Without skill |
| --- | --- | --- |
| Paired cases | 99.6% (248/249) | 68% (169/249) |
| Single-arm cases | 98% (183/186) | — |
| Avg tokens per run | 23,624 | 16,183 (+7,441) |
| Avg time per run | 45.3s | 38.5s (+6.8s) |

Single-arm cases test what only the skill supplies (child skill names, the Ephemeral Cluster API), so they have no baseline. Token and time figures are from the iteration 7 `clean` group.

## Key findings

- **Deployment choice is where the skill differentiates most.** Without it, the model never suggests an Ephemeral Cluster (understandably) for a no-signup prototype (12), rarely keeps Atlas as the goal when the user can't sign in (13), misses that Stream Processing is cloud-only (14), and writes its own install steps instead of linking the self-hosted docs (11).
- **With the skill, the agent doesn't provision or leak unasked.** Baseline runs tried `docker run` and `atlas projects create` in the employer's org without asking (cases 12, 18), and planned to run `atlas setup` themselves once the user agreed (29, 30). With the skill, no run produced a `BLOCKED` line, every run left `atlas setup` to the user, and no run printed an existing `MONGODB_URI` or the Ephemeral Cluster password (16, 19).
- **Three `SKILL.md` fixes came out of these evals.** It now checks the Atlas CLI login before recommending Atlas cloud (case 17: 67% → 100%), offers the MCP server alongside installing the CLI (29), and warns that `$vectorSearch` can't run inside `$lookup` (25).