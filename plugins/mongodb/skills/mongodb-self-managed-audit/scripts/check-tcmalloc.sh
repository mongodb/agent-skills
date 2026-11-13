#!/usr/bin/env bash
# check-tcmalloc.sh
# MongoDB 8.0 and later: validates TCMalloc configuration
# TCMalloc is updated in 8.0 for performance improvements
# Usage: bash check-tcmalloc.sh [--version 8.0|8.3|9.0]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-version.sh
. "$SCRIPT_DIR/lib-version.sh"
mongo_parse_args "$@" || exit 1

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"
UNKNOWN="[UNKNOWN]"

echo "=== TCMalloc Check (MongoDB 8.0 and later) ==="

if ! mongo_version_at_least 8 0; then
  echo "$INFO tcmalloc-version: this check applies to MongoDB 8.0 and later; supplied version is $MONGO_VERSION"
  exit 0
fi

ARCH=$(uname -m)
DISTRO=""
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO="$ID"
fi

# --- Identify if this system uses legacy TCMalloc ---
LEGACY_TCMALLOC=0
if [ "$ARCH" = "ppc64le" ]; then
  LEGACY_TCMALLOC=1
  echo "$INFO tcmalloc-arch: ppc64le uses legacy TCMalloc in MongoDB 8.0 (expected behavior)"
elif [ "$ARCH" = "s390x" ]; then
  LEGACY_TCMALLOC=1
  echo "$INFO tcmalloc-arch: s390x uses legacy TCMalloc in MongoDB 8.0 (expected behavior)"
else
  echo "$INFO tcmalloc-arch: $ARCH uses updated TCMalloc in MongoDB 8.0"
fi

# --- Allocator-related environment of the running mongod ---
MONGOD_PID=$(pgrep -x mongod | head -1)
if [ -n "$MONGOD_PID" ]; then
  MONGOD_ENV=$(tr '\0' '\n' < /proc/"$MONGOD_PID"/environ 2>/dev/null || true)
  if [ -z "$MONGOD_ENV" ]; then
    echo "$UNKNOWN tcmalloc-environ: /proc/$MONGOD_PID/environ not readable by this run; re-run with sudo to check LD_PRELOAD and GLIBC_TUNABLES"
  else
    # --- LD_PRELOAD for custom allocators ---
    LD_PRELOAD_SET=$(echo "$MONGOD_ENV" | grep '^LD_PRELOAD=' || true)
    if [ -n "$LD_PRELOAD_SET" ]; then
      echo "$WARN tcmalloc-LD_PRELOAD: $LD_PRELOAD_SET - custom allocator may conflict with MongoDB's TCMalloc"
    else
      echo "$PASS tcmalloc-LD_PRELOAD: No LD_PRELOAD override detected"
    fi

    # --- GLIBC_TUNABLES, the only variable the TCMalloc page names ---
    # glibc.pthread.rseq=0 is the documented fix when per-CPU caches are not
    # in use because glibc registered rseq first. Whether per-CPU caches are
    # active is a runtime value; see the note below.
    GLIBC_SET=$(echo "$MONGOD_ENV" | grep '^GLIBC_TUNABLES=' || true)
    if [ -n "$GLIBC_SET" ]; then
      echo "$INFO tcmalloc-glibc-tunables: $GLIBC_SET (glibc.pthread.rseq=0 lets TCMalloc register rseq for per-CPU caches)"
    else
      echo "$INFO tcmalloc-glibc-tunables: GLIBC_TUNABLES is not set for mongod; set glibc.pthread.rseq=0 only if per-CPU caches are not active"
    fi
  fi
fi

# --- Per-CPU caches (updated TCMalloc, x86_64 and arm64) ---
if [ "$LEGACY_TCMALLOC" -eq 0 ]; then
  KERNEL_NUM=$(kernel_version_num "$(uname -r)" 2>/dev/null || true)
  if [ -n "$KERNEL_NUM" ]; then
    if [ "$KERNEL_NUM" -lt $(( 4 * 1000000 + 18 * 1000 )) ]; then
      echo "$WARN tcmalloc-percpu-kernel: kernel $(uname -r) is older than 4.18; per-CPU caches need Linux 4.18 or later, so TCMalloc falls back to per-thread caches"
    else
      echo "$PASS tcmalloc-percpu-kernel: kernel $(uname -r) meets the 4.18 minimum for per-CPU caches"
    fi
  else
    echo "$UNKNOWN tcmalloc-percpu-kernel: kernel version string could not be parsed"
  fi
  echo "$INFO tcmalloc-percpu-runtime: confirm in serverStatus that tcmalloc.usingPerCPUCaches is true and tcmalloc.tcmalloc.cpu_free is greater than 0; the scripts cannot read these (UNKNOWN without a live server)"
