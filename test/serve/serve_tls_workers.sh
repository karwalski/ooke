#!/bin/sh
# Story 134.47 (3): `ooke serve` honours [server].workers under TLS.
#
# Before, serve.tk called toke's http.servetlson, which takes no worker count,
# so with [tls] the pool was sized from TK_HTTP_WORKERS or the CPU count and
# [server].workers was ignored (docs/logging-and-tls.md said so). It now calls
# http.servetlsworkerson (toke 138.1) with the configured count.
#
#   tls3    [tls] + workers = 3: the server answers HTTPS and has exactly 3
#           worker processes (children of the ooke process, read with pgrep)
#   http3   the plain-HTTP control, workers = 3: 3 worker processes
#
# TK_HTTP_WORKERS is unset for the run, so an ignored setting shows as the CPU
# count rather than as a coincidental 3.
#
# Negative control (2026-09-28): with serve.tk calling http.servetlson again,
# "tls3" reports the CPU count of worker processes instead of 3 (1 failed).
#
# Usage: test/serve/serve_tls_workers.sh [path/to/ooke-toke]  (run by `make test`)
set -u
unset TK_HTTP_WORKERS

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 2; }
command -v openssl >/dev/null 2>&1 || { echo "error: openssl is required" >&2; exit 2; }
command -v pgrep >/dev/null 2>&1 || { echo "error: pgrep is required" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-tls-workers.XXXXXX") || exit 2
pid=""
cleanup() { [ -n "$pid" ] && { pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; }; rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

base=$(( 20000 + (($$ + 5003) % 20000) ))
n=0

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=localhost" \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" >/dev/null 2>&1 \
  || { echo "error: openssl could not make a test certificate" >&2; exit 2; }

# mkproj NAME WORKERS TLS(0|1) -> $tmp/NAME, with its own port in $port
mkproj() {
  n=$((n+1)); port=$((base+n)); proj=$tmp/$1
  cp -R "$ROOT/testproj" "$proj" && rm -rf "$proj/build" || return 1
  awk -v port="$port" -v w="$2" -v tls="$3" -v cert="$tmp/cert.pem" -v key="$tmp/key.pem" '
    /^\[tls\]/    { skip=1; next }
    /^\[/         { skip=0 }
    skip          { next }
    /^port = /    { print "port = " port; next }
    /^workers = / { print "workers = " w; next }
    { print }
    END { if (tls == 1) { print ""; print "[tls]"; print "cert = \"" cert "\""; print "key = \"" key "\"" } }
  ' "$ROOT/testproj/ooke.toml" >"$proj/ooke.toml" || return 1
}

start() {
  (cd "$tmp/$1" && exec "$BIN" serve) >"$tmp/$1.out" 2>"$tmp/$1.err" &
  pid=$!
}
stop() { [ -n "$pid" ] && { pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; }; pid=""; }

waitup() { # SCHEME
  i=0
  while [ $i -lt 50 ]; do
    kill -0 "$pid" 2>/dev/null || return 1
    curl -sk --max-time 2 -o /dev/null "$1://127.0.0.1:$port/" 2>/dev/null && return 0
    sleep 0.2; i=$((i+1))
  done
  return 1
}

# workers NAME SCHEME TLS WANT
check() {
  mkproj "$1" "$4" "$3" || { bad "$1: could not make the project"; return; }
  start "$1"
  if waitup "$2"; then
    ok "$1: answers $2"
    sleep 0.5
    got=$(pgrep -P "$pid" | wc -l | tr -d ' ')
    if [ "$got" = "$4" ]; then ok "$1: $4 worker processes"
    else bad "$1: $got worker processes, [server].workers = $4"; fi
  else
    bad "$1: server did not start"; tail -5 "$tmp/$1.err" | sed 's/^/       /'
  fi
  stop
}

echo "=== ooke serve [server].workers under TLS (134.47) ==="
check tls3  https 1 3
check http3 http  0 3
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
