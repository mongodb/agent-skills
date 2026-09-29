#!/usr/bin/env bash
# check-numa.sh
# Validates NUMA configuration for MongoDB production deployments

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"

echo "=== NUMA Check ==="

# --- Detect NUMA ---
NUMA_NODES=0
if [ -d /sys/devices/system/node ]; then
  NUMA_NODES=$(ls /sys/devices/system/node/ | grep -c 'node[0-9]' 2>/dev/null || echo 0)
fi

if [ "$NUMA_NODES" -le 1 ]; then
  echo "$INFO numa-topology: Single NUMA node or NUMA not present — no NUMA tuning required"
  exit 0
fi

echo "$INFO numa-topology: $NUMA_NODES NUMA nodes detected"

# --- numactl availability ---
if ! command -v numactl &>/dev/null; then
  echo "$FAIL numa-numactl: numactl not installed. Install it and configure mongod to launch with numactl --interleave=all"
  echo "       Fix: yum install numactl -y  OR  apt-get install numactl -y"
  exit 0
fi

# --- Check mongod startup command for numactl ---
MONGOD_CMD=$(ps -eo args | grep '[m]ongod' | head -1)
if echo "$MONGOD_CMD" | grep -q 'numactl.*interleave'; then
  echo "$PASS numa-interleave: mongod is running with numactl --interleave=all"
else
  echo "$FAIL numa-interleave: mongod is NOT running with numactl --interleave=all"
  echo "       Fix: Start mongod with: numactl --interleave=all mongod <options>"
  echo "       For systemd: add ExecStart prefix in the unit file"
fi

# --- zone_reclaim_mode ---
ZONE_RECLAIM=$(sysctl -n vm.zone_reclaim_mode 2>/dev/null)
if [ "$ZONE_RECLAIM" = "0" ]; then
  echo "$PASS numa-zone-reclaim: vm.zone_reclaim_mode=0 (correct)"
else
  echo "$FAIL numa-zone-reclaim: vm.zone_reclaim_mode=$ZONE_RECLAIM (must be 0 on NUMA systems)"
  echo "       Fix: echo 'vm.zone_reclaim_mode=0' >> /etc/sysctl.conf && sysctl -p"
fi

# --- numad daemon ---
if pgrep -x numad >/dev/null 2>&1; then
  echo "$FAIL numa-numad: the numad daemon is running; production notes require it stopped"
  echo "       Fix: systemctl stop numad && systemctl disable numad"
else
  echo "$PASS numa-numad: numad is not running"
fi

echo "$INFO numa-bios: where the platform allows it, disable NUMA in BIOS"

# --- NUMA memory balance ---
if command -v numactl &>/dev/null; then
  echo "$INFO numa-hardware:"
  numactl --hardware 2>/dev/null | head -20 || true
fi

# --- NUMA stats for mongod pid ---
MONGOD_PID=$(pgrep -x mongod | head -1)
if [ -n "$MONGOD_PID" ] && [ -f /proc/"$MONGOD_PID"/numa_maps ]; then
  INTERLEAVED=$(grep -c interleave /proc/"$MONGOD_PID"/numa_maps 2>/dev/null || echo 0)
  echo "$INFO numa-mongod-maps: $INTERLEAVED interleaved memory regions in mongod"
fi
