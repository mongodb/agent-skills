#!/usr/bin/env bash
# lib-version.sh
# Shared version handling for the self-managed production checks.
# Sourced, never executed. Dependency-free bash: no awk, sed, grep or cut.
#
# Provides:
#   mongo_parse_args "$@"            parse --version / --dbpath, error on anything else
#   mongo_normalize_version [value]  canonicalise to major.minor from the accepted set
#   mongo_version_at_least MAJ MIN   compare the resolved version against a floor
#   kernel_in_bad_tcmalloc_range     the documented 6.19.0 - 7.0.13 kernel range test
#   kernel_tcmalloc_status           version-aware verdict:
#                                    ok|do_not_use|bad_range|ge_619|ubuntu_needs_upgrade
#   platform_support_status          Enterprise support matrix verdict for an
#                                    OS release and architecture
#
# Exports MONGO_VERSION (e.g. 8.3, or "unknown"), MONGO_VERSION_MAJOR,
# MONGO_VERSION_MINOR and MONGO_VERSION_NUM (major*1000+minor).
# MONGO_VERSION_PATCH holds the patch component when the caller supplied one
# (e.g. 4 from 8.0.4) and is empty when only major.minor was given. The patch
# matters because the kernel rule below narrows at 8.0.30, so a bare "8.0"
# cannot be scored against the narrower rule.

# Versions this checklist has expected values for.
MONGO_SUPPORTED_VERSIONS="7.0 8.0 8.3 9.0"

MONGO_VERSION="${MONGO_VERSION:-unknown}"
MONGO_VERSION_MAJOR=""
MONGO_VERSION_MINOR=""
MONGO_VERSION_PATCH=""
MONGO_VERSION_NUM=0

