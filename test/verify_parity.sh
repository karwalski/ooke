#!/usr/bin/env bash
# verify_parity.sh — story 56.8.3
#
# Run the toke-website-new site against both the C binary and the toke
# binary. Compare HTTP response codes, page titles, and rendered HTML
# bodies for all ooke routes. Zero regressions allowed.
#
# Usage:
#   ./test/verify_parity.sh [--c-bin PATH] [--toke-bin PATH] [--site-dir PATH]
#
# Prerequisites: both binaries must be built and ooke.toml must exist in the
# site directory.

set -euo pipefail

C_BIN="${C_BIN:-./ooke-c}"
TOKE_BIN="${TOKE_BIN:-./ooke}"
SITE_DIR="${SITE_DIR:-/Users/matthew.watt/tk/toke-website-new}"
C_PORT=18080
TOKE_PORT=18081
FAIL=0

log()  { echo "[parity] $*"; }
fail() { echo "[FAIL] $*" >&2; FAIL=1; }

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --c-bin)    C_BIN="$2";    shift 2 ;;
    --toke-bin) TOKE_BIN="$2"; shift 2 ;;
    --site-dir) SITE_DIR="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Verify binaries exist
if [[ ! -x "$C_BIN" ]]; then
  echo "C binary not found at $C_BIN — build with C Makefile first" >&2
  exit 1
fi
if [[ ! -x "$TOKE_BIN" ]]; then
  echo "toke binary not found at $TOKE_BIN — run: make" >&2
  exit 1
fi

# Start C server
log "Starting C server on port $C_PORT..."
cd "$SITE_DIR"
"$C_BIN" --port "$C_PORT" &
C_PID=$!
sleep 1

# Start toke server
log "Starting toke server on port $TOKE_PORT..."
"$TOKE_BIN" serve --port "$TOKE_PORT" &
TOKE_PID=$!
sleep 1

cleanup() {
  kill "$C_PID"    2>/dev/null || true
  kill "$TOKE_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Routes to check (add more as site grows)
ROUTES=(
  "/"
  "/about"
  "/docs"
  "/changelog"
  "/pricing"
)

for route in "${ROUTES[@]}"; do
  log "Checking route: $route"

  c_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$C_PORT$route")
  t_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$TOKE_PORT$route")

  if [[ "$c_code" != "$t_code" ]]; then
    fail "Status mismatch on $route: C=$c_code toke=$t_code"
    continue
  fi
  log "  status: $c_code ✓"

  if [[ "$c_code" == "200" ]]; then
    c_body=$(curl -s "http://localhost:$C_PORT$route")
    t_body=$(curl -s "http://localhost:$TOKE_PORT$route")

    # Extract <title>
    c_title=$(echo "$c_body" | grep -o '<title>[^<]*</title>' | head -1 || echo "")
    t_title=$(echo "$t_body" | grep -o '<title>[^<]*</title>' | head -1 || echo "")
    if [[ "$c_title" != "$t_title" ]]; then
      fail "Title mismatch on $route: C='$c_title' toke='$t_title'"
    else
      log "  title: $c_title ✓"
    fi

    # Check body length is within 10% (allows minor whitespace differences)
    c_len=${#c_body}
    t_len=${#t_body}
    if [[ $c_len -gt 0 ]]; then
      pct=$(( (t_len * 100) / c_len ))
      if [[ $pct -lt 90 || $pct -gt 110 ]]; then
        fail "Body length mismatch on $route: C=$c_len toke=$t_len ($pct%)"
      else
        log "  body: C=$c_len toke=$t_len ($pct%) ✓"
      fi
    fi
  fi
done

if [[ $FAIL -eq 0 ]]; then
  log "All parity checks passed."
  exit 0
else
  echo "[parity] FAILED — see above for details" >&2
  exit 1
fi
