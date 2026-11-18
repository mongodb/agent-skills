#!/usr/bin/env bash
# test-checks.sh
# Regression tests for the check scripts' verdicts, run against fake inputs.
#
# Run: bash scripts/test-checks.sh
# Exits 0 when every case passes, 1 otherwise, so CI can gate on it. Linux
# only (GNU userland). Cases that need root, or that need a non-root user to
# see a permission error, are skipped with a note instead of failing.
#
# Each case pins one reviewer-reported failure mode so it cannot come back:
#   - kernel 6.19.2 on 8.0.25 must not be told to upgrade the kernel
#   - javascriptEnabled omitted under SELinux Enforcing is a FAIL (default true)
#   - nested net.tls.mode: requireTLS is recognized
#   - dbPath access is tested as the MongoDB service user
#   - failed reads are UNKNOWN, never a default PASS or a finding
#   - the OS check follows the version-specific support matrix
#   - a category that exits non-zero is recorded as UNKNOWN
#   - the installed-version check compares the patch
#
# Inputs are faked through PATH shims (uname, getenforce, mongod) and the
# scripts' test seams (MONGO_CONF_FILE, MONGO_OS_RELEASE, THP_SYSFS_DIR,
# NUMA_NODE_DIR, MONGO_SERVICE_USER, MONGO_DISTRO). Nothing on the host is
# changed; everything lives under a temporary directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(uname -s)" != "Linux" ]; then
  echo "SKIP: test-checks.sh needs Linux"; exit 0
fi

TMP=$(mktemp -d)
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
REAL_UNAME=$(command -v uname)
IS_ROOT=0; [ "$(id -u)" -eq 0 ] && IS_ROOT=1

cat > "$BIN/uname" <<EOF
#!/usr/bin/env bash
case "\$1" in
  -r) echo "\${FAKE_UNAME_R:-\$($REAL_UNAME -r)}" ;;
  -m) echo "\${FAKE_UNAME_M:-\$($REAL_UNAME -m)}" ;;
  *)  exec $REAL_UNAME "\$@" ;;
esac
EOF
cat > "$BIN/getenforce" <<'EOF'
#!/usr/bin/env bash
echo "${FAKE_SELINUX:-Disabled}"
EOF
chmod +x "$BIN/uname" "$BIN/getenforce"

# A fake mongod binary goes in its own directory, added only where needed.
MBIN="$TMP/mongod-bin"; mkdir -p "$MBIN"
cat > "$MBIN/mongod" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "--version" ] && echo "db version v${FAKE_MONGOD_VERSION:-8.0.25}"
EOF
chmod +x "$MBIN/mongod"

PASSED=0; FAILED=0; SKIPPED=0
OUT=""

# run <script> [args...]: run a check with the shims first on PATH
run() { OUT=$(PATH="$BIN:$PATH" bash "$SCRIPT_DIR/$1" "${@:2}" 2>&1); }

ok()   { PASSED=$((PASSED + 1)); }
bad()  { FAILED=$((FAILED + 1)); printf 'FAIL  %s\n      %s\n' "$CASE" "$1"; printf '%s\n' "$OUT" | sed 's/^/      | /' | head -40; }
skip() { SKIPPED=$((SKIPPED + 1)); printf 'SKIP  %s (%s)\n' "$CASE" "$1"; }

# expect <regex> / expect_not <regex> against the last run's output
expect()     { if printf '%s\n' "$OUT" | grep -qE -- "$1"; then ok; else bad "expected: $1"; fi; }
expect_not() { if printf '%s\n' "$OUT" | grep -qE -- "$1"; then bad "unexpected: $1"; else ok; fi; }

conf() { local f="$TMP/conf-$1.yaml"; cat > "$f"; echo "$f"; }
osrel() { local f="$TMP/os-$1"; printf 'NAME="%s"\nID=%s\nVERSION_ID="%s"\n' "$2" "$3" "$4" > "$f"; echo "$f"; }

