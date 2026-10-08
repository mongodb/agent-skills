#!/usr/bin/env bash
# check-clock.sh
# Validates clock synchronization. Production notes require NTP on all hosts,
# and it matters most in sharded clusters.
# Source: https://www.mongodb.com/docs/manual/administration/production-notes/
# Usage: bash check-clock.sh [--version 7.0|8.0|8.3|9.0]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-version.sh
. "$SCRIPT_DIR/lib-version.sh"
mongo_parse_args "$@" || exit 1

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"

echo "=== Clock Synchronization Check ==="

echo "$INFO clock-now: $(date '+%Y-%m-%d %H:%M:%S %Z')"

# --- A time daemon must be running ---
TIME_DAEMON=""
for d in chronyd ntpd systemd-timesyncd timesyncd; do
  if pgrep -x "$d" >/dev/null 2>&1; then TIME_DAEMON="$d"; break; fi
done

if [ -n "$TIME_DAEMON" ]; then
  echo "$PASS clock-daemon: $TIME_DAEMON is running"
else
  echo "$FAIL clock-daemon: no time daemon detected (chronyd, ntpd, or systemd-timesyncd)"
  echo "       Production notes require NTP on all hosts, and sharded clusters depend on it"
  echo "       Fix: install and enable chrony, then systemctl enable --now chronyd"
fi

# --- Synchronization state ---
if command -v timedatectl >/dev/null 2>&1; then
  SYNCED=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
  if [ -z "$SYNCED" ]; then
    SYNCED=$(timedatectl status 2>/dev/null | sed -n 's/.*[Ss]ystem clock synchronized: *//p')
  fi
  case "$SYNCED" in
    yes|true) echo "$PASS clock-synchronized: the system clock is synchronized" ;;
    no|false) echo "$FAIL clock-synchronized: the system clock is not synchronized"
              echo "       Fix: confirm the time daemon can reach its upstream servers" ;;
    *)        echo "$WARN clock-synchronized: synchronization state undetermined" ;;
  esac
fi

# --- Measured offset, where the daemon reports one ---
if command -v chronyc >/dev/null 2>&1; then
  OFFSET=$(chronyc tracking 2>/dev/null | sed -n 's/.*System time *: *\([0-9.]*\).*/\1/p')
  if [ -n "$OFFSET" ]; then
    echo "$INFO clock-offset: chrony reports a system time offset of ${OFFSET}s"
  fi
elif command -v ntpq >/dev/null 2>&1; then
  ntpq -p 2>/dev/null | head -5 | sed "s/^/$INFO clock-peers: /"
fi

# --- Timezone consistency across a cluster ---
TZ_NAME=$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null)
echo "$INFO clock-timezone: ${TZ_NAME:-unknown}; keep this consistent across every cluster member"

echo "$INFO clock-drift-parameter: mongod caps tolerated drift with maxAcceptableLogicalClockDriftSecs; drift beyond it breaks communication between components"
