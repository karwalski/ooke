#!/bin/bash
# Run Playwright browser tests against an ooke dev server
# Usage: ./run_playwright.sh
#   OOKE_E2E_PORT  port to use instead of a free one
#
# Story 127.562: no fixed port. This used to start `PORT=3099 ooke-toke serve`
# and poll localhost:3099, but ooke serve takes its port only from [server]
# port in ooke.toml (3000 here), so the server and the poll disagreed and
# whatever else listened on 3099 was what the tests reached. It now serves a
# temporary copy of the project whose [server] port is a port freeport
# (test/support/freeport.sh) found free on 127.0.0.1, or $OOKE_E2E_PORT if
# set, and exports OOKE_E2E_PORT, which playwright.config.js and ooke.spec.js
# read (they refuse to run without it).
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$PROJECT_DIR/test/support/freeport.sh"
OOKE="$PROJECT_DIR/ooke-toke"
SERVER_PID=""
TMP=""

cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "Stopping ooke server (PID $SERVER_PID)..."
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  if [ -n "$TMP" ]; then rm -rf "$TMP"; fi
}
trap cleanup EXIT

# --- Step 1: Check playwright is installed ---
echo "=== Checking Playwright installation ==="
if ! npx playwright --version 2>/dev/null; then
  echo "Playwright not found. Install with: npm install -D @playwright/test && npx playwright install"
  exit 1
fi
echo ""

# --- Step 2: Build the binary if needed ---
if [ ! -x "$OOKE" ]; then
  echo "=== Building ooke-toke binary ==="
  cd "$PROJECT_DIR"
  make
  echo ""
fi

# --- Step 3: Start ooke dev server on port $PORT ---
PORT=${OOKE_E2E_PORT:-$(freeport)}
export OOKE_E2E_PORT=$PORT
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ooke-e2e-playwright.XXXXXX")
SITE=$TMP/site
mkdir "$SITE"
for d in pages templates static models content islands; do
  if [ -e "$PROJECT_DIR/$d" ]; then cp -R "$PROJECT_DIR/$d" "$SITE/"; fi
done
awk -v port="$PORT" '
  /^\[/ { sec = $0 }
  sec == "[server]" && /^port[ \t]*=/ { print "port = " port; next }
  { print }
' "$PROJECT_DIR/ooke.toml" >"$SITE/ooke.toml"
if ! grep -q "^port = $PORT\$" "$SITE/ooke.toml"; then
  echo "ABORT: could not set [server] port in a copy of $PROJECT_DIR/ooke.toml"
  exit 1
fi
# Nothing may already listen on $PORT (an $OOKE_E2E_PORT someone else holds):
# curl must be refused (exit 7) before our server starts.
CURL_RC=0
curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$PORT/" || CURL_RC=$?
if [ "$CURL_RC" -ne 7 ]; then
  echo "ABORT: something is already listening on 127.0.0.1:$PORT"
  exit 1
fi

echo "=== Starting ooke dev server on port $PORT ==="
"$OOKE" serve "$SITE" &
SERVER_PID=$!

# Wait for our server to become ready (and fail if it exits instead)
echo "Waiting for server..."
TRIES=0
MAX_TRIES=30
while ! curl -sf -o /dev/null --max-time 1 "http://127.0.0.1:$PORT/api/health"; do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "ABORT: ooke server exited before answering on port $PORT"
    SERVER_PID=""
    exit 1
  fi
  TRIES=$((TRIES + 1))
  if [ "$TRIES" -ge "$MAX_TRIES" ]; then
    echo "ABORT: Server did not start within ${MAX_TRIES}s"
    exit 1
  fi
  sleep 1
done
echo "Server ready (PID $SERVER_PID)"
echo ""

# --- Step 4: Run Playwright tests ---
echo "=== Running Playwright tests ==="
cd "$SCRIPT_DIR"
npx playwright test --config=playwright.config.js
TEST_EXIT=$?
echo ""

# --- Step 5: Report results ---
if [ "$TEST_EXIT" -eq 0 ]; then
  echo "=== All Playwright tests passed ==="
else
  echo "=== Playwright tests failed (exit code $TEST_EXIT) ==="
fi

exit $TEST_EXIT
