#!/usr/bin/env bash
# check-numa.sh
# Validates NUMA configuration for MongoDB production deployments
# Source: "Configuring NUMA on Linux" in the production notes. The section is
# identical in 7.0, 8.0, 8.3 and 9.0; only the numad guidance differs.
# Usage: bash check-numa.sh [--version 7.0|8.0|8.3|9.0]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-version.sh
. "$SCRIPT_DIR/lib-version.sh"
mongo_parse_args "$@" || exit 1

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"
UNKNOWN="[UNKNOWN]"

# Test seams only: let the regression tests point at a fake topology. Never set
# these on a real audit.
NODE_DIR="${NUMA_NODE_DIR:-/sys/devices/system/node}"
PROC_DIR="${NUMA_PROC_DIR:-/proc}"

# numactl spells interleave-all several ways; the docs use --interleave=all.
INTERLEAVE_RE='numactl.*(--interleave[= ]all|-i[ =]?all)'

echo "=== NUMA Check ==="

# --- Detect NUMA ---
NUMA_NODES=0
for node in "$NODE_DIR"/node[0-9]*; do
  [ -d "$node" ] && NUMA_NODES=$((NUMA_NODES + 1))
done

if [ "$NUMA_NODES" -le 1 ]; then
  echo "$INFO numa-topology: Single NUMA node or NUMA not present — no NUMA tuning required"
  exit 0
fi

echo "$INFO numa-topology: $NUMA_NODES NUMA nodes detected"

# --- numactl availability ---
# Keep going when it is missing: zone reclaim and numad are independent of it.
if command -v numactl &>/dev/null; then
  echo "$PASS numa-numactl: numactl is installed"
else
  echo "$FAIL numa-numactl: numactl is not installed; mongod and mongos must be started through numactl --interleave=all"
  echo "       Fix: install the numactl package for your platform (yum install numactl  OR  apt-get install numactl)"
fi

# --- Interleave, live evidence ---
# numactl execs the program it launches, so a correctly started mongod shows as
# plain /usr/bin/mongod in ps. The proof is the memory policy the kernel
# recorded for the process, in /proc/<pid>/numa_maps.
INSTANCES=0
for proc_name in mongod mongos; do
  for pid in $(pgrep -x "$proc_name"); do
    INSTANCES=$((INSTANCES + 1))
    maps="$PROC_DIR/$pid/numa_maps"
    # numa_maps is mode 0444, so test -r passes, but the kernel refuses the read
    # for another user's process. Only an actual read tells us.
    if ! policies=$(cut -d' ' -f2 "$maps" 2>/dev/null) || [ -z "$policies" ]; then
      if [ "$(id -u)" -ne 0 ]; then
        reason="not readable by this unprivileged run; re-run with sudo"
      else
        reason="$maps could not be read"
      fi
      echo "$UNKNOWN numa-interleave: $proc_name (PID $pid) memory policy unknown: $reason"
      continue
    fi
    interleaved=$(echo "$policies" | grep -c '^interleave')
    if [ "$interleaved" -gt 0 ]; then
      echo "$PASS numa-interleave: $proc_name (PID $pid) runs with an interleave memory policy ($interleaved interleaved regions)"
    else
      echo "$FAIL numa-interleave: $proc_name (PID $pid) has no interleave memory policy; it was not started through numactl --interleave=all"
    fi
  done
done

