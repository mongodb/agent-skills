#!/usr/bin/env bash
# check-security.sh
# Validates security configuration: SELinux/AppArmor, user, TLS, audit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-conf.sh
. "$SCRIPT_DIR/lib-conf.sh"

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"
UNKNOWN="[UNKNOWN]"

echo "=== Security Check ==="

# --- AES-NI (encrypted storage engine) ---
if grep -qw aes /proc/cpuinfo 2>/dev/null; then
  echo "$PASS cpu-aes-ni: AES-NI is available, which the encrypted storage engine benefits from"
else
  echo "$WARN cpu-aes-ni: AES-NI not detected; encryption at rest carries a larger CPU cost on this host"
fi

# --- SELinux ---
if command -v getenforce &>/dev/null; then
  SELINUX=$(getenforce 2>/dev/null)
  echo "$INFO selinux-status: $SELINUX"
  case "$SELINUX" in
    Enforcing)
      echo "$PASS selinux: SELinux is Enforcing"
      ;;
    Permissive)
      echo "$WARN selinux: SELinux is Permissive — consider Enforcing for production"
      ;;
    Disabled)
      echo "$WARN selinux: SELinux is Disabled — consider enabling for security hardening"
      ;;
  esac
fi

# --- AppArmor ---
if command -v apparmor_status &>/dev/null; then
  AA_STATUS=$(apparmor_status 2>/dev/null | head -3)
  echo "$INFO apparmor: $AA_STATUS"
fi

# --- mongod user ---
MONGOD_PID=$(pgrep -x mongod | head -1)
if [ -n "$MONGOD_PID" ]; then
  MONGOD_USER=$(ps -o user= -p "$MONGOD_PID" | tr -d ' ')
  if [ "$MONGOD_USER" = "root" ]; then
    echo "$FAIL mongod-user: mongod is running as root — must use a dedicated non-root user"
  else
    echo "$PASS mongod-user: mongod running as $MONGOD_USER"
  fi
fi

# --- Config file ---
conf_detect
if [ "$CONF_STATE" = "unreadable" ]; then
  echo "$UNKNOWN security-config: $CONF_FILE exists but is not readable by this run; authorization, TLS, cluster auth, audit and encryption settings were not checked. Re-run with sudo."
elif [ "$CONF_STATE" = "missing" ]; then
  echo "$UNKNOWN security-config: no mongod.conf found in the standard locations; set MONGO_CONF_FILE to the config path to check authorization, TLS and the other config settings"
fi

if [ "$CONF_STATE" = "readable" ]; then
  # --- Authorization ---
  AUTH=$(conf_get security.authorization)
  if [ "$AUTH" = "enabled" ]; then
    echo "$PASS security-auth: authorization: enabled"
  else
    echo "$FAIL security-auth: authorization not enabled in $CONF_FILE"
    echo "       Fix: Set security.authorization: enabled in $CONF_FILE"
  fi

  # --- TLS ---
  # Read the scoped net.tls.mode (net.ssl.mode on older configs), not any line
  # that happens to mention tls, so the nested YAML layout is recognized.
  TLS_MODE=$(conf_get net.tls.mode)
  [ -n "$TLS_MODE" ] || TLS_MODE=$(conf_get net.ssl.mode)
  case "$TLS_MODE" in
    requireTLS|requireSSL)
      echo "$PASS security-tls: net.tls.mode is $TLS_MODE" ;;
    allowTLS|preferTLS|allowSSL|preferSSL)
      echo "$WARN security-tls: net.tls.mode is $TLS_MODE, which accepts unencrypted connections; use requireTLS in production"
      echo "       Fix: set net.tls.mode: requireTLS in $CONF_FILE" ;;
    disabled|"")
      echo "$WARN security-tls: TLS is not configured (net.tls.mode is ${TLS_MODE:-not set})"
      echo "       Fix: set net.tls.mode: requireTLS and provide the TLS certificate and key" ;;
    *)
      echo "$WARN security-tls: unrecognized net.tls.mode '$TLS_MODE'" ;;
  esac

  # --- Keyfile for replica set ---
  REPL=$(grep -E 'replSetName' "$CONF_FILE" 2>/dev/null | head -1)
  if [ -n "$REPL" ]; then
    KEYFILE=$(grep -E 'keyFile' "$CONF_FILE" 2>/dev/null | head -1)
    X509=$(grep -E 'clusterAuthMode.*x509' "$CONF_FILE" 2>/dev/null | head -1)
    if [ -n "$KEYFILE" ] || [ -n "$X509" ]; then
      echo "$PASS security-replication-auth: Cluster auth configured for replica set"
    else
      echo "$FAIL security-replication-auth: Replica set configured but no keyFile or x.509 cluster auth found"
    fi
  fi

  # --- Audit log ---
  AUDIT=$(grep -E 'auditLog' "$CONF_FILE" 2>/dev/null | head -1)
  if [ -n "$AUDIT" ]; then
    echo "$PASS security-audit: Audit logging configured"
  else
    echo "$WARN security-audit: Audit logging (MongoDB Enterprise feature) not configured"
    echo "       Consider enabling for compliance and security monitoring"
  fi

  # --- FIPS ---
  FIPS=$(grep -iE 'fips' "$CONF_FILE" 2>/dev/null | head -1)
  if [ -n "$FIPS" ]; then
    echo "$INFO security-fips: FIPS configuration found: $FIPS"
  else
    echo "$INFO security-fips: FIPS mode not configured (only required for specific compliance regimes)"
  fi

  # --- Encryption at rest ---
  ENCRYPT=$(grep -E 'enableEncryption' "$CONF_FILE" 2>/dev/null | head -1)
  if echo "$ENCRYPT" | grep -q 'true'; then
    echo "$PASS security-encryption-at-rest: Encryption at rest is enabled"
  else
    echo "$WARN security-encryption-at-rest: Encryption at rest not detected (recommended for regulated environments)"
  fi
