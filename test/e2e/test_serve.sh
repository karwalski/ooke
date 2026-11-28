#!/bin/bash
# Build the website with ooke, then serve its build/ from a small toke program
# (http.getstatic + http.servedir) and check it over HTTP.
#
# Story 127.562: no fixed port. The test server used to be compiled with
# http.serve(3099) and polled on localhost:3099, so anything else on 3099
# could answer for it. The port is now one freeport (test/support/freeport.sh)
# found free on 127.0.0.1, or $OOKE_E2E_PORT if set, and is written into the
# test program before it is compiled. The program, its IR and its binary go in
# a temporary directory, not fixed names under /tmp.
#
# Usage: test/e2e/test_serve.sh
#   WEBSITE_DIR    site to build and serve (default: ~/tk/toke-website;
#                  `ooke-toke build` writes its build output there)
#   OOKE           ooke binary (default: this repository's ooke-toke)
#   TOKE_ROOT      toke tree with a built compiler (default: ~/tk/toke)
#   OOKE_E2E_PORT  port to use instead of a free one

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
. "$ROOT/test/support/freeport.sh"
PASS=0; FAIL=0
WEBSITE_DIR=${WEBSITE_DIR:-$HOME/tk/toke-website}
OOKE=${OOKE:-$ROOT/ooke-toke}
TOKE_ROOT=${TOKE_ROOT:-$HOME/tk/toke}
TOKE=$TOKE_ROOT/toke
STDLIB=$TOKE_ROOT/src/stdlib
VENDOR=$TOKE_ROOT/stdlib/vendor
PORT=${OOKE_E2E_PORT:-$(freeport)} || exit 2
SERVER_PID=
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ooke-e2e-serve.XXXXXX") || exit 2

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

# Build content
cd "$WEBSITE_DIR" || { echo "FAIL: no website at $WEBSITE_DIR"; exit 1; }
"$OOKE" build 2>/dev/null

# Build a test server binary listening on $PORT
cat << 'TKEOF' | sed "s/@PORT@/$PORT/" > "$TMP/test_serve.tk"
m=testserve;
i=http:std.http;
f=main():i64{
  http.getstatic("/health"; "{\"ok\":true}");
  http.servedir("/";"build");
  http.serve(@PORT@);
  <0;
};
TKEOF
grep -q "http.serve($PORT);" "$TMP/test_serve.tk" || { echo "FAIL: could not write port $PORT into the test server"; exit 1; }

"$TOKE" --emit-llvm --out "$TMP/test_serve.ll" "$TMP/test_serve.tk" 2>/dev/null
clang -std=c99 -D_GNU_SOURCE -O1 -iquote $STDLIB \
  -I$VENDOR/cmark/src -I$VENDOR/tomlc99 -Wno-pedantic -DTK_HAVE_OPENSSL \
  -I/opt/homebrew/include -L/opt/homebrew/lib \
  -x ir "$TMP/test_serve.ll" \
  -x c $(find $STDLIB -name "*.c" | grep -v llm_tool | grep -v secure_mem | grep -v infer_stream | tr "\n" " ") \
  $(find $VENDOR/cmark/src -name "*.c" | grep -v main.c | tr "\n" " ") \
  $VENDOR/tomlc99/toml.c \
  -o "$TMP/test_serve_bin" -lssl -lcrypto -lz -lm -lsqlite3 -lpthread \
  -framework Security -framework CoreFoundation 2>/dev/null

if [ ! -f "$TMP/test_serve_bin" ]; then
  echo "FAIL: could not build test server"
  exit 1
fi

# Nothing may already listen on $PORT (an $OOKE_E2E_PORT someone else holds):
# curl must be refused (exit 7) before our server starts.
curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$PORT/" 2>/dev/null
if [ $? -ne 7 ]; then
  echo "FAIL: something is already listening on 127.0.0.1:$PORT"
  exit 1
fi

# Start server and wait until it answers, failing if it exits first
"$TMP/test_serve_bin" >"$TMP/serve.log" 2>&1 &
SERVER_PID=$!
TRIES=0
until [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "http://127.0.0.1:$PORT/health")" = "200" ]; do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "FAIL: test server exited before answering on port $PORT; its log:"
    cat "$TMP/serve.log"
    SERVER_PID=
    exit 1
  fi
  TRIES=$((TRIES + 1))
  if [ "$TRIES" -ge 50 ]; then
    echo "FAIL: test server did not answer on port $PORT within 10s"
    exit 1
  fi
  sleep 0.2
done

check() {
  local desc=$1 url=$2 expect=$3
  local code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url")
  if [ "$code" = "$expect" ]; then
    echo "PASS: $desc (HTTP $code)"
    PASS=$((PASS+1))
  else
    echo "FAIL: $desc (expected $expect, got $code)"
    FAIL=$((FAIL+1))
  fi
}

BASE="http://127.0.0.1:$PORT"
check "health endpoint" "$BASE/health" "200"
check "homepage" "$BASE/" "200"
check "docs page" "$BASE/docs/" "200"
check "CSS" "$BASE/static/css/style.css" "200"
check "nonexistent" "$BASE/nonexistent-page" "404"

# Check content-type
CT=$(curl -sI --max-time 5 "$BASE/" | grep -i "content-type" | tr -d '\r')
if echo "$CT" | grep -qi "text/html"; then
  echo "PASS: homepage Content-Type is text/html"
  PASS=$((PASS+1))
else
  echo "FAIL: homepage Content-Type wrong: $CT"
  FAIL=$((FAIL+1))
fi

# Check health returns JSON
BODY=$(curl -s --max-time 5 "$BASE/health")
if echo "$BODY" | grep -q '"ok"'; then
  echo "PASS: health returns JSON"
  PASS=$((PASS+1))
else
  echo "FAIL: health body wrong: $BODY"
  FAIL=$((FAIL+1))
fi

echo ""
echo "=== Serve Tests: $PASS passed, $FAIL failed ==="
exit $FAIL