echo "=== check script regression tests ==="

# --- 1. Kernel remedy on the always-exit band --------------------------------
export MONGO_DISTRO=rhel FAKE_UNAME_M=x86_64
CASE="8.0.25 on kernel 6.19.2: tcmalloc check offers a MongoDB upgrade, not a kernel upgrade"
FAKE_UNAME_R=6.19.2-1.el9.x86_64 run check-tcmalloc.sh --version 8.0.25
expect '^\[FAIL\] tcmalloc-kernel619: .*kernel upgrade alone does not clear it'
expect 'upgrade MongoDB to 8\.0\.30 or later'
expect_not 'Move to kernel 7\.0\.14 or later'

CASE="8.0.25 on kernel 6.19.2: platform check offers a MongoDB upgrade, not a kernel upgrade"
FAKE_UNAME_R=6.19.2-1.el9.x86_64 run check-platform.sh --version 8.0.25
expect '^\[FAIL\] kernel-version: .*kernel upgrade alone is not a remedy'
expect_not 'Move to kernel 7\.0\.14 or later'

CASE="8.0.30 on kernel 6.19.2: the narrowed guard is still cleared by kernel 7.0.14"
FAKE_UNAME_R=6.19.2-1.el9.x86_64 run check-platform.sh --version 8.0.30
expect '^\[FAIL\] kernel-version: .*Move to kernel 7\.0\.14 or later'

CASE="8.0 without a patch on kernel 6.19.2: strictest remedy plus a note to resolve the patch"
FAKE_UNAME_R=6.19.2-1.el9.x86_64 run check-platform.sh --version 8.0
expect 'kernel upgrade alone is not a remedy'
expect 'no patch version was supplied'
unset MONGO_DISTRO

# --- 2. Server-side JavaScript under SELinux Enforcing -----------------------
C_OMIT=$(conf js-omitted <<'EOF'
storage:
  dbPath: /var/lib/mongo
security:
  authorization: enabled
EOF
)
C_FALSE=$(conf js-false <<'EOF'
security:
  authorization: enabled
  javascriptEnabled: false
EOF
)
C_TRUE=$(conf js-true <<'EOF'
security:
  javascriptEnabled: true
EOF
)
CASE="Enforcing, javascriptEnabled omitted: FAIL, because the default is true"
FAKE_SELINUX=Enforcing MONGO_CONF_FILE="$C_OMIT" run check-security.sh
expect '^\[FAIL\] selinux-javascript: .*not set, so it defaults to true'
expect_not '^\[PASS\] selinux-javascript'

CASE="Enforcing, javascriptEnabled: false: PASS"
FAKE_SELINUX=Enforcing MONGO_CONF_FILE="$C_FALSE" run check-security.sh
expect '^\[PASS\] selinux-javascript: security.javascriptEnabled is false'

CASE="Enforcing, javascriptEnabled: true: FAIL"
FAKE_SELINUX=Enforcing MONGO_CONF_FILE="$C_TRUE" run check-security.sh
expect '^\[FAIL\] selinux-javascript: .*javascriptEnabled is true'

CASE="Enforcing, config not found: UNKNOWN, not PASS"
FAKE_SELINUX=Enforcing MONGO_CONF_FILE="$TMP/does-not-exist.conf" run check-security.sh
expect '^\[UNKNOWN\] selinux-javascript'
expect_not '^\[PASS\] selinux-javascript'

CASE="Permissive: the SELinux JavaScript check does not apply"
FAKE_SELINUX=Permissive MONGO_CONF_FILE="$C_OMIT" run check-security.sh
expect_not 'selinux-javascript'

