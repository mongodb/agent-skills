#!/usr/bin/env bash
# check-mongod.sh
# Validates running mongod process configuration and mongod.conf settings
# Usage: bash check-mongod.sh [--version 7.0|8.0|8.3|9.0]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-version.sh
. "$SCRIPT_DIR/lib-version.sh"
mongo_parse_args "$@" || exit 1

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"

echo "=== MongoDB Process Check ==="

# --- Detect mongod ---
MONGOD_PID=$(pgrep -x mongod | head -1)
if [ -z "$MONGOD_PID" ]; then
  echo "$WARN mongod-running: mongod is not running — checking config files only"
else
  echo "$PASS mongod-running: mongod is running (PID $MONGOD_PID)"
fi

# --- Version check ---
if command -v mongod &>/dev/null; then
  MONGO_VER=$(mongod --version 2>/dev/null | grep -oP 'db version v\K[\d.]+')
  echo "$INFO mongod-version: $MONGO_VER"
  MAJOR=$(echo "$MONGO_VER" | cut -d. -f1)
  if [ "$MAJOR" -ge 7 ] 2>/dev/null; then
    echo "$PASS mongod-version-support: $MONGO_VER is a supported version (7.0, 8.0, 8.3 or 9.0)"
  elif [ "$MAJOR" -eq 6 ]; then
    echo "$FAIL mongod-version-support: MongoDB 6.0 reached end of life July 31, 2025. Upgrade immediately."
  else
    echo "$WARN mongod-version-support: $MONGO_VER — verify this is a supported, non-EOL version"
  fi

  # --- Cross-check the installed binary against the audited version ---
  # A mismatch means the whole report is scored against the wrong expectations.
  if [ "$MONGO_VERSION" != "unknown" ] && [ -n "$MONGO_VER" ]; then
    DETECTED_MM="$(echo "$MONGO_VER" | cut -d. -f1-2)"
    if [ "$DETECTED_MM" != "$MONGO_VERSION" ]; then
      echo "$WARN mongod-version-match: installed mongod is $MONGO_VER but the audit was run with --version $MONGO_VERSION"
      echo "       Fix: re-run with --version $DETECTED_MM so the checks use the right expected values"
    else
      echo "$PASS mongod-version-match: installed mongod $MONGO_VER matches the audited version $MONGO_VERSION"
    fi
  fi
fi

# --- Running as root ---
if [ -n "$MONGOD_PID" ]; then
  MONGOD_USER=$(ps -o user= -p "$MONGOD_PID" 2>/dev/null | tr -d ' ')
  echo "$INFO mongod-user: Running as $MONGOD_USER"
  if [ "$MONGOD_USER" = "root" ]; then
    echo "$FAIL mongod-user: mongod is running as root. Run as a dedicated non-root user."
  else
    echo "$PASS mongod-user: mongod is running as non-root user ($MONGOD_USER)"
  fi
fi

# --- Config file detection ---
CONF_FILE=""
for path in /etc/mongod.conf /etc/mongodb.conf /etc/mongod/mongod.conf; do
  if [ -f "$path" ]; then
    CONF_FILE="$path"
    break
  fi
done

if [ -z "$CONF_FILE" ]; then
  echo "$WARN mongod-config: No mongod.conf found in standard locations"
