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
#   kernel_tcmalloc_status           version-aware verdict: ok|bad_range|ge_619
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
# SERVER-125742 (status as of 2026-08-24). rseq behaviour changes in the Linux
# kernel broke the vendored TCMalloc; kernel 7.0.14+ and 7.1.0+ restore the old
# userspace behaviour, and mongod's own guard was narrowed to match in 8.0.30,
# 8.3.9 and 9.0.
#
#   MongoDB            kernel <6.19   6.19-7.0.13                  7.0.14+/7.1.0+
#   7.0 (all)          ok             ok                           ok
#   8.0.0 - 8.0.20     ok             DO NOT USE: crashes after     ok
#                                     ~60s, potential corruption
#   8.0.21 - 8.0.29    ok             exits during startup         exits during startup
#   8.3.0 - 8.3.8      ok             exits during startup         exits during startup
#   8.0.30+ 8.3.9+ 9.0 ok             exits during startup         ok
#
# Echoes one of:
#   ok              no restriction for this release and kernel
#   do_not_use      data-loss risk: runs, then crashes, may corrupt
#   bad_range       mongod refuses to start, kernel 7.0.14+ clears it
#   ge_619          mongod refuses to start on any kernel >= 6.19; upgrading
#                   the kernel is not a remedy, only a MongoDB upgrade is
# and returns 0 for ok, 1 otherwise, so callers can branch either way.
#
# A target with no patch component cannot be placed in a band, so the caller
# gets the strictest verdict that band could carry. A production gate should
# not infer a fix it cannot see. Resolve the patch version to score precisely.
# Usage: kernel_tcmalloc_status [kernel-string]   (default: uname -r)
kernel_tcmalloc_status() {
  local num p band
  num=$(kernel_version_num "${1:-$(uname -r)}") || { echo "ok"; return 0; }

  # 7.0 is unaffected on every kernel.
  if [ "$MONGO_VERSION" = "7.0" ]; then echo "ok"; return 0; fi

  p="$MONGO_VERSION_PATCH"

  if [ "$MONGO_VERSION" = "8.0" ]; then
    if [ -z "$p" ]; then                 band="unknown"
    elif [ "$p" -le 20 ]; then           band="corrupt"
    elif [ "$p" -le 29 ]; then           band="always"
    else                                 band="bounded"
    fi
  elif [ "$MONGO_VERSION" = "8.3" ]; then
    if [ -z "$p" ]; then                 band="unknown"
    elif [ "$p" -le 8 ]; then            band="always"
    else                                 band="bounded"
    fi
  else
    # 9.0 and later carry the narrowed guard.
    band="bounded"
  fi

  if [ "$num" -lt "$KERNEL_TCMALLOC_LOW" ]; then echo "ok"; return 0; fi

  if [ "$num" -le "$KERNEL_TCMALLOC_HIGH" ]; then
    # Inside 6.19 - 7.0.13: every affected band is blocked here.
    case "$band" in
      corrupt) echo "do_not_use"; return 1 ;;
      *)       echo "bad_range";  return 1 ;;
    esac
  fi

  # Kernel 7.0.14 or later.
  case "$band" in
    always|unknown) echo "ge_619"; return 1 ;;
    *)              echo "ok";     return 0 ;;
  esac
}
