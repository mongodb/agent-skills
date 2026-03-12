# mongodb-query-optimizer — test workspace

Mirrors the layout used in [PR #2](https://github.com/mongodb/agent-skills/pull/2/changes) for natural-language querying: `iteration-1/<case>/eval_metadata.json` plus this `evals/evals.json` registry.

## Purpose

- **Invocation**: Cases with `expect_invoke: true` should trigger the mongodb-query-optimizer skill (explicit optimization / performance / slow-query asks).
- **Boundary**: Cases with `expect_invoke: false` should **not** trigger the optimizer when the user only wants a query generated without optimization language.

## Running evals

Use your agent harness or skill-validator flow to:

1. Load each `eval_metadata.json` prompt.
2. Assert the skill is selected when `expect_invoke` is true and not selected when false (or that the optimizer workflow is not applied for negative cases).

## MCP branches (for manual or integration checks)

| Scenario | Tools |
|----------|--------|
| DB connection works | `collection-indexes`, `explain` |
| Atlas API + PA works | `atlas-get-performance-advisor` with `slowQueryLogs`, `suggestedIndexes`, etc. |
| Neither | Index suggestion from query shape only |

See `skills/mongodb-query-optimizer/SKILL.md` for full workflow.
