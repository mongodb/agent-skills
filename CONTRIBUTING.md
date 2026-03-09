# Contributing

## Adding a new skill

To add a new skill, create a new directory in the `skills` directory with the name of the skill. The directory should contain a `SKILL.md` file with the skill's metadata and instructions. You may find the [`skill-creator`](https://github.com/anthropics/skills/tree/main/skills/skill-creator) skill by Anthropic helpful for creating the initial draft. To install in Claude Code, add the `skill-creator` plugin.

## Testing new skills

### Structural testing

Use the `tools/validate-skills.sh` script to test the structural validity of the skill. This script uses the [`skill-validator`](https://github.com/agent-ecosystem/skill-validator) tool to check the skill's metadata and instructions.

### LLM testing

Use the `tools/review-skill` skill to have an agent review the skill and interpret the results. On top of the structural validation offered by the `validate-skills.sh` script, it can also perform LLM scoring and provide a summary of the results.

Exact installation instructions depend on the client, but should be something similar to:

```bash
mkdir -p ~/.claude/skills && ln -s **path-to-agent-skills**/tools/review-skill ~/.claude/skills/review-skill
```

This creates a symlink to the `review-skill` tool in the `~/.claude/skills` directory so that it can be used in Claude Code.
