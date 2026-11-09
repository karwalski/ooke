#!/bin/sh
# Story 138.29 (loke O-4): an unknown directive, a stray `end` and a block
# still open at the end of a template are each a $tplerr, LOGGED where it is
# raised (the 121.59 / 134.24 pattern: a caller cannot read e.msg off the
# payload while toke 127.78 is open, so an unlogged $tplerr reaches nobody).
#
# test/template/test_template.tk checks that each shape answers $tplerr; this
# runs that binary and reads its stderr for one error-level line per shape.
# Negative control: the known-directive controls in the same test log none of
# these lines.
#
# Usage: test/template/directive_log.sh
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-tpldir.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0; fail=0
ok()  { printf '  PASS %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

echo "=== an unknown directive, a stray end and an unclosed block are logged errors (138.29) ==="

if ! test/run_tests.sh template >"$tmp/build.log" 2>&1; then
  bad "test/run_tests.sh template failed"; tail -8 "$tmp/build.log" | sed 's/^/       /'
fi
exe=$ROOT/build/testbin/test_template
[ -x "$exe" ] || { bad "no test binary at $exe"; echo "  $pass passed, $fail failed"; exit 1; }

"$exe" >"$tmp/out" 2>"$tmp/err"; rc=$?
[ "$rc" = "0" ] && ok "test_template exits 0" \
  || { bad "test_template exited $rc"; grep 'FAIL' "$tmp/out" "$tmp/err" | head -6 | sed 's/^/       /'; }

KNOWN='(known: layout, block, end, var, yield, partial, island)'
# logged MSG WHAT -- an error-level line carrying MSG exactly (JSON-escaped)
logged() {
  if grep '"level":"error"' "$tmp/err" | grep -qF "\"msg\":\"$1\""; then ok "$2"
  else bad "$2 -- no error line: $1"; fi
}
logged "template: unknown directive \\\"frobnicate\\\" $KNOWN" "an unknown directive with an argument is logged"
logged "template: unknown directive \\\"z112nosuchdir\\\" $KNOWN" "a bare unknown directive is logged"
logged "template: unknown directive \\\"z112inblock\\\" $KNOWN" "an unknown directive inside an unyielded block is logged"
logged "template: unknown directive \\\"endblock\\\" $KNOWN" "{! endblock !} is logged as an unknown directive"
logged "template: {! end !} with no open block" "a stray end is logged"
logged "template: block \\\"body\\\" is never closed with {! end !}" "a block open at the end of a layout child is logged"
logged "template: block \\\"t\\\" is never closed with {! end !}" "a block open at the end of a plain template is logged"

# control: no known directive is reported as unknown
for d in layout block end var yield partial island; do
  if grep -qF "unknown directive \\\"$d\\\"" "$tmp/err"; then bad "control: known directive $d was logged as unknown"
  else ok "control: known directive $d is not logged as unknown"; fi
done

echo "  $pass passed, $fail failed"
[ "$fail" = "0" ]
