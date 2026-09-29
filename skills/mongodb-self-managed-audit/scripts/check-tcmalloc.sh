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

# --- Check MALLOC_CONF environment variable ---
MONGOD_PID=$(pgrep -x mongod | head -1)
if [ -n "$MONGOD_PID" ]; then
  MALLOC_CONF=$(cat /proc/"$MONGOD_PID"/environ 2>/dev/null | tr '\0' '\n' | grep MALLOC_CONF || true)
  if [ -n "$MALLOC_CONF" ]; then
    echo "$INFO tcmalloc-MALLOC_CONF: $MALLOC_CONF"
    echo "$WARN tcmalloc-MALLOC_CONF: MALLOC_CONF is set for mongod — verify this is intentional and correct"
  else
    echo "$PASS tcmalloc-MALLOC_CONF: MALLOC_CONF is not set (using MongoDB defaults)"
  fi

  # --- Check LD_PRELOAD for custom allocators ---
  LD_PRELOAD=$(cat /proc/"$MONGOD_PID"/environ 2>/dev/null | tr '\0' '\n' | grep LD_PRELOAD || true)
  if [ -n "$LD_PRELOAD" ]; then
    echo "$WARN tcmalloc-LD_PRELOAD: LD_PRELOAD=$LD_PRELOAD — custom allocator may conflict with MongoDB's TCMalloc"
  else
    echo "$PASS tcmalloc-LD_PRELOAD: No LD_PRELOAD override detected"
  fi
fi

# --- tcmalloc.aggressive_memory_decommit ---
# This is a mongod parameter tunable at runtime
if [ -n "$MONGOD_PID" ]; then
  MONGOD_PORT=$(grep -E '^\s*port' /etc/mongod.conf 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' ' | head -1)
  MONGOD_PORT="${MONGOD_PORT:-27017}"
  echo "$INFO tcmalloc-decommit: To check aggressiveMemoryDecommit, run in mongosh:"
  echo "       db.adminCommand({getParameter:1, tcmallocAggressiveMemoryDecommit:1})"
fi

# --- Kernel TCMalloc incompatibility ---
# Same version-aware test as check-platform.sh, from lib-version.sh.
KERNEL=$(uname -r)
MONGO_REL="$MONGO_VERSION${MONGO_VERSION_PATCH:+.$MONGO_VERSION_PATCH}"
case "$(kernel_tcmalloc_status "$KERNEL")" in
  do_not_use)
    echo "$FAIL tcmalloc-kernel619: DO NOT USE. rseq changes in kernel $KERNEL break the TCMalloc vendored in MongoDB $MONGO_REL: mongod runs, then crashes after roughly 60 seconds, with potential data corruption. Move to kernel 7.0.14 or later, or to the latest 8.0 maintenance release. (SERVER-125742)"
    ;;
  bad_range)
    echo "$FAIL tcmalloc-kernel619: Kernel $KERNEL is not compliant with MongoDB documented guidance for $MONGO_REL; mongod detects the kernel and exits during startup. Affected range is 6.19 through 7.0.13. Move to kernel 7.0.14 or later. (SERVER-125742)"
    ;;
  ge_619)
    echo "$FAIL tcmalloc-kernel619: Kernel $KERNEL is not compliant with MongoDB documented guidance for $MONGO_REL; this release exits during startup on any kernel 6.19 or later, including 7.0.14 and above, so only a MongoDB upgrade clears it. (SERVER-125742)"
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
  echo "$INFO tcmalloc-summary: This system uses legacy TCMalloc — this is expected and documented by MongoDB."
  echo "       See: https://www.mongodb.com/docs/manual/administration/tcmalloc-performance/"
else
  echo "$INFO tcmalloc-summary: Updated TCMalloc (8.0 and later default). See tuning guide:"
  echo "       https://www.mongodb.com/docs/manual/administration/tcmalloc-performance/"
fi
