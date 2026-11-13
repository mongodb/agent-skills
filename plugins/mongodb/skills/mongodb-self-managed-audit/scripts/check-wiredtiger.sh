#!/usr/bin/env bash
# check-wiredtiger.sh
# Validates WiredTiger storage engine configuration

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"
UNKNOWN="[UNKNOWN]"

echo "=== WiredTiger Check ==="

# --- Detect config ---
CONF_FILE=""
for path in /etc/mongod.conf /etc/mongodb.conf /etc/mongod/mongod.conf; do
  if [ -f "$path" ]; then
    CONF_FILE="$path"
    break
  fi
done

# --- RAM available ---
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
TOTAL_RAM_GB=$(echo "scale=1; $TOTAL_RAM_KB / 1024 / 1024" | bc 2>/dev/null || echo "unknown")
echo "$INFO system-ram: ${TOTAL_RAM_GB} GB total RAM"

# Documented default: max(50% of (RAM - 1GB), 0.256GB), bounded at 10000GB
if [[ "$TOTAL_RAM_KB" =~ ^[0-9]+$ ]]; then
  RECOMMENDED_CACHE=$(echo "scale=3; ($TOTAL_RAM_KB / 1024 / 1024 - 1) * 0.5" | bc 2>/dev/null)
  FLOOR_APPLIES=$(echo "$RECOMMENDED_CACHE < 0.256" | bc 2>/dev/null)
  if [ "$FLOOR_APPLIES" = "1" ]; then
    RECOMMENDED_CACHE="0.256"
    echo "$INFO wiredtiger-cache-recommended: ${RECOMMENDED_CACHE} GB (the 0.256GB floor applies on this host)"
  else
    echo "$INFO wiredtiger-cache-recommended: ~${RECOMMENDED_CACHE} GB (default is max(50% of (RAM - 1GB), 0.256GB))"
  fi
fi
DEFAULT_CACHE_GB="${RECOMMENDED_CACHE:-}"

# --- Container memory limit ---
CGROUP_LIMIT=""
for f in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes; do
  if [ -f "$f" ]; then CGROUP_LIMIT=$(cat "$f" 2>/dev/null); break; fi
done
if [ -n "$CGROUP_LIMIT" ] && [ "$CGROUP_LIMIT" != "max" ] && [[ "$CGROUP_LIMIT" =~ ^[0-9]+$ ]]; then
  LIMIT_GB=$(echo "scale=2; $CGROUP_LIMIT / 1024 / 1024 / 1024" | bc 2>/dev/null)
  RAM_GB_INT=$(echo "$TOTAL_RAM_KB / 1024 / 1024" | bc 2>/dev/null)
  LIMIT_LOWER=$(echo "$LIMIT_GB < $RAM_GB_INT" | bc 2>/dev/null)
  if [ "$LIMIT_LOWER" = "1" ]; then
    echo "$WARN wiredtiger-container-limit: a cgroup memory limit of ${LIMIT_GB} GB is below host RAM; set the cache below the container limit"
    echo "       The hostInfo command reports system.memLimitMB for this purpose"
  fi
fi