# Canonicalise $1 (default: current MONGO_VERSION) to major.minor.
#   7 -> 7.0   8 -> 8.0   8.0.4 -> 8.0   8.3 -> 8.3   8.3.1 -> 8.3
# Anything outside the accepted set sets MONGO_VERSION=unknown and returns 1.
mongo_normalize_version() {
  local raw="${1:-$MONGO_VERSION}"
  local major minor patch rest v found

  MONGO_VERSION="unknown"
  MONGO_VERSION_MAJOR=""
  MONGO_VERSION_MINOR=""
  MONGO_VERSION_PATCH=""
  MONGO_VERSION_NUM=0

  # major[.minor[.patch]] with digits only; the patch component is discarded
  case "$raw" in
    *[!0-9.]*|""|.*|*.) return 1 ;;
  esac

  major="${raw%%.*}"
  patch=""
  rest="${raw#*.}"
  if [ "$rest" = "$raw" ]; then
    minor="0"                      # bare major, e.g. "8"
  else
    minor="${rest%%.*}"
    if [ "${rest#*.}" != "$rest" ]; then
      rest="${rest#*.}"
      # a fourth component is not a version we understand
      case "$rest" in
        *.*) return 1 ;;
      esac
      patch="$rest"                # keep it: the kernel rule narrows at 8.0.30
    fi
  fi

  [ -n "$major" ] && [ -n "$minor" ] || return 1
  # strip leading zeros so 08 and 8 compare the same
  major=$((10#$major)) || return 1
  minor=$((10#$minor)) || return 1

  found=0
  for v in $MONGO_SUPPORTED_VERSIONS; do
    if [ "$major.$minor" = "$v" ]; then found=1; break; fi
  done
  [ "$found" -eq 1 ] || return 1

  MONGO_VERSION="$major.$minor"
  MONGO_VERSION_MAJOR="$major"
  MONGO_VERSION_MINOR="$minor"
  MONGO_VERSION_NUM=$(( major * 1000 + minor ))
  if [ -n "$patch" ]; then
    case "$patch" in
      *[!0-9]*) return 1 ;;
    esac
    MONGO_VERSION_PATCH=$((10#$patch))
  fi
  export MONGO_VERSION MONGO_VERSION_MAJOR MONGO_VERSION_MINOR \
         MONGO_VERSION_PATCH MONGO_VERSION_NUM
  return 0
}

# True when the resolved version is >= the given major.minor.
# Always false when the version is unknown, so an unresolved version never
# silently takes the 8.0-and-later path.
mongo_version_at_least() {
  local want_major="$1" want_minor="${2:-0}"
  [ "$MONGO_VERSION" != "unknown" ] || return 1
  [ "$MONGO_VERSION_NUM" -ge $(( want_major * 1000 + want_minor )) ]
}

# Parse the common CLI. Errors on a missing value or an unrecognised flag;
# there is no positional fallback, so a stray flag can never become the version.
# Sets MONGO_VERSION via mongo_normalize_version and MONGO_DBPATH/DBPATH.
mongo_parse_args() {
  local raw_version="" have_version=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --version)
        if [ $# -lt 2 ]; then
          echo "error: --version requires a value ($MONGO_SUPPORTED_VERSIONS)" >&2
          return 2
        fi
        raw_version="$2"; have_version=1; shift 2 ;;
      --dbpath)
        if [ $# -lt 2 ]; then
          echo "error: --dbpath requires a value" >&2
          return 2
        fi
        DBPATH="$2"; MONGO_DBPATH="$2"; export MONGO_DBPATH; shift 2 ;;
      *)
        echo "error: unrecognized argument '$1'" >&2
        return 2 ;;
    esac
  done

  if [ "$have_version" -eq 1 ]; then
    if ! mongo_normalize_version "$raw_version"; then
      echo "error: unsupported --version '$raw_version'" >&2
      return 1
    fi
  else
    mongo_normalize_version "$MONGO_VERSION" || true
  fi
  return 0
}

# Parse a kernel string to a comparable integer (maj*1e6 + min*1e3 + patch).
# Echoes the number, or returns 1 when the string has no numeric leading triple.
# Usage: kernel_version_num [kernel-string]   (default: uname -r)
kernel_version_num() {
  local kernel="${1:-$(uname -r)}"
  local triple maj min pat rest rest2

  # keep the leading numeric major[.minor[.patch]], drop any -suffix
  triple="${kernel%%-*}"
  triple="${triple%%[!0-9.]*}"
  maj="${triple%%.*}"
  rest="${triple#*.}"
  if [ "$rest" = "$triple" ]; then min=0; pat=0; else
    min="${rest%%.*}"
    rest2="${rest#*.}"
    if [ "$rest2" = "$rest" ]; then pat=0; else pat="${rest2%%.*}"; fi
  fi
  maj=${maj:-0}; min=${min:-0}; pat=${pat:-0}
  case "$maj$min$pat" in
    *[!0-9]*|"") return 1 ;;
  esac

  echo $(( 10#$maj * 1000000 + 10#$min * 1000 + 10#$pat ))
}

KERNEL_TCMALLOC_LOW=$((  6 * 1000000 + 19 * 1000 + 0  ))   # 6.19.0
KERNEL_TCMALLOC_HIGH=$(( 7 * 1000000 +  0 * 1000 + 13 ))   # 7.0.13

# The documented incompatibility range: 6.19.0 through 7.0.13 inclusive crash
# mongod on startup (TCMalloc). 7.0.14 or later clears this range. Single
# implementation so check-platform.sh and check-tcmalloc.sh cannot disagree.
# Usage: kernel_in_bad_tcmalloc_range [kernel-string]   (default: uname -r)
kernel_in_bad_tcmalloc_range() {
  local num
  num=$(kernel_version_num "${1:-$(uname -r)}") || return 1
  [ "$num" -ge "$KERNEL_TCMALLOC_LOW" ] && [ "$num" -le "$KERNEL_TCMALLOC_HIGH" ]
}

# Version-aware kernel verdict, implementing the compatibility matrix in
# SERVER-125742 (as read 2026-10-21). rseq behaviour changes in the Linux
# kernel broke the vendored TCMalloc; kernel 7.0.14+ and 7.1.0+ restore the old
# userspace behaviour, and mongod's own guard was narrowed to match in 8.0.30,
# 8.3.9 and 9.0. Ubuntu reports its kernel as 7.0.0-NNN even when it carries the
# fix, so the numeric guard stays tripped there until the Ubuntu-aware guard
# (SERVER-131779) in 8.0.35 and 8.3.14.
#
#   MongoDB            kernel <6.19   6.19-7.0.13                  7.0.14+/7.1.0+
#   7.0 (all)          ok             ok                           ok
#   8.0.0 - 8.0.20     ok             DO NOT USE: crashes after     ok
#                                     ~60s, potential corruption
#   8.0.21 - 8.0.29    ok             exits during startup         exits during startup
#   8.3.0 - 8.3.8      ok             exits during startup         exits during startup
#   8.0.30-34, 8.3.9-13 ok            exits during startup         ok, except Ubuntu
#                                                                  kernels labelled 7.0.0
#   8.0.35+ 8.3.14+ 9.0 ok            exits during startup         ok
#
# Echoes one of:
#   ok                  no restriction for this release and kernel
#   do_not_use          data-loss risk: runs, then crashes, may corrupt
#   bad_range           mongod refuses to start, kernel 7.0.14+ clears it
#   ge_619              mongod refuses to start on any kernel >= 6.19, in the
#                       6.19 - 7.0.13 range and above it; upgrading the kernel
#                       is not a remedy. Either run a kernel below 6.19, or
#                       upgrade MongoDB (8.0.30+ / 8.3.9+) and run 7.0.14+.
#                       Also returned for an unresolved 8.0 or 8.3 patch.
#   ubuntu_needs_upgrade  Ubuntu kernel labelled 7.0.0-NNN on a release that
#                       predates the Ubuntu-aware guard; only a MongoDB upgrade
#                       to 8.0.35+ or 8.3.14+ clears it
# and returns 0 for ok, 1 otherwise, so callers can branch either way.
#
# The distro comes from the second argument, then MONGO_DISTRO, then the ID in
# /etc/os-release. A 7.0.0-NNN label on Ubuntu counts as the fixed kernel only
# when the upstream version Ubuntu records in /proc/version_signature (third
# argument, then MONGO_KERNEL_SIGNATURE) is 7.0.14 or later; "none" means no
# signature. Without that evidence the label is scored literally, so an
# unpatched Ubuntu kernel keeps its strict verdict. Release dates for 8.0.35
# and 8.3.14 are not stated here.
#
# A target with no patch component cannot be placed in a band, so the caller
# gets the strictest verdict that band could carry. A production gate should
# not infer a fix it cannot see. Resolve the patch version to score precisely.
# Usage: kernel_tcmalloc_status [kernel-string] [distro-id] [upstream-version]
kernel_distro_id() {
  local ID=""
  if [ -n "${1:-}" ]; then echo "$1"; return 0; fi
  if [ -n "${MONGO_DISTRO:-}" ]; then echo "$MONGO_DISTRO"; return 0; fi
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    ID=$( . /etc/os-release 2>/dev/null; echo "${ID:-}" )
  fi
  echo "$ID"
}

# Upstream kernel version Ubuntu records as the last field of
# /proc/version_signature, e.g. "Ubuntu 7.0.0-1011.11~24.04.1-gcp 7.0.14".
# Echoes nothing when the file is absent or the caller passed "none".
kernel_upstream_signature() {
  local sig="${1:-${MONGO_KERNEL_SIGNATURE:-}}" line
  if [ "$sig" = "none" ]; then return 0; fi
  if [ -n "$sig" ]; then echo "$sig"; return 0; fi
  if [ -r /proc/version_signature ]; then
    read -r line < /proc/version_signature || true
    echo "${line##* }"
  fi
}

kernel_tcmalloc_status() {
  local num p band distro upstream upstream_num ubuntu_label=0
  num=$(kernel_version_num "${1:-$(uname -r)}") || { echo "ok"; return 0; }
  distro=$(kernel_distro_id "${2:-}")

  # 7.0 is unaffected on every kernel.
  if [ "$MONGO_VERSION" = "7.0" ]; then echo "ok"; return 0; fi

  # Ubuntu labels a kernel carrying the rseq fix as 7.0.0-NNN. Score it as the
  # fixed kernel only when /proc/version_signature shows upstream 7.0.14 or
  # later, and let the release band decide whether mongod's guard recognises
  # that label.
  if [ "$distro" = "ubuntu" ] && [ "$num" -eq $(( 7 * 1000000 )) ]; then
    upstream=$(kernel_upstream_signature "${3:-}")
    if [ -n "$upstream" ] && upstream_num=$(kernel_version_num "$upstream") \
       && [ "$upstream_num" -gt "$KERNEL_TCMALLOC_HIGH" ]; then
      ubuntu_label=1
      num="$upstream_num"
    fi
  fi

  p="$MONGO_VERSION_PATCH"

  if [ "$MONGO_VERSION" = "8.0" ]; then
    if [ -z "$p" ]; then                 band="unknown"
    elif [ "$p" -le 20 ]; then           band="corrupt"
    elif [ "$p" -le 29 ]; then           band="always"
    elif [ "$p" -le 34 ]; then           band="bounded"
    else                                 band="full"
    fi
  elif [ "$MONGO_VERSION" = "8.3" ]; then
    if [ -z "$p" ]; then                 band="unknown"
    elif [ "$p" -le 8 ]; then            band="always"
    elif [ "$p" -le 13 ]; then           band="bounded"
    else                                 band="full"
    fi
  else
    # 9.0 and later carry the narrowed, Ubuntu-aware guard.
    band="full"
  fi

  if [ "$num" -lt "$KERNEL_TCMALLOC_LOW" ]; then echo "ok"; return 0; fi

  if [ "$num" -le "$KERNEL_TCMALLOC_HIGH" ]; then
    # Inside 6.19 - 7.0.13: every affected band is blocked here. Only the
    # narrowed-guard bands are cleared by moving to kernel 7.0.14+; the
    # "always" band exits there too, so its remedy is a MongoDB upgrade. An
    # unresolved patch takes the strictest remedy for the same reason.
    case "$band" in
      corrupt)        echo "do_not_use"; return 1 ;;
      always|unknown) echo "ge_619";     return 1 ;;
      *)              echo "bad_range";  return 1 ;;
    esac
  fi

  # Kernel 7.0.14 or later.
  case "$band" in
    always|unknown) echo "ge_619"; return 1 ;;
    bounded)
      if [ "$ubuntu_label" -eq 1 ]; then echo "ubuntu_needs_upgrade"; return 1; fi
      echo "ok"; return 0 ;;
    *) echo "ok"; return 0 ;;
  esac
}

