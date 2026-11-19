#!/usr/bin/env bash
# Usage: create-ephemeral.sh [--replace] <env-file> <var-name> [cluster-name]
#
# Creates an Ephemeral Atlas cluster and writes its connection string to
# <env-file> as <var-name>="...", with a marker comment above it:
#   # ephemeral-cluster: var=<var-name> claimUrl=<url> expiresAt=<time>
# Prints only clusterId, claimUrl, status, and expiresAt. The connection string
# is never printed and never written anywhere but <env-file>.
#
# --replace  remove existing <var-name> entries (and their marker comment)
#            after the cluster is created, instead of refusing with exit 3.
#
# Exit codes:
#   0  created and written
#   1  no 201 received: an error response or a network failure. Prints the
#      HTTP status (or curl error), the API's errorCode/detail, and any
#      retry-after header. After a network failure the request may still have
#      reached the server.
#   2  nothing sent: bad arguments, jq missing, or <env-file> not writable
#   3  nothing sent: <var-name> is already set in <env-file> (use --replace)
#   4  the cluster WAS created, but the connection string couldn't be saved.
#      Prints clusterId and claimUrl; the password is lost, so claim the
#      cluster and set a new database user password in Atlas.
set -euo pipefail

replace=0
if [ "${1:-}" = --replace ]; then replace=1; shift; fi
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "usage: create-ephemeral.sh [--replace] <env-file> <var-name> [cluster-name]" >&2
  exit 2
fi
env_file=$1 var=$2 name=${3:-}

command -v jq >/dev/null || { echo "jq is required: install it, then rerun" >&2; exit 2; }
[[ $var =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "invalid variable name: $var" >&2; exit 2; }

env_dir=$(dirname "$env_file")
if [ -e "$env_file" ]; then
  [ -f "$env_file" ] && [ -w "$env_file" ] || { echo "$env_file is not a writable file" >&2; exit 2; }
else
  [ -d "$env_dir" ] && [ -w "$env_dir" ] || { echo "can't create $env_file: $env_dir is not a writable directory" >&2; exit 2; }
fi
if [ "$replace" = 1 ]; then
  [ -w "$env_dir" ] || { echo "--replace needs $env_dir to be writable" >&2; exit 2; }
fi

# Matches VAR=..., export VAR=..., and VAR = ... (python-dotenv allows spaces).
entry_re="^[[:space:]]*(export[[:space:]]+)?$var[[:space:]]*="
marker_re="^# ephemeral-cluster: var=$var( |$)"

# Check before creating, so a rate-limited create isn't spent on a name conflict.
if [ "$replace" = 0 ] && [ -f "$env_file" ] && grep -qE "$entry_re" "$env_file"; then
  echo "$var is already set in $env_file (rerun with --replace to replace it)" >&2
  exit 3
fi

body='{}'
[ -n "$name" ] && body=$(jq -nc --arg n "$name" '{clusterName: $n}')

hdr=$(mktemp) # response headers only; nothing secret
tmp=""
trap 'rm -f "$hdr" ${tmp:+"$tmp"}' EXIT

resp=$(curl -sS --connect-timeout 10 --max-time 60 -D "$hdr" -w '\n%{http_code}' -X POST \
  -H 'Accept: application/vnd.atlas.preview+json' \
  -H 'Content-Type: application/json' \
  -d "$body" \
  https://cloud.mongodb.com/api/atlas/v2/unauth/ephemeralClusters:create) && rc=0 || rc=$?

if [ "$rc" != 0 ]; then
  echo "curl error $rc: no response received. The request may still have reached the server."
  exit 1
fi
code=${resp##*$'\n'}
resp=${resp%$'\n'*}

if [ "$code" != 201 ]; then
  echo "HTTP $code"
  # Error bodies carry no credentials, but print only the known fields.
  jq -r '[.errorCode, .detail] | map(select(. != null)) | join(": ")' <<<"$resp" 2>/dev/null || true
  grep -i '^retry-after:' "$hdr" || true
  exit 1
fi

# From here on the cluster exists, and $resp holds the only copy of the password.
created_but_unsaved() {
  echo "The cluster was created, but its connection string could not be saved to $env_file: $1" >&2
  jq -r '"clusterId: \(.clusterId // "unknown")\nclaimUrl: \(.claimUrl // "unknown")"' <<<"$resp" 2>/dev/null || true
  echo "The password is lost. Claim the cluster, then set a new database user password in Atlas." >&2
  exit 4
}

uri=$(jq -er '.connectionString' <<<"$resp" 2>/dev/null) || created_but_unsaved "no connectionString in the response"
claim=$(jq -r '.claimUrl // "unknown"' <<<"$resp" 2>/dev/null) || claim=unknown
expires=$(jq -r '.expiresAt // "unknown"' <<<"$resp" 2>/dev/null) || expires=unknown

entry=$(printf '# ephemeral-cluster: var=%s claimUrl=%s expiresAt=%s\n%s="%s"' \
  "$var" "$claim" "$expires" "$var" "$uri")

if [ "$replace" = 1 ] && [ -f "$env_file" ]; then
  # Build the new file beside the old one, then swap it in atomically, so a
  # failed write can't truncate the user's env file.
  # $(...) drops trailing blank lines, so repeated replaces don't pile them up.
  kept=$(grep -vE "$entry_re|$marker_re" "$env_file" || true)
  tmp=$(mktemp "$env_dir/.env-ephemeral.XXXXXX") || created_but_unsaved "couldn't create a temp file in $env_dir"
  { [ -n "$kept" ] && printf '%s\n\n' "$kept"; printf '%s\n' "$entry"; } >"$tmp" ||
    created_but_unsaved "write failed"
  mv "$tmp" "$env_file" || created_but_unsaved "couldn't replace $env_file"
  tmp=""
else
  printf '\n%s\n' "$entry" >>"$env_file" || created_but_unsaved "write failed"
fi

jq '{clusterId, claimUrl, status, expiresAt}' <<<"$resp"
