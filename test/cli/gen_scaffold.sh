#!/bin/sh
# Story 121.66 (j, k): `ooke gen` and `ooke new` tell the truth.
#
#   help      `ooke gen --help` lists every type cligen makes: page, type,
#             api, island (it listed page, type)                          (j)
#
# Usage: test/cli/gen_scaffold.sh [path/to/ooke-toke]   (run by `make test`)
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-gen.XXXXXX") || exit 2
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); tail -3 "$tmp/out" | cut -c1-200 | sed 's/^/       /'; }

echo "=== ooke gen / new report what they did (121.66 j, k) ==="

"$BIN" gen --help >"$tmp/out" 2>&1
line=$(grep 'types:' "$tmp/out")
case $line in
  *page*type*api*island*) ok "help: gen --help lists page, type, api, island" ;;
  *) bad "help: gen --help types line is: $line" ;;
esac

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
