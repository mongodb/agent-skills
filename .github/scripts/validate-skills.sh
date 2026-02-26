#!/bin/bash
# Validates all skill directories changed in a pull request.
#
# Usage: validate-skills.sh <base-ref>
#   base-ref  The base branch name to diff against (e.g. "main").
#             When omitted or when the remote is unavailable, all skills are validated.
#
# Exit codes:
#   0  All validated skills passed.
#   1  One or more skills failed validation.

# -e is intentionally omitted: all error paths are handled explicitly,
# so abort-on-error would conflict with the || FAILED=1 accumulator pattern.
set -uo pipefail

BASE_REF="${1:-}"

# Find unique skill directories containing files changed in this PR.
# The three-dot diff requires fetch-depth: 0 and a properly configured remote,
# which is always the case on GitHub Actions but may not be in local act runs.
changed_skills=()
if [ -n "$BASE_REF" ]; then
  mapfile -t changed_skills < <(git diff --name-only "origin/${BASE_REF}...HEAD" -- skills/ \
    2>/dev/null \
    | cut -d'/' -f2 \
    | sort -u \
    | grep -v '^$')
fi

if [ "${#changed_skills[@]}" -eq 0 ]; then
  # Fallback: validate all skill directories (e.g. when git remote is unavailable
  # in local act testing, or when a PR only deletes files with no remaining dirs).
  echo "Could not determine changed skills from git diff; validating all skills."
  mapfile -t changed_skills < <(find skills -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort -u)
fi

if [ "${#changed_skills[@]}" -eq 0 ]; then
  echo "No skill directories found, skipping validation."
  exit 0
fi

FAILED=0
for skill in "${changed_skills[@]}"; do
  # Skip skills whose directories were deleted in this PR.
  if [ ! -d "skills/$skill" ]; then
    echo "Skipping deleted skill: $skill"
    continue
  fi

  # Run validation with markdown output so the result is written to the job
  # summary in one pass. --emit-annotations works with any output format, so
  # inline PR annotations are still emitted alongside the markdown report.
  skill-validator check --strict --emit-annotations -o markdown "skills/$skill/" \
    >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || FAILED=1
done

exit $FAILED

