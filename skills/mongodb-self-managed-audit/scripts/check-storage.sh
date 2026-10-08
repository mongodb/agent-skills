#!/usr/bin/env bash
# check-storage.sh
# Validates filesystem type, I/O scheduler, readahead, and dbPath configuration
# Usage: bash check-storage.sh [--dbpath /var/lib/mongo]

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"

DBPATH="${MONGO_DBPATH:-}"

# Try to detect dbPath from running mongod
if [ -z "$DBPATH" ]; then
  DBPATH=$(ps -eo args | grep '[m]ongod' | grep -oP -- '--dbpath[ =]\K\S+' | head -1)
fi

# Try mongod.conf
if [ -z "$DBPATH" ]; then
  for conf in /etc/mongod.conf /etc/mongodb.conf /etc/mongod/mongod.conf; do
    if [ -f "$conf" ]; then
      DBPATH=$(grep -E '^\s*dbPath' "$conf" | awk -F': ' '{print $2}' | tr -d ' ' | head -1)
      break
    fi
  done
fi

DBPATH="${DBPATH:-/var/lib/mongo}"
echo "$INFO dbpath: Using $DBPATH"

echo "=== Storage & Filesystem Check ==="

# --- Filesystem type ---
if [ -d "$DBPATH" ]; then
  FS_TYPE=$(df -T "$DBPATH" 2>/dev/null | awk 'NR==2{print $2}')
  echo "$INFO filesystem-type: $FS_TYPE on $DBPATH"
  case "$FS_TYPE" in
    xfs)
      echo "$PASS filesystem-type: XFS is the recommended filesystem for MongoDB WiredTiger"
      ;;
    ext4)
      echo "$PASS filesystem-type: ext4 is supported (XFS preferred for new deployments)"
      ;;
    nfs|nfs4|nfsd)
      echo "$WARN filesystem-type: $FS_TYPE detected. NFS is acceptable with WiredTiger when POSIX.1 compliant, but performance degrades versus local storage."
      NFS_OPTS=$(findmnt -n -o OPTIONS "$DBPATH" 2>/dev/null)
      for opt in bg hard nolock noatime nointr; do
        if echo "$NFS_OPTS" | grep -qw "$opt"; then
          echo "$PASS nfs-mount-$opt: $opt is set"
        else
          echo "$WARN nfs-mount-$opt: $opt missing from the NFS mount options"
          echo "       Fix: mount dbPath with bg hard nolock noatime nointr in /etc/fstab"
        fi
      done
      ;;
    tmpfs|ramfs)
      echo "$WARN filesystem-type: $FS_TYPE detected — data is not persistent across reboots"
      ;;
    *)
      echo "$WARN filesystem-type: $FS_TYPE may not be optimal. MongoDB recommends XFS or ext4."
      ;;
  esac
else
  echo "$WARN dbpath-exists: $DBPATH does not exist or is not accessible"
fi

# --- dbPath permissions ---
if [ -d "$DBPATH" ]; then
  MONGOD_USER=$(ps -eo user,args | grep '[m]ongod' | awk '{print $1}' | head -1)
  MONGOD_USER="${MONGOD_USER:-mongod}"
  if [ -r "$DBPATH" ] && [ -w "$DBPATH" ]; then
    echo "$PASS dbpath-permissions: $DBPATH is readable and writable"
  else
    echo "$FAIL dbpath-permissions: $DBPATH is not readable/writable by current user. Ensure mongod user owns it."
    echo "       Fix: chown -R mongod:mongod $DBPATH"
  fi
fi

# --- Mount options (noatime) ---
if [ -d "$DBPATH" ]; then
  MOUNT_OPTS=$(findmnt -n -o OPTIONS "$DBPATH" 2>/dev/null || grep " $DBPATH " /proc/mounts 2>/dev/null | awk '{print $4}')
  if echo "$MOUNT_OPTS" | grep -q noatime; then
    echo "$PASS mount-noatime: noatime is set on $DBPATH mount"
  else
    echo "$WARN mount-noatime: noatime not found in mount options ($MOUNT_OPTS)"
    echo "       Fix: Add 'noatime' to the filesystem mount options in /etc/fstab and remount"
  fi
fi

# --- Block device for dbPath ---
BLOCK_DEV=$(df "$DBPATH" 2>/dev/null | awk 'NR==2{print $1}' | sed 's/[0-9]*$//')
BLOCK_NAME=$(basename "$BLOCK_DEV" 2>/dev/null)

