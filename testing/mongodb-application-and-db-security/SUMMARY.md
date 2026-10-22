# mongodb-application-and-db-security — Eval Results

**Date:** 2026-10-22
**Model:** Claude Opus 5.5 (`claude-opus-5-5`) for every run in both configurations, and for grading.
**Harness:** Headless `claude -p`, implementing the Anthropic `skill-creator` with-skill vs. without-skill method. The `with_skill` configuration mounts the skill at `.claude/skills/` and tells the model to read `SKILL.md` and decide for itself whether it applies; `without_skill` has no skill. Tools are restricted to `Read`, `Glob` and `Grep` in both.
**MCP config:** All 29 evals ran without an MCP server and without a live cluster. Eval 17's prompt states that an MCP server is connected; none was available, and the skill is advisory-only regardless, so the case still tests the intended refusal.
**Runs:** One run per eval per configuration — 58 runs, 188 assertions.

## Results

| Eval | with_skill | without_skill | Differentiates? |
| ---- | ---------- | ------------- | --------------- |
| 1. rbac-reporting-read-audit-insert | 9/9 (100%) | 6/9 (67%) | Yes |
| 2. x509-application-user | 8/8 (100%) | 8/8 (100%) | No |
| 3. ldap-corporate-directory | 9/9 (100%) | 8/9 (89%) | Yes |
| 4. enable-auth-first-admin | 8/8 (100%) | 8/8 (100%) | No |
| 5. nodejs-scram-username-password | 7/7 (100%) | 6/7 (86%) | Yes |
| 6. oidc-company-sso | 7/7 (100%) | 6/7 (86%) | Yes |
| 7. mechanism-overview | 8/8 (100%) | 7/8 (88%) | Yes |
| 8. negative-connection-pool-tuning | 4/4 (100%) | 1/4 (25%) | Yes |
| 9. negative-production-best-practices-audit | 4/4 (100%) | 2/4 (50%) | Yes |
| 10. negative-queryable-encryption-sizing | 4/4 (100%) | 2/4 (50%) | Yes |
| 11. negative-aggregation-pipeline | 3/4 (75%) | 1/4 (25%) | Yes |
| 12. edge-x509-compromised-certificate | 7/7 (100%) | 6/7 (86%) | Yes |
| 13. edge-posture-review-partial-sharded-evidence | 8/8 (100%) | 3/8 (38%) | Yes |
| 14. edge-x509-setup-mixed-scram-clients | 7/7 (100%) | 6/7 (86%) | Yes |
| 15. edge-atlas-custom-role | 8/8 (100%) | 8/8 (100%) | No |
| 16. edge-tls-disabled-remote-credentials | 5/5 (100%) | 2/5 (40%) | Yes |
| 17. edge-request-agent-to-apply-changes | 7/7 (100%) | 2/7 (29%) | Yes |
| 18. edge-live-inspection-with-credentials | 6/6 (100%) | 5/6 (83%) | Yes |
| 19. edge-enable-auth-running-replica-set | 8/8 (100%) | 5/8 (62%) | Yes |
| 20. kerberos-service-account | 9/10 (90%) | 7/10 (70%) | Yes |
| 21. edge-kerberos-on-atlas | 5/5 (100%) | 5/5 (100%) | No |
| 22. edge-community-edition-enterprise-mechanisms | 6/6 (100%) | 4/6 (67%) | Yes |
| 23. aws-iam-atlas-lambda | 8/8 (100%) | 7/8 (88%) | Yes |
| 24. oidc-workload-identity-azure | 8/8 (100%) | 3/8 (38%) | Yes |
| 25. edge-mixed-auth-and-pool-tuning | 6/6 (100%) | 4/6 (67%) | Yes |
| 26. troubleshoot-authentication-failed-authsource | 5/5 (100%) | 5/5 (100%) | No |
| 27. troubleshoot-unauthorized-out-stage | 6/6 (100%) | 5/6 (83%) | Yes |
| 28. negative-audit-log-configuration | 3/3 (100%) | 0/3 (0%) | Yes |
| 29. negative-csfle-setup | 3/3 (100%) | 0/3 (0%) | Yes |

**Overall: with_skill 98.8% vs without_skill 65.5% (+33%)**, as the mean of per-eval pass rates. By assertion: 186/188 (98.9%) vs 132/188 (70.2%). No eval scores below its baseline.

| Metric | with_skill | without_skill | Delta |
| ------ | ---------- | ------------- | ----- |
| Pass Rate | 98.8% | 65.5% | +33% |
| Avg Time | 35.9s | 31.9s | +3.9s |
| Avg Tokens | 148,148 | 51,854 | +96,294 |

## Key findings

