#!/usr/bin/env bash
# lib-conf.sh
# Shared mongod.conf handling for the self-managed production checks.
# Sourced, never executed.
#
# Provides:
#   conf_detect          find the config file and record whether it can be read
#   conf_get dotted.key  read one scalar from the YAML config, scoped by its
#                        parent keys, e.g. conf_get net.tls.mode
#
# conf_detect sets:
#   CONF_FILE   path of the config file, or empty when none was found
#   CONF_STATE  readable | unreadable | missing
#
# Callers must branch on CONF_STATE. An unreadable file is not evidence that a
# setting is absent, so it has to surface as UNKNOWN, never as a default PASS.
#
# Search order: MONGO_CONF_FILE when set (only that path), then the --config or
# -f path of a running mongod, then /etc/mongod.conf, /etc/mongodb.conf and
# /etc/mongod/mongod.conf.

conf_running_path() {
  local args
  args=$(ps -eo args 2>/dev/null | grep -E '(^|/)mongod( |$)' | grep -v grep | head -1)
  [ -n "$args" ] || return 0
  case "$args" in
    *"--config="*) args="${args#*--config=}" ;;
    *"--config "*) args="${args#*--config }" ;;
    *" -f "*)      args="${args#* -f }" ;;
    *) return 0 ;;
  esac
  echo "${args%% *}"
}

conf_detect() {
  local path candidates=()
  CONF_FILE=""
  CONF_STATE="missing"

  if [ -n "${MONGO_CONF_FILE:-}" ]; then
    candidates=("$MONGO_CONF_FILE")
  else
    path=$(conf_running_path)
    [ -n "$path" ] && candidates+=("$path")
    candidates+=(/etc/mongod.conf /etc/mongodb.conf /etc/mongod/mongod.conf)
  fi

  for path in "${candidates[@]}"; do
    if [ -f "$path" ]; then
      CONF_FILE="$path"
      if [ -r "$path" ] && head -c 0 "$path" 2>/dev/null; then
        CONF_STATE="readable"
      else
        CONF_STATE="unreadable"
      fi
      return 0
    fi
  done
  return 0
}

# Echo the scalar value at a dotted key path. Block-style YAML only, which is
# what mongod.conf uses. Comments and surrounding quotes are stripped. Echoes
# nothing when the key is absent or the file cannot be read.
conf_get() {
  [ "${CONF_STATE:-}" = "readable" ] || return 0
  awk -v want="$1" -v q="'" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^[ \t]*#/ || /^[ \t]*$/ || /^[ \t]*-/ { next }
    {
      line = $0
      sub(/[ \t]+#.*$/, "", line)
      match(line, /^[ \t]*/); ind = RLENGTH
      s = trim(line)
      c = index(s, ":")
      if (c == 0) next
      k = trim(substr(s, 1, c - 1))
      v = trim(substr(s, c + 1))
      while (depth > 0 && ind <= indents[depth]) depth--
      depth++; indents[depth] = ind; keys[depth] = k
      path = keys[1]
      for (i = 2; i <= depth; i++) path = path "." keys[i]
      if (path == want && v != "") {
        if (v ~ /^".*"$/ || v ~ ("^" q ".*" q "$")) v = substr(v, 2, length(v) - 2)
        print v
        exit
      }
    }
  ' "$CONF_FILE" 2>/dev/null
}
