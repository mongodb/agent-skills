#!/usr/bin/env bash
# Regression test for .github/scripts/qa-resolve-skills.sh's PR-mode resolution, with
# particular focus on the deleted/renamed-skill path.
#
# The resolver previously derived the changed-skill list from the HEAD tree only, so a PR
# that deleted or renamed skills/<name>/SKILL.md removed that skill from the head-derived
# ALL_SKILLS, its changed path was dropped, `skills=[]` was emitted, and the seeder posted
# "no skill changes" SUCCESS — letting the deletion bypass the required qa-eval gate.
# These cases pin the fix: removals under skills/ resolve to a separate deleted_skills
# output (runnable head skills stay in skills), and never to a silent "no changes".
#
# Run: bash testing/qa-resolve-skills.test.sh  (needs jq; gh is stubbed to a fixture)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$SCRIPT_DIR/.github/scripts/qa-resolve-skills.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# Simulated HEAD tree: 'keep' and 'other' exist; 'doomed' and 'old' are the base-only
# skills this PR removed (so they must NOT exist on disk).
mkdir -p skills/keep skills/other skills/mongodb-connection testing/keep/evals
for s in keep other mongodb-connection; do echo "# ${s}" > "skills/$s/SKILL.md"; done
touch testing/keep/evals/evals.json

# Stub gh api: keyed on the PR number, returns Git's per-file filename<TAB>status TSV.
cat > gh <<'STUB'
#!/usr/bin/env bash
case "$*" in
  */pulls/1/*)  printf 'skills/doomed/SKILL.md\tremoved\n';;
  */pulls/2/*)  printf 'README.md\tmodified\n';;
  */pulls/3/*)  printf 'skills/new/SKILL.md\trenamed\tskills/old/SKILL.md\nskills/keep/SKILL.md\tmodified\t\n';;
  */pulls/4/*)  printf 'skills/mongodb-connection/SKILL.md\tmodified\n';;
  */pulls/5/*)  printf 'skills/mongodb-connection/SKILL.md\tmodified\nskills/keep/SKILL.md\tmodified\n';;
  */pulls/6/*)  printf 'skills/other/new.md\trenamed\tskills/keep/old.md\n';;
  *) exit 1;;
esac
STUB
chmod +x gh
export GITHUB_REPOSITORY=agent-skills-test/agent-skills
export PATH="$WORK:$PATH"

failures=0
check() {
  local pr="$1" exp_skills="$2" exp_deleted="$3"
  local out="$WORK/out.$pr"
  export GITHUB_OUTPUT="$out"
  bash "$RESOLVER" --pr "$pr" >/dev/null 2>&1
  local s d u
  s=$(sed -n 's/^skills=//p' "$out")
  d=$(sed -n 's/^deleted_skills=//p' "$out")
  u=$(sed -n 's/^unsupported_skills=//p' "$out")
  if [ "$s" != "$exp_skills" ] || [ "$d" != "$exp_deleted" ] || [ "$u" != "[]" ]; then
    echo "FAIL pr=$pr: skills=$s (want $exp_skills), deleted=$d (want $exp_deleted), unsupported=$u (want [])"
    failures=$((failures + 1))
  else
    echo "ok   pr=$pr: skills=$s deleted=$d unsupported=$u"
  fi
}

echo "1) a skill deleted outright must resolve to deleted_skills, never a silent no-change"
check 1 '[]' '["doomed"]'
echo "2) non-skill changes only -> genuinely no skill changes"
check 2 '[]' '[]'
echo "3) a rename (old removed, new added) + a real edit -> eval keeps, flag old"
check 3 '["keep"]' '["old"]'
echo "4) capability classification stays out of the public resolver"
check 4 '["mongodb-connection"]' '[]'
echo "5) every changed skill is returned for private classification"
check 5 '["keep","mongodb-connection"]' '[]'
echo "6) a renamed file evaluates both existing source and destination skills"
check 6 '["keep","other"]' '[]'

export GITHUB_OUTPUT="$WORK/out.explicit"
if bash "$RESOLVER" --skill mongodb-connection >/dev/null 2>&1; then
  s=$(sed -n 's/^skills=//p' "$WORK/out.explicit")
  u=$(sed -n 's/^unsupported_skills=//p' "$WORK/out.explicit")
  if [ "$s" = '["mongodb-connection"]' ] && [ "$u" = '[]' ]; then
    echo "ok   --skill existing -> public resolver returns the skill"
  else
    echo "FAIL --skill existing: skills=$s unsupported=$u"
    failures=$((failures + 1))
  fi
else
  echo "FAIL --skill mongodb-connection exited nonzero"
  failures=$((failures + 1))
fi
# And a genuinely missing skill name still fails loud.
if bash "$RESOLVER" --skill does-not-exist >/dev/null 2>&1; then
  echo "FAIL --skill does-not-exist should have exited nonzero"
  failures=$((failures + 1))
else
  echo "ok   --skill missing fails loud"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures resolver regression case(s) failed"
  exit 1
fi
echo "all cases passed"