# --- 3. Nested TLS mode -------------------------------------------------------
C_TLS=$(conf tls-nested <<'EOF'
net:
  port: 27017
  bindIp: 10.0.0.5
  tls:
    mode: requireTLS   # cluster-wide
    certificateKeyFile: /etc/ssl/mongodb.pem
security:
  authorization: enabled
EOF
)
C_TLS_PREFER=$(conf tls-prefer <<'EOF'
net:
  tls:
    mode: "preferTLS"
EOF
)
C_NOTLS=$(conf tls-none <<'EOF'
net:
  port: 27017
systemLog:
  mode: something-unrelated
EOF
)
CASE="nested net.tls.mode: requireTLS is recognized by check-security"
MONGO_CONF_FILE="$C_TLS" run check-security.sh
expect '^\[PASS\] security-tls: net.tls.mode is requireTLS'

CASE="nested net.tls.mode: requireTLS is recognized by check-mongod"
MONGO_CONF_FILE="$C_TLS" run check-mongod.sh --version 8.0.30
expect '^\[PASS\] mongod-tls: net.tls.mode is requireTLS'

CASE="quoted preferTLS is a WARN"
MONGO_CONF_FILE="$C_TLS_PREFER" run check-security.sh
expect '^\[WARN\] security-tls: net.tls.mode is preferTLS'

CASE="a mode: key outside net.tls is not mistaken for the TLS mode"
MONGO_CONF_FILE="$C_NOTLS" run check-mongod.sh --version 8.0.30
expect '^\[WARN\] mongod-tls: TLS is not configured \(net.tls.mode is not set\)'

# --- 4. dbPath access as the service user ------------------------------------
DB="$TMP/db"; mkdir -p "$DB"
ME=$(id -un)
CASE="dbPath usable by the service user (the user running the test): PASS"
MONGO_DBPATH="$DB" MONGO_SERVICE_USER="$ME" run check-storage.sh
expect "^\[PASS\] dbpath-permissions: .*service user $ME"

if [ "$IS_ROOT" -eq 0 ]; then
  CASE="dbPath not writable by the service user: FAIL with a chown for that user"
  chmod 500 "$DB"
  MONGO_DBPATH="$DB" MONGO_SERVICE_USER="$ME" run check-storage.sh
  expect "^\[FAIL\] dbpath-permissions: the MongoDB service user $ME"
  expect "chown -R $ME:"
  chmod 700 "$DB"

  CASE="another service user from an unprivileged run: UNKNOWN, not a false FAIL"
  MONGO_DBPATH="$DB" MONGO_SERVICE_USER=nobody run check-storage.sh
  expect '^\[UNKNOWN\] dbpath-permissions: .*cannot be tested from this unprivileged run'
  expect_not '^\[(PASS|FAIL)\] dbpath-permissions'
else
  CASE="root audit, dbPath owned by root 0700, service user nobody: FAIL, not PASS"
  chmod 700 "$DB"
  MONGO_DBPATH="$DB" MONGO_SERVICE_USER=nobody run check-storage.sh
  if command -v runuser >/dev/null 2>&1 || command -v sudo >/dev/null 2>&1; then
    expect '^\[FAIL\] dbpath-permissions: the MongoDB service user nobody'
    expect_not '^\[PASS\] dbpath-permissions'
  else
    skip "neither runuser nor sudo is installed"
  fi
fi

# --- 5. Failed reads are UNKNOWN ---------------------------------------------
C_WT=$(conf wt <<'EOF'
storage:
  wiredTiger:
    engineConfig:
      cacheSizeGB: 1
EOF
)
if [ "$IS_ROOT" -eq 0 ]; then
  CASE="unreadable config: WiredTiger reports UNKNOWN, not the default-cache PASS"
  chmod 000 "$C_WT"
  MONGO_CONF_FILE="$C_WT" run check-wiredtiger.sh
  expect '^\[UNKNOWN\] wiredtiger-config: .*not readable'
  expect_not '^\[PASS\] wiredtiger-cachesize'
  chmod 600 "$C_WT"
else
  CASE="unreadable config: WiredTiger reports UNKNOWN"; skip "root can read every file"
fi

