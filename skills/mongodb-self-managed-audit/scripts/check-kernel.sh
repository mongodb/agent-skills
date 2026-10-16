#!/usr/bin/env bash
# check-kernel.sh
# Validates kernel parameters critical for MongoDB production performance

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"
UNKNOWN="[UNKNOWN]"

echo "=== Kernel & System Parameters Check ==="

# Echoes the value and returns 0, or returns 1 having printed nothing.
# Returning the value on stdout and the outcome in the exit status keeps an
# unreadable key from being substituted into the caller as if it were data.
check_sysctl() {
  local key="$1"
  local val
  val=$(sysctl -n "$key" 2>/dev/null)
  [ -n "$val" ] || return 1
  echo "$val"
}

# Why a read failed, as far as we can tell from here. An unprivileged run and a
# kernel without the key are different remediations, so name which one applies.
sysctl_unknown_reason() {
  local key="$1"
  if [ ! -e "/proc/sys/${key//.//}" ]; then
    echo "key not present on this kernel"
  elif [ "$(id -u)" -ne 0 ]; then
    echo "not readable by this unprivileged run; re-run with sudo"
  else
    echo "sysctl returned no value"
  fi
}

# --- vm.swappiness ---
if ! SWAPPINESS=$(check_sysctl vm.swappiness); then
  echo "$UNKNOWN vm.swappiness: $(sysctl_unknown_reason vm.swappiness)"
fi
if [[ "$SWAPPINESS" =~ ^[0-9]+$ ]]; then
  if [ "$SWAPPINESS" -eq 1 ]; then
    echo "$PASS vm.swappiness: $SWAPPINESS (recommended: 1)"
  elif [ "$SWAPPINESS" -eq 0 ]; then
    echo "$PASS vm.swappiness: 0 (valid on a host dedicated to MongoDB with swap disabled)"
  elif [ "$SWAPPINESS" -le 10 ]; then
    echo "$WARN vm.swappiness: $SWAPPINESS (recommended: 1 — swapping under memory pressure can cause latency spikes)"
  else
    echo "$FAIL vm.swappiness: $SWAPPINESS (recommended: 1 — high swappiness causes severe MongoDB performance degradation)"
    echo "       Fix: echo 'vm.swappiness=1' >> /etc/sysctl.conf && sysctl -p"
  fi
elif [ -n "$SWAPPINESS" ]; then
  echo "$UNKNOWN vm.swappiness: sysctl returned a non-numeric value: $SWAPPINESS"
fi

# --- vm.dirty_ratio ---
if ! DIRTY_RATIO=$(check_sysctl vm.dirty_ratio); then
  echo "$UNKNOWN vm.dirty_ratio: $(sysctl_unknown_reason vm.dirty_ratio)"
fi
if [[ "$DIRTY_RATIO" =~ ^[0-9]+$ ]]; then
  if [ "$DIRTY_RATIO" -le 15 ]; then
    echo "$PASS vm.dirty_ratio: $DIRTY_RATIO (recommended: <= 15)"
  elif [ "$DIRTY_RATIO" -le 40 ]; then
    echo "$WARN vm.dirty_ratio: $DIRTY_RATIO (recommended: <= 15 — high value delays flushing dirty pages)"
    echo "       Fix: echo 'vm.dirty_ratio=15' >> /etc/sysctl.conf && sysctl -p"
  else
    echo "$FAIL vm.dirty_ratio: $DIRTY_RATIO (critically high — may cause large write stalls)"
    echo "       Fix: echo 'vm.dirty_ratio=15' >> /etc/sysctl.conf && sysctl -p"
  fi
fi

# --- vm.dirty_background_ratio ---
if ! DIRTY_BG=$(check_sysctl vm.dirty_background_ratio); then
  echo "$UNKNOWN vm.dirty_background_ratio: $(sysctl_unknown_reason vm.dirty_background_ratio)"
fi
if [[ "$DIRTY_BG" =~ ^[0-9]+$ ]]; then
  if [ "$DIRTY_BG" -le 5 ]; then
    echo "$PASS vm.dirty_background_ratio: $DIRTY_BG (recommended: 3-5)"
  else
    echo "$WARN vm.dirty_background_ratio: $DIRTY_BG (recommended: 3-5)"
    echo "       Fix: echo 'vm.dirty_background_ratio=5' >> /etc/sysctl.conf && sysctl -p"
  fi
fi

# --- kernel.pid_max ---
if ! PID_MAX=$(check_sysctl kernel.pid_max); then
  echo "$UNKNOWN kernel.pid_max: $(sysctl_unknown_reason kernel.pid_max)"
fi
if [[ "$PID_MAX" =~ ^[0-9]+$ ]]; then
  if [ "$PID_MAX" -ge 64000 ]; then
    echo "$PASS kernel.pid_max: $PID_MAX"
  else
    echo "$WARN kernel.pid_max: $PID_MAX (recommended: >= 64000)"
    echo "       Fix: echo 'kernel.pid_max=64000' >> /etc/sysctl.conf && sysctl -p"
  fi
fi

