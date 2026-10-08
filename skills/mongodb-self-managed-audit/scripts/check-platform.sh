#!/usr/bin/env bash
# check-platform.sh
# Validates OS and CPU architecture against the MongoDB 7.0/8.0/8.3/9.0 support matrix
# Usage: bash check-platform.sh [--version 7.0|8.0|8.3|9.0]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-version.sh
. "$SCRIPT_DIR/lib-version.sh"
mongo_parse_args "$@" || exit 1

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"

echo "=== Platform & OS Check ==="

# --- OS detection ---
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_NAME="$NAME"
  OS_VERSION="$VERSION_ID"
else
  OS_NAME=$(uname -s)
  OS_VERSION="unknown"
fi

KERNEL=$(uname -r)
ARCH=$(uname -m)

echo "$INFO os: $OS_NAME $OS_VERSION"
echo "$INFO kernel: $KERNEL"
echo "$INFO architecture: $ARCH"

# --- Kernel compatibility check ---
# The verdict depends on the MongoDB maintenance release, so the version-aware
# test lives in lib-version.sh and this script and check-tcmalloc.sh share it.
MONGO_REL="$MONGO_VERSION${MONGO_VERSION_PATCH:+.$MONGO_VERSION_PATCH}"
case "$(kernel_tcmalloc_status "$KERNEL")" in
  do_not_use)
    echo "$FAIL kernel-version: DO NOT USE. MongoDB $MONGO_REL on kernel $KERNEL starts, then crashes after roughly 60 seconds, with potential data corruption. Kernel 6.19 through 7.0.13 is affected. Move to kernel 7.0.14 or later, or to the latest 8.0 maintenance release. (SERVER-125742)"
    ;;
  bad_range)
    echo "$FAIL kernel-version: Kernel $KERNEL is not compliant with MongoDB documented guidance for $MONGO_REL; mongod exits during startup by design. Affected range is 6.19 through 7.0.13. Move to kernel 7.0.14 or later. (SERVER-125742)"
    ;;
  ge_619)
    echo "$FAIL kernel-version: Kernel $KERNEL is not compliant with MongoDB documented guidance for $MONGO_REL; mongod exits during startup on any kernel 6.19 or later, so a kernel upgrade is not a remedy on this release. Move to MongoDB 8.0.30 or later, 8.3.9 or later, or a kernel below 6.19. (SERVER-125742)"
    ;;
  *)
    echo "$PASS kernel-version: $KERNEL is outside the documented kernel restrictions for $MONGO_REL"
    ;;
esac

# --- Architecture check ---
case "$ARCH" in
  x86_64)
    # Check AVX support (required from MongoDB 5.0+)
    if grep -q avx /proc/cpuinfo 2>/dev/null; then
      echo "$PASS cpu-avx: AVX instruction set available"
    else
      echo "$FAIL cpu-avx: AVX instruction set NOT found. MongoDB 5.0+ requires AVX. Check CPU model."
    fi
    CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //')
    echo "$INFO cpu-model: ${CPU_MODEL:-unknown}"
    echo "$INFO cpu-microarch: minimum is Intel Haswell or later Core, Intel Tiger Lake or later Celeron/Pentium, or AMD Bulldozer or later"
    ;;
  aarch64|arm64)
    # Check ARMv8.2-A or later via /proc/cpuinfo features
    if grep -qE 'asimdrdm|asimddp|atomics' /proc/cpuinfo 2>/dev/null; then
      echo "$PASS cpu-arm64: ARMv8.2-A+ features detected"
    else
      echo "$WARN cpu-arm64: Could not confirm ARMv8.2-A. Verify CPU is ARMv8.2-A or later."
    fi
    ;;
  ppc64le)
    echo "$INFO cpu-ppc64le: ppc64le detected. Enterprise only. Legacy TCMalloc used on RHEL8/9 with MongoDB 8.0."
    ;;
  s390x)
    echo "$INFO cpu-s390x: s390x detected. Enterprise only. Legacy TCMalloc used on RHEL8/9 with MongoDB 8.0."
    ;;
  *)
    echo "$WARN cpu-arch: Unrecognized architecture $ARCH. Verify MongoDB support."
    ;;
esac

# --- Minimum kernel version ---
KVER=$(echo "$KERNEL" | grep -oE '^[0-9]+(\.[0-9]+){0,2}' | head -1)
K1=$(echo "$KVER" | cut -d. -f1); K2=$(echo "$KVER" | cut -d. -f2); K3=$(echo "$KVER" | cut -d. -f3)
K1=${K1:-0}; K2=${K2:-0}; K3=${K3:-0}
KNUM=$(( K1 * 1000000 + K2 * 1000 + K3 ))
if [ "$KNUM" -ge 2006036 ]; then
  echo "$PASS kernel-minimum: $KERNEL meets the 2.6.36 minimum"
else
  echo "$FAIL kernel-minimum: $KERNEL is below the 2.6.36 minimum (XFS needs 2.6.25, ext4 needs 2.6.28)"
fi

# --- CPU core count ---
CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null)
if [[ "$CORES" =~ ^[0-9]+$ ]]; then
  if [ "$CORES" -ge 2 ]; then
    echo "$PASS cpu-cores: $CORES cores available (minimum 2 real cores per mongod or mongos)"
  else
    echo "$FAIL cpu-cores: $CORES core detected; each mongod or mongos needs at least 2 real cores"
  fi
fi

# --- Oracle Linux kernel check ---
if echo "$OS_NAME" | grep -qi oracle; then
  KERNEL_TYPE=$(uname -r)
  if echo "$KERNEL_TYPE" | grep -qi uek; then
    echo "$FAIL oracle-kernel: Unbreakable Enterprise Kernel (UEK) detected. MongoDB only supports RHCK on Oracle Linux."
  else
    echo "$PASS oracle-kernel: Red Hat Compatible Kernel (RHCK) in use"
  fi
fi

# --- Supported OS check ---
SUPPORTED=0
for pattern in "Amazon Linux" "Red Hat" "Rocky" "AlmaLinux" "Oracle" "CentOS" "Ubuntu" "Debian" "SLES" "SUSE" "Windows"; do
  if echo "$OS_NAME" | grep -qi "$pattern"; then
    SUPPORTED=1
    break
  fi
done

if [ "$SUPPORTED" -eq 1 ]; then
  echo "$PASS os-supported: $OS_NAME appears to be in the MongoDB supported OS list"
else
  echo "$WARN os-supported: $OS_NAME may not be in the MongoDB supported OS list. Verify at https://www.mongodb.com/docs/manual/administration/production-notes/#platform-support-matrix"
fi

# --- Virtualization info ---
if command -v systemd-detect-virt &>/dev/null; then
  VIRT=$(systemd-detect-virt 2>/dev/null || echo "none")
  echo "$INFO virtualization: $VIRT"
fi
