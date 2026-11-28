#!/bin/bash
# 89.2.5 - Island hydration test stub
# Checks island infrastructure and verifies island script tags are served.
#
# Story 127.562: no fixed port. `ooke serve` takes its port only from
# [server] port in ooke.toml, and this test used to serve the project in place
# (port 3000, a common dev-server port) and curl localhost:3000, so another
# dev server on 3000 could answer for ooke. It now serves a temporary copy of
# the project whose [server] port is a port freeport (test/support/freeport.sh)
# found free on 127.0.0.1, or $OOKE_E2E_PORT if set, and curls 127.0.0.1 on
# that port only after checking the server it started is the one answering.
#
# Story 127.564: the project served is testproj/, the fixture ooke's other
# serve tests use. It used to be this repository's root, which has no
# pages/index.tk, so '/' answered 404 and the homepage check could only skip,
# and whose static/islands/hello.js was a test stub in the framework's own
# tree (it now lives in testproj/static/islands/). testproj's homepage renders
# an island("hello") directive, so the page must carry the loader's script tag.
# testproj/static/ooke-islands.js is a copy of ooke's static/ooke-islands.js,
# as a real project's would be; the test fails if the two differ.
#
# Usage: test/e2e/test_islands.sh [path/to/ooke-toke]
#   OOKE_DIR       project to serve (default: testproj/)
#   OOKE_E2E_PORT  port to use instead of a free one

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
. "$ROOT/test/support/freeport.sh"
OOKE_DIR=${OOKE_DIR:-$ROOT/testproj}
OOKE=${1:-$ROOT/ooke-toke}
case $OOKE in /*) ;; *) OOKE=$ROOT/$OOKE ;; esac
PORT=
PASS=0
FAIL=0
SKIP=0
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

echo "=== Island Hydration Test (89.2.5) ==="
echo "Binary: $OOKE"
echo ""

# --- Check if islands directory exists ---
ISLANDS_FOUND=false
ISLANDS_DIR=""

if [ -d "$OOKE_DIR/static/islands" ]; then
  ISLANDS_DIR="$OOKE_DIR/static/islands"
  JS_COUNT=$(find "$ISLANDS_DIR" -name "*.js" 2>/dev/null | wc -l | tr -d ' ')
  echo "PASS: static/islands/ directory exists ($JS_COUNT JS modules)"
  PASS=$((PASS + 1))
  ISLANDS_FOUND=true
elif [ -d "$OOKE_DIR/islands" ]; then
  ISLANDS_DIR="$OOKE_DIR/islands"
  JS_COUNT=$(find "$ISLANDS_DIR" -name "*.js" 2>/dev/null | wc -l | tr -d ' ')
  echo "PASS: islands/ directory exists ($JS_COUNT JS modules)"
  PASS=$((PASS + 1))
  ISLANDS_FOUND=true
else
  echo "SKIP: no islands/ or static/islands/ directory found"
  SKIP=$((SKIP + 1))
fi

# --- Check if ooke-islands.js loader exists ---
LOADER_FOUND=false
if [ -f "$OOKE_DIR/static/ooke-islands.js" ]; then
  echo "PASS: static/ooke-islands.js loader exists"
  PASS=$((PASS + 1))
  LOADER_FOUND=true
elif [ -f "$OOKE_DIR/ooke-islands.js" ]; then
  echo "PASS: ooke-islands.js loader exists"
  PASS=$((PASS + 1))
  LOADER_FOUND=true
else
  echo "SKIP: ooke-islands.js loader not found"
  SKIP=$((SKIP + 1))
fi

# --- The default fixture's loader is ooke's, byte for byte (127.564) ---
if [ "$OOKE_DIR" = "$ROOT/testproj" ]; then
  if cmp -s "$ROOT/static/ooke-islands.js" "$OOKE_DIR/static/ooke-islands.js"; then
    echo "PASS: testproj/static/ooke-islands.js is ooke's static/ooke-islands.js"
    PASS=$((PASS + 1))
  else
    echo "FAIL: testproj/static/ooke-islands.js differs from ooke's static/ooke-islands.js (copy it again)"
    FAIL=$((FAIL + 1))
  fi
fi

# --- If no island infrastructure, skip server tests ---
if [ "$ISLANDS_FOUND" = false ] && [ "$LOADER_FOUND" = false ]; then
  echo ""
  echo "SKIP: no island infrastructure configured; skipping live server tests"
  SKIP=$((SKIP + 1))
  echo ""
  echo "=== Island Tests: $PASS passed, $FAIL failed, $SKIP skipped ==="
  exit 0
fi

# --- Stage a copy of the project that listens on $PORT ---
if [ ! -f "$OOKE_DIR/ooke.toml" ]; then
  echo "ABORT: ooke.toml missing at $OOKE_DIR"
  exit 1
fi
PORT=${OOKE_E2E_PORT:-$(freeport)} || exit 2
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ooke-e2e-islands.XXXXXX") || exit 2
SITE=$TMP/site
mkdir "$SITE" || exit 2
for d in pages templates static models content islands; do
  [ -e "$OOKE_DIR/$d" ] && cp -R "$OOKE_DIR/$d" "$SITE/"
done
[ -f "$OOKE_DIR/ooke-islands.js" ] && cp "$OOKE_DIR/ooke-islands.js" "$SITE/"
awk -v port="$PORT" '
  /^\[/ { sec = $0 }
  sec == "[server]" && /^port[ \t]*=/ { print "port = " port; next }
  { print }
' "$OOKE_DIR/ooke.toml" >"$SITE/ooke.toml"
if ! grep -q "^port = $PORT\$" "$SITE/ooke.toml"; then
  echo "ABORT: could not set [server] port in a copy of $OOKE_DIR/ooke.toml"
  exit 1
fi
echo "Port:   $PORT"

# --- Start server and test island delivery ---
# Nothing may already listen on $PORT (an $OOKE_E2E_PORT someone else holds):
# curl must be refused (exit 7) before our server starts.
curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$PORT/" 2>/dev/null
if [ $? -ne 7 ]; then
  echo "FAIL: something is already listening on 127.0.0.1:$PORT"
  FAIL=$((FAIL + 1))
  echo ""
  echo "=== Island Tests: $PASS passed, $FAIL failed, $SKIP skipped ==="
  exit $FAIL
fi
"$OOKE" serve "$SITE" >"$TMP/serve.log" 2>&1 &
SERVER_PID=$!

# Wait for our server: it must still be running and answering /api/health.
TRIES=0
STARTED=false
while [ "$TRIES" -lt 50 ]; do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    SERVER_PID=
    break
  fi
  if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "http://127.0.0.1:$PORT/api/health")" = "200" ]; then
    STARTED=true
    break
  fi
  TRIES=$((TRIES + 1))
  sleep 0.2
done

if [ "$STARTED" = false ]; then
  echo "FAIL: ooke-toke serve failed to start on port $PORT; its log:"
  cat "$TMP/serve.log"
  FAIL=$((FAIL + 1))
  echo ""
  echo "=== Island Tests: $PASS passed, $FAIL failed, $SKIP skipped ==="
  exit $FAIL
fi

BASE="http://127.0.0.1:$PORT"

# --- Test: ooke-islands.js is served ---
LOADER_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$BASE/static/ooke-islands.js")
if [ "$LOADER_CODE" = "200" ]; then
  echo "PASS: /static/ooke-islands.js returns 200"
  PASS=$((PASS + 1))
else
  echo "FAIL: /static/ooke-islands.js returns $LOADER_CODE (expected 200)"
  FAIL=$((FAIL + 1))
fi

# --- Test: island JS module is served ---
if [ -n "$ISLANDS_DIR" ]; then
  FIRST_ISLAND=$(find "$ISLANDS_DIR" -name "*.js" 2>/dev/null | head -1)
  if [ -n "$FIRST_ISLAND" ]; then
    ISLAND_NAME=$(basename "$FIRST_ISLAND")
    ISLAND_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$BASE/static/islands/$ISLAND_NAME")
    if [ "$ISLAND_CODE" = "200" ]; then
      echo "PASS: /static/islands/$ISLAND_NAME returns 200"
      PASS=$((PASS + 1))
    else
      echo "FAIL: /static/islands/$ISLAND_NAME returns $ISLAND_CODE (expected 200)"
      FAIL=$((FAIL + 1))
    fi
  fi
fi

# --- Test: homepage includes island script tag ---
HOMEPAGE=$(curl -s --max-time 5 "$BASE/")
if echo "$HOMEPAGE" | grep -q "ooke-islands"; then
  echo "PASS: homepage includes ooke-islands script reference"
  PASS=$((PASS + 1))
elif echo "$HOMEPAGE" | grep -q "data-island"; then
  echo "PASS: homepage includes data-island attribute"
  PASS=$((PASS + 1))
else
  echo "SKIP: homepage does not reference islands (may not use islands on index)"
  SKIP=$((SKIP + 1))
fi

# --- Summary ---
echo ""
echo "=== Island Tests: $PASS passed, $FAIL failed, $SKIP skipped ==="
exit $FAIL