# --- fs.file-max ---
if ! FILE_MAX=$(check_sysctl fs.file-max); then
  echo "$UNKNOWN fs.file-max: $(sysctl_unknown_reason fs.file-max)"
fi
if [[ "$FILE_MAX" =~ ^[0-9]+$ ]]; then
  if [ "$FILE_MAX" -ge 98000 ]; then
    echo "$PASS fs.file-max: $FILE_MAX"
  elif [ "$FILE_MAX" -ge 64000 ]; then
    echo "$WARN fs.file-max: $FILE_MAX (recommended: >= 98000)"
  else
    echo "$FAIL fs.file-max: $FILE_MAX (critically low)"
    echo "       Fix: echo 'fs.file-max=98000' >> /etc/sysctl.conf && sysctl -p"
  fi
fi

# --- net.core.somaxconn ---
if ! SOMAXCONN=$(check_sysctl net.core.somaxconn); then
  echo "$UNKNOWN net.core.somaxconn: $(sysctl_unknown_reason net.core.somaxconn)"
fi
if [[ "$SOMAXCONN" =~ ^[0-9]+$ ]]; then
  if [ "$SOMAXCONN" -ge 4096 ]; then
    echo "$PASS net.core.somaxconn: $SOMAXCONN"
  else
    echo "$WARN net.core.somaxconn: $SOMAXCONN (recommended: >= 4096 for high-connection workloads)"
    echo "       Fix: echo 'net.core.somaxconn=4096' >> /etc/sysctl.conf && sysctl -p"
  fi
fi

# --- net.ipv4.tcp_keepalive_time ---
if ! TCP_KEEPALIVE=$(check_sysctl net.ipv4.tcp_keepalive_time); then
  echo "$UNKNOWN net.ipv4.tcp_keepalive_time: $(sysctl_unknown_reason net.ipv4.tcp_keepalive_time)"
fi
if [[ "$TCP_KEEPALIVE" =~ ^[0-9]+$ ]]; then
  if [ "$TCP_KEEPALIVE" -le 120 ]; then
    echo "$PASS net.ipv4.tcp_keepalive_time: $TCP_KEEPALIVE seconds (recommended: 120)"
  elif [ "$TCP_KEEPALIVE" -le 300 ]; then
    echo "$WARN net.ipv4.tcp_keepalive_time: $TCP_KEEPALIVE seconds (recommended: 120; 300 is the documented override ceiling)"
    echo "       Fix: echo 'net.ipv4.tcp_keepalive_time=120' >> /etc/sysctl.conf && sysctl -p"
  else
    echo "$WARN net.ipv4.tcp_keepalive_time: $TCP_KEEPALIVE seconds (recommended: 120; the 7200 default leaves stale connections)"
    echo "       Fix: echo 'net.ipv4.tcp_keepalive_time=120' >> /etc/sysctl.conf && sysctl -p"
  fi
fi

# --- vm.force_cgroup_v2_swappiness (RHEL/CentOS, overrides cgroup swappiness defaults) ---
if [ -f /etc/redhat-release ]; then
  FORCE_CGROUP=$(sysctl -n vm.force_cgroup_v2_swappiness 2>/dev/null)
  if [ -z "$FORCE_CGROUP" ]; then
    echo "$INFO vm.force_cgroup_v2_swappiness: not present on this kernel"
  elif [ "$FORCE_CGROUP" = "1" ]; then
    echo "$PASS vm.force_cgroup_v2_swappiness: 1 (vm.swappiness overrides the cgroup default)"
  else
    echo "$WARN vm.force_cgroup_v2_swappiness: $FORCE_CGROUP (set to 1 on RHEL so vm.swappiness takes effect)"
    echo "       Fix: echo 'vm.force_cgroup_v2_swappiness=1' >> /etc/sysctl.conf && sysctl -p"
  fi
fi

# --- vm.zone_reclaim_mode ---
if ! ZONE_RECLAIM=$(check_sysctl vm.zone_reclaim_mode); then
  echo "$UNKNOWN vm.zone_reclaim_mode: $(sysctl_unknown_reason vm.zone_reclaim_mode)"
fi
if [[ "$ZONE_RECLAIM" =~ ^[0-9]+$ ]]; then
  if [ "$ZONE_RECLAIM" -eq 0 ]; then
    echo "$PASS vm.zone_reclaim_mode: 0 (correct for NUMA systems)"
  else
    echo "$FAIL vm.zone_reclaim_mode: $ZONE_RECLAIM (must be 0 — non-zero causes severe latency on NUMA systems)"
    echo "       Fix: echo 'vm.zone_reclaim_mode=0' >> /etc/sysctl.conf && sysctl -p"
  fi
fi

# --- Current open files count ---
CURRENT_FD=$(cat /proc/sys/fs/file-nr 2>/dev/null | awk '{print $1}')
FD_MAX=$(cat /proc/sys/fs/file-nr 2>/dev/null | awk '{print $3}')
if [ -n "$CURRENT_FD" ]; then
  echo "$INFO fs.file-nr: $CURRENT_FD open / $FD_MAX max"
fi
