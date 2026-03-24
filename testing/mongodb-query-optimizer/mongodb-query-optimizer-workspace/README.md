# mongodb-query-optimizer — test workspace

Generated eval outputs go here, organized by iteration (e.g. `iteration-1/`, `iteration-2/`). These directories are ephemeral and should not be committed.

## Running evals

Use the `skill-creator` skill to run and evaluate test cases:

1. Open Claude Code in the `agent-skills/` directory.
2. Run `/skill-creator` and ask it to run the evals for the `mongodb-query-optimizer` skill.
3. It will read `evals/evals.json`, spawn test runs (with and without the skill), grade assertions, and open a viewer for you to review results.

The eval prompts and assertions are defined in `evals/evals.json`. Each eval has:
- **prompt** — the simulated user input
- **expected_output** — human-readable description of a good response
- **expectations** — specific, verifiable assertions that get graded automatically

Eval 6 (`"Write a find query..."`) is a negative test case — the optimizer skill should **not** trigger for it.

## MCP scenarios

Some evals benefit from a live MongoDB connection or Atlas API access:

| Scenario | MCP tools used |
|----------|----------------|
| DB connection available | `collection-indexes`, `explain` |
| Atlas API available | `atlas-get-performance-advisor` (slow query logs, suggested indexes) |
| Neither available | Skill suggests indexes from query shape only |

See `skills/mongodb-query-optimizer/SKILL.md` for the full skill workflow.
