#!/usr/bin/env bash
# test-kernel-matrix.sh
# Regression tests for the version-aware kernel verdict in lib-version.sh.
#
# Run: bash scripts/test-kernel-matrix.sh
# Exits 0 when every case passes, 1 otherwise, so CI can gate on it.
#
# Why this file exists: kernel_tcmalloc_status encodes the five-band
# compatibility matrix from SERVER-125742. The bands are not intuitive, and the
# rule took two corrections to get right. The case that matters most is
# 8.0.21-8.0.29 on kernel 7.0.14: the public docs say 7.0.14 resolves the
# incompatibility, and for that band it does not. Without these assertions a
# later edit could quietly restore the simpler, wrong rule and nothing would
# notice until it reached a customer.
#
# Source of truth (do not adjust these expectations without re-reading it):
#
#   MongoDB            kernel <6.19   6.19-7.0.13                  7.0.14+/7.1.0+
#   7.0 (all)          ok             ok                           ok
#   8.0.0 - 8.0.20     ok             do_not_use (corruption)      ok
#   8.0.21 - 8.0.29    ok             bad_range                    ge_619
#   8.3.0 - 8.3.8      ok             bad_range                    ge_619
#   8.0.30+ 8.3.9+ 9.0 ok             bad_range                    ok

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-version.sh
. "$SCRIPT_DIR/lib-version.sh"

PASSED=0
FAILED=0

# assert_status <mongo-version> <kernel-string> <expected-status>
assert_status() {
  local mongo="$1" kernel="$2" want="$3" got

  # Reset so a previous case cannot leak its patch component into this one.
  MONGO_VERSION="unknown"
  MONGO_VERSION_PATCH=""
  mongo_normalize_version "$mongo" >/dev/null 2>&1 || true

  got=$(kernel_tcmalloc_status "$kernel")
  if [ "$got" = "$want" ]; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    printf 'FAIL  mongo=%-8s kernel=%-28s got=%-11s want=%s\n' \
      "$mongo" "$kernel" "$got" "$want"
  fi
}

section() { printf '\n-- %s\n' "$1"; }

echo "=== kernel_tcmalloc_status regression tests ==="

section "7.0 is unaffected on every kernel"
assert_status 7.0.14 6.19.2                      ok
assert_status 7.0.14 7.0.13                      ok
assert_status 7.0.14 5.14.0                      ok
assert_status 7.0    6.19.2                      ok

section "8.0.0-8.0.20: corruption risk in range, clear on 7.0.14+"
assert_status 8.0.4  6.19.2                      do_not_use
assert_status 8.0.4  7.0.13                      do_not_use
assert_status 8.0.4  7.0.14                      ok
assert_status 8.0.4  5.14.0                      ok
assert_status 8.0.20 6.19.0                      do_not_use
assert_status 8.0.20 7.1.0                       ok

section "8.0.21-8.0.29: blocked at 6.19 and up; a kernel upgrade is no remedy"
assert_status 8.0.21 6.19.2                      bad_range
assert_status 8.0.21 7.0.14                      ge_619
assert_status 8.0.29 7.1.3                       ge_619
assert_status 8.0.29 5.14.0                      ok

section "8.0.30+: bounded range only"
assert_status 8.0.30 6.19.2                      bad_range
assert_status 8.0.30 7.0.14                      ok
assert_status 8.0.45 7.1.3                       ok

section "8.3.0-8.3.8 blocked above 6.19; 8.3.9+ bounded"
assert_status 8.3.0  7.0.14                      ge_619
assert_status 8.3.8  6.19.2                      bad_range
assert_status 8.3.9  7.0.14                      ok
assert_status 8.3.9  6.19.2                      bad_range

section "9.0 carries the narrowed guard"
assert_status 9.0.1  7.0.14                      ok
assert_status 9.0.1  6.19.2                      bad_range

section "no patch supplied: strictest verdict the band could carry"
assert_status 8.0    7.0.14                      ge_619
assert_status 8.3    7.0.14                      ge_619
assert_status 8.0    5.14.0                      ok

section "real distro kernel strings parse correctly"
assert_status 8.0.4  5.14.0-427.13.1.el9_4.x86_64 ok
assert_status 8.0.30 6.19.2-1.el9.x86_64          bad_range
# Ubuntu ships 7.0.0-XX-generic. It is numerically >= 6.19 but never >= 7.0.14,
# so the guard keeps treating it as affected even once the rseq fix is
# backported (SERVER-131155, SERVER-131779). Asserted so the known-wrong
# real-world behaviour stays visible rather than being silently "fixed" here.
assert_status 9.0.1  7.0.0-28-generic             bad_range

printf '\n=== %d passed, %d failed ===\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
