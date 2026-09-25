#!/bin/sh
# Story 134.40: `ooke serve` applies [log] and [tls].
#
# Before 134.40 `[log]` was read and used by nothing -- serve opened no log, so
# no request was logged anywhere -- and serve passed an empty certificate and
# key to serverun, so it could only speak plain HTTP. This serves a copy of
# testproj/, sends real requests, and reads what was written:
#
#   access file   [log] access = "logs/access.log" -> one combined line per request
#   error file    [log] error  = "logs/error.log"  -> the 4xx line only
#   json          [log] accessformat = "json"      -> NDJSON access lines
#   default       no access key                    -> access lines on stderr
#   off           access = ""                      -> no access lines at all
#   refusals      bad accessformat, unopenable log path, half a [tls] pair,
#                 a missing cert, an unloadable cert -> non-zero exit, named
#   rotation      maxlines/maxagedays -> named as ignored, no rotated files
#   tls           [tls] cert/key (self-signed, generated here with openssl,
#                 no network) -> HTTPS answers, plain HTTP does not
#
# Usage: test/serve/serve_logs_tls.sh [path/to/ooke-toke]
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-serve-logs.XXXXXX") || exit 2
pid=""
cleanup() { [ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

MARKER="ooke is running"
UA="ooke-134-40-probe"
base=$(( 20000 + ($$ % 20000) ))
n=0

# mkproj NAME LOGBLOCK [TLSBLOCK] -> $tmp/NAME, with its own port in $port
mkproj() {
  n=$((n+1)); port=$((base+n)); proj=$tmp/$1
  cp -R "$ROOT/testproj" "$proj" && rm -rf "$proj/build" || return 1
  # Blocks go through the environment: BSD awk rejects a newline in -v.
  LOGBLOCK=$2 TLSBLOCK=${3:-} awk -v port="$port" '
    /^\[log\]/ { skip=1; next }
    /^\[/      { skip=0 }
    skip       { next }
    /^port = / { print "port = " port; next }
    /^workers = / { print "workers = 1"; next }
    { print }
    END { print ""; print "[log]"; printf "%s\n", ENVIRON["LOGBLOCK"];
          if (ENVIRON["TLSBLOCK"] != "") { print ""; print "[tls]"; printf "%s\n", ENVIRON["TLSBLOCK"] } }
  ' "$ROOT/testproj/ooke.toml" >"$proj/ooke.toml" || return 1
}

# start NAME -> server running in $tmp/NAME, stderr in $tmp/NAME.err
start() {
  (cd "$tmp/$1" && exec "$BIN" serve) >"$tmp/$1.out" 2>"$tmp/$1.err" &
  pid=$!
}
stop() { [ -n "$pid" ] && kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=""; }

# waitup SCHEME -> 0 once "/" answers
waitup() {
  i=0
  while [ $i -lt 50 ]; do
    kill -0 "$pid" 2>/dev/null || return 1
    curl -sk --max-time 2 -o /dev/null "$1://127.0.0.1:$port/" 2>/dev/null && return 0
    sleep 0.2; i=$((i+1))
  done
  return 1
}

# refuses NAME WHAT PATTERN -> the server must exit non-zero, naming PATTERN
refuses() {
  start "$1"; i=0
  while [ $i -lt 50 ] && kill -0 "$pid" 2>/dev/null; do sleep 0.2; i=$((i+1)); done
  if kill -0 "$pid" 2>/dev/null; then bad "$2: server started anyway"; stop; return; fi
  wait "$pid"; rc=$?; pid=""
  if [ "$rc" -ne 0 ]; then ok "$2: exits non-zero ($rc)"; else bad "$2: exited 0"; fi
  if grep -q "$3" "$tmp/$1.err"; then ok "$2: the error names $3"
  else bad "$2: no message naming $3"; tail -3 "$tmp/$1.err" | sed 's/^/       /'; fi
}

requests() { # SCHEME
  curl -sk --max-time 2 -o /dev/null -A "$UA" "$1://127.0.0.1:$port/"
  curl -sk --max-time 2 -o /dev/null -A "$UA" "$1://127.0.0.1:$port/no-such-page-134-40"
  sleep 0.3
}

echo "=== ooke serve [log] and [tls] (134.40) ==="

# ── access + error to files, combined ───────────────────────────────────────
mkproj files 'access = "logs/access.log"
error = "logs/error.log"
accessformat = "combined"'
start files
if waitup http; then
  requests http; stop
  a=$tmp/files/logs/access.log; e=$tmp/files/logs/error.log
  if [ -f "$a" ]; then ok "files: logs/access.log created, relative to the project"; else bad "files: no logs/access.log"; fi
  if grep -q "\"GET / HTTP/1.1\" 200 .*\"$UA\"" "$a" 2>/dev/null; then ok "files: access log has the 200 for / with its user agent"
  else bad "files: no combined 200 line for / in the access log"; cat "$a" 2>/dev/null | sed 's/^/       /'; fi
  if grep -q '"GET /no-such-page-134-40 HTTP/1.1" 404' "$a" 2>/dev/null; then ok "files: access log has the 404"
  else bad "files: no 404 line in the access log"; fi
  if grep -q '" 404 ' "$e" 2>/dev/null && ! grep -q '" 200 ' "$e" 2>/dev/null; then ok "files: error log has the 404 and not the 200"
  else bad "files: error log is not exactly the 4xx line"; cat "$e" 2>/dev/null | sed 's/^/       /'; fi
  if grep -q "$UA" "$tmp/files.err"; then bad "files: access lines also went to stderr"; else ok "files: nothing logged to stderr per request"; fi
else
  bad "files: server did not start"; tail -5 "$tmp/files.err" | sed 's/^/       /'; stop
fi

# ── json ────────────────────────────────────────────────────────────────────
mkproj json 'access = "logs/access.log"
accessformat = "json"'
start json
if waitup http; then
  requests http; stop
  if grep -q "\"path\":\"/\",\"status\":200,.*\"ua\":\"$UA\"" "$tmp/json/logs/access.log" 2>/dev/null
  then ok "json: access log line is NDJSON with status 200"
  else bad "json: no NDJSON 200 line"; cat "$tmp/json/logs/access.log" 2>/dev/null | sed 's/^/       /'; fi
else
  bad "json: server did not start"; stop
fi

# ── default: stderr ─────────────────────────────────────────────────────────
mkproj dflt 'accessformat = "combined"'
start dflt
if waitup http; then
  requests http; stop
  if grep -q "\"GET / HTTP/1.1\" 200 .*\"$UA\"" "$tmp/dflt.err"; then ok "default: access lines go to stderr"
  else bad "default: no access line on stderr"; fi
else
  bad "default: server did not start"; stop
fi

# ── off ─────────────────────────────────────────────────────────────────────
mkproj off 'access = ""'
start off
if waitup http; then
  requests http; stop
  if grep -q "$UA" "$tmp/off.err" "$tmp/off.out"; then bad "off: a request was logged"
  else ok "off: access = \"\" logs no request"; fi
else
  bad "off: server did not start"; stop
fi

# ── rotation keys are named and ignored ─────────────────────────────────────
mkproj rot 'access = "logs/access.log"
maxlines = 1
maxagedays = 1'
start rot
if waitup http; then
  requests http; stop
  if grep -q "maxlines, maxagedays ignored" "$tmp/rot.err"; then ok "rotation: maxlines/maxagedays named as ignored"
  else bad "rotation: no warning naming maxlines/maxagedays"; fi
  lines=$(wc -l <"$tmp/rot/logs/access.log" 2>/dev/null | tr -d ' ')
  rotated=$(ls "$tmp/rot/logs" 2>/dev/null | grep -c '\.gz$')
  if [ "${lines:-0}" -ge 3 ] && [ "$rotated" -eq 0 ]; then ok "rotation: every line kept in one file ($lines lines, 0 archives)"
  else bad "rotation: $lines lines, $rotated archives"; fi
else
  bad "rotation: server did not start"; stop
fi

# ── refusals ────────────────────────────────────────────────────────────────
mkproj badfmt 'accessformat = "ndjson"'
refuses badfmt "bad accessformat" "accessformat"
mkproj badpath 'access = "/dev/null/not-a-dir/access.log"'
refuses badpath "unopenable access log" "access log could not be opened"
mkproj halftls 'access = "-"' 'cert = "cert.pem"'
refuses halftls "[tls] cert without key" "needs both cert and key"
mkproj nocert 'access = "-"' 'cert = "nope.pem"
key = "nope.key"'
refuses nocert "[tls] missing cert file" "cert not found"

# ── TLS ─────────────────────────────────────────────────────────────────────
if ! command -v openssl >/dev/null 2>&1; then
  bad "tls: openssl is not installed, so no self-signed certificate can be made"
else
  mkproj tls 'access = "logs/access.log"' 'cert = "certs/cert.pem"
key = "certs/key.pem"'
  mkdir -p "$tmp/tls/certs"
  if openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=127.0.0.1" \
       -keyout "$tmp/tls/certs/key.pem" -out "$tmp/tls/certs/cert.pem" >/dev/null 2>&1; then
    start tls
    if waitup https; then
      body=$(curl -sk --max-time 2 -A "$UA" "https://127.0.0.1:$port/")
      case $body in *"$MARKER"*) ok "tls: HTTPS serves / from the project" ;;
                    *) bad "tls: HTTPS body lacks the marker" ;; esac
      if curl -s --max-time 2 -o /dev/null "http://127.0.0.1:$port/" 2>/dev/null
      then bad "tls: plain HTTP was answered on the TLS port"
      else ok "tls: plain HTTP is not answered on the TLS port"; fi
      sleep 0.3; stop
      if grep -q "\"GET / HTTP/1.1\" 200 .*\"$UA\"" "$tmp/tls/logs/access.log" 2>/dev/null
      then ok "tls: the HTTPS request is in the access log"
      else bad "tls: the HTTPS request is not in the access log"; fi
    else
      bad "tls: HTTPS server did not start"; tail -5 "$tmp/tls.err" | sed 's/^/       /'; stop
    fi

    # A cert file that exists but does not load: serve used to discard
    # servetls' -1 and exit 0 with no message.
    mkproj badcert 'access = "-"' 'cert = "cert.pem"
key = "key.pem"'
    echo "not a certificate" >"$tmp/badcert/cert.pem"
    echo "not a key" >"$tmp/badcert/key.pem"
    refuses badcert "[tls] unloadable cert" "server stopped with an error"
  else
    bad "tls: openssl could not generate a self-signed certificate"
  fi
fi

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
