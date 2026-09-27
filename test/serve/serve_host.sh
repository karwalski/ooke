#!/bin/sh
# Story 138.7 (O-3, loke handoff 2026-09-27): `ooke serve` binds [server] host.
#
# Before, ooke called toke's port-only serve functions, which listen on every
# interface, and ooke.toml had no way to say otherwise. It now reads
# [server] host and calls toke's `...on` forms (toke story 138.1). Absent, the
# host is 127.0.0.1: ooke's default is loopback only (why: src/config.tk,
# serverhost; docs/logging-and-tls.md, "Bind address").
#
#   default   no host key: the listening socket is 127.0.0.1:PORT, not *:PORT,
#             and the start log says it is loopback only and how to open it
#   public    host = "0.0.0.0": the listening socket is *:PORT
#   explicit  host = "127.0.0.1" answers on 127.0.0.1
#   refused   host = "example.com" (a name, which toke refuses rather than
#             resolving): serve exits non-zero, naming the host
#
# The socket is read with lsof, so the address is what the kernel reports,
# not what ooke logs.
#
# Negative control (2026-09-28): with serve.tk calling the port-only
# http.serveworkers again, "default" and "explicit" report *:PORT and
# "refused" keeps running (3 failed); with the host form, 0 failed.
#
# Usage: test/serve/serve_host.sh [path/to/ooke-toke]   (run by `make test`)
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 2; }
command -v lsof >/dev/null 2>&1 || { echo "error: lsof is required" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-host.XXXXXX") || exit 2
pid=""
cleanup() { [ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

port=$(( 20000 + (($$ + 4099) % 20000) ))
proj=$tmp/proj
cp -R "$ROOT/testproj" "$proj" && rm -rf "$proj/build" || exit 2

# sethost HOSTLINE : rewrite [server] with port $port, 1 worker and HOSTLINE
# (empty for no host key)
sethost() {
  awk -v port="$port" -v hl="$1" '
    /^\[server\]/ { print; if (hl != "") print hl; next }
    /^host = /    { next }
    /^port = /    { print "port = " port; next }
    /^workers = / { print "workers = 1"; next }
    { print }
  ' "$ROOT/testproj/ooke.toml" >"$proj/ooke.toml"
}

# start : run ooke serve in the project; wait until something listens on $port
start() {
  (cd "$proj" && exec "$BIN" serve) >"$tmp/out" 2>"$tmp/err" &
  pid=$!
  i=0
  while [ $i -lt 50 ]; do
    kill -0 "$pid" 2>/dev/null || return 1
    lsof -nP -a -p "$pid" -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 && return 0
    sleep 0.2; i=$((i+1))
  done
  return 1
}
stop() { [ -n "$pid" ] && { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; }; pid=""; }
# listenaddr : the NAME column of the listening socket, e.g. 127.0.0.1:8092 or *:8092
listenaddr() { lsof -nP -a -p "$pid" -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9; exit}'; }

echo "=== ooke serve binds [server] host (138.7 O-3) ==="

# ── default ────────────────────────────────────────────────────────────────
sethost ""
if start; then
  a=$(listenaddr)
  if [ "$a" = "127.0.0.1:$port" ]; then ok "default: no host key listens on 127.0.0.1:$port"
  else bad "default: no host key listens on '$a', want 127.0.0.1:$port"; fi
  if grep -q "listening on loopback only (127.0.0.1:$port)" "$tmp/err" "$tmp/out" 2>/dev/null
  then ok "default: the start log says loopback only and names the setting"
  else bad "default: no loopback-only line in the start log"; fi
  body=$(curl -s --max-time 2 "http://127.0.0.1:$port/")
  case $body in *"ooke is running"*) ok "default: answers on 127.0.0.1" ;;
                *) bad "default: GET http://127.0.0.1:$port/ did not answer" ;; esac
else
  bad "default: serve did not start"; tail -3 "$tmp/err" | sed 's/^/       /'
fi
stop

# ── public ─────────────────────────────────────────────────────────────────
sethost 'host = "0.0.0.0"'
if start; then
  a=$(listenaddr)
  if [ "$a" = "*:$port" ]; then ok "public: host = \"0.0.0.0\" listens on *:$port"
  else bad "public: host = \"0.0.0.0\" listens on '$a', want *:$port"; fi
else
  bad "public: serve did not start"; tail -3 "$tmp/err" | sed 's/^/       /'
fi
stop

# ── explicit ───────────────────────────────────────────────────────────────
sethost 'host = "127.0.0.1"'
if start; then
  a=$(listenaddr)
  if [ "$a" = "127.0.0.1:$port" ]; then ok "explicit: host = \"127.0.0.1\" listens on 127.0.0.1:$port"
  else bad "explicit: host = \"127.0.0.1\" listens on '$a'"; fi
else
  bad "explicit: serve did not start"; tail -3 "$tmp/err" | sed 's/^/       /'
fi
stop

# ── refused ────────────────────────────────────────────────────────────────
sethost 'host = "example.com"'
(cd "$proj" && "$BIN" serve) >"$tmp/out" 2>"$tmp/err" &
pid=$!
i=0; while [ $i -lt 50 ] && kill -0 "$pid" 2>/dev/null; do sleep 0.2; i=$((i+1)); done
if kill -0 "$pid" 2>/dev/null; then
  bad "refused: host = \"example.com\" kept running"; stop
else
  wait "$pid"; rc=$?; pid=""
  if [ "$rc" -ne 0 ] && grep -q "server stopped with an error on port $port (host example.com)" "$tmp/err"
  then ok "refused: host = \"example.com\" exits non-zero ($rc), naming the host"
  else bad "refused: rc=$rc"; tail -3 "$tmp/err" | sed 's/^/       /'; fi
fi

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