fi

# --- Config file permissions ---
if [ "$CONF_STATE" != "missing" ]; then
  CONF_PERMS=$(stat -c '%a' "$CONF_FILE" 2>/dev/null)
  if [ "$CONF_PERMS" = "600" ] || [ "$CONF_PERMS" = "640" ]; then
    echo "$PASS config-permissions: $CONF_FILE has secure permissions ($CONF_PERMS)"
  else
    echo "$WARN config-permissions: $CONF_FILE permissions are $CONF_PERMS (recommended: 600 or 640)"
    echo "       Fix: chmod 600 $CONF_FILE"
  fi
fi

# --- Check for open MongoDB port without auth ---
MONGO_PORT=$(conf_get net.port)
MONGO_PORT="${MONGO_PORT:-27017}"
LISTENING=$(ss -tlnp 2>/dev/null | grep ":$MONGO_PORT" | head -1)
if [ -n "$LISTENING" ]; then
  echo "$INFO network-port: mongod listening on port $MONGO_PORT: $LISTENING"
fi

# --- SELinux together with server-side JavaScript ---
# security.javascriptEnabled defaults to true, so an omitted setting counts as
# enabled. Under SELinux any operation that needs server-side JavaScript
# segfaults mongod. A running mongod started with --noscripting is disabled
# whatever the file says.
SEL_MODE=$(getenforce 2>/dev/null)
if [ "$SEL_MODE" = "Enforcing" ]; then
  NOSCRIPTING=$(ps -eo args 2>/dev/null | grep -E '(^|/)mongod( |$)' | grep -v grep | grep -c -- '--noscripting')
  JS_SETTING=$(conf_get security.javascriptEnabled)
  if [ "${NOSCRIPTING:-0}" -gt 0 ]; then
    echo "$PASS selinux-javascript: the running mongod was started with --noscripting, so server-side JavaScript is disabled under SELinux Enforcing"
  elif [ "$CONF_STATE" != "readable" ]; then
    echo "$UNKNOWN selinux-javascript: SELinux is Enforcing and the config could not be read (${CONF_FILE:-no config found}); javascriptEnabled defaults to true, which makes server-side JavaScript operations segfault mongod. Re-run with sudo or set MONGO_CONF_FILE."
  elif [ "$JS_SETTING" = "false" ]; then
    echo "$PASS selinux-javascript: security.javascriptEnabled is false under SELinux Enforcing"
  else
    echo "$FAIL selinux-javascript: server-side JavaScript is enabled under SELinux Enforcing (security.javascriptEnabled is ${JS_SETTING:-not set, so it defaults to true}); any operation that needs server-side JavaScript segfaults mongod"
    echo "       Fix: set security.javascriptEnabled: false in $CONF_FILE, or start mongod with --noscripting"
  fi
  echo "$INFO selinux-paths: SELinux needs explicit configuration only when dbPath, logPath, or the port differ from the packaged defaults"
fi

# Reaching the end means every check in this category ran. run-all-checks.sh
# treats any other exit status as an incomplete category.
exit 0
