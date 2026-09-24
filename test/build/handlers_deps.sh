#!/bin/sh
# Story 134.37: editing a page at ANY depth under pages/ must regenerate
# src/_handlers.tk.
#
# The Makefile listed its prerequisites as `$(wildcard pages/**/*.tk)`, but
# make's wildcard has no recursive `**` -- it matches exactly one directory --
# so a change to pages/a/b/c.tk left a stale handler registry behind while
# scripts/gen_handlers.sh (which uses find) would have picked it up.
#
# This copies the Makefile and the generator into a scratch project with a
# page three levels deep, generates the registry, makes the deep page newer,
# and asks make whether the registry is out of date. No compiler is needed:
# only the _handlers.tk rule runs.
#
# Usage: test/build/handlers_deps.sh
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-deps.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

echo "=== _handlers.tk depends on pages/ at every depth (134.37) ==="

mkdir -p "$tmp/scripts" "$tmp/src" "$tmp/pages/a/b" || exit 2
cp "$ROOT/Makefile" "$tmp/Makefile" && cp "$ROOT/scripts/gen_handlers.sh" "$tmp/scripts/" || exit 2
printf 'm=pages.a.b.deep;\ni=http:std.http;\nf=get(req:i64):i64{<0};\n' >"$tmp/pages/a/b/deep.tk"
printf 'm=pages.top;\n' >"$tmp/pages/top.tk"

# TOKE_ROOT points somewhere harmless: this rule never touches toke.
mk() { make -s --no-print-directory -C "$tmp" TOKE_ROOT="$tmp/no-toke" "$@"; }

if mk src/_handlers.tk >"$tmp/gen.log" 2>&1 && grep -q 'pages.a.b.deep' "$tmp/src/_handlers.tk"; then
  ok "the generator registers a page three levels deep"
else
  bad "the generator did not register pages/a/b/deep.tk"; sed 's/^/       /' "$tmp/gen.log" | tail -5
fi

if mk -q src/_handlers.tk 2>/dev/null; then ok "registry is up to date right after generation"
else bad "registry is out of date right after generation"; fi

# Make the deep page strictly newer; make compares mtimes to the second here.
sleep 1; touch "$tmp/pages/a/b/deep.tk"
if mk -q src/_handlers.tk 2>/dev/null; then
  bad "editing pages/a/b/deep.tk did not make src/_handlers.tk out of date"
else
  ok "editing pages/a/b/deep.tk makes src/_handlers.tk out of date"
fi

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
