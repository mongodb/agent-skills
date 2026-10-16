#!/usr/bin/env bash
# check-ulimits.sh
# Validates system ulimits for the mongod process and system-wide limits

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"

echo "=== Ulimits Check ==="

MONGOD_PID=$(pgrep -x mongod | head -1)

# check_limit NAME SOFT HARD RECOMMENDED LABEL [FAIL_BELOW]
# FAIL_BELOW is the threshold under which the limit is blocking rather than
# suboptimal, and it differs per limit: references/checks-reference.md puts
# nofile at 1024 and nproc at 32768. It defaults to 1024 so a caller that omits
# it keeps the old behaviour.
check_limit() {
  local name="$1"
  local soft="$2"
  local hard="$3"
  local recommended_soft="$4"
  local label="$5"
  local fail_below="${6:-1024}"

  if [ "$soft" = "unlimited" ] || [ "$soft" -ge "$recommended_soft" ] 2>/dev/null; then
    echo "$PASS ulimit-$label: soft=$soft hard=$hard (recommended >= $recommended_soft)"
  elif [ "$soft" = "unlimited" ]; then
    echo "$PASS ulimit-$label: unlimited"
  else
    if [ "$soft" -lt "$fail_below" ] 2>/dev/null; then
      echo "$FAIL ulimit-$label: soft=$soft hard=$hard (critically low, recommended >= $recommended_soft)"
    else
      echo "$WARN ulimit-$label: soft=$soft hard=$hard (recommended >= $recommended_soft)"
    fi
    echo "       Fix: Add to /etc/security/limits.conf or /etc/security/limits.d/99-mongodb.conf:"
    echo "         mongod soft $name $recommended_soft"
    echo "         mongod hard $name $recommended_soft"
  fi
}

if [ -n "$MONGOD_PID" ]; then
  echo "$INFO ulimits-source: Reading from running mongod process (PID $MONGOD_PID)"

  # Parse /proc/<pid>/limits
  while IFS= read -r line; do
    case "$line" in
      *"Max open files"*)
        NOFILE_SOFT=$(echo "$line" | awk '{print $4}')
        NOFILE_HARD=$(echo "$line" | awk '{print $5}')
        ;;
      *"Max processes"*)
        NPROC_SOFT=$(echo "$line" | awk '{print $3}')
        NPROC_HARD=$(echo "$line" | awk '{print $4}')
        ;;
      *"Max locked memory"*)
        MEMLOCK_SOFT=$(echo "$line" | awk '{print $4}')
        MEMLOCK_HARD=$(echo "$line" | awk '{print $5}')
        ;;
      *"Max virtual memory"*)
        AS_SOFT=$(echo "$line" | awk '{print $4}')
        AS_HARD=$(echo "$line" | awk '{print $5}')
        ;;
      *"Max core file size"*)
        CORE_SOFT=$(echo "$line" | awk '{print $5}')
        CORE_HARD=$(echo "$line" | awk '{print $6}')
        ;;
    esac
  done < /proc/"$MONGOD_PID"/limits

  check_limit "nofile"  "${NOFILE_SOFT:-0}"   "${NOFILE_HARD:-0}"   64000 "open-files"
  check_limit "nproc"   "${NPROC_SOFT:-0}"    "${NPROC_HARD:-0}"    64000 "processes" 32768

  if [ "${MEMLOCK_SOFT:-0}" = "unlimited" ]; then
    echo "$PASS ulimit-memlock: unlimited (required for WiredTiger)"
  else
    echo "$WARN ulimit-memlock: soft=$MEMLOCK_SOFT (recommended: unlimited for WiredTiger)"
    echo "       Fix: mongod soft memlock unlimited in /etc/security/limits.d/99-mongodb.conf"
  fi

  if [ "${AS_SOFT:-0}" = "unlimited" ]; then
    echo "$PASS ulimit-virtual-memory: unlimited"
  else
    echo "$WARN ulimit-virtual-memory: soft=$AS_SOFT (recommended: unlimited)"
  fi

  if [ "${CORE_SOFT:-0}" = "unlimited" ]; then
    echo "$PASS ulimit-core: unlimited (useful for debugging)"
  else
    echo "$INFO ulimit-core: soft=$CORE_SOFT (set to unlimited to enable core dumps for debugging)"
  fi

else
  echo "$WARN ulimits-source: mongod not running — checking system-level limits"

  # Fall back to current shell limits
  NOFILE_SOFT=$(ulimit -Sn 2>/dev/null)
  NOFILE_HARD=$(ulimit -Hn 2>/dev/null)
  NPROC_SOFT=$(ulimit -Su 2>/dev/null)
  NPROC_HARD=$(ulimit -Hu 2>/dev/null)

  check_limit "nofile" "$NOFILE_SOFT" "$NOFILE_HARD" 64000 "open-files"
  check_limit "nproc"  "$NPROC_SOFT"  "$NPROC_HARD"  64000 "processes" 32768

  # Check /etc/security/limits.d/ for mongod entries
  LIMITS_FILE=$(grep -rl 'mongod' /etc/security/limits.d/ 2>/dev/null | head -1)
  if [ -n "$LIMITS_FILE" ]; then
    echo "$INFO limits-file: Found mongod limits in $LIMITS_FILE"
    grep 'mongod' "$LIMITS_FILE"
  else
    echo "$WARN limits-file: No mongod-specific limits file found in /etc/security/limits.d/"
    echo "       Fix: Create /etc/security/limits.d/99-mongodb.conf with:"
    echo "         mongod soft nofile 64000"
    echo "         mongod hard nofile 64000"
    echo "         mongod soft nproc 64000"
    echo "         mongod hard nproc 64000"
    echo "         mongod soft memlock unlimited"
    echo "         mongod hard memlock unlimited"
  fi
fi

# --- systemd LimitNOFILE (if applicable) ---
if systemctl is-active mongod &>/dev/null || systemctl status mongod &>/dev/null 2>&1; then
  SYSTEMD_NOFILE=$(systemctl show mongod --property=LimitNOFILE 2>/dev/null | cut -d= -f2)
  if [ -n "$SYSTEMD_NOFILE" ] && [ "$SYSTEMD_NOFILE" != "infinity" ]; then
    if [ "$SYSTEMD_NOFILE" -ge 64000 ] 2>/dev/null; then
      echo "$PASS systemd-LimitNOFILE: $SYSTEMD_NOFILE"
    else
      echo "$WARN systemd-LimitNOFILE: $SYSTEMD_NOFILE (recommended >= 64000)"
      echo "       Fix: Add LimitNOFILE=64000 under [Service] in the mongod systemd unit file"
    fi
  elif [ "$SYSTEMD_NOFILE" = "infinity" ]; then
    echo "$PASS systemd-LimitNOFILE: infinity"
  fi
fi
