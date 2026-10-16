#!/usr/bin/env bash
# check-thp.sh
# Validates Transparent Huge Pages (THP) configuration.
# MongoDB 8.0 and later require THP ENABLED. MongoDB 7.0 and earlier require it DISABLED.
# Source: https://www.mongodb.com/docs/manual/tutorial/transparent-huge-pages/
# Usage: bash check-thp.sh [--version 7.0|8.0|8.3|9.0]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-version.sh
. "$SCRIPT_DIR/lib-version.sh"
mongo_parse_args "$@" || exit 1

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"
UNKNOWN="[UNKNOWN]"

echo "=== Transparent Huge Pages (THP) Check ==="

THP_ENABLED_PATH="/sys/kernel/mm/transparent_hugepage/enabled"
THP_DEFRAG_PATH="/sys/kernel/mm/transparent_hugepage/defrag"
THP_MAX_PTES_PATH="/sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none"

# Extract the bracketed active value, e.g. "always madvise [never]" -> "never"
active_value() {
  sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$1" 2>/dev/null
}

if [ "$MONGO_VERSION" = "unknown" ]; then
  echo "$INFO thp-version: MongoDB version not supplied; THP guidance is version-specific"
  echo "       8.0 and later require THP enabled; 7.0 and earlier require it disabled"
else
  echo "$INFO thp-version: scoring against MongoDB $MONGO_VERSION expectations"
fi

# --- THP enabled ---
if [ -f "$THP_ENABLED_PATH" ]; then
  ACTIVE=$(active_value "$THP_ENABLED_PATH")
  echo "$INFO thp-enabled-raw: $(cat "$THP_ENABLED_PATH")"

  if mongo_version_at_least 8 0; then
    case "$ACTIVE" in
      always)
        echo "$PASS thp-enabled: THP is 'always', as MongoDB 8.0 and later require" ;;
      madvise)
        echo "$WARN thp-enabled: THP is 'madvise'; MongoDB 8.0 and later expect 'always'"
        echo "       Fix: echo always > $THP_ENABLED_PATH" ;;
      never)
        echo "$FAIL thp-enabled: THP is 'never'; MongoDB 8.0 and later require 'always'"
        echo "       Fix: echo always > $THP_ENABLED_PATH" ;;
      *)
        echo "$WARN thp-enabled: unrecognized THP state '$ACTIVE'" ;;
    esac
  else
    case "$ACTIVE" in
      never)
        echo "$PASS thp-enabled: THP is 'never', as MongoDB 7.0 and earlier require" ;;
      madvise)
        echo "$WARN thp-enabled: THP is 'madvise'; MongoDB 7.0 and earlier expect 'never'"
        echo "       Fix: echo never > $THP_ENABLED_PATH" ;;
      always)
        echo "$FAIL thp-enabled: THP is 'always'; MongoDB 7.0 and earlier require 'never'"
        echo "       Fix: echo never > $THP_ENABLED_PATH" ;;
      *)
        echo "$WARN thp-enabled: unrecognized THP state '$ACTIVE'" ;;
    esac
  fi
else
  echo "$UNKNOWN thp-enabled: $THP_ENABLED_PATH not found. Inside a container this is the node's setting and is not visible here; re-check on the host. On a kernel built without THP the setting does not exist."
fi

# --- THP defrag ---
if [ -f "$THP_DEFRAG_PATH" ]; then
  DEFRAG_ACTIVE=$(active_value "$THP_DEFRAG_PATH")

  if mongo_version_at_least 8 0; then
    if [ "$DEFRAG_ACTIVE" = "defer+madvise" ]; then
      echo "$PASS thp-defrag: defrag is 'defer+madvise', as MongoDB 8.0 and later require"
    else
      echo "$WARN thp-defrag: defrag is '$DEFRAG_ACTIVE'; MongoDB 8.0 and later expect 'defer+madvise'"
      echo "       Fix: echo defer+madvise > $THP_DEFRAG_PATH"
    fi
  else
    if [ "$DEFRAG_ACTIVE" = "never" ]; then
      echo "$PASS thp-defrag: defrag is 'never', as MongoDB 7.0 and earlier require"
    else
      echo "$FAIL thp-defrag: defrag is '$DEFRAG_ACTIVE'; MongoDB 7.0 and earlier require 'never'"
      echo "       Fix: echo never > $THP_DEFRAG_PATH"
    fi
  fi
