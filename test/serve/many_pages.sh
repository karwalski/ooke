#!/bin/sh
# Story 138.7 (O-2, loke handoff 2026-09-27): an application with more pages
# than toke's default import cap compiles and serves every page.
#
# scripts/gen_handlers.sh writes ONE _handlers.tk that imports every page
# module plus std.http. toke caps a module at 32 imports by default (E9010,
# "compiler limit exceeded: too many imports"), so an app stopped compiling
# at 32 pages -- about 30 routes. The cap is raised per compile with
# --max-imports=N, and nothing in ooke set it. gen_app_makefile.sh (and ooke's
# own Makefile) now pass --max-imports=<the registry's import count> when
# that count exceeds 32.
#
#   registry  the generated _handlers.tk has NPAGES + 1 imports, and
#             Makefile.serve compiles it with --max-imports=NPAGES+1
#   compile   `ooke compile` on a NPAGES-page app exits 0 and writes the binary
#   serves    the first, a middle and the last page each answer with their own
#             body, so every page was registered, not just the first 31
#   small     an app under the cap gets no --max-imports (its build line is
#             unchanged; generated only, not built)
#
# Negative control (2026-09-28): run with an ooke-toke built from main
# b5b198f, whose scripts/gen_app_makefile.sh has no --max-imports, "compile"
# fails with E9010 at the registry's 33rd import (i=p32:page.p32) and the
# test reports 3 failures; with this branch it reports 0.
#
# Usage: test/serve/many_pages.sh [path/to/ooke-toke] [npages]  (run by `make test`)
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
NPAGES=${2:-40}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-pages.XXXXXX") || exit 2
pid=""
cleanup() { [ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

port=$(( 20000 + (($$ + 7919) % 20000) ))

# mkapp DIR N : an app with N pages, pages/pNN.tk answering GET /pNN with "pageNN"
mkapp() {
  mkdir -p "$1/pages" "$1/templates" "$1/content" || exit 2
  awk -v port="$port" '/^port = / { print "port = " port; next } { print }' \
    "$ROOT/testproj/ooke.toml" >"$1/ooke.toml"
  i=1
  while [ $i -le "$2" ]; do
    n=$(printf '%02d' $i)
    printf 'm=page.p%s;\ni=http:std.http;\n\nf=get(req:i64):i64{\n  <http.resok("page%s")\n};\n' "$n" "$n" >"$1/pages/p$n.tk"
    i=$((i+1))
  done
}

echo "=== an app with $NPAGES pages compiles past the 32-import cap (138.7 O-2) ==="

proj=$tmp/big
mkapp "$proj" "$NPAGES"

if (cd "$tmp" && "$BIN" compile big) >"$tmp/compile.out" 2>&1; then
  ok "compile: ooke compile exits 0 for $NPAGES pages"
else
  bad "compile: ooke compile exited non-zero for $NPAGES pages"
  grep -E 'error|E9010' "$tmp/compile.out" | grep -v 'warning generated' | head -4 | cut -c1-240 | sed 's/^/       /'
fi

nimp=$(grep -c '^i=' "$proj/_handlers.tk" 2>/dev/null || echo 0)
if [ "$nimp" -eq $((NPAGES + 1)) ]; then ok "registry: _handlers.tk imports $nimp modules ($NPAGES pages + std.http)"
else bad "registry: _handlers.tk imports $nimp modules, want $((NPAGES + 1))"; fi
if grep -q -- "--max-imports=$((NPAGES + 1)) " "$proj/Makefile.serve" 2>/dev/null
then ok "registry: Makefile.serve compiles it with --max-imports=$((NPAGES + 1))"
else bad "registry: Makefile.serve does not pass --max-imports=$((NPAGES + 1))"; fi

appname=$(sed -n 's/^name *= *"\(.*\)"/\1/p' "$proj/ooke.toml" | head -1)
app=$proj/build/$appname
if [ -n "$app" ] && [ -x "$app" ]; then
  ok "compile: $(basename "$app") written"
  (cd "$proj" && exec "$app" .) >"$tmp/app.out" 2>"$tmp/app.err" &
  pid=$!
  i=0; up=1
  while [ $i -lt 50 ]; do
    kill -0 "$pid" 2>/dev/null || { up=0; break; }
    curl -s --max-time 2 -o /dev/null "http://127.0.0.1:$port/p01" 2>/dev/null && break
    sleep 0.2; i=$((i+1))
  done
  [ $i -ge 50 ] && up=0
  if [ $up -eq 1 ]; then
    mid=$(printf '%02d' $(( (NPAGES + 1) / 2 )))
    last=$(printf '%02d' "$NPAGES")
    for n in 01 "$mid" "$last"; do
      body=$(curl -s --max-time 2 "http://127.0.0.1:$port/p$n")
      if [ "$body" = "page$n" ]; then ok "serves: GET /p$n answers page$n"
      else bad "serves: GET /p$n returned '$body'"; fi
    done
  else
    bad "serves: the compiled binary did not start"; tail -5 "$tmp/app.err" | sed 's/^/       /'
  fi
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=""
else
  bad "compile: no binary under build/"
fi

# An app under the cap keeps the default: no --max-imports on its build line.
small=$tmp/small
mkapp "$small" 3
# Generation only (no build): the build line is what is under test.
if sh "$ROOT/scripts/gen_app_makefile.sh" "$small" "$ROOT" >"$tmp/small.out" 2>&1 && \
   grep -q -- '_handlers.tk$' "$small/Makefile.serve" && \
   ! grep -q -- '--max-imports' "$small/Makefile.serve"
then ok "small: a 3-page app's Makefile.serve has no --max-imports"
else bad "small: a 3-page app's generation failed or got --max-imports"; tail -3 "$tmp/small.out" | sed 's/^/       /'; fi

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
