#!/usr/bin/env bash
# check-network.sh
# Validates network configuration for MongoDB production

PASS="[PASS]"
WARN="[WARN]"
FAIL="[FAIL]"
INFO="[INFO]"
UNKNOWN="[UNKNOWN]"

# Why a sysctl read failed. Kept identical to check-kernel.sh so the two scripts
# cannot describe the same failure differently.
sysctl_unknown_reason() {
  local key="$1"
  if [ ! -e "/proc/sys/${key//.//}" ]; then
    echo "key not present on this kernel"
  elif [ "$(id -u)" -ne 0 ]; then
    echo "not readable by this unprivileged run; re-run with sudo"
  else
    echo "sysctl returned no value"
  fi
}


echo "=== Network Check ==="

# --- Hostname resolution ---
HOSTNAME=$(hostname -f 2>/dev/null || hostname)
echo "$INFO hostname: $HOSTNAME"

if host "$HOSTNAME" &>/dev/null || getent hosts "$HOSTNAME" &>/dev/null; then
  echo "$PASS dns-resolution: Hostname $HOSTNAME resolves correctly"
else
  echo "$FAIL dns-resolution: Hostname $HOSTNAME does not resolve — MongoDB replica sets require proper hostname resolution"
  echo "       Fix: Add $HOSTNAME to /etc/hosts or configure DNS"
fi

# --- TCP keepalive ---
TCP_KEEPALIVE=$(sysctl -n net.ipv4.tcp_keepalive_time 2>/dev/null)
if [ -z "$TCP_KEEPALIVE" ]; then
  echo "$UNKNOWN net-tcp-keepalive: net.ipv4.tcp_keepalive_time could not be read ($(sysctl_unknown_reason net.ipv4.tcp_keepalive_time))"
elif [ -n "$TCP_KEEPALIVE" ]; then
  if [ "$TCP_KEEPALIVE" -le 120 ]; then
    echo "$PASS net-tcp-keepalive: net.ipv4.tcp_keepalive_time=$TCP_KEEPALIVE (recommended: 120)"
  elif [ "$TCP_KEEPALIVE" -le 300 ]; then
    echo "$WARN net-tcp-keepalive: net.ipv4.tcp_keepalive_time=$TCP_KEEPALIVE (recommended: 120; 300 is the override ceiling)"
    echo "       Fix: echo 'net.ipv4.tcp_keepalive_time=120' >> /etc/sysctl.conf && sysctl -p"
  else
    echo "$WARN net-tcp-keepalive: net.ipv4.tcp_keepalive_time=$TCP_KEEPALIVE (recommended: 120; the 7200 default leaves stale connections)"
    echo "       Fix: echo 'net.ipv4.tcp_keepalive_time=120' >> /etc/sysctl.conf && sysctl -p"
  fi
fi

# --- somaxconn ---
SOMAXCONN=$(sysctl -n net.core.somaxconn 2>/dev/null)
if [ -z "$SOMAXCONN" ]; then
  echo "$UNKNOWN net-somaxconn: net.core.somaxconn could not be read ($(sysctl_unknown_reason net.core.somaxconn))"
elif [ -n "$SOMAXCONN" ]; then
  if [ "$SOMAXCONN" -ge 4096 ]; then
    echo "$PASS net-somaxconn: net.core.somaxconn=$SOMAXCONN"
  else
    echo "$WARN net-somaxconn: net.core.somaxconn=$SOMAXCONN (recommended >= 4096)"
    echo "       Fix: echo 'net.core.somaxconn=4096' >> /etc/sysctl.conf && sysctl -p"
  fi
fi

# --- tcp_max_syn_backlog ---
SYN_BACKLOG=$(sysctl -n net.ipv4.tcp_max_syn_backlog 2>/dev/null)
if [ -z "$SYN_BACKLOG" ]; then
  echo "$UNKNOWN net-syn-backlog: net.ipv4.tcp_max_syn_backlog could not be read ($(sysctl_unknown_reason net.ipv4.tcp_max_syn_backlog))"
