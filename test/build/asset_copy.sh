#!/bin/sh
# Story 121.67 (1): `ooke build` reports a static asset it could not copy.
#
# buildcopyassets matched both file.mkdir and file.copy to a bool and dropped
# a failure: the asset was missing from the site, "assets copied" was one
# lower, and the build exited 0. A project with static/app.css and
# static/img/logo.txt is built three ways:
#
#   dirblocked   build/static is a regular file, so no directory under it can
#                be made: build exits non-zero and names the directory
#   fileblocked  build/static/app.css is a directory, so the copy fails:
#                build exits non-zero and names the asset; the other asset is
#                still copied (one bad file does not stop the rest)
#   control      nothing in the way: build exits 0 and copies both
#   both         (121.69 3) a page is skipped (build/404.html is a directory)
#                AND an asset is not copied: both summaries are printed. The
#                "assets not copied" line was never reached, because the
#                "pages skipped" branch returned first
#
# Usage: test/build/asset_copy.sh [path/to/ooke-toke]   (run by `make test`)
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-assets.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); grep '"level":"error"' "$tmp/out" | tail -3 | cut -c1-200 | sed 's/^/       /'; }

echo "=== ooke build reports a static asset it could not copy (121.67 1) ==="

P=$tmp/proj
mkdir -p "$P/pages" "$P/static/img" || exit 2
printf 'body{}\n' >"$P/static/app.css"
printf 'logo\n' >"$P/static/img/logo.txt"
printf '[site]\nname = "a"\n' >"$P/ooke.toml"

mkdir -p "$P/build" && echo x >"$P/build/static"
"$BIN" build "$P" >"$tmp/out" 2>&1; rc=$?
if [ $rc -ne 0 ] && grep '"level":"error"' "$tmp/out" | grep -q "could not create the directory $P/build/static"
then ok "dirblocked: build exits $rc naming the directory under build/static"
else bad "dirblocked: rc=$rc, no error naming the directory"; fi

rm -rf "$P/build"; mkdir -p "$P/build/static/app.css"
"$BIN" build "$P" >"$tmp/out" 2>&1; rc=$?
if [ $rc -ne 0 ] && grep '"level":"error"' "$tmp/out" | grep -q "could not copy $P/static/app.css"
then ok "fileblocked: build exits $rc naming the asset it could not copy"
else bad "fileblocked: rc=$rc, no error naming the asset"; fi
if [ -s "$P/build/static/img/logo.txt" ]
then ok "fileblocked: the other asset is still copied"
else bad "fileblocked: img/logo.txt was not copied"; fi

rm -rf "$P/build"
"$BIN" build "$P" >"$tmp/out" 2>&1; rc=$?
if [ $rc -eq 0 ] && [ -s "$P/build/static/app.css" ] && [ -s "$P/build/static/img/logo.txt" ] && grep -q 'assets copied: 2' "$tmp/out"
then ok "control: with nothing in the way, build exits 0 and copies both assets"
else bad "control: rc=$rc"; grep -i asset "$tmp/out" | head -3; fi

rm -rf "$P/build"; mkdir -p "$P/templates/errors" "$P/build/404.html" "$P/build/static/app.css"
printf '<h1>not found</h1>\n' >"$P/templates/errors/404.tkt"
"$BIN" build "$P" >"$tmp/out" 2>&1; rc=$?
errs=$(grep '"level":"error"' "$tmp/out")
if [ $rc -ne 0 ] && printf '%s\n' "$errs" | grep -q 'pages skipped: 1 ' && printf '%s\n' "$errs" | grep -q 'assets not copied: 1 '
then ok "both: a skipped page and an uncopied asset each get their summary (rc=$rc)"
else bad "both: rc=$rc, summaries: $(grep -o '"msg":"\(pages skipped\|assets not copied\)[^"]*' "$tmp/out" | tr '\n' ' ')"; fi
rm -rf "$P/templates"

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