- **Scope and safety behaviours are the largest differentiator.** Eval 17 (agent asked to apply changes) scores 7/7 against a baseline of 2/7, eval 13 (partial sharded evidence) 8/8 against 3/8, eval 24 (OIDC workload identity) 8/8 against 3/8, eval 28 (audit log) 3/3 against 0/3, eval 29 (CSFLE) 3/3 against 0/3, and eval 16 (TLS disabled) 5/5 against 2/5. Without the skill the model configures credentials over a plaintext connection, offers to apply changes itself, accepts an invitation to inspect a live cluster, and writes a complete CSFLE schema map and `auditLog` filter.
- **Out-of-scope routing works and names the owning skill.** Evals 8 and 25 both require the answer to name the `mongodb-connection` skill rather than substitute a documentation link; both now pass, against baselines of 1/4 and 4/6.
- **Mechanism-specific accuracy differentiates clearly.** Eval 20 (Kerberos service account) scores 9/10 against 7/10, eval 19 (enabling auth on a running replica set) 8/8 against 5/8, eval 1 (least-privilege custom role) 9/9 against 6/9, and eval 22 (Community vs Enterprise) 6/6 against 4/6.
- **One out-of-scope case falls short of the standard the suite sets.** Eval 11 (aggregation pipeline) scores 3/4: the skill names the boundary and points at the documentation, then writes the pipeline anyway. The eval requires the artifact to be withheld, which is the correct bar for a security skill, so this is recorded as a known gap rather than relaxed. Repeated attempts to close it by strengthening the directive produced no sustained improvement. The gate holds reliably on the security-sensitive topics — encryption, audit configuration, deployment audits, live inspection and connection tuning — and not on this one.
- **Five evals do not differentiate:** 2, 4, 15, 21 and 26. Opus answers x.509 application users, first-admin bootstrap, Atlas custom roles, "Kerberos isn't on Atlas" and the `authSource` diagnosis correctly unaided. They are retained as regression guards.
- **Non-discriminating assertions are 70% of the suite.** 132 of 188 assertions pass in both configurations; the measured difference rests on the remaining 54.
- **Token cost:** about 96k extra tokens per run, roughly 2.9x the baseline, from `SKILL.md` plus the reference files its routing directives load. Time overhead is +3.9s.

## Iteration history

| Iteration | Change | Model | with_skill |
| --------- | ------ | ----- | ---------- |
| 1–4 | Initial skill and 18 evals, through reference-file cleanup, the `readWrite` caveat, and the expansion to 29 evals | Sonnet 5.5 | 98.4% → 100% |
| 5 | `references/kerberos.md` rewritten: guardrails on what never to request, availability matrix, symptom-to-cause table | Sonnet 5.5 | 90.5% |
| 6 | Out-of-scope gate: declining means naming the boundary, linking the documentation and offering adjacent in-scope help | Sonnet 5.5 | 99.2% |
| 7 | Keytab source-control warning restored to `kerberos.md`; OIDC driver-only constraint generalized beyond Atlas; encryption gate extended to sizing numbers | Sonnet 5.5 | 98.6% |
| 8 | Credential-echo rule in `SKILL.md`; no-immediate-cutoff rule in `x509.md`; pre-change check captures effective privileges | Sonnet 5.5 | 98.8% ± 0.8% |
| 9 | Re-ran both configurations and the grader on Opus, which exposed the scope gate failing on a more capable model | Opus 5.5 | 91.5% |
| 10 | Scope gate rewritten to bind the response rather than the choice of skill | Opus 5.5 | 95.0% |
| 11 | Verified CommonJS connection example added to `references/scram.md` | Opus 5.5 | 95.9% |
| 12 | `TOKEN_RESOURCE` must match the configured `audience` verbatim (`oidc.md`); out-of-scope routing must name the `mongodb-connection` skill, not replace it with a link | Opus 5.5 | 98.8% |

Iterations 1–8 were measured on Sonnet 5.5 and are not comparable to 9–12: the baseline differs by seven points between the two models on identical prompts.

## Caveats

- Single run per eval per configuration; the figures carry no run-to-run variance estimate. Repeated passes during development varied by up to one assertion on several evals, and occasionally more.
- Grading is LLM-based. Assertions that turn on emphasis rather than fact can be scored differently by another grader.
- Eval 3's prompt does not state the deployment type. `SKILL.md` instructs the agent to ask one focused question when the answer changes the commands, which Atlas versus self-managed does, so a minority of runs ask instead of showing configuration and fail the assertions that require it. Adding the deployment type to that prompt would remove the ambiguity.
- The suite was read closely during development and is not a fully independent measure. Five assertions were revised: eval 22's edition check now accepts either a verification command or an explicit unverified-assumption statement; eval 15's compound assertion was split in two, and the resulting mongosh assertion then broadened to accept either `db.createRole` or `db.createUser` being named; eval 8's routing assertion accepts naming a skill that is not installed in the test environment; and evals 8 and 11 had their `expected_output` aligned with the stricter bar their assertions already set. Each was re-graded against the baseline to confirm it still discriminates.
- No eval exercises a live cluster, an MCP tool call, or a real identity provider. The skill is advisory-only, so its output is text; the correctness of the commands it emits was judged by the grader, not by running them.
