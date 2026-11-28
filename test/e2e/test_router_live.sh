#!/bin/bash
# 89.1.3 - Router test via live ooke server
# Tests static routes, 404 handling, and API handler against running server.
#
# Story 127.562: no fixed port. `ooke serve` takes its port only from
# [server] port in ooke.toml, and this test used to serve the project in place
# (port 3000, a common dev-server port) and curl localhost:3000, so another
# dev server on 3000 could answer for ooke. It now serves a temporary copy of
# the project whose [server] port is a port freeport (test/support/freeport.sh)
# found free on 127.0.0.1, or $OOKE_E2E_PORT if set, and curls 127.0.0.1 on
# that port only after checking the server it started is the one answering.
#
# Usage: test/e2e/test_router_live.sh [path/to/ooke-toke]
#   OOKE_DIR       project to serve (default: this repository)
#   OOKE_E2E_PORT  port to use instead of a free one

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
. "$ROOT/test/support/freeport.sh"
OOKE_DIR=${OOKE_DIR:-$ROOT}
OOKE=${1:-$ROOT/ooke-toke}
case $OOKE in /*) ;; *) OOKE=$ROOT/$OOKE ;; esac
PORT=${OOKE_E2E_PORT:-$(freeport)} || exit 2
PASS=0
FAIL=0
SERVER_PID=
TMP=

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
  fi
  [ -n "$TMP" ] && rm -rf "$TMP"
}
trap cleanup EXIT

# --- Preflight ---
if [ ! -x "$OOKE" ]; then
  echo "ABORT: ooke-toke binary not found or not executable at $OOKE"
  exit 1
fi

if [ ! -f "$OOKE_DIR/ooke.toml" ]; then
  echo "ABORT: ooke.toml missing at $OOKE_DIR"
  exit 1
fi

# --- Stage a copy of the project that listens on $PORT ---
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ooke-e2e-router.XXXXXX") || exit 2
SITE=$TMP/site
mkdir "$SITE" || exit 2
for d in pages templates static models content islands; do
  [ -e "$OOKE_DIR/$d" ] && cp -R "$OOKE_DIR/$d" "$SITE/"
done
awk -v port="$PORT" '
  /^\[/ { sec = $0 }
  sec == "[server]" && /^port[ \t]*=/ { print "port = " port; next }
  { print }
' "$OOKE_DIR/ooke.toml" >"$SITE/ooke.toml"
if ! grep -q "^port = $PORT\$" "$SITE/ooke.toml"; then
  echo "ABORT: could not set [server] port in a copy of $OOKE_DIR/ooke.toml"
  exit 1
fi

echo "=== Router Live Test (89.1.3) ==="
echo "Binary: $OOKE"
echo "Site:   $OOKE_DIR (served from a copy)"
echo "Port:   $PORT"
echo ""

# --- Start server ---
# Nothing may already listen on $PORT (an $OOKE_E2E_PORT someone else holds):
# curl must be refused (exit 7) before our server starts.
curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$PORT/" 2>/dev/null
if [ $? -ne 7 ]; then
  echo "ABORT: something is already listening on 127.0.0.1:$PORT"
  exit 1
fi
"$OOKE" serve "$SITE" >"$TMP/serve.log" 2>&1 &
SERVER_PID=$!

# Wait for our server: it must still be running and answering /api/health.
TRIES=0
until [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "http://127.0.0.1:$PORT/api/health")" = "200" ]; do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "ABORT: ooke-toke serve failed to start on port $PORT; its log:"
    cat "$TMP/serve.log"
    SERVER_PID=
    exit 1
  fi
  TRIES=$((TRIES + 1))
  if [ "$TRIES" -ge 50 ]; then
    echo "ABORT: ooke-toke serve did not answer on port $PORT within 10s"
    exit 1
  fi
  sleep 0.2
done

check_status() {
  local desc="$1" url="$2" expect="$3"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url")
  if [ "$code" = "$expect" ]; then
    echo "PASS: $desc (HTTP $code)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc (expected $expect, got $code)"
    FAIL=$((FAIL + 1))
  fi
}

check_body() {
  local desc="$1" url="$2" pattern="$3"
  local body
  body=$(curl -s --max-time 5 "$url")
  if echo "$body" | grep -q "$pattern"; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc (pattern '$pattern' not found in response)"
    FAIL=$((FAIL + 1))
  fi
}

BASE="http://127.0.0.1:$PORT"

# --- Test static routes ---
check_status "GET /about returns 200"     "$BASE/about"     "200"
check_status "GET /testpage returns 200"   "$BASE/testpage"  "200"

# --- Test 404 ---
check_status "GET /nonexistent returns 404" "$BASE/nonexistent" "404"

# --- Test API handler ---
check_status "GET /api/health returns 200" "$BASE/api/health" "200"
check_body   "GET /api/health returns JSON" "$BASE/api/health" '"status"'

# --- Test content-type on API ---
CT=$(curl -sI --max-time 5 "$BASE/api/health" | grep -i "content-type" | tr -d '\r')
if echo "$CT" | grep -qi "application/json"; then
  echo "PASS: /api/health Content-Type is application/json"
  PASS=$((PASS + 1))
else
  echo "FAIL: /api/health Content-Type wrong: $CT"
  FAIL=$((FAIL + 1))
fi

# --- Summary ---
echo ""
echo "=== Router Live Tests: $PASS passed, $FAIL failed ==="
exit $FAIL