if [ -n "$BLOCK_NAME" ]; then
  echo "$INFO block-device: $BLOCK_DEV"

  # --- Readahead ---
  RA_VAL=$(blockdev --getra "$BLOCK_DEV" 2>/dev/null)
  if [ -n "$RA_VAL" ]; then
    if [ "$RA_VAL" -ge 8 ] && [ "$RA_VAL" -le 32 ]; then
      echo "$PASS readahead: $RA_VAL sectors (recommended: 8-32 for WiredTiger)"
    elif [ "$RA_VAL" -lt 8 ]; then
      echo "$WARN readahead: $RA_VAL sectors (recommended: 8-32 for WiredTiger)"
      echo "       Fix: blockdev --setra 8 $BLOCK_DEV"
    else
      echo "$WARN readahead: $RA_VAL sectors (recommended: 8-32; higher favors sequential I/O while MongoDB is random)"
      echo "       Fix: blockdev --setra 32 $BLOCK_DEV"
      echo "       Make persistent: add a rule in /etc/udev/rules.d/"
    fi
  fi

  # --- I/O scheduler ---
  SCHED_PATH="/sys/block/$BLOCK_NAME/queue/scheduler"
  ROTATIONAL=$(cat "/sys/block/$BLOCK_NAME/queue/rotational" 2>/dev/null)
  VIRTUAL=0
  if command -v systemd-detect-virt >/dev/null 2>&1 && [ "$(systemd-detect-virt 2>/dev/null)" != "none" ]; then
    VIRTUAL=1
  fi

  if [ -f "$SCHED_PATH" ]; then
    SCHEDULER=$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$SCHED_PATH")
    echo "$INFO io-scheduler: $SCHEDULER on $BLOCK_NAME (rotational=${ROTATIONAL:-unknown}, virtualized=$VIRTUAL)"

    if [ "$VIRTUAL" -eq 1 ] || [ "$ROTATIONAL" = "0" ]; then
      # Virtual or cloud-hosted devices, NVMe, and SSD all want 'none'
      case "$SCHEDULER" in
        none)
          echo "$PASS io-scheduler: none is correct for virtual or solid-state storage" ;;
        kyber)
          echo "$PASS io-scheduler: kyber is acceptable where several workloads share the device" ;;
        *)
          echo "$WARN io-scheduler: $SCHEDULER; virtual and solid-state devices want 'none', or 'kyber' for mixed workloads"
          echo "       Fix: echo none > $SCHED_PATH" ;;
      esac
    elif [ "$ROTATIONAL" = "1" ]; then
      case "$SCHEDULER" in
        mq-deadline)
          echo "$PASS io-scheduler: mq-deadline is correct for spinning disks" ;;
        *)
          echo "$WARN io-scheduler: $SCHEDULER; spinning disks want 'mq-deadline'"
          echo "       Fix: echo mq-deadline > $SCHED_PATH" ;;
      esac
    else
      echo "$WARN io-scheduler: media type undetermined; confirm 'none' for solid-state or 'mq-deadline' for spinning"
    fi
  fi

  # --- RAID level ---
  if command -v mdadm >/dev/null 2>&1 && [ -e /proc/mdstat ] && grep -q '^md' /proc/mdstat 2>/dev/null; then
    RAID_LEVEL=$(grep -o 'raid[0-9]*' /proc/mdstat 2>/dev/null | head -1)
    case "$RAID_LEVEL" in
      raid10)
        echo "$PASS raid-level: $RAID_LEVEL is the recommended level" ;;
      raid5|raid6)
        echo "$WARN raid-level: $RAID_LEVEL does not provide sufficient performance for MongoDB; RAID-10 is recommended" ;;
      *)
        echo "$INFO raid-level: $RAID_LEVEL detected; RAID-10 is the recommended level" ;;
    esac
  fi

  # --- Disk type (rotational) ---
  ROT_PATH="/sys/block/$BLOCK_NAME/queue/rotational"
  if [ -f "$ROT_PATH" ]; then
    ROTATIONAL=$(cat "$ROT_PATH")
    if [ "$ROTATIONAL" = "0" ]; then
      echo "$INFO disk-type: SSD/NVMe (non-rotational)"
    else
      echo "$INFO disk-type: HDD (rotational) — consider SSD for production MongoDB"
    fi
  fi
fi

# --- Storage engine consistency ---
CONF_ENGINE=""
for conf in /etc/mongod.conf /etc/mongodb.conf; do
  if [ -f "$conf" ]; then
    CONF_ENGINE=$(grep -E '^\s*engine' "$conf" | awk -F': ' '{print $2}' | tr -d ' ' | head -1)
    break
  fi
done
CONF_ENGINE="${CONF_ENGINE:-wiredTiger}"
echo "$INFO storage-engine: Configured engine: $CONF_ENGINE"
if [ "$CONF_ENGINE" != "wiredTiger" ]; then
  echo "$WARN storage-engine: $CONF_ENGINE is not WiredTiger. WiredTiger is the recommended storage engine for MongoDB."
fi

# --- Disk space ---
DISK_USE=$(df -h "$DBPATH" 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
DISK_AVAIL=$(df -h "$DBPATH" 2>/dev/null | awk 'NR==2{print $4}')
if [ -n "$DISK_USE" ]; then
  if [ "$DISK_USE" -ge 85 ]; then
    echo "$FAIL disk-space: $DISK_USE% used on $DBPATH ($DISK_AVAIL available) — dangerously full"
  elif [ "$DISK_USE" -ge 70 ]; then
    echo "$WARN disk-space: $DISK_USE% used on $DBPATH ($DISK_AVAIL available)"
  else
    echo "$PASS disk-space: $DISK_USE% used on $DBPATH ($DISK_AVAIL available)"
  fi
fi
