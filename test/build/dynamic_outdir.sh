#!/bin/sh
# Story 121.66 (l): the dynamic (content-backed) pass of `ooke build` names
# the output directory it could not create.
#
# The static pass (buildpage) reports "could not create the output directory
# <dir>"; the dynamic pass ignored file.mkdir's result, so the same failure
# surfaced as "write failed for <dir>/index.html". A project with
# pages/blog/[slug].tk and one post is built with build/blog already a regular
# file, so build/blog/post cannot be created:
#
#   blocked   build exits non-zero and the error names build/blog/post as the
#             directory it could not create
#   control   the same project with nothing in the way builds, exit 0, and
#             writes build/blog/post/index.html
#
# Usage: test/build/dynamic_outdir.sh [path/to/ooke-toke]   (run by `make test`)
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-dynout.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); grep '"level":"error"' "$tmp/out" | tail -3 | cut -c1-200 | sed 's/^/       /'; }

echo "=== ooke build names a dynamic page's output directory it cannot create (121.66 l) ==="

P=$tmp/proj
mkdir -p "$P/pages/blog" "$P/templates/blog" "$P/content/blog" || exit 2
printf 'm=pages.blog.slug;\n' >"$P/pages/blog/[slug].tk"
printf '<h1>{= title =}</h1>\n' >"$P/templates/blog/[slug].tkt"
printf -- '---\nslug: post\ntitle: T\n---\nbody\n' >"$P/content/blog/post.md"
printf '[site]\nname = "d"\n' >"$P/ooke.toml"

mkdir -p "$P/build" && echo x >"$P/build/blog"
"$BIN" build "$P" >"$tmp/out" 2>&1; rc=$?
if [ $rc -ne 0 ] && grep '"level":"error"' "$tmp/out" | grep -q "could not create the output directory $P/build/blog/post"
then ok "blocked: build exits $rc naming the directory build/blog/post"
else bad "blocked: rc=$rc, no error naming the output directory"; fi

rm -rf "$P/build"
"$BIN" build "$P" >"$tmp/out" 2>&1; rc=$?
if [ $rc -eq 0 ] && [ -s "$P/build/blog/post/index.html" ]
then ok "control: with nothing in the way, build exits 0 and writes blog/post/index.html"
else bad "control: rc=$rc"; fi

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
