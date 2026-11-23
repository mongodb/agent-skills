#!/bin/bash
# Install the same verified Grove validator release used by CI.
set -euo pipefail

# Update the tag and all four SHA-256 pins together when upgrading.
VERSION=v1.8.0-grove.1
if [[ "${1:-}" == --version ]]; then
  printf '%s\n' "$VERSION"
  exit 0
fi
if (( $# > 1 )); then
  printf 'Usage: bash tools/install-skill-validator.sh [install-directory]\n' >&2
  exit 1
fi

install_dir="${1:-$HOME/.local/bin}"
case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) printf 'Unsupported operating system: %s\n' "$(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac
platform="${os}_${arch}"
case "$platform" in
  darwin_amd64) sha256=81cd4f4e026291f1c6b48d3ba8c4b42c47d91db4cf004544a0031a10cecd1d25 ;;
  darwin_arm64) sha256=e2ec3cda9fa74bb7a51811af6ee38b6f477fd0c0ac43bbf5e2c39e6540ca5143 ;;
  linux_amd64) sha256=d55c2146075e63a90ad14d140bac93fd6f08e5368295a3643cc661ec6a8a38e2 ;;
  linux_arm64) sha256=7329b41f927a7bd63dbda6fe4ae6533990ba9f12fe5162ecaf2571d0718c98d0 ;;
esac

if ! command -v gh >/dev/null; then
  printf 'Install the GitHub CLI (gh) to download skill-validator.\n' >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT
archive="skill-validator_${VERSION#v}_${platform}.tar.gz"
gh release download "$VERSION" --repo grove-platform/skill-validator \
  --pattern "$archive" --dir "$tmp_dir"

# Keep the expected hash in this repo, not alongside the downloadable asset.
# Replacing the archive on the release page must not change what we accept.
(
  cd "$tmp_dir"
  if command -v sha256sum >/dev/null; then
    printf '%s  %s\n' "$sha256" "$archive" | sha256sum -c -
  else
    printf '%s  %s\n' "$sha256" "$archive" | shasum -a 256 -c -
  fi
)
tar -xzf "$tmp_dir/$archive" -C "$tmp_dir" skill-validator
mkdir -p "$install_dir"
install -m 0755 "$tmp_dir/skill-validator" "$install_dir/skill-validator"
