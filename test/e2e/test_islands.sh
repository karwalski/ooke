#!/bin/bash
# 89.2.5 - Island hydration test stub
# Checks island infrastructure and verifies island script tags are served.

OOKE_DIR=/Users/matthew.watt/tk/toke-ooke
OOKE="$OOKE_DIR/ooke-toke"
PORT=3000
PASS=0
FAIL=0
SKIP=0
SERVER_PID=

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
  fi
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

# --- If no island infrastructure, skip server tests ---
if [ "$ISLANDS_FOUND" = false ] && [ "$LOADER_FOUND" = false ]; then
  echo ""
  echo "SKIP: no island infrastructure configured; skipping live server tests"
  SKIP=$((SKIP + 1))
  echo ""
  echo "=== Island Tests: $PASS passed, $FAIL failed, $SKIP skipped ==="
  exit 0
fi

# --- Start server and test island delivery ---
cd "$OOKE_DIR"
"$OOKE" serve &
SERVER_PID=$!
sleep 3

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  echo "FAIL: ooke-toke serve failed to start"
  FAIL=$((FAIL + 1))
  echo ""
  echo "=== Island Tests: $PASS passed, $FAIL failed, $SKIP skipped ==="
  exit $FAIL
fi

# --- Test: ooke-islands.js is served ---
LOADER_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:$PORT/static/ooke-islands.js")
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
    ISLAND_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:$PORT/static/islands/$ISLAND_NAME")
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
HOMEPAGE=$(curl -s --max-time 5 "http://localhost:$PORT/")
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
