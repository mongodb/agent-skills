#!/usr/bin/env bash
# check-security.sh
# Validates security configuration: SELinux/AppArmor, user, TLS, audit

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"

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
CONF_FILE=""
for path in /etc/mongod.conf /etc/mongodb.conf; do
  if [ -f "$path" ]; then
    CONF_FILE="$path"
    break
  fi
done

if [ -n "$CONF_FILE" ]; then
  # --- Authorization ---
  AUTH=$(grep -E '^\s*authorization' "$CONF_FILE" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' ')
  if [ "$AUTH" = "enabled" ]; then
    echo "$PASS security-auth: authorization: enabled"
  else
    echo "$FAIL security-auth: authorization not enabled in $CONF_FILE"
    echo "       Fix: Set security.authorization: enabled in $CONF_FILE"
  fi

  # --- TLS ---
  TLS_BLOCK=$(grep -A10 '^net:' "$CONF_FILE" 2>/dev/null | grep -E 'tls|ssl' | head -5)
  if echo "$TLS_BLOCK" | grep -qiE 'requireSSL|requireTLS'; then
    echo "$PASS security-tls: requireTLS/requireSSL configured"
  elif echo "$TLS_BLOCK" | grep -qi 'allow\|prefer'; then
    echo "$WARN security-tls: TLS set to allow/prefer — use requireTLS in production"
  else
    echo "$WARN security-tls: TLS not configured or set to disabled"
    echo "       Fix: Configure net.tls.mode: requireTLS and provide TLS cert/key"
  fi

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
if [ -n "$CONF_FILE" ]; then
  CONF_PERMS=$(stat -c '%a' "$CONF_FILE" 2>/dev/null)
  if [ "$CONF_PERMS" = "600" ] || [ "$CONF_PERMS" = "640" ]; then
    echo "$PASS config-permissions: $CONF_FILE has secure permissions ($CONF_PERMS)"
  else
    echo "$WARN config-permissions: $CONF_FILE permissions are $CONF_PERMS (recommended: 600 or 640)"
    echo "       Fix: chmod 600 $CONF_FILE"
  fi
fi

# --- Check for open MongoDB port without auth ---
MONGO_PORT=$(grep -E '^\s*port' "$CONF_FILE" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' ' | head -1)
MONGO_PORT="${MONGO_PORT:-27017}"
LISTENING=$(ss -tlnp 2>/dev/null | grep ":$MONGO_PORT" | head -1)
if [ -n "$LISTENING" ]; then
  echo "$INFO network-port: mongod listening on port $MONGO_PORT: $LISTENING"
fi

# --- SELinux together with server-side JavaScript ---
SEL_MODE=$(getenforce 2>/dev/null)
if [ "$SEL_MODE" = "Enforcing" ]; then
  CONF=""
  for path in /etc/mongod.conf /etc/mongodb.conf; do
    [ -f "$path" ] && CONF="$path" && break
  done
  if [ -n "$CONF" ] && grep -qE '^\s*javascriptEnabled:\s*true' "$CONF" 2>/dev/null; then
    echo "$FAIL selinux-javascript: server-side JavaScript is enabled while SELinux is Enforcing, which segfaults mongod"
    echo "       Fix: set security.javascriptEnabled: false in $CONF"
  else
    echo "$PASS selinux-javascript: server-side JavaScript is not explicitly enabled under SELinux Enforcing"
  fi
  echo "$INFO selinux-paths: SELinux needs explicit configuration only when dbPath, logPath, or the port differ from the packaged defaults"
fi
