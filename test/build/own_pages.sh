#!/bin/sh
# Story 134.47 (1): a handler page added to ooke's OWN pages/ builds and serves.
#
# gen_handlers.sh puts every pages/*.tk with f=get( or f=post( into
# src/_handlers.tk, but ooke's Makefile compiled none of those pages: the only
# handler page ooke ships, pages/api/health.tk, is m=ooke.apihealth, which the
# Makefile builds from src/apihealth.tk.  So a new handler page failed the
# registry with E2030 (unresolved import) and `make` stopped.  The Makefile
# now compiles each such page (scripts/handler_pages.sh lists them), searches
# its directory for the registry, and links it.
#
# A copy of this tree (tracked files, plus the already-built src/ooke modules
# so only what the new pages touch is rebuilt) gets two pages -- pages/hxtop.tk
# and pages/hx/deep.tk -- and is built with make; its binary then serves
# testproj and must answer both routes and the built-in /api/health.
#
# Negative control (2026-09-28): the same copy with main's Makefile stops at
# the registry: E2030 for page.hxtop.
#
# Usage: test/build/own_pages.sh [path/to/ooke-toke]  (run by `make test`;
# needs TOKE_ROOT, and TKC if not $TOKE_ROOT/toke)
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
[ -n "${TOKE_ROOT:-}" ] || { echo "error: TOKE_ROOT is required" >&2; exit 2; }
TKC=${TKC:-$TOKE_ROOT/toke}
command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-own-pages.XXXXXX") || exit 2
pid=""
cleanup() { [ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

echo "=== a handler page in ooke's own pages/ builds and serves (134.47) ==="

tree=$tmp/ooke
mkdir -p "$tree"
git ls-files -z | (cd "$ROOT" && xargs -0 tar cf -) | (cd "$tree" && tar xf -) || exit 2
# Built modules, timestamps kept, so make rebuilds only what the pages touch.
[ -d src/ooke ] && cp -Rp src/ooke "$tree/src/" 2>/dev/null
for f in src/_floor.tk src/*.tki; do [ -f "$f" ] && cp -p "$f" "$tree/$f"; done

mkdir -p "$tree/pages/hx"
printf 'm=page.hxtop;\ni=http:std.http;\n\nf=get(req:i64):i64{\n  <http.resok("hxtop")\n};\n' >"$tree/pages/hxtop.tk"
printf 'm=page.hxdeep;\ni=http:std.http;\n\nf=get(req:i64):i64{\n  <http.resok("hxdeep")\n};\n' >"$tree/pages/hx/deep.tk"

if (cd "$tree" && make --no-print-directory TOKE_ROOT="$TOKE_ROOT" TKC="$TKC" ooke-toke) >"$tmp/make.out" 2>&1; then
  ok "make: builds with two extra handler pages"
else
  bad "make: failed with two extra handler pages"
  grep -E 'E[0-9]{4}|Error|error:' "$tmp/make.out" | grep -v 'warning' | head -4 | cut -c1-240 | sed 's/^/       /'
fi

port=$(( 20000 + (($$ + 3001) % 20000) ))
proj=$tmp/proj
cp -R "$ROOT/testproj" "$proj" && rm -rf "$proj/build" || exit 2
awk -v port="$port" '/^port = / { print "port = " port; next } /^workers = / { print "workers = 1"; next } { print }' \
  "$ROOT/testproj/ooke.toml" >"$proj/ooke.toml"

if [ -x "$tree/ooke-toke" ]; then
  (cd "$proj" && exec "$tree/ooke-toke" serve) >"$tmp/serve.out" 2>"$tmp/serve.err" &
  pid=$!
  i=0; up=0
  while [ $i -lt 50 ]; do
    kill -0 "$pid" 2>/dev/null || break
    curl -s --max-time 2 -o /dev/null "http://127.0.0.1:$port/" 2>/dev/null && { up=1; break; }
    sleep 0.2; i=$((i+1))
  done
  if [ $up -eq 1 ]; then
    for r in "/hxtop hxtop" "/hx/deep hxdeep"; do
      set -- $r
      body=$(curl -s --max-time 2 "http://127.0.0.1:$port$1")
      if [ "$body" = "$2" ]; then ok "serves: GET $1 answers $2"; else bad "serves: GET $1 returned '$body'"; fi
    done
    if curl -s --max-time 2 "http://127.0.0.1:$port/api/health" | grep -q '"status":"ok"'
    then ok "serves: the built-in /api/health still answers"; else bad "serves: /api/health does not answer"; fi
  else
    bad "serves: the binary did not start"; tail -5 "$tmp/serve.err" | sed 's/^/       /'
  fi
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=""
else
  bad "serves: no binary was built"
fi

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