fi

# --- tcmalloc.aggressive_memory_decommit ---
echo "$INFO tcmalloc-decommit: tcmallocAggressiveMemoryDecommit is deprecated in MongoDB 8.0; do not tune it. To release memory to the OS, see tcmallocEnableBackgroundThread."

# --- Kernel TCMalloc incompatibility ---
# Same version-aware test as check-platform.sh, from lib-version.sh.
KERNEL=$(uname -r)
MONGO_REL="$MONGO_VERSION${MONGO_VERSION_PATCH:+.$MONGO_VERSION_PATCH}"
case "$(kernel_tcmalloc_status "$KERNEL")" in
  do_not_use)
    echo "$FAIL tcmalloc-kernel619: DO NOT USE. rseq changes in kernel $KERNEL break the TCMalloc vendored in MongoDB $MONGO_REL: mongod runs, then crashes after roughly 60 seconds, with potential data corruption. Move to kernel 7.0.14 or later, or to the latest 8.0 maintenance release. (SERVER-125742)"
    case "$KERNEL" in
      7.0.0-*) echo "       Note: on Ubuntu a 7.0.0-NNN label can carry the rseq fix; /proc/version_signature shows the upstream version. If it reads 7.0.14 or later, re-run where it is readable or score it with MONGO_KERNEL_SIGNATURE." ;;
    esac
    ;;
  bad_range)
    echo "$FAIL tcmalloc-kernel619: Kernel $KERNEL is not compliant with MongoDB documented guidance for $MONGO_REL; mongod detects the kernel and exits during startup. Affected range is 6.19 through 7.0.13. Move to kernel 7.0.14 or later. (SERVER-125742)"
    case "$KERNEL" in
      7.0.0-*) echo "       Note: on Ubuntu a 7.0.0-NNN label can carry the rseq fix; /proc/version_signature shows the upstream version. If it reads 7.0.14 or later, re-run where it is readable or score it with MONGO_KERNEL_SIGNATURE." ;;
    esac
    ;;
  ge_619)
    echo "$FAIL tcmalloc-kernel619: Kernel $KERNEL is not compliant with MongoDB documented guidance for $MONGO_REL; this release exits during startup on any kernel 6.19 or later, including 7.0.14 and above, so only a MongoDB upgrade clears it: 8.0.30 or later or 8.3.9 or later (8.0.35 or later, 8.3.14 or later on Ubuntu). (SERVER-125742)"
    ;;
  ubuntu_needs_upgrade)
    echo "$FAIL tcmalloc-kernel619: Kernel $KERNEL is Ubuntu's label for a kernel that carries the rseq fix, but mongod $MONGO_REL compares the version literally and exits during startup. Fixed in MongoDB 8.0.35 and 8.3.14 (SERVER-131779). Upgrading the Ubuntu kernel package does not help while it keeps the 7.0.0 label; a kernel labelled 7.0.14 or later would also clear the guard. (SERVER-125742)"
    ;;
  *)
    echo "$PASS tcmalloc-kernel619: Kernel $KERNEL is outside the documented kernel restrictions for $MONGO_REL"
    ;;
esac

# --- Check mongod binary links ---
if command -v mongod &>/dev/null; then
  MONGOD_BIN=$(which mongod)
  LINKED_TCMALLOC=$(ldd "$MONGOD_BIN" 2>/dev/null | grep -i tcmalloc || true)
  if [ -n "$LINKED_TCMALLOC" ]; then
    echo "$INFO tcmalloc-linked: $LINKED_TCMALLOC"
  else
    echo "$INFO tcmalloc-linked: TCMalloc appears statically compiled into mongod (normal for 8.0)"
  fi
fi

if [ "$LEGACY_TCMALLOC" -eq 1 ]; then
  echo "$INFO tcmalloc-summary: This system uses legacy TCMalloc regardless of OS version, which is documented by MongoDB; THP must be disabled here."
  echo "       See: https://www.mongodb.com/docs/manual/administration/tcmalloc-performance/"
else
  echo "$INFO tcmalloc-summary: Updated TCMalloc (8.0 and later default). See tuning guide:"
  echo "       https://www.mongodb.com/docs/manual/administration/tcmalloc-performance/"
fi