# --- Enterprise platform support matrix ---------------------------------------
# Transcribed from "Supported Platforms for MongoDB Enterprise", Linux table
# (https://www.mongodb.com/docs/enterprise-platform-support/), read 2026-11-18.
# One row per platform and architecture; the three cells are the 9.x, 8.x and
# 7.x columns. Y = supported, - = not supported, a version such as 8.0.7 = that
# release or later within the series. The page applies the matrix to the OS
# version present at install time. Re-read the page before changing a row.
#
#   family  release  arch     9.x    8.x    7.x
MONGO_PLATFORM_MATRIX="
amzn    2023     x86_64   Y      Y      Y
amzn    2023     arm64    Y      Y      Y
amzn    2        x86_64   -      -      Y
amzn    2        arm64    -      -      Y
debian  13       x86_64   Y      -      -
debian  12       x86_64   Y      Y      Y
debian  11       x86_64   -      -      Y
rhel    10       x86_64   Y      Y      Y
rhel    10       arm64    Y      Y      Y
rhel    10       ppc64le  Y      -      -
rhel    10       s390x    Y      -      -
rhel    9        x86_64   Y      Y      Y
rhel    9        arm64    Y      Y      Y
rhel    9        ppc64le  Y      8.0.7  -
rhel    9        s390x    Y      8.0.7  7.0.20
rhel    8        x86_64   Y      Y      Y
rhel    8        arm64    Y      Y      Y
rhel    8        ppc64le  Y      Y      Y
rhel    8        s390x    Y      Y      Y
rhel    7        x86_64   -      -      Y
ol      10       x86_64   Y      Y      Y
ol      9        x86_64   Y      Y      Y
ol      8        x86_64   Y      Y      Y
ol      7        x86_64   -      -      Y
sles    16       x86_64   Y      -      -
sles    15       x86_64   Y      Y      Y
sles    12       x86_64   -      -      Y
ubuntu  26.04    x86_64   9.0.4  -      -
ubuntu  26.04    arm64    9.0.4  -      -
ubuntu  24.04    x86_64   Y      Y      -
ubuntu  24.04    arm64    Y      Y      -
ubuntu  22.04    x86_64   Y      Y      Y
ubuntu  22.04    arm64    Y      Y      Y
ubuntu  20.04    x86_64   -      Y      Y
ubuntu  20.04    arm64    -      Y      Y
"
MONGO_PLATFORM_MATRIX_READ="2026-11-18"

