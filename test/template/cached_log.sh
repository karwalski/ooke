#!/bin/sh
# Story 121.63: the cached render path logs a missing or unreadable template
# exactly as tplrenderfile does (121.59).
#
# tplrenderfilecached and tplcacheget read the file with
# `file.read(p)!$tplerr`: a missing or unreadable template came back as a
# $tplerr with nothing logged. They now share tplrenderfile's reader, so each
# failure logs one error line naming the file.
#
# This builds test/template/test_template.tk (via test/run_tests.sh), makes the
# symlink fixtures its unreadable-file cases need (toke has no symlink call),
# runs it, and reads its stderr. Negative control: the readable template the
# same test renders through the cache logs nothing.
#
# Usage: test/template/cached_log.sh
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-tplcache.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0; fail=0
ok()  { printf '  PASS %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

echo "=== the cached render path logs a missing or unreadable template (121.63) ==="

# The unit test's fixed directory (test_template.tk testcachedmissing).
D=/tmp/test_ooke_12163
mkdir -p "$D" || exit 2
echo 'OUTSIDE' >"$D/linktarget.txt"
ln -sf "$D/linktarget.txt" "$D/linkrender.tkt"
ln -sf "$D/linktarget.txt" "$D/linkget.tkt"

if ! test/run_tests.sh template >"$tmp/build.log" 2>&1; then
  bad "test/run_tests.sh template failed"; tail -8 "$tmp/build.log" | sed 's/^/       /'
fi
exe=$ROOT/build/testbin/test_template
[ -x "$exe" ] || { bad "no test binary at $exe"; echo "  $pass passed, $fail failed"; exit 1; }

"$exe" >"$tmp/out" 2>"$tmp/err"; rc=$?
[ "$rc" = "0" ] && ok "test_template exits 0 with the fixtures in place" \
  || { bad "test_template exited $rc"; grep 'FAIL' "$tmp/out" "$tmp/err" | head -6 | sed 's/^/       /'; }
grep -q 'SKIP 121.63' "$tmp/out" "$tmp/err" \
  && bad "the unreadable-file cases were skipped (fixtures not seen)" \
  || ok "the unreadable-file cases ran"

# logged MSG WHAT -- one error-level line carrying MSG exactly
logged() {
  if grep '"level":"error"' "$tmp/err" | grep -qF "\"msg\":\"$1\""; then ok "$2"
  else bad "$2 -- no error line: $1"; fi
}
logged "template: no template file: $D/nosuchrender.tkt" \
  "tplrenderfilecached logs a missing template"
logged "template: no template file: $D/nosuchget.tkt" \
  "tplcacheget logs a missing template"
logged "template: template file could not be read: $D/linkrender.tkt" \
  "tplrenderfilecached logs an unreadable template"
logged "template: template file could not be read: $D/linkget.tkt" \
  "tplcacheget logs an unreadable template"

grep -q "$D/good.tkt" "$tmp/err" \
  && bad "control: the readable template logged: $(grep "$D/good.tkt" "$tmp/err" | head -1)" \
  || ok "control: the readable template rendered through the cache logs nothing"

rm -f "$D/linkrender.tkt" "$D/linkget.tkt" "$D/linktarget.txt"

echo "  $pass passed, $fail failed"
[ "$fail" = "0" ]