# --- Interleave, startup configuration ---
# Live evidence does not survive a restart, so also check how instances start.
INIT_SYSTEM=$(ps --no-headers -o comm 1 2>/dev/null | tr -d ' ')
case "$INIT_SYSTEM" in
  systemd)
    UNITS=$(systemctl list-unit-files --type=service --no-legend 'mongo*' 2>/dev/null | cut -d' ' -f1)
    if [ -z "$UNITS" ]; then
      if [ "$INSTANCES" -eq 0 ]; then
        echo "$UNKNOWN numa-interleave-config: no mongod or mongos is running and no mongo* systemd unit was found; confirm how instances will be started"
      else
        echo "$WARN numa-interleave-config: mongod or mongos is running but no mongo* systemd unit was found; confirm the instances are started through numactl --interleave=all after a restart"
      fi
    fi
    for unit in $UNITS; do
      exec_start=$(systemctl show -p ExecStart --value "$unit" 2>/dev/null)
      if [ -z "$exec_start" ]; then
        # Template units (mongod@.service) have no ExecStart until instantiated.
        exec_start=$(systemctl cat "$unit" 2>/dev/null | grep -E '^[[:space:]]*ExecStart=.+' | tail -1)
      fi
      if [ -z "$exec_start" ]; then
        echo "$UNKNOWN numa-interleave-config: $unit ExecStart could not be read"
      elif echo "$exec_start" | grep -qE "$INTERLEAVE_RE"; then
        echo "$PASS numa-interleave-config: $unit starts through numactl --interleave=all"
      else
        fragment=$(systemctl show -p FragmentPath --value "$unit" 2>/dev/null)
        echo "$FAIL numa-interleave-config: $unit ExecStart does not start through numactl --interleave=all"
        case "$fragment" in
          /etc/*) echo "       Fix: edit $fragment so ExecStart begins with /usr/bin/numactl --interleave=all" ;;
          *)      echo "       Fix: sudo cp ${fragment:-/lib/systemd/system/$unit} /etc/systemd/system/"
                  echo "            then edit /etc/systemd/system/$unit so ExecStart begins with /usr/bin/numactl --interleave=all" ;;
        esac
        echo "            sudo systemctl daemon-reload, then restart $unit"
      fi
    done
    ;;
  init)
    echo "$PASS numa-interleave-config: SysV init; the default MongoDB init script starts instances through numactl. Re-check if the script was modified"
    ;;
  *)
    echo "$UNKNOWN numa-interleave-config: init system '${INIT_SYSTEM:-unknown}' is not systemd or SysV init; confirm each custom init script starts MongoDB with numactl --interleave=all <path> <options>"
    ;;
esac

# --- zone_reclaim_mode ---
ZONE_RECLAIM=$(sysctl -n vm.zone_reclaim_mode 2>/dev/null)
if [ -z "$ZONE_RECLAIM" ]; then
  if [ "$(id -u)" -ne 0 ]; then
    echo "$UNKNOWN numa-zone-reclaim: vm.zone_reclaim_mode not readable by this unprivileged run; re-run with sudo"
  else
    echo "$UNKNOWN numa-zone-reclaim: vm.zone_reclaim_mode could not be read"
  fi
elif [ "$ZONE_RECLAIM" = "0" ]; then
  echo "$PASS numa-zone-reclaim: vm.zone_reclaim_mode=0 (correct)"
else
  echo "$FAIL numa-zone-reclaim: vm.zone_reclaim_mode=$ZONE_RECLAIM (must be 0 on NUMA systems)"
  echo "       Fix: sudo sysctl -w vm.zone_reclaim_mode=0, and persist it in /etc/sysctl.conf"
fi

# --- numad daemon ---
# The 8.0-and-later production notes say numad should not be enabled. The 7.0
# notes do not mention it; there it is advisory, since numad rebinds memory
# against the numactl interleave policy that every version documents.
NUMAD_STATE=""
if pgrep -x numad >/dev/null 2>&1; then
  NUMAD_STATE="running"
fi
if [ "$(systemctl is-enabled numad 2>/dev/null)" = "enabled" ]; then
  NUMAD_STATE="${NUMAD_STATE:+$NUMAD_STATE and }enabled at boot"
fi

if [ -z "$NUMAD_STATE" ]; then
  echo "$PASS numa-numad: numad is not running and not enabled"
elif [ "$MONGO_VERSION" = "unknown" ]; then
  echo "$WARN numa-numad: numad is $NUMAD_STATE; MongoDB version not supplied (8.0 and later: FAIL, 7.0: advisory)"
  echo "       Fix: systemctl disable --now numad"
elif mongo_version_at_least 8 0; then
  echo "$FAIL numa-numad: numad is $NUMAD_STATE; MongoDB $MONGO_VERSION production notes say numad should not be enabled on MongoDB servers"
  echo "       Fix: systemctl disable --now numad"
else
  echo "$WARN numa-numad: numad is $NUMAD_STATE; not in the 7.0 production notes, but numad can override the documented numactl --interleave=all policy"
  echo "       Fix: systemctl disable --now numad"
fi

echo "$INFO numa-bios: where the platform allows it, disable NUMA in BIOS"

# --- NUMA hardware layout ---
if command -v numactl &>/dev/null; then
  echo "$INFO numa-hardware:"
  numactl --hardware 2>/dev/null | head -20 || true
fi
