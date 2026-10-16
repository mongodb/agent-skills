#!/usr/bin/env bash
# run-all-checks.sh
# Master script: runs all MongoDB EA production checks and produces a summary report
# Usage: bash run-all-checks.sh --version 7.0|8.0|8.3|9.0 [--dbpath /var/lib/mongo]

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"

DBPATH="${MONGO_DBPATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Shared version parsing, normalization and comparison
# shellcheck source=lib-version.sh
. "$SCRIPT_DIR/lib-version.sh"

usage() {
  echo "Usage: bash run-all-checks.sh --version 7.0 | 8.0 | 8.3 | 9.0 [--dbpath /var/lib/mongo]" >&2
}

if ! mongo_parse_args "$@"; then
  usage
  exit 1
fi

if [ "$MONGO_VERSION" = "unknown" ]; then
  echo "error: --version is required" >&2
  usage
  exit 1
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname -f 2>/dev/null || hostname)
KERNEL=$(uname -r)

echo "============================================================"
echo " Self-Managed Deployments Checks"
echo " Host:    $HOSTNAME"
echo " Date:    $TIMESTAMP"
echo " Kernel:  $KERNEL"
echo " Version: MongoDB $MONGO_VERSION"
echo "============================================================"
echo ""

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
UNKNOWN_COUNT=0
ALL_OUTPUT=""

run_check() {
  local script="$1"
  local label="$2"
  # Third argument is a MINIMUM version, e.g. "8.0" means 8.0 and later
  local minimum_version="${3:-any}"

  if [ "$minimum_version" != "any" ]; then
    local min_major="${minimum_version%%.*}"
    local min_minor="${minimum_version#*.}"
    [ "$min_minor" = "$minimum_version" ] && min_minor=0
    if ! mongo_version_at_least "$min_major" "$min_minor"; then
      echo "--- Skipping $label (requires MongoDB $minimum_version or later) ---"
      echo ""
      return
    fi
  fi

  echo "--- $label ---"
  OUTPUT=$(bash "$SCRIPT_DIR/$script" --version "$MONGO_VERSION" 2>&1)
  echo "$OUTPUT"
  echo ""

  PASS_COUNT=$((PASS_COUNT + $(echo "$OUTPUT" | grep -c '^\[PASS\]' || true)))
  WARN_COUNT=$((WARN_COUNT + $(echo "$OUTPUT" | grep -c '^\[WARN\]' || true)))
  FAIL_COUNT=$((FAIL_COUNT + $(echo "$OUTPUT" | grep -c '^\[FAIL\]' || true)))
  UNKNOWN_COUNT=$((UNKNOWN_COUNT + $(echo "$OUTPUT" | grep -c '^\[UNKNOWN\]' || true)))

  ALL_OUTPUT="$ALL_OUTPUT
=== $label ===
$OUTPUT"
}

run_check "check-platform.sh"   "Platform & OS"
run_check "check-kernel.sh"     "Kernel & System Parameters"
run_check "check-numa.sh"       "NUMA Configuration"
run_check "check-thp.sh"        "Transparent Huge Pages"
run_check "check-storage.sh"    "Filesystem & Storage"
run_check "check-ulimits.sh"    "Ulimits"
run_check "check-network.sh"    "Network"
run_check "check-clock.sh"      "Clock Synchronization"
run_check "check-mongod.sh"     "MongoDB Process & Config"
run_check "check-wiredtiger.sh" "WiredTiger Configuration"
run_check "check-security.sh"   "Security"

run_check "check-tcmalloc.sh"  "TCMalloc (8.0 and later)" "8.0"

echo "============================================================"
echo " SUMMARY"
echo "============================================================"
echo " PASS:  $PASS_COUNT"
echo " WARN:  $WARN_COUNT"
echo " FAIL:  $FAIL_COUNT"
echo " UNKNOWN: $UNKNOWN_COUNT"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "FAILURES (must fix before production):"
  echo "$ALL_OUTPUT" | grep '^\[FAIL\]' | sed 's/^\[FAIL\] /  FAIL: /'
  echo ""
fi

if [ "$WARN_COUNT" -gt 0 ]; then
  echo "WARNINGS (fix before high-load production use):"
  echo "$ALL_OUTPUT" | grep '^\[WARN\]' | sed 's/^\[WARN\] /  WARN: /'
  echo ""
fi

if [ "$UNKNOWN_COUNT" -gt 0 ]; then
  echo "UNKNOWN (not verified by this run; each line carries the reason):"
  echo "$ALL_OUTPUT" | grep '^\[UNKNOWN\]' | sed 's/^\[UNKNOWN\] /  UNKNOWN: /'
  echo ""
  echo "  An UNKNOWN is not a pass. Establish these on the host, with sufficient"
  echo "  privilege, before treating the audit as complete."
  echo ""
fi

if [ "$FAIL_COUNT" -eq 0 ] && [ "$WARN_COUNT" -eq 0 ]; then
  if [ "$UNKNOWN_COUNT" -gt 0 ]; then
    echo "No failures or warnings, but $UNKNOWN_COUNT check(s) could not be verified."
    echo "Resolve the UNKNOWN items above before calling this system production ready."
  else
    echo "All checks PASSED. This system meets MongoDB $MONGO_VERSION EA production requirements."
  fi
elif [ "$FAIL_COUNT" -eq 0 ]; then
  echo "No failures. Review $WARN_COUNT warning(s) before going to production under heavy load."
else
  echo "Found $FAIL_COUNT failure(s). Resolve all FAILs before deploying to production."
fi

echo ""
echo "Reference: https://www.mongodb.com/docs/manual/administration/production-notes/"
echo "============================================================"
