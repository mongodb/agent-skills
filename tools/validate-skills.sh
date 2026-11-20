#!/bin/bash
# Validates skill directories locally with human-readable output.
#
# NOTE: The validator flags used here (e.g. --strict) should stay aligned with
# .github/scripts/validate-skills.sh (the CI version). If you change which checks
# are run or how strictly they're enforced, update both scripts. The scripts
# otherwise differ by design:
#   - CI script:    diffs changed skills, uses --emit-annotations and -o markdown
#   - Local script: accepts an optional path or validates all skills, uses default
#                   terminal output
#
# Usage: validate-skills.sh [path/to/skill/]
#   path  Optional path to a single skill directory to validate.
#         When omitted, all directories under skills/ are validated.
#
# Exit codes:
#   0  All validated skills passed.
#   1  One or more skills failed validation.

set -euo pipefail

FORK_URL="https://github.com/grove-platform/skill-validator"

print_install_help() {
  echo "This repo uses the grove-platform fork of skill-validator, which adds"
  echo "MongoDB-specific checks. The upstream Homebrew and 'go install' builds"
  echo "do not include them."
  echo ""
  echo "Install the latest release (replace darwin_arm64 with your platform):"
  echo "  gh release download --repo grove-platform/skill-validator --pattern '*_darwin_arm64.tar.gz' -O - | tar -xz skill-validator"
  echo "  sudo install -m 0755 skill-validator /usr/local/bin/"
  echo ""
  echo "Or from source (requires Go 1.25.5+):"
  echo "  git clone $FORK_URL.git && cd skill-validator"
  echo "  go install ./cmd/skill-validator"
}

if ! command -v skill-validator &>/dev/null; then
  echo "Error: skill-validator is not installed."
  echo ""
  print_install_help
  exit 1
fi

# Fork releases carry a -grove version suffix. The flag check also catches a
# fork build too old to support --allow-token-warnings, which would otherwise
# fail with a usage error.
if ! skill-validator --version 2>&1 | grep -q -- "-grove" ||
  ! skill-validator check --help 2>&1 | grep -q -- "--allow-token-warnings"; then
  echo "Error: the installed skill-validator ($(command -v skill-validator)) is not the grove-platform fork, or is out of date."
  echo ""
  print_install_help
  exit 1
fi

# Resolve and cd to the repo root so relative paths always work,
# regardless of where the script is invoked from.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Error: not inside a git repository."
  exit 1
}
cd "$REPO_ROOT"

SKILL_PATH="${1:-skills/}"

# Normalize absolute paths to be relative to the repo root.
if [[ "$SKILL_PATH" == /* ]]; then
  SKILL_PATH="${SKILL_PATH#"$REPO_ROOT"/}"
fi

if [ ! -d "$SKILL_PATH" ]; then
  echo "Error: '$SKILL_PATH' is not a directory."
  exit 1
fi

# Ensure the path ends with a trailing slash for consistency with the validator.
[[ "$SKILL_PATH" != */ ]] && SKILL_PATH="$SKILL_PATH/"

# --allow-token-warnings keeps token-budget warnings visible without failing
# the check; hard token limits still fail.
skill-validator check --strict --allow-token-warnings "$SKILL_PATH"
