#!/usr/bin/env bash
# Manage background `mdts` markdown preview servers bound to the LAN.
#
# Every server is launched detached in its own process group, keyed by port, with
# a small state record so a later invocation (or a different agent session) can
# find it, report its URLs, and shut it down without guessing at PIDs.
#
# Usage:
#   mdts-server.sh start [DIR] [-p PORT] [-g GLOB...]
#   mdts-server.sh status
#   mdts-server.sh stop [PORT|DIR|--all]
#   mdts-server.sh logs [PORT]
#
# Written for bash 3.2 (the macOS system bash) - no associative arrays, no ${var,,}.

set -uo pipefail

STATE_DIR="${MDTS_SERVER_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mdts-server}"
BASE_PORT="${MDTS_SERVER_PORT:-8521}"
PORT_SCAN_LIMIT=20
READY_TIMEOUT="${MDTS_SERVER_TIMEOUT:-120}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- primitives ---------------------------------------------------------------

# A TCP connect that succeeds means something is already listening there.
port_in_use() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1
}

pid_alive() { kill -0 "$1" 2>/dev/null; }

# Best-effort primary LAN IPv4. Asking the routing table for the interface that
# would carry outbound traffic is more reliable than picking the first `inet`
# line, which on macOS is often a VPN or virtualisation bridge.
lan_ip() {
  local ip="" iface=""
  if command -v ip >/dev/null 2>&1; then
    ip=$(ip route get 1.1.1.1 2>/dev/null |
      awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }')
  fi
  if [ -z "$ip" ] && command -v route >/dev/null 2>&1; then
    iface=$(route -n get default 2>/dev/null | awk '/interface:/ { print $2; exit }')
    if [ -n "$iface" ] && command -v ipconfig >/dev/null 2>&1; then
      ip=$(ipconfig getifaddr "$iface" 2>/dev/null)
    fi
  fi
  if [ -z "$ip" ] && command -v ifconfig >/dev/null 2>&1; then
    ip=$(ifconfig 2>/dev/null |
      awk '/inet /  { if ($2 != "127.0.0.1") { print $2; exit } }')
  fi
  printf '%s' "$ip"
}

record_path() { printf '%s/%s.server' "$STATE_DIR" "$1"; }

record_get() {
  # record_get PORT KEY
  local file
  file=$(record_path "$1")
  [ -f "$file" ] || return 1
  sed -n "s/^$2=//p" "$file" | head -1
}