# --- cacheSizeGB from config ---
# Documented rule: avoid increasing the cache above its default (v7.0
# Configuration File Options). An unset value is the default, so it passes.
# Decimal GB values are compared with bc; one status is emitted per check.
if [ -n "$CONF_FILE" ]; then
  CACHE_SIZE=$(grep -E 'cacheSizeGB' "$CONF_FILE" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' ' | head -1)
  if [ -n "$CACHE_SIZE" ]; then
    ABOVE_DEFAULT=$(echo "$CACHE_SIZE > ${DEFAULT_CACHE_GB:-0}" | bc 2>/dev/null)
    if [ -z "$DEFAULT_CACHE_GB" ] || [ -z "$ABOVE_DEFAULT" ]; then
      echo "$UNKNOWN wiredtiger-cachesize: cacheSizeGB=$CACHE_SIZE configured; could not compare it with the default (RAM or value not readable)"
    elif [ "$ABOVE_DEFAULT" = "1" ]; then
      echo "$WARN wiredtiger-cachesize: cacheSizeGB=${CACHE_SIZE} is above the default of ~${DEFAULT_CACHE_GB} GB; MongoDB documents avoiding an increase above the default"
      echo "       Fix: lower storage.wiredTiger.engineConfig.cacheSizeGB in $CONF_FILE, or remove it to use the default"
    else
      echo "$PASS wiredtiger-cachesize: cacheSizeGB=$CACHE_SIZE is at or below the default of ~${DEFAULT_CACHE_GB} GB"
    fi
  elif ! grep -qE 'cacheSizePct' "$CONF_FILE" 2>/dev/null; then
    echo "$PASS wiredtiger-cachesize: cacheSizeGB and cacheSizePct not set; the default of max(50% of (RAM - 1GB), 0.256GB) applies"
  fi

  # --- cacheSizePct, mutually exclusive with cacheSizeGB ---
  CACHE_PCT=$(grep -E 'cacheSizePct' "$CONF_FILE" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' ' | head -1)
  if [ -n "$CACHE_PCT" ] && [ -n "$CACHE_SIZE" ]; then
    echo "$FAIL wiredtiger-cache-exclusive: cacheSizeGB and cacheSizePct are both set; only one may be specified"
    echo "       Fix: remove one of them from $CONF_FILE"
  elif [ -n "$CACHE_PCT" ]; then
    PCT_INT=$(echo "$CACHE_PCT" | cut -d. -f1)
    if [[ "$PCT_INT" =~ ^[0-9]+$ ]] && [ "$PCT_INT" -gt 80 ]; then
      echo "$FAIL wiredtiger-cachesizepct: cacheSizePct=$CACHE_PCT exceeds the documented maximum of 80"
      echo "       Fix: set cacheSizePct to 80 or lower in $CONF_FILE"
    else
      PCT_GB=$(echo "scale=3; $CACHE_PCT * $TOTAL_RAM_KB / 1024 / 1024 / 100" | bc 2>/dev/null)
      PCT_ABOVE=$(echo "$PCT_GB > ${DEFAULT_CACHE_GB:-0}" | bc 2>/dev/null)
      if [ -n "$DEFAULT_CACHE_GB" ] && [ "$PCT_ABOVE" = "1" ]; then
        echo "$WARN wiredtiger-cachesizepct: cacheSizePct=$CACHE_PCT is about ${PCT_GB} GB, above the default of ~${DEFAULT_CACHE_GB} GB; MongoDB documents avoiding an increase above the default (maximum is 80)"
      else
        echo "$PASS wiredtiger-cachesizepct: cacheSizePct=$CACHE_PCT (maximum is 80)"
      fi
    fi
  fi

  # --- Block compressor ---
  COMPRESSOR=$(grep -E 'blockCompressor' "$CONF_FILE" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' ' | head -1)
  case "${COMPRESSOR:-snappy}" in
    snappy) echo "$INFO wiredtiger-compressor: ${COMPRESSOR:-snappy (default)} — lower compression at lower CPU cost" ;;
    zstd)   echo "$INFO wiredtiger-compressor: zstd — best compression at lower CPU cost than zlib" ;;
    zlib)   echo "$INFO wiredtiger-compressor: zlib — better compression at higher CPU cost" ;;
    *)      echo "$WARN wiredtiger-compressor: $COMPRESSOR is not one of snappy, zlib, or zstd" ;;
  esac

  # --- Compression ---
  COMPRESS=$(grep -E 'blockCompressor' "$CONF_FILE" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' ' | head -1)
  COMPRESS="${COMPRESS:-snappy}"
  echo "$INFO wiredtiger-compression: blockCompressor=$COMPRESS"
  case "$COMPRESS" in
    snappy)
      echo "$INFO wiredtiger-compression: snappy is the default — good balance of CPU and compression ratio"
      ;;
    zstd)
      echo "$PASS wiredtiger-compression: zstd provides better compression ratio (available MongoDB 4.2+)"
      ;;
    zlib)
      echo "$INFO wiredtiger-compression: zlib provides higher compression at higher CPU cost"
      ;;
    none)
      echo "$WARN wiredtiger-compression: Compression is disabled — consider snappy or zstd for storage efficiency"
      ;;
  esac
fi

# --- Check WiredTiger stats from mongod if running ---
MONGOD_PID=$(pgrep -x mongod | head -1)
if [ -n "$MONGOD_PID" ]; then
  echo "$INFO mongod-pid: $MONGOD_PID"
  # Check mongod open files for WT
  WT_FILES=$(ls /proc/"$MONGOD_PID"/fd 2>/dev/null | wc -l)
  echo "$INFO mongod-open-fds: $WT_FILES file descriptors open"
  if [ "$WT_FILES" -gt 50000 ] 2>/dev/null; then
    echo "$WARN mongod-open-fds: $WT_FILES open FDs — verify ulimits are sufficient"
  fi
fi

# --- Checkpoint interval ---
CHECKPOINT=$(grep -E 'checkpointDelaySecs\|checkpoint' "$CONF_FILE" 2>/dev/null | grep -v '#' | head -3)
if [ -n "$CHECKPOINT" ]; then
  echo "$INFO wiredtiger-checkpoint: $CHECKPOINT"
else
  echo "$INFO wiredtiger-checkpoint: Using default 60-second checkpoint interval"
fi
