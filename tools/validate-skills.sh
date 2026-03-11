#!/bin/bash
# Validates skill directories locally with human-readable output.
#
# NOTE: This script mirrors the validation logic in .github/scripts/validate-skills.sh
# (the CI version). If you update the validation logic here, update it there too,
# and vice versa. The two scripts differ only in output format:
#   - CI script:    uses --emit-annotations and -o markdown for GitHub Actions
#   - Local script: uses default output for human-readable terminal viewing
#
# Usage: validate-skills.sh [path/to/skill/]
#   path  Optional path to a single skill directory to validate.
#         When omitted, all directories under skills/ are validated.
#
# Exit codes:
#   0  All validated skills passed.
#   1  One or more skills failed validation.

set -uo pipefail

# Resolve and cd to the repo root so relative paths (e.g. find skills/) always work,
# regardless of where the script is invoked from.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Error: not inside a git repository."
  exit 1
}
cd "$REPO_ROOT"

SKILL_PATH="${1:-}"

skills_to_validate=()

if [ -n "$SKILL_PATH" ]; then
  # Normalize absolute paths to be relative to the repo root.
  if [[ "$SKILL_PATH" == /* ]]; then
    SKILL_PATH="${SKILL_PATH#"$REPO_ROOT"/}"
  fi

  if [ ! -d "$SKILL_PATH" ]; then
    echo "Error: '$SKILL_PATH' is not a directory."
    exit 1
  fi
  skills_to_validate+=("$SKILL_PATH")
else
  # Validate all skill directories.
  mapfile -t skills_to_validate < <(find skills -mindepth 1 -maxdepth 1 -type d | sort)

  if [ "${#skills_to_validate[@]}" -eq 0 ]; then
    echo "No skill directories found under skills/."
    exit 0
  fi
fi

FAILED=0
for skill_dir in "${skills_to_validate[@]}"; do
  # Ensure the path ends with a trailing slash for consistency with the validator.
  [[ "$skill_dir" != */ ]] && skill_dir="$skill_dir/"

  echo "Validating: $skill_dir"
  skill-validator-ent check --strict "$skill_dir" || FAILED=1
  echo ""
done

if [ $FAILED -ne 0 ]; then
  echo "Skill validation failed."
fi

exit $FAILED
