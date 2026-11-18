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
# MONGO_OS_RELEASE is a test seam only; never set it on a real audit.
OS_RELEASE_FILE="${MONGO_OS_RELEASE:-/etc/os-release}"
OS_ID=""
if [ -r "$OS_RELEASE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$OS_RELEASE_FILE"
  OS_NAME="$NAME"
  OS_VERSION="$VERSION_ID"
  OS_ID="$ID"
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
    case "$KERNEL" in
      7.0.0-*) echo "       Note: on Ubuntu a 7.0.0-NNN label can carry the rseq fix; /proc/version_signature shows the upstream version. If it reads 7.0.14 or later, re-run where it is readable or score it with MONGO_KERNEL_SIGNATURE." ;;
    esac
    ;;
  bad_range)
    echo "$FAIL kernel-version: Kernel $KERNEL is not compliant with MongoDB documented guidance for $MONGO_REL; mongod exits during startup by design. Affected range is 6.19 through 7.0.13. Move to kernel 7.0.14 or later. (SERVER-125742)"
    case "$KERNEL" in
      7.0.0-*) echo "       Note: on Ubuntu a 7.0.0-NNN label can carry the rseq fix; /proc/version_signature shows the upstream version. If it reads 7.0.14 or later, re-run where it is readable or score it with MONGO_KERNEL_SIGNATURE." ;;
    esac
    ;;
  ge_619)
    echo "$FAIL kernel-version: Kernel $KERNEL is not compliant with MongoDB documented guidance for $MONGO_REL; mongod exits during startup on any kernel 6.19 or later, including 7.0.14 and above, so a kernel upgrade alone is not a remedy on this release. Either run a kernel below 6.19, or upgrade MongoDB to 8.0.30 or later or 8.3.9 or later (8.0.35 or later, 8.3.14 or later on Ubuntu) and run it on kernel 7.0.14 or later. (SERVER-125742)"
    ;;
  ubuntu_needs_upgrade)
    echo "$FAIL kernel-version: Kernel $KERNEL is Ubuntu's label for a kernel that carries the rseq fix, but mongod $MONGO_REL compares the version literally and exits during startup. Fixed in MongoDB 8.0.35 and 8.3.14 (SERVER-131779). Upgrading the Ubuntu kernel package does not help while it keeps the 7.0.0 label; a kernel labelled 7.0.14 or later would also clear the guard. (SERVER-125742)"
    ;;
  *)
    echo "$PASS kernel-version: $KERNEL is outside the documented kernel restrictions for $MONGO_REL"
    KERNEL_OK=1
    ;;
esac
if [ -z "${KERNEL_OK:-}" ] && [ -z "$MONGO_VERSION_PATCH" ] && [ "$MONGO_VERSION" != "7.0" ]; then
  echo "       Note: no patch version was supplied, so the strictest band for $MONGO_VERSION was applied. Re-run with the full version that mongod --version reports for the exact verdict; on 8.0.0 through 8.0.20 this kernel range also carries a data-corruption risk."
fi

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
    echo "$INFO cpu-ppc64le: ppc64le detected. Enterprise only. Legacy TCMalloc used with MongoDB 8.0 and later regardless of OS version; disable THP."
    ;;
  s390x)
    echo "$INFO cpu-s390x: s390x detected. Enterprise only. Legacy TCMalloc used with MongoDB 8.0 and later regardless of OS version; disable THP."
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
# Version-specific: the Enterprise matrix lists each OS release and
# architecture per MongoDB series, so a recognized distro name is not enough.
UNKNOWN="[UNKNOWN]"
MATRIX_URL="https://www.mongodb.com/docs/enterprise-platform-support/"
PLATFORM_LABEL="$OS_NAME $OS_VERSION ($ARCH)"
{ read -r OS_STATUS; read -r OS_MIN; } < <(platform_support_status "$OS_ID" "$OS_VERSION" "$ARCH")
case "$OS_STATUS" in
  supported)
    echo "$PASS os-supported: $PLATFORM_LABEL is listed for MongoDB Enterprise $MONGO_REL (support matrix as read $MONGO_PLATFORM_MATRIX_READ)" ;;
  unsupported)
    if [ -n "${OS_MIN:-}" ]; then
      echo "$FAIL os-supported: $PLATFORM_LABEL is listed for MongoDB Enterprise only from $OS_MIN; $MONGO_REL is not supported on it"
      echo "       Fix: upgrade MongoDB to $OS_MIN or later, or move to a platform listed for $MONGO_REL. See $MATRIX_URL"
    else
      echo "$FAIL os-supported: $PLATFORM_LABEL is not supported for MongoDB Enterprise $MONGO_VERSION (support matrix as read $MONGO_PLATFORM_MATRIX_READ)"
      echo "       Fix: move to a platform listed for $MONGO_VERSION, or to a MongoDB release listed for this platform. See $MATRIX_URL"
    fi ;;
  needs_patch)
    echo "$UNKNOWN os-supported: $PLATFORM_LABEL is listed for MongoDB Enterprise only from $OS_MIN; no patch version was supplied, so support for $MONGO_REL cannot be confirmed. Re-run with the full version." ;;
  unlisted_release)
    echo "$WARN os-supported: $OS_NAME is a MongoDB platform, but release $OS_VERSION on $ARCH has no row in the Enterprise support matrix as read $MONGO_PLATFORM_MATRIX_READ"
    echo "       Fix: confirm the release at $MATRIX_URL, or move to a listed release" ;;
  unlisted_distro)
    echo "$WARN os-supported: $OS_NAME is not in the MongoDB Enterprise support matrix. Verify at $MATRIX_URL" ;;
  *)
    echo "$UNKNOWN os-supported: OS release or MongoDB version not resolved (os=${OS_ID:-unknown} ${OS_VERSION:-unknown}, mongodb=$MONGO_VERSION); support could not be checked" ;;
esac

# --- Virtualization info ---
if command -v systemd-detect-virt &>/dev/null; then
  VIRT=$(systemd-detect-virt 2>/dev/null || echo "none")
  echo "$INFO virtualization: $VIRT"
fi

# Reaching the end means every check in this category ran. run-all-checks.sh
# treats any other exit status as an incomplete category.
exit 0