THP="$TMP/thp"; mkdir -p "$THP/khugepaged"
echo "always madvise [never]" > "$THP/enabled"
: > "$THP/defrag"          # present but empty: a failed read
CASE="THP defrag that cannot be read on 7.0: UNKNOWN, not FAIL"
THP_SYSFS_DIR="$THP" FAKE_UNAME_M=x86_64 run check-thp.sh --version 7.0.21
expect '^\[PASS\] thp-enabled'
expect '^\[UNKNOWN\] thp-defrag'
expect_not '^\[FAIL\] thp-defrag'

echo "[always] madvise never" > "$THP/enabled"
echo "always [defer+madvise] madvise never" > "$THP/defrag"
: > "$THP/khugepaged/max_ptes_none"
CASE="max_ptes_none that cannot be read on 8.0: UNKNOWN, not WARN"
THP_SYSFS_DIR="$THP" FAKE_UNAME_M=x86_64 run check-thp.sh --version 8.0.30
expect '^\[UNKNOWN\] thp-max-ptes-none'
expect_not '^\[WARN\] thp-max-ptes-none'

CASE="missing NUMA node directory: UNKNOWN, not 'no tuning required'"
NUMA_NODE_DIR="$TMP/no-such-node-dir" run check-numa.sh --version 8.0.30
expect '^\[UNKNOWN\] numa-topology'
expect_not 'no NUMA tuning required'

CASE="NUMA node directory with no node entries: UNKNOWN"
mkdir -p "$TMP/node-empty"
NUMA_NODE_DIR="$TMP/node-empty" run check-numa.sh --version 8.0.30
expect '^\[UNKNOWN\] numa-topology'

CASE="readable single-node topology: informational, nothing to tune"
mkdir -p "$TMP/node-one/node0"
NUMA_NODE_DIR="$TMP/node-one" run check-numa.sh --version 8.0.30
expect '^\[INFO\] numa-topology: single NUMA node'

# --- 6. Version-specific OS support ------------------------------------------
U2404=$(osrel u2404 "Ubuntu" ubuntu 24.04)
U2604=$(osrel u2604 "Ubuntu" ubuntu 26.04)
U2310=$(osrel u2310 "Ubuntu" ubuntu 23.10)
R9=$(osrel r9 "Rocky Linux" rocky 9.4)
FED=$(osrel fed "Fedora Linux" fedora 41)
export FAKE_UNAME_R=5.14.0-427.13.1.el9_4.x86_64
CASE="MongoDB 7.0 on Ubuntu 24.04: FAIL (not in the 7.x column)"
MONGO_OS_RELEASE="$U2404" FAKE_UNAME_M=x86_64 run check-platform.sh --version 7.0.21
expect '^\[FAIL\] os-supported: Ubuntu 24.04 \(x86_64\) is not supported for MongoDB Enterprise 7.0'

CASE="MongoDB 8.0 on Ubuntu 24.04: PASS"
MONGO_OS_RELEASE="$U2404" FAKE_UNAME_M=x86_64 run check-platform.sh --version 8.0.30
expect '^\[PASS\] os-supported'

CASE="MongoDB 9.0.1 on Ubuntu 26.04: FAIL (listed from 9.0.4)"
MONGO_OS_RELEASE="$U2604" FAKE_UNAME_M=x86_64 run check-platform.sh --version 9.0.1
expect '^\[FAIL\] os-supported: .*only from 9\.0\.4'

CASE="MongoDB 9.0.4 on Ubuntu 26.04: PASS"
MONGO_OS_RELEASE="$U2604" FAKE_UNAME_M=x86_64 run check-platform.sh --version 9.0.4
expect '^\[PASS\] os-supported'

CASE="MongoDB 8.0.4 on Rocky 9 s390x: FAIL (8.x listed from 8.0.7)"
MONGO_OS_RELEASE="$R9" FAKE_UNAME_M=s390x run check-platform.sh --version 8.0.4
expect '^\[FAIL\] os-supported: .*only from 8\.0\.7'

