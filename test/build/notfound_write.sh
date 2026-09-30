#!/bin/sh
# Story 121.67 (2): `ooke build` reports a 404.html it could not write.
#
# The 404 pass rendered templates/errors/404.tkt and matched file.write to a
# bool; a failed write was dropped, so the site shipped with no 404.html and
# the build exited 0. (A 404 template that fails to RENDER already fails the
# build, 121.59.) A project with a 404 template is built twice:
#
#   blocked   build/404.html is a directory, so the write fails: build exits
#             non-zero and the error names build/404.html
#   control   nothing in the way: build exits 0 and writes 404.html. The
#             project has no other page, so the 404 pass is the first to
#             need build/ -- at 50b2baf this case failed too: build/ was never
#             made, the write failed silently, and no 404.html was written
#
# Usage: test/build/notfound_write.sh [path/to/ooke-toke]   (run by `make test`)
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-404.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); grep '"level":"error"' "$tmp/out" | tail -3 | cut -c1-200 | sed 's/^/       /'; }

echo "=== ooke build reports a 404.html it could not write (121.67 2) ==="

P=$tmp/proj
mkdir -p "$P/pages" "$P/templates/errors" || exit 2
printf '<h1>not found</h1>\n' >"$P/templates/errors/404.tkt"
printf '[site]\nname = "n"\n' >"$P/ooke.toml"

mkdir -p "$P/build/404.html"
"$BIN" build "$P" >"$tmp/out" 2>&1; rc=$?
if [ $rc -ne 0 ] && grep '"level":"error"' "$tmp/out" | grep -q "could not write $P/build/404.html"
then ok "blocked: build exits $rc naming build/404.html"
else bad "blocked: rc=$rc, no error naming 404.html"; fi

rm -rf "$P/build"
"$BIN" build "$P" >"$tmp/out" 2>&1; rc=$?
if [ $rc -eq 0 ] && [ -s "$P/build/404.html" ]
then ok "control: with nothing in the way, build exits 0 and writes 404.html"
else bad "control: rc=$rc"; fi

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