# Map an os-release ID and VERSION_ID to the matrix family and release.
# Rocky and AlmaLinux are listed with RHEL on the page; Oracle Linux only on
# x86_64. Echoes "family release", or nothing for a distro the page omits.
platform_family_release() {
  local id="$1" ver="$2"
  case "$id" in
    rhel|rocky|almalinux) echo "rhel ${ver%%.*}" ;;
    ol)                   echo "ol ${ver%%.*}" ;;
    amzn)                 echo "amzn ${ver%%.*}" ;;
    debian)               echo "debian ${ver%%.*}" ;;
    sles|sled)            echo "sles ${ver%%.*}" ;;
    ubuntu)               echo "ubuntu $ver" ;;
    *)                    echo "" ;;
  esac
}

# platform_support_status <os-id> <version-id> <arch>
# Uses the resolved MONGO_VERSION and MONGO_VERSION_PATCH. Echoes one of:
#   supported        listed for this series (and patch minimum met)
#   unsupported      the platform row exists but not for this release
#   needs_patch      listed only from a minimum patch the run cannot confirm
#   unlisted_release a known distro, but this release or arch has no row
#   unlisted_distro  the distro is not on the page
#   unknown          MongoDB version or OS release not resolved
# A second line carries the minimum version when one applies.
platform_support_status() {
  local id="$1" ver="$2" arch="$3" fr family release col cell
  local r_family r_release r_arch c9 c8 c7 min_maj min_min min_pat rest

  case "$arch" in aarch64) arch="arm64" ;; esac
  if [ "$MONGO_VERSION" = "unknown" ] || [ -z "$id" ] || [ -z "$ver" ]; then
    echo "unknown"; return 0
  fi
  fr=$(platform_family_release "$id" "$ver")
  if [ -z "$fr" ]; then echo "unlisted_distro"; return 0; fi
  family="${fr% *}"; release="${fr#* }"

  case "$MONGO_VERSION_MAJOR" in
    9) col=1 ;; 8) col=2 ;; 7) col=3 ;; *) echo "unknown"; return 0 ;;
  esac

  cell=""
  while read -r r_family r_release r_arch c9 c8 c7; do
    [ -n "$r_family" ] || continue
    if [ "$r_family" = "$family" ] && [ "$r_release" = "$release" ] && [ "$r_arch" = "$arch" ]; then
      case "$col" in 1) cell="$c9" ;; 2) cell="$c8" ;; 3) cell="$c7" ;; esac
      break
    fi
  done <<< "$MONGO_PLATFORM_MATRIX"

  case "$cell" in
    "")  echo "unlisted_release" ;;
    Y)   echo "supported" ;;
    -)   echo "unsupported" ;;
    *)
      min_maj="${cell%%.*}"; rest="${cell#*.}"; min_min="${rest%%.*}"; min_pat="${rest#*.}"
      if [ "$MONGO_VERSION_NUM" -gt $(( min_maj * 1000 + min_min )) ]; then
        echo "supported"
      elif [ "$MONGO_VERSION_NUM" -lt $(( min_maj * 1000 + min_min )) ]; then
        echo "unsupported"; echo "$cell"
      elif [ -z "$MONGO_VERSION_PATCH" ]; then
        echo "needs_patch"; echo "$cell"
      elif [ "$MONGO_VERSION_PATCH" -ge "$min_pat" ]; then
        echo "supported"
      else
        echo "unsupported"; echo "$cell"
      fi
      ;;
  esac
}