else
  echo "$UNKNOWN thp-defrag: $THP_DEFRAG_PATH not found. Same cause as thp-enabled: re-check on the host."
fi

# --- khugepaged max_ptes_none (8.0 and later) ---
if mongo_version_at_least 8 0; then
  if [ -f "$THP_MAX_PTES_PATH" ]; then
    MAX_PTES=$(cat "$THP_MAX_PTES_PATH" 2>/dev/null)
    if [ "$MAX_PTES" = "0" ]; then
      echo "$PASS thp-max-ptes-none: khugepaged max_ptes_none is 0, as MongoDB 8.0 and later require"
    else
      echo "$WARN thp-max-ptes-none: khugepaged max_ptes_none is $MAX_PTES; MongoDB 8.0 and later expect 0"
      echo "       Fix: echo 0 > $THP_MAX_PTES_PATH"
    fi
  else
    echo "$UNKNOWN thp-max-ptes-none: $THP_MAX_PTES_PATH not found. Re-check on the host."
  fi

  # --- vm.overcommit_memory (set alongside THP on 8.0 and later) ---
  OVERCOMMIT=$(cat /proc/sys/vm/overcommit_memory 2>/dev/null)
  if [ -z "$OVERCOMMIT" ]; then
    echo "$UNKNOWN thp-overcommit: /proc/sys/vm/overcommit_memory could not be read. Re-check on the host, or with sudo if this run was unprivileged."
  elif [ "$OVERCOMMIT" = "1" ]; then
    echo "$PASS thp-overcommit: vm.overcommit_memory is 1, as MongoDB 8.0 and later require"
  else
    echo "$WARN thp-overcommit: vm.overcommit_memory is $OVERCOMMIT; MongoDB 8.0 and later expect 1"
    echo "       Fix: sysctl -w vm.overcommit_memory=1 and persist in /etc/sysctl.conf"
  fi
fi

# --- Persistence across reboot ---
if command -v tuned-adm >/dev/null 2>&1; then
  TUNED_PROFILE=$(tuned-adm active 2>/dev/null | sed -n 's/.*Current active profile: //p')
  echo "$INFO thp-tuned: tuned active profile: ${TUNED_PROFILE:-none}"
fi

PERSISTENT=0
if [ -n "${TUNED_PROFILE:-}" ] && [ "${TUNED_PROFILE:-}" != "none" ]; then
  PERSISTENT=1
  echo "$INFO thp-persistent: tuned profile '$TUNED_PROFILE' is active and may set THP at boot; confirm it sets the value this version needs"
fi
if systemctl list-unit-files --type=service 2>/dev/null | grep -qi 'thp\|hugepage'; then
  PERSISTENT=1
  echo "$INFO thp-persistent: a THP-related systemd unit is present; confirm it sets the value this version needs"
fi
if grep -rq 'transparent_hugepage' /etc/rc.local /etc/rc.d/ 2>/dev/null; then
  PERSISTENT=1
  echo "$INFO thp-persistent: transparent_hugepage referenced in rc.local or rc.d"
fi

if [ "$PERSISTENT" -eq 0 ]; then
  echo "$WARN thp-persistent: no persistence mechanism detected; THP settings reset on reboot"
  if mongo_version_at_least 8 0; then
    echo "       Fix: persist these across reboot with a systemd unit ordered before"
    echo "       mongod, a tuned profile, or the host build image. Whichever you use,"
    echo "       it must set:"
    echo "         echo always > /sys/kernel/mm/transparent_hugepage/enabled"
    echo "         echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag"
    echo "         echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none"
    echo "         echo 1 > /proc/sys/vm/overcommit_memory"
  else
    echo "       Fix: create a systemd unit that runs before mongod and sets:"
    echo "         echo never > /sys/kernel/mm/transparent_hugepage/enabled"
    echo "         echo never > /sys/kernel/mm/transparent_hugepage/defrag"
  fi
fi