elif [ -n "$SYN_BACKLOG" ]; then
  if [ "$SYN_BACKLOG" -ge 4096 ]; then
    echo "$PASS net-syn-backlog: net.ipv4.tcp_max_syn_backlog=$SYN_BACKLOG"
  else
    echo "$WARN net-syn-backlog: net.ipv4.tcp_max_syn_backlog=$SYN_BACKLOG (recommended >= 4096)"
    echo "       Fix: echo 'net.ipv4.tcp_max_syn_backlog=4096' >> /etc/sysctl.conf && sysctl -p"
  fi
fi

# --- netdev_max_backlog ---
NETDEV_BACKLOG=$(sysctl -n net.core.netdev_max_backlog 2>/dev/null)
if [ -z "$NETDEV_BACKLOG" ]; then
  echo "$UNKNOWN net-netdev-backlog: net.core.netdev_max_backlog could not be read ($(sysctl_unknown_reason net.core.netdev_max_backlog))"
elif [ -n "$NETDEV_BACKLOG" ]; then
  if [ "$NETDEV_BACKLOG" -ge 3000 ]; then
    echo "$PASS net-netdev-backlog: net.core.netdev_max_backlog=$NETDEV_BACKLOG"
  else
    echo "$WARN net-netdev-backlog: net.core.netdev_max_backlog=$NETDEV_BACKLOG (recommended >= 3000)"
    echo "       Fix: echo 'net.core.netdev_max_backlog=3000' >> /etc/sysctl.conf && sysctl -p"
  fi
fi

# --- MongoDB port listening ---
CONF_FILE=""
for path in /etc/mongod.conf /etc/mongodb.conf; do
  if [ -f "$path" ]; then CONF_FILE="$path"; break; fi
done

MONGO_PORT=27017
if [ -n "$CONF_FILE" ]; then
  P=$(grep -E '^\s*port' "$CONF_FILE" 2>/dev/null | awk -F': ' '{print $2}' | tr -d ' ' | head -1)
  MONGO_PORT="${P:-27017}"
fi

LISTENING=$(ss -tlnp 2>/dev/null | grep ":$MONGO_PORT" | head -1)
if [ -n "$LISTENING" ]; then
  echo "$INFO net-mongo-port: mongod listening on $MONGO_PORT: $LISTENING"
  # Check if binding to 0.0.0.0
  if echo "$LISTENING" | grep -qE '0\.0\.0\.0|::'; then
    echo "$WARN net-bind-all: mongod appears to be listening on all interfaces — ensure firewall restricts access to port $MONGO_PORT"
  fi
else
  echo "$INFO net-mongo-port: Nothing detected on port $MONGO_PORT (mongod may not be running)"
fi

# --- maxIncomingConnections ---
if [ -n "$CONF_FILE" ]; then
  MAXCONN=$(grep -E '^\s*maxIncomingConnections' "$CONF_FILE" 2>/dev/null | awk -F: '{print $2}' | tr -d ' ' | head -1)
  if [ -z "$MAXCONN" ]; then
    echo "$INFO net-maxconn: maxIncomingConnections not set (defaults to 65536); size it at 110-115% of typical concurrent requests"
  else
    echo "$INFO net-maxconn: maxIncomingConnections=$MAXCONN; size it at 110-115% of typical concurrent requests"
  fi
fi

# --- Legacy HTTP interface ---
if [ -n "$CONF_FILE" ] && grep -qE '^\s*(httpinterface|net\.http)' "$CONF_FILE" 2>/dev/null; then
  echo "$FAIL net-http-interface: the HTTP interface is configured; production notes require it off in production"
  echo "       Fix: remove the httpinterface setting from $CONF_FILE"
fi

# --- NIC speed (informational) ---
for iface in $(ls /sys/class/net/ | grep -v lo); do
  SPEED=$(cat /sys/class/net/"$iface"/speed 2>/dev/null || echo "unknown")
  STATE=$(cat /sys/class/net/"$iface"/operstate 2>/dev/null || echo "unknown")
  if [ "$STATE" = "up" ]; then
    echo "$INFO nic-$iface: speed=${SPEED}Mb/s state=$STATE"
    if [[ "$SPEED" =~ ^[0-9]+$ ]] && [ "$SPEED" -lt 1000 ]; then
      echo "$WARN nic-$iface: NIC speed < 1Gbps — MongoDB replica sets benefit from >= 1Gbps network"
    fi
  fi
done