else
  echo "$INFO mongod-config: Using $CONF_FILE"

  # Helper: extract YAML value
  get_conf() {
    grep -E "^\s*$1" "$CONF_FILE" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' ' | head -1
  }

  # --- Auth ---
  AUTH=$(get_conf "authorization")
  if [ "$AUTH" = "enabled" ]; then
    echo "$PASS mongod-auth: authorization is enabled"
  else
    echo "$FAIL mongod-auth: authorization is NOT enabled — MongoDB must run with auth in production"
    echo "       Fix: Set security.authorization: enabled in $CONF_FILE"
  fi

  # --- Bind IP ---
  BIND_IP=$(get_conf "bindIp")
  if [ -z "$BIND_IP" ]; then
    echo "$WARN mongod-bindip: bindIp not explicitly set (defaults to 127.0.0.1 in newer versions)"
  elif [ "$BIND_IP" = "0.0.0.0" ]; then
    echo "$WARN mongod-bindip: bindIp=0.0.0.0 — listening on all interfaces. Ensure firewall rules restrict access."
  else
    echo "$PASS mongod-bindip: bindIp=$BIND_IP"
  fi

  # --- SSL/TLS ---
  TLS_MODE=$(get_conf "mode" | head -1)  # net.tls.mode
  NET_SSL=$(grep -E "ssl|tls" "$CONF_FILE" 2>/dev/null | head -5)
  if echo "$NET_SSL" | grep -qiE 'requireSSL|requireTLS'; then
    echo "$PASS mongod-tls: TLS/SSL is required"
  elif echo "$NET_SSL" | grep -qiE 'allowSSL|allowTLS|preferSSL|preferTLS'; then
    echo "$WARN mongod-tls: TLS/SSL mode allows unencrypted connections — use requireSSL/requireTLS in production"
  else
    echo "$WARN mongod-tls: TLS/SSL does not appear to be configured"
    echo "       Fix: Configure net.tls.mode: requireTLS in $CONF_FILE"
  fi

  # --- logAppend ---
  LOG_APPEND=$(get_conf "logAppend")
  if [ "$LOG_APPEND" = "true" ]; then
    echo "$PASS mongod-logappend: logAppend is enabled"
  else
    echo "$WARN mongod-logappend: logAppend is not enabled — log rotation may lose entries"
    echo "       Fix: Set systemLog.logAppend: true in $CONF_FILE"
  fi

  # --- Log destination ---
  LOG_DEST=$(get_conf "destination")
  if [ "$LOG_DEST" = "file" ] || [ "$LOG_DEST" = "syslog" ]; then
    echo "$PASS mongod-log-destination: $LOG_DEST"
  else
    echo "$WARN mongod-log-destination: No log destination explicitly set"
  fi

  # --- JavaScript engine ---
  JS_ENABLED=$(grep -E 'javascriptEnabled' "$CONF_FILE" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' ')
  if [ "$JS_ENABLED" = "false" ]; then
    echo "$PASS mongod-javascript: javascriptEnabled is false (recommended if server-side JS not needed)"
  elif [ "$JS_ENABLED" = "true" ]; then
    echo "$WARN mongod-javascript: javascriptEnabled is true — disable if server-side JS is not required"
  else
    echo "$INFO mongod-javascript: javascriptEnabled not explicitly set (defaults to true)"
  fi

  # --- Replication keyFile / x.509 ---
  REPL_SET=$(get_conf "replSetName")
  if [ -n "$REPL_SET" ]; then
    echo "$INFO mongod-replication: replSetName=$REPL_SET"
    KEYFILE=$(grep -E 'keyFile' "$CONF_FILE" 2>/dev/null | head -1)
    CLUSTERAUTH=$(grep -E 'clusterAuthMode' "$CONF_FILE" 2>/dev/null | head -1)
    if [ -n "$KEYFILE" ] || [ -n "$CLUSTERAUTH" ]; then
      echo "$PASS mongod-replication-auth: Keyfile or clusterAuthMode configured for replica set"
    else
      echo "$FAIL mongod-replication-auth: Replica set detected but no keyFile or clusterAuthMode found"
      echo "       Fix: Configure security.keyFile or security.clusterAuthMode in $CONF_FILE"
    fi
  fi

  # --- Audit logging (Enterprise) ---
  AUDIT=$(grep -E 'auditLog' "$CONF_FILE" 2>/dev/null | head -1)
  if [ -n "$AUDIT" ]; then
    echo "$PASS mongod-audit: Audit logging appears to be configured"
  else
    echo "$WARN mongod-audit: Audit logging (Enterprise feature) not detected in $CONF_FILE"
  fi
fi