# Drop records whose process is gone so `status` never shows ghosts.
prune_records() {
  local file port pid
  [ -d "$STATE_DIR" ] || return 0
  for file in "$STATE_DIR"/*.server; do
    [ -f "$file" ] || continue
    port=$(basename "$file" .server)
    pid=$(record_get "$port" pid)
    if [ -z "$pid" ] || ! pid_alive "$pid"; then
      rm -f "$file"
    fi
  done
}

live_ports() {
  local file port
  prune_records
  [ -d "$STATE_DIR" ] || return 0
  for file in "$STATE_DIR"/*.server; do
    [ -f "$file" ] || continue
    port=$(basename "$file" .server)
    printf '%s\n' "$port"
  done
}

report() {
  # report PORT
  local port="$1" dir ip
  dir=$(record_get "$port" dir)
  ip=$(lan_ip)
  printf 'serving   %s\n' "$dir"
  printf 'local     http://localhost:%s\n' "$port"
  if [ -n "$ip" ]; then
    printf 'lan       http://%s:%s\n' "$ip" "$port"
  else
    printf 'lan       http://<this-machine-lan-ip>:%s  (could not detect LAN IP)\n' "$port"
  fi
  printf 'log       %s\n' "$(record_get "$port" log)"
  printf 'stop      %s stop %s\n' "$0" "$port"
}

# --- commands -----------------------------------------------------------------

cmd_start() {
  local dir="." port="" globs=() arg
  while [ $# -gt 0 ]; do
    case "$1" in
      -p|--port) [ $# -ge 2 ] || die "--port needs a value"; port="$2"; shift 2 ;;
      -g|--glob)
        shift
        while [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; do globs+=("$1"); shift; done
        [ ${#globs[@]} -gt 0 ] || die "--glob needs at least one pattern"
        ;;
      -*) die "unknown option: $1" ;;
      *) dir="$1"; shift ;;
    esac
  done

  [ -e "$dir" ] || die "no such path: $dir"
  # mdts serves a directory tree; a file argument means "serve its parent".
  [ -d "$dir" ] || dir=$(dirname "$dir")
  dir=$(cd "$dir" && pwd) || die "cannot resolve directory: $dir"

  # Already serving this exact tree? Reuse it rather than stacking servers.
  for arg in $(live_ports); do
    if [ "$(record_get "$arg" dir)" = "$dir" ]; then
      printf 'already running\n'
      report "$arg"
      return 0
    fi
  done

  if [ -n "$port" ]; then
    port_in_use "$port" && die "port $port is already in use"
  else
    local candidate=$BASE_PORT limit=$((BASE_PORT + PORT_SCAN_LIMIT))
    while [ "$candidate" -lt "$limit" ]; do
      port_in_use "$candidate" || { port="$candidate"; break; }
      candidate=$((candidate + 1))
    done
    [ -n "$port" ] || die "no free port in range $BASE_PORT-$limit"
  fi

  mkdir -p "$STATE_DIR" || die "cannot create state dir: $STATE_DIR"
  local log="$STATE_DIR/$port.log"
  : >"$log"

  # Job control gives the background job its own process group, so `stop` can
  # signal the whole tree (npx -> node) instead of orphaning the real server.
  set -m
  nohup npx -y mdts "$dir" -H 0.0.0.0 -p "$port" --no-open \
    ${globs[@]+-g "${globs[@]}"} >>"$log" 2>&1 &
  local pid=$!
  set +m

  local waited=0
  while [ "$waited" -lt "$READY_TIMEOUT" ]; do
    if port_in_use "$port"; then
      {
        printf 'pid=%s\n' "$pid"
        printf 'port=%s\n' "$port"
        printf 'dir=%s\n' "$dir"
        printf 'log=%s\n' "$log"
      } >"$(record_path "$port")"
      report "$port"
      return 0
    fi
    pid_alive "$pid" || break
    sleep 1
    waited=$((waited + 1))
  done

  printf 'mdts failed to start on port %s. Last log lines:\n' "$port" >&2
  tail -20 "$log" >&2
  pid_alive "$pid" && kill -TERM -"$pid" 2>/dev/null
  return 1
}

cmd_status() {
  local ports port found=0
  ports=$(live_ports)
  for port in $ports; do
    [ "$found" -eq 0 ] || printf '\n'
    report "$port"
    found=1
  done
  [ "$found" -eq 1 ] || printf 'no mdts servers running\n'
}

stop_port() {
  local port="$1" pid
  pid=$(record_get "$port" pid) || die "no server recorded on port $port"
  # Signal the process group first; npx is only a launcher for the real node
  # process, so killing the group is what actually frees the port.
  kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
  local waited=0
  while [ "$waited" -lt 10 ] && pid_alive "$pid"; do
    sleep 1
    waited=$((waited + 1))
  done
  pid_alive "$pid" && { kill -KILL -"$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null; }
  rm -f "$(record_path "$port")"
  printf 'stopped mdts on port %s\n' "$port"
}

cmd_stop() {
  local target="${1:-}" ports port matched=0 resolved
  ports=$(live_ports)
  [ -n "$ports" ] || { printf 'no mdts servers running\n'; return 0; }

  if [ "$target" = "--all" ]; then
    for port in $ports; do stop_port "$port"; done
    return 0
  fi

  if [ -z "$target" ]; then
    set -- $ports
    [ $# -eq 1 ] || die "several servers running; pass a port or --all (see: $0 status)"
    stop_port "$1"
    return 0
  fi

  case "$target" in
    ''|*[!0-9]*)
      resolved=$(cd "$target" 2>/dev/null && pwd) || die "not a port or directory: $target"
      for port in $ports; do
        if [ "$(record_get "$port" dir)" = "$resolved" ]; then
          stop_port "$port"
          matched=1
        fi
      done
      [ "$matched" -eq 1 ] || die "no server is serving $resolved"
      ;;
    *) stop_port "$target" ;;
  esac
}

cmd_logs() {
  local port="${1:-}" ports
  if [ -z "$port" ]; then
    ports=$(live_ports)
    set -- $ports
    [ $# -eq 1 ] || die "pass a port (see: $0 status)"
    port="$1"
  fi
  local log
  log=$(record_get "$port" log) || die "no server recorded on port $port"
  cat "$log"
}

usage() {
  cat <<'EOF'
Manage background `mdts` markdown preview servers bound to 0.0.0.0 (LAN-visible).

  mdts-server.sh start [DIR] [-p PORT] [-g GLOB...]
      Serve DIR (default: current directory) and print local + LAN URLs.
      Picks the first free port from 8521 upward unless -p is given.
      Re-running for a directory that is already served reuses that server.

  mdts-server.sh status
      List running servers with their directories and URLs.

  mdts-server.sh stop [PORT|DIR|--all]
      Stop one server (by port or served directory) or all of them.
      With no argument, stops the only running server, or errors if ambiguous.

  mdts-server.sh logs [PORT]
      Print the server log.
EOF
}

case "${1:-}" in
  start)  shift; cmd_start "$@" ;;
  status) shift; cmd_status "$@" ;;
  stop)   shift; cmd_stop "$@" ;;
  logs)   shift; cmd_logs "$@" ;;
  -h|--help|help|'') usage ;;
  *) die "unknown command: $1 (try: start, status, stop, logs)" ;;
esac
