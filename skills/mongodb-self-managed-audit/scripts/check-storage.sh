#!/usr/bin/env bash
# check-storage.sh
# Validates filesystem type, I/O scheduler, readahead, and dbPath configuration
# Usage: bash check-storage.sh [--dbpath /var/lib/mongo]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-conf.sh
. "$SCRIPT_DIR/lib-conf.sh"

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"
UNKNOWN="[UNKNOWN]"

DBPATH="${MONGO_DBPATH:-}"

# Try to detect dbPath from running mongod
if [ -z "$DBPATH" ]; then
  DBPATH=$(ps -eo args | grep '[m]ongod' | grep -oP -- '--dbpath[ =]\K\S+' | head -1)
fi

# Try mongod.conf
conf_detect
if [ -z "$DBPATH" ]; then
  DBPATH=$(conf_get storage.dbPath)
fi

if [ -z "$DBPATH" ]; then
  # Packaged default: /var/lib/mongodb on Debian and Ubuntu, /var/lib/mongo elsewhere.
  DISTRO_ID=$( . /etc/os-release 2>/dev/null; echo "${ID:-}" )
  case "$DISTRO_ID" in
    ubuntu|debian) DBPATH="/var/lib/mongodb" ;;
    *)             DBPATH="/var/lib/mongo" ;;
  esac
  if [ "$CONF_STATE" = "unreadable" ]; then
    echo "$UNKNOWN dbpath-source: $CONF_FILE is not readable, so storage.dbPath is unknown; checking the packaged default $DBPATH. Re-run with sudo or pass --dbpath."
  fi
fi
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
# The question is whether the MongoDB service user can use dbPath, not whether
# the user running the audit can. Resolve the service user from the running
# process, then the mongod systemd unit, then the packaged account (mongod on
# RHEL-family and SUSE, mongodb on Debian and Ubuntu).
service_user() {
  local pid u
  # MONGO_SERVICE_USER names a custom service account explicitly.
  if [ -n "${MONGO_SERVICE_USER:-}" ]; then echo "$MONGO_SERVICE_USER MONGO_SERVICE_USER"; return; fi
  pid=$(pgrep -x mongod 2>/dev/null | head -1)
  if [ -n "$pid" ]; then
    u=$(ps -o user= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$u" ] && { echo "$u running"; return; }
  fi
  u=$(systemctl show -p User --value mongod 2>/dev/null)
  [ -n "$u" ] && { echo "$u systemd"; return; }
  for u in mongod mongodb; do
    id "$u" >/dev/null 2>&1 && { echo "$u account"; return; }
  done
}

# Run test(1) as another user. Needs root; echoes nothing if no tool is usable.
test_as() {
  local user="$1"; shift
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$user" -- test "$@" 2>/dev/null && echo yes || echo no
  elif command -v sudo >/dev/null 2>&1; then
    sudo -n -u "$user" test "$@" 2>/dev/null && echo yes || echo no
  fi
}

if [ -d "$DBPATH" ]; then
  read -r MONGOD_USER USER_SOURCE <<< "$(service_user)"
  OWNER=$(stat -c '%U:%G %a' "$DBPATH" 2>/dev/null)
  if [ -z "$MONGOD_USER" ]; then
    echo "$UNKNOWN dbpath-permissions: the MongoDB service user could not be determined (mongod not running, no mongod unit, no mongod or mongodb account); $DBPATH is ${OWNER:-of unknown ownership}. Re-check after installation."
  else
    MONGOD_GROUP=$(id -gn "$MONGOD_USER" 2>/dev/null || echo "$MONGOD_USER")
    ACCESS=""
    if [ "$(id -un)" = "$MONGOD_USER" ]; then
      if [ -r "$DBPATH" ] && [ -w "$DBPATH" ] && [ -x "$DBPATH" ]; then ACCESS=yes; else ACCESS=no; fi
    elif [ "$(id -u)" -eq 0 ]; then
      ACCESS=$(test_as "$MONGOD_USER" -r "$DBPATH" -a -w "$DBPATH" -a -x "$DBPATH")
    fi
    case "$ACCESS" in
      yes)
        echo "$PASS dbpath-permissions: $DBPATH is readable, writable and traversable by the MongoDB service user $MONGOD_USER (from $USER_SOURCE; owner ${OWNER:-unknown})" ;;
      no)
        echo "$FAIL dbpath-permissions: the MongoDB service user $MONGOD_USER (from $USER_SOURCE) cannot read, write and traverse $DBPATH (owner ${OWNER:-unknown})"
        echo "       Fix: chown -R $MONGOD_USER:$MONGOD_GROUP $DBPATH, and make sure every parent directory is traversable by $MONGOD_USER" ;;
      *)
        echo "$UNKNOWN dbpath-permissions: access for the MongoDB service user $MONGOD_USER (from $USER_SOURCE) cannot be tested from this unprivileged run; $DBPATH is ${OWNER:-of unknown ownership}. Re-run with sudo." ;;
    esac
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
CONF_ENGINE=$(conf_get storage.engine)
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

# Reaching the end means every check in this category ran. run-all-checks.sh
# treats any other exit status as an incomplete category.
exit 0
