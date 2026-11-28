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
# Story 127.563: three defects that made this script fail on every run.
#  1. It linked the server with a hand-kept clang line naming toke's stdlib C
#     files, which stopped linking against toke main (CoreGraphics/ImageIO
#     symbols, tk_infer_stream_cleanup), so it always said "could not build
#     test server" -- the defect scripts/testmod.sh was retired for (121.83).
#     The compiler, flags, C sources and link flags now come from
#     `make print-build-vars` with the test program as DEPS_EXTRA_TK, i.e.
#     from `tkc --emit-deps` (121.76), as test/run_tests.sh gets them.
#  2. It ran `ooke build` in the real site and then served the site's build/,
#     which ooke does not write: toke-website's [build] output is build-docs/
#     (its build/ is assembled by its own scripts and has no index.html, the
#     homepage being a route since toke 134.8), so "/" was a 404. It now builds
#     a temporary copy of the site, with any previous output removed, and
#     serves the directory that copy's ooke.toml names in [build] output --
#     what `ooke build` just wrote -- so the site checkout is never written to.
#  3. The Content-Type check grepped for "content-type" anywhere in the
#     headers, so X-Content-Type-Options satisfied it. It now requires exactly
#     one Content-Type header whose media type is text/html.
#
# Usage: test/e2e/test_serve.sh
#   WEBSITE_DIR    site to build and serve (default: ~/tk/toke-website; only
#                  read -- its pages/ templates/ static/ models/ content/
#                  islands/ and ooke.toml are copied to a temporary directory)
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
PORT=${OOKE_E2E_PORT:-$(freeport)} || exit 2
SERVER_PID=
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ooke-e2e-serve.XXXXXX") || exit 2
SITE=$TMP/site

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

[ -x "$OOKE" ] || { echo "FAIL: no ooke binary at $OOKE"; exit 1; }
[ -f "$WEBSITE_DIR/ooke.toml" ] || { echo "FAIL: no ooke site at $WEBSITE_DIR"; exit 1; }

# Build a temporary copy of the site (the staging test_router_live.sh uses)
mkdir "$SITE" || exit 2
for d in pages templates static models content islands; do
  [ -e "$WEBSITE_DIR/$d" ] && cp -R "$WEBSITE_DIR/$d" "$SITE/"
done
cp "$WEBSITE_DIR/ooke.toml" "$SITE/" || exit 2
# [build] output, as ooke reads it (default build/), without the trailing slash
OUT=$(awk '
  /^\[/ { sec = $0; next }
  sec == "[build]" && /^output[ \t]*=/ {
    v = $0; sub(/^[^=]*=[ \t]*"/, "", v); sub(/".*$/, "", v); print v; exit
  }' "$SITE/ooke.toml")
OUT=${OUT:-build/}
OUT=${OUT%/}
case $OUT in
  ''|/*|*..*|*[!A-Za-z0-9._/-]*) echo "FAIL: unusable [build] output '$OUT' in $WEBSITE_DIR/ooke.toml"; exit 1 ;;
esac
rm -rf "${SITE:?}/$OUT"
if ! (cd "$SITE" && "$OOKE" build) >"$TMP/build.log" 2>&1; then
  echo "FAIL: ooke build failed for a copy of $WEBSITE_DIR; its log:"
  tail -20 "$TMP/build.log"
  exit 1
fi
[ -d "$SITE/$OUT" ] || { echo "FAIL: ooke build wrote no $OUT/"; exit 1; }

# Build a test server binary listening on $PORT, serving $OUT (relative to $SITE)
cat << 'TKEOF' | sed -e "s/@PORT@/$PORT/" -e "s|@DIR@|$OUT|" > "$TMP/test_serve.tk"
m=testserve;
i=http:std.http;
f=main():i64{
  http.getstatic("/health"; "{\"ok\":true}");
  http.servedir("/";"@DIR@");
  http.serve(@PORT@);
  <0;
};
TKEOF
grep -q "http.serve($PORT);" "$TMP/test_serve.tk" || { echo "FAIL: could not write port $PORT into the test server"; exit 1; }

# Capability grant (ADR-0010), as scripts/gen_app_makefile.sh writes one for an
# app's serve binary: without it the server exits with CAP001 on its first
# read. It reads $OUT and listens; it writes and spawns nothing.
cat > "$TMP/test_serve.tkc.toml" << 'CAPS'
[capabilities]
fs_read = true
net = true
enforce = true
CAPS

# Compiler, flags, stdlib/vendor C sources and link flags: from the Makefile,
# which asks tkc --emit-deps (121.76) -- nothing about the link is kept here.
vars=$(make -s --no-print-directory print-build-vars TOKE_ROOT="$TOKE_ROOT" \
         DEPS_EXTRA_TK="$TMP/test_serve.tk" 2>"$TMP/deps.log") || {
  echo "FAIL: 'make print-build-vars' could not derive the test server's link set:"
  cat "$TMP/deps.log"
  exit 1
}
eval "$vars"
if ! "$TKC" --config="$TMP/test_serve.tkc.toml" --emit-llvm --out "$TMP/test_serve.ll" "$TMP/test_serve.tk" >"$TMP/cc.log" 2>&1 ||
   ! clang $CFLAGS $LDFLAGS -x ir "$TMP/test_serve.ll" -x c $STDLIB_SRCS $VENDOR_SRCS \
       -o "$TMP/test_serve_bin" $LIBS >>"$TMP/cc.log" 2>&1 ||
   [ ! -x "$TMP/test_serve_bin" ]; then
  echo "FAIL: could not build test server; compiler output:"
  grep -v -e 'warning' -e '^ *[0-9]* |' -e '^ *|' "$TMP/cc.log" | tail -20
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
(cd "$SITE" && exec "$TMP/test_serve_bin") >"$TMP/serve.log" 2>&1 &
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

# Check content-type: exactly one Content-Type header (matched by name, so
# X-Content-Type-Options does not count) whose media type is text/html.
CT=$(curl -s -D - -o /dev/null --max-time 5 "$BASE/" | tr -d '\r' | grep -i '^content-type:')
if [ "$(printf '%s\n' "$CT" | grep -c .)" = 1 ] &&
   printf '%s\n' "$CT" | grep -Eiq '^content-type:[[:space:]]*text/html[[:space:]]*(;.*)?$'; then
  echo "PASS: homepage Content-Type is text/html"
  PASS=$((PASS+1))
else
  echo "FAIL: homepage Content-Type wrong: ${CT:-<none>}"
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
