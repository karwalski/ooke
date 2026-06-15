#!/bin/bash
# Run Playwright browser tests against an ooke dev server
# Usage: ./run_playwright.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PORT=3099
OOKE="$PROJECT_DIR/ooke-toke"
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "Stopping ooke server (PID $SERVER_PID)..."
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
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
echo "=== Starting ooke dev server on port $PORT ==="
cd "$PROJECT_DIR"
PORT=$PORT $OOKE serve &
SERVER_PID=$!

# Wait for server to become ready
echo "Waiting for server..."
TRIES=0
MAX_TRIES=30
while ! curl -s "http://localhost:$PORT/api/health" > /dev/null 2>&1; do
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
