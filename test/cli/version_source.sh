#!/bin/sh
# Story 121.66 (i): VERSION is the one place ooke's version is written.
#
# `ooke --version` printed a literal in src/cli.tk that every release had to
# bump beside VERSION (check-ooke-version caught a half-done bump, but it was
# still two edits). The Makefile now generates floor.ookeversion() from
# VERSION into src/_floor.tk and cli.tk prints that.
#
# A copy of this tree (tracked files, plus the already-built src/ooke modules
# so only floor, cli and main rebuild) gets a different VERSION:
#
#   bump      make ooke-toke, then --version prints the new VERSION
#   gate      make check-ooke-version passes on the bumped copy
#   quote     a VERSION that cannot be spliced into a toke string (it holds a
#             `"`) fails check-ooke-version, naming VERSION (control)
#
# Negative control (2026-10-01): on e71a4ee the bumped copy's binary printed
# "ooke 3.0.0-rc.2" and check-ooke-version failed.
#
# Usage: test/cli/version_source.sh   (run by `make test`; needs TOKE_ROOT,
# and TKC if not $TOKE_ROOT/toke)
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
[ -n "${TOKE_ROOT:-}" ] || { echo "error: TOKE_ROOT is required" >&2; exit 2; }
TKC=${TKC:-$TOKE_ROOT/toke}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-version.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

echo "=== ooke --version comes from VERSION (121.66 i) ==="

tree=$tmp/ooke
mkdir -p "$tree"
git ls-files -z | (cd "$ROOT" && xargs -0 tar cf -) | (cd "$tree" && tar xf -) || exit 2
[ -d src/ooke ] && cp -Rp src/ooke "$tree/src/" 2>/dev/null
for f in src/_floor.tk src/_handlers.tk src/*.tki; do [ -f "$f" ] && cp -p "$f" "$tree/$f"; done

want=9.8.7-rc.121
printf '%s\n' "$want" >"$tree/VERSION"
if (cd "$tree" && make --no-print-directory TOKE_ROOT="$TOKE_ROOT" TKC="$TKC" ooke-toke) >"$tmp/make.out" 2>&1; then
  got=$("$tree/ooke-toke" --version 2>/dev/null)
  [ "$got" = "ooke $want" ] && ok "bump: --version prints 'ooke $want'" \
                            || bad "bump: --version prints '$got', want 'ooke $want'"
else
  bad "bump: make failed"
  grep -E 'E[0-9]{4}|ERROR|error:' "$tmp/make.out" | head -4 | cut -c1-200 | sed 's/^/       /'
fi

if (cd "$tree" && make --no-print-directory TOKE_ROOT="$TOKE_ROOT" check-ooke-version) >"$tmp/chk.out" 2>&1
then ok "gate: check-ooke-version passes with VERSION alone bumped"
else bad "gate: check-ooke-version fails: $(tail -1 "$tmp/chk.out" | cut -c1-200)"; fi

printf '9.9"x\n' >"$tree/VERSION"
if (cd "$tree" && make --no-print-directory TOKE_ROOT="$TOKE_ROOT" check-ooke-version) >"$tmp/chk.out" 2>&1
then bad "quote: check-ooke-version accepted a VERSION holding a quote"
elif grep -q 'VERSION is' "$tmp/chk.out"
then ok "quote: a VERSION holding a quote fails check-ooke-version, naming VERSION"
else bad "quote: failed without naming VERSION: $(tail -1 "$tmp/chk.out" | cut -c1-200)"; fi

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
