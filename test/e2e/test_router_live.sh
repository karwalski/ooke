#!/bin/bash
# 89.1.3 - Router test via live ooke server
# Tests static routes, 404 handling, and API handler against running server.

OOKE_DIR=/Users/matthew.watt/tk/toke-ooke
OOKE="$OOKE_DIR/ooke-toke"
PORT=3000
PASS=0
FAIL=0
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

if [ ! -f "$OOKE_DIR/ooke.toml" ]; then
  echo "ABORT: ooke.toml missing at $OOKE_DIR"
  exit 1
fi

echo "=== Router Live Test (89.1.3) ==="
echo "Binary: $OOKE"
echo "Port:   $PORT"
echo ""

# --- Start server ---
cd "$OOKE_DIR"
"$OOKE" serve &
SERVER_PID=$!
sleep 3

# Check server started
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  echo "ABORT: ooke-toke serve failed to start"
  exit 1
fi

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

# --- Test static routes ---
check_status "GET /about returns 200"     "http://localhost:$PORT/about"     "200"
check_status "GET /testpage returns 200"   "http://localhost:$PORT/testpage"  "200"

# --- Test 404 ---
check_status "GET /nonexistent returns 404" "http://localhost:$PORT/nonexistent" "404"

# --- Test API handler ---
check_status "GET /api/health returns 200" "http://localhost:$PORT/api/health" "200"
check_body   "GET /api/health returns JSON" "http://localhost:$PORT/api/health" '"status"'

# --- Test content-type on API ---
CT=$(curl -sI --max-time 5 "http://localhost:$PORT/api/health" | grep -i "content-type" | tr -d '\r')
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
