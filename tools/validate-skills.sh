#!/bin/bash
# Validates all skill directories.
#
# Exit codes:
#   0  All validated skills passed.
#   1  One or more skills failed validation.

# -e is intentionally omitted: all error paths are handled explicitly,
# so abort-on-error would conflict with the || FAILED=1 accumulator pattern.
set -uo pipefail

# Find repository root (script is at tools/validate-skills.sh)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Check if skill-validator is available
if ! command -v skill-validator &> /dev/null; then
  echo "❌ skill-validator is not installed."
  echo ""
  echo "To install it, run:"
  echo "  brew tap agent-ecosystem/tap"
  echo "  brew install skill-validator"
  echo "--- or ---"
  echo "  go install github.com/agent-ecosystem/skill-validator/cmd/skill-validator@latest"
  echo ""
  exit 1
fi

FAILED=0

# Find and validate all skill directories
for skill_dir in "$REPO_ROOT"/skills/*/; do
  # Check if the glob matched anything
  [ -d "$skill_dir" ] || continue

  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    # In CI: use markdown output with annotations, filter annotations from summary
    skill-validator check --strict --emit-annotations -o markdown "$skill_dir" \
      | tee >(grep -v '^::' >> "$GITHUB_STEP_SUMMARY") || FAILED=1
  else
    # Local: simple output
    skill-validator check --strict "$skill_dir" || FAILED=1
  fi
done

echo ""
if [ $FAILED -ne 0 ]; then
  echo "❌ Skill validation failed!"
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo ""
    echo "📋 See the Job Summary for detailed validation results:"
    echo "   https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
  fi
else
  echo "✅ Skill validation passed!"
fi

echo ""

exit $FAILED

