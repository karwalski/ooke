#!/bin/sh
# Story 121.66 (g): `ooke repair <file>` exits by tkc's verdict, not by a
# count of its stderr lines.
#
# repair.tk counted non-blank stderr lines from `tkc --check` and ignored the
# exit status; main.tk returned that count as ooke's exit status. So:
#
#   many     a file with 256 diagnostics exited 0 (256 mod 256)
#   silent   tkc exiting non-zero with nothing on stderr read as "clean", 0
#   warn     tkc exiting 0 with a warning on stderr read as broken, 1
#   clean    a clean file exits 0 (control)
#   broken   a file with one error exits non-zero (control)
#
# many/clean/broken use the real tkc from TOKE_ROOT; silent/warn put a stub
# `tkc` first on PATH.
#
# Usage: test/repair/repair_exit.sh [path/to/ooke-toke]   (run by `make test`)
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }
TKCDIR=${TOKE_ROOT:-$ROOT/../toke}
[ -x "$TKCDIR/tkc" ] || { echo "error: no tkc in $TKCDIR (set TOKE_ROOT)" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-repair.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); tail -3 "$tmp/out" | cut -c1-200 | sed 's/^/       /'; }

echo "=== ooke repair exits by tkc's verdict (121.66 g) ==="

# 256 functions, one type error each: 256 diagnostics on stderr.
{
  echo 'm=t;'
  i=0
  while [ $i -lt 256 ]; do echo "f=g$i():i64{let a:i64=\"s\";<0};"; i=$((i+1)); done
  echo 'f=main():i64{<0};'
} >"$tmp/many.tk"
printf 'm=t;\nf=main():i64{<0};\n' >"$tmp/clean.tk"
printf 'm=t;\nf=main():i64{<undefinedname};\n' >"$tmp/broken.tk"

(PATH=$TKCDIR:$PATH "$BIN" repair "$tmp/many.tk") >"$tmp/out" 2>&1; rc=$?
if [ $rc -ne 0 ] && grep -q 'found 256 diagnostic' "$tmp/out"
then ok "many: 256 diagnostics exit non-zero ($rc)"
else bad "many: 256 diagnostics exit $rc"; fi

(PATH=$TKCDIR:$PATH "$BIN" repair "$tmp/clean.tk") >"$tmp/out" 2>&1; rc=$?
[ $rc -eq 0 ] && ok "clean: a clean file exits 0" || bad "clean: exit $rc"

(PATH=$TKCDIR:$PATH "$BIN" repair "$tmp/broken.tk") >"$tmp/out" 2>&1; rc=$?
[ $rc -ne 0 ] && ok "broken: one error exits non-zero ($rc)" || bad "broken: exit 0"

mkdir -p "$tmp/stub"
printf '#!/bin/sh\nexit 1\n' >"$tmp/stub/tkc"; chmod +x "$tmp/stub/tkc"
(PATH=$tmp/stub:$PATH "$BIN" repair "$tmp/clean.tk") >"$tmp/out" 2>&1; rc=$?
if [ $rc -ne 0 ] && grep -q 'with no diagnostics' "$tmp/out"
then ok "silent: tkc failing with no output exits non-zero ($rc)"
else bad "silent: tkc exit 1, no output: ooke repair exit $rc"; fi

printf '#!/bin/sh\necho "{\\"severity\\":\\"warning\\"}" >&2\nexit 0\n' >"$tmp/stub/tkc"
(PATH=$tmp/stub:$PATH "$BIN" repair "$tmp/clean.tk") >"$tmp/out" 2>&1; rc=$?
[ $rc -eq 0 ] && ok "warn: tkc exit 0 with a warning exits 0" || bad "warn: exit $rc"

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
