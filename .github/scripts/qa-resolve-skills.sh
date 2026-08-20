#!/usr/bin/env bash
# Resolve which skills a QA workflow should run, and write the JSON array to
# $GITHUB_OUTPUT as `skills`.
#
# Modes (exactly one):
#   --skill NAME   Explicit request (dispatch input, /qa-eval argument). A NAME with no
#                  skills/NAME/SKILL.md fails loudly: silently resolving to "nothing"
#                  has the same shape as "evaluated, found no work", which is the same
#                  shape as success.
#   --pr NUMBER    Skills changed anywhere in the PR (skills/ or testing/ paths), per the
#                  GitHub files API. Known ceiling: the endpoint returns at most 3,000
#                  changed files per PR; PR-size expectations live in CONTRIBUTING.md.
#   --all          Every skill on disk.
#
# "Skill" = a directory under skills/ containing SKILL.md — DERIVED from the tree, never
# a hardcoded list, so a brand-new skill in a community PR is in scope the moment it
# exists. The changed-path list is only ever CANDIDATES: testing/ also holds non-skill
# directories and loose files, so a path-derived name with no SKILL.md is dropped with a
# ::notice:: rather than passed through to fail deep inside the harness on a skill that
# does not exist.
#
# Used by qa-mutation-battery.yml from its own (trusted) checkout. qa-eval.yml fetches
# it from the DEFAULT branch at runtime: that job runs with credentials against PR-head
# content, and its sparse checkout deliberately excludes .github/ so no PR-provided
# executable ever runs there — consistent with issue_comment workflows, whose YAML itself
# is read from the default branch. qa-pr-screen.yml takes a single required skill input
# and does its own two-line existence check instead.
#
# Requires: a git checkout of the ref under test as CWD, jq; gh + GH_TOKEN for --pr.
set -euo pipefail

SKILL=""
PR=""
ALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --skill) SKILL="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --all) ALL=1; shift ;;
    *) echo "::error::qa-resolve-skills.sh: unknown argument '$1'"; exit 2 ;;
  esac
done
MODES=0
[ -n "$SKILL" ] && MODES=$((MODES + 1))
[ -n "$PR" ] && MODES=$((MODES + 1))
[ "$ALL" -eq 1 ] && MODES=$((MODES + 1))
if [ "$MODES" -ne 1 ]; then
  echo "::error::qa-resolve-skills.sh: pass exactly one of --skill NAME, --pr NUMBER, --all"
  exit 2
fi

ALL_SKILLS=$(
  for d in skills/*/; do
    [ -f "${d}SKILL.md" ] || continue
    basename "$d"
  done | sort -u | jq -R . | jq -sc .
)

if [ -n "$SKILL" ]; then
  CANDIDATES=$(jq -cn --arg s "$SKILL" '[$s]')
elif [ -n "$PR" ]; then
  # The `gh api` call stays on its own line so a failure fails the script CLOSED under
  # set -e — not silently read as "no skill changes". The grep is separate because no
  # match is a legitimate empty list, but under pipefail a non-matching grep exits 1.
  FILES=$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR}/files" --paginate --jq '.[].filename')
  CANDIDATES=$(printf '%s\n' "$FILES" \
    | { grep -oE '^(skills|testing)/[^/]+' || true; } \
    | sed -E 's#^(skills|testing)/##' \
    | sort -u \
    | jq -R . | jq -sc .)
else
  CANDIDATES="$ALL_SKILLS"
fi

SKILLS=$(jq -cn --argjson c "$CANDIDATES" --argjson all "$ALL_SKILLS" '$c - ($c - $all)')
DROPPED=$(jq -cn --argjson c "$CANDIDATES" --argjson all "$ALL_SKILLS" '$c - $all')
echo "skills=$SKILLS" >> "$GITHUB_OUTPUT"
echo "Will run: $SKILLS"
# Say what was dropped. A silent skip and "nothing to run" look identical, and for a path
# that SHOULD have been a skill that is the wrong thing to be quiet about.
[ "$DROPPED" = "[]" ] || echo "::notice::Ignored non-skill paths: $DROPPED"

if [ -n "$SKILL" ] && [ "$SKILLS" = "[]" ]; then
  echo "::error::No skill named '$SKILL' under skills/. Available: $ALL_SKILLS"
  exit 1
fi
