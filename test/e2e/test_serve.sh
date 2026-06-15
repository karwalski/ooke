#!/bin/bash
PASS=0; FAIL=0; PORT=3099
WEBSITE_DIR=/Users/matthew.watt/tk/toke-website

# Build content
cd $WEBSITE_DIR
/Users/matthew.watt/tk/toke-ooke/ooke-toke build 2>/dev/null

# Build a test server binary
cat << 'TKEOF' > /tmp/test_serve.tk
m=testserve;
i=http:std.http;
f=main():i64{
  http.getstatic("/health"; "{\"ok\":true}");
  http.servedir("/";"build");
  http.serve(3099);
  <0;
};
TKEOF

TOKE=/Users/matthew.watt/tk/toke/toke
STDLIB=/Users/matthew.watt/tk/toke/src/stdlib
VENDOR=/Users/matthew.watt/tk/toke/stdlib/vendor

$TOKE --emit-llvm --out /tmp/test_serve.ll /tmp/test_serve.tk 2>/dev/null
clang -std=c99 -D_GNU_SOURCE -O1 -iquote $STDLIB \
  -I$VENDOR/cmark/src -I$VENDOR/tomlc99 -Wno-pedantic -DTK_HAVE_OPENSSL \
  -I/opt/homebrew/include -L/opt/homebrew/lib \
  -x ir /tmp/test_serve.ll \
  -x c $(find $STDLIB -name "*.c" | grep -v llm_tool | grep -v secure_mem | grep -v infer_stream | tr "\n" " ") \
  $(find $VENDOR/cmark/src -name "*.c" | grep -v main.c | tr "\n" " ") \
  $VENDOR/tomlc99/toml.c \
  -o /tmp/test_serve_bin -lssl -lcrypto -lz -lm -lsqlite3 -lpthread \
  -framework Security -framework CoreFoundation 2>/dev/null

if [ ! -f /tmp/test_serve_bin ]; then
  echo "FAIL: could not build test server"
  exit 1
fi

# Start server
/tmp/test_serve_bin &
SERVER_PID=$!
sleep 2

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

check "health endpoint" "http://localhost:$PORT/health" "200"
check "homepage" "http://localhost:$PORT/" "200"
check "docs page" "http://localhost:$PORT/docs/" "200"
check "CSS" "http://localhost:$PORT/static/css/style.css" "200"
check "nonexistent" "http://localhost:$PORT/nonexistent-page" "404"

# Check content-type
CT=$(curl -sI --max-time 5 http://localhost:$PORT/ | grep -i "content-type" | tr -d '\r')
if echo "$CT" | grep -qi "text/html"; then
  echo "PASS: homepage Content-Type is text/html"
  PASS=$((PASS+1))
else
  echo "FAIL: homepage Content-Type wrong: $CT"
  FAIL=$((FAIL+1))
fi

# Check health returns JSON
BODY=$(curl -s --max-time 5 http://localhost:$PORT/health)
if echo "$BODY" | grep -q '"ok"'; then
  echo "PASS: health returns JSON"
  PASS=$((PASS+1))
else
  echo "FAIL: health body wrong: $BODY"
  FAIL=$((FAIL+1))
fi

# Cleanup
kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null

echo ""
echo "=== Serve Tests: $PASS passed, $FAIL failed ==="
exit $FAIL