CASE="MongoDB 8.3 on Rocky 9 s390x: PASS (8.3 is past the 8.0.7 minimum)"
MONGO_OS_RELEASE="$R9" FAKE_UNAME_M=s390x run check-platform.sh --version 8.3.14
expect '^\[PASS\] os-supported'

CASE="MongoDB 8.0 without a patch on Rocky 9 s390x: UNKNOWN"
MONGO_OS_RELEASE="$R9" FAKE_UNAME_M=s390x run check-platform.sh --version 8.0
expect '^\[UNKNOWN\] os-supported'

CASE="non-LTS Ubuntu release: WARN, no row in the matrix"
MONGO_OS_RELEASE="$U2310" FAKE_UNAME_M=x86_64 run check-platform.sh --version 8.0.30
expect '^\[WARN\] os-supported: .*has no row'

CASE="distro not on the page: WARN"
MONGO_OS_RELEASE="$FED" FAKE_UNAME_M=x86_64 run check-platform.sh --version 8.0.30
expect '^\[WARN\] os-supported: Fedora Linux is not in the MongoDB Enterprise support matrix'
unset FAKE_UNAME_R

# --- 7. A category that exits non-zero is UNKNOWN ----------------------------
COPY="$TMP/scripts"; mkdir -p "$COPY"
cp "$SCRIPT_DIR"/*.sh "$COPY"/
printf '#!/usr/bin/env bash\necho "[PASS] clock-fake: partial output"\nexit 3\n' > "$COPY/check-clock.sh"
CASE="run-all-checks records a category that exited non-zero as UNKNOWN"
OUT=$(PATH="$BIN:$PATH" bash "$COPY/run-all-checks.sh" --version 8.0.30 2>&1)
expect '^\[UNKNOWN\] check-incomplete: check-clock\.sh exited with status 3'
expect 'UNKNOWN: check-incomplete'
expect_not 'All checks PASSED'

# --- 8. Installed version is compared to the patch ---------------------------
CASE="installed 8.0.25 audited as 8.0.30: WARN with the exact re-run version"
OUT=$(PATH="$MBIN:$BIN:$PATH" FAKE_MONGOD_VERSION=8.0.25 MONGO_CONF_FILE="$C_TLS" bash "$SCRIPT_DIR/check-mongod.sh" --version 8.0.30 2>&1)
expect '^\[WARN\] mongod-version-match: installed mongod is 8\.0\.25 but the audit was run with --version 8\.0\.30'
expect 're-run with --version 8\.0\.25'

CASE="installed 8.0.25 audited as 8.0.25: PASS"
OUT=$(PATH="$MBIN:$BIN:$PATH" FAKE_MONGOD_VERSION=8.0.25 MONGO_CONF_FILE="$C_TLS" bash "$SCRIPT_DIR/check-mongod.sh" --version 8.0.25 2>&1)
expect '^\[PASS\] mongod-version-match: installed mongod 8\.0\.25 matches the audited version 8\.0\.25'

CASE="installed 8.0.25 audited as bare 8.0: PASS with a note to supply the patch"
OUT=$(PATH="$MBIN:$BIN:$PATH" FAKE_MONGOD_VERSION=8.0.25 MONGO_CONF_FILE="$C_TLS" bash "$SCRIPT_DIR/check-mongod.sh" --version 8.0 2>&1)
expect '^\[PASS\] mongod-version-match: .*audited series 8\.0'
expect 're-run with --version 8\.0\.25'

CASE="installed 7.0.21 audited as 8.0.30: WARN, re-run as 7.0"
OUT=$(PATH="$MBIN:$BIN:$PATH" FAKE_MONGOD_VERSION=7.0.21 MONGO_CONF_FILE="$C_TLS" bash "$SCRIPT_DIR/check-mongod.sh" --version 8.0.30 2>&1)
expect '^\[WARN\] mongod-version-match: installed mongod is 7\.0\.21'

printf '\n=== %d passed, %d failed, %d skipped ===\n' "$PASSED" "$FAILED" "$SKIPPED"
[ "$FAILED" -eq 0 ]
