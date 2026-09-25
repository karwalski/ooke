#!/bin/sh
# Story 134.45: `ooke run` and `ooke build --cli` report the compile and the
# program's exit status truthfully.
#
# src/run.tk matched process.wait's plain i32 with $ok/$err arms, which always
# took $err for a status of 0 (127.202): every successful tkc compile was
# reported as "tkc error" and ooke run never ran anything, and runexec read a
# program's exit 0 as -1. The cases:
#
#   ok        a program that exits 0 compiles, runs, and ooke run exits 0
#   args      arguments after the path reach the program (its log line shows)
#   dot       `ooke run` with no path, from inside the project, does the same
#   fails     a program that exits 3 makes ooke run exit 3
#   tkc       a program that does not compile makes ooke run exit non-zero
#             with "tkc error" and never runs it
#   build     `ooke build --cli` exits 0 and writes build/<name>
#
# testproj is a site (no [package], no src/main.tk), so the CLI projects are
# made here, in a temporary directory, and run from its parent.
#
# Usage: test/run/run_cli.sh [path/to/ooke-toke]   (run by `make test`)
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }
# ooke run spawns `tkc` from PATH; use the toke this ooke is built against.
TKCDIR=${TOKE_ROOT:-$ROOT/../toke}
[ -x "$TKCDIR/tkc" ] || { echo "error: no tkc in $TKCDIR (set TOKE_ROOT)" >&2; exit 2; }
PATH=$TKCDIR:$PATH; export PATH

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-run.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); tail -4 "$tmp/out" | cut -c1-200 | sed 's/^/       /'; }

mkproj() {  # mkproj DIR NAME BODY
  mkdir -p "$tmp/$1/src" || exit 2
  printf '[package]\nname = "%s"\nentry = "src/main.tk"\n' "$2" >"$tmp/$1/ooke.toml"
  printf '%s\n' "$3" >"$tmp/$1/src/main.tk"
}
mkproj good hello 'm=main;
i=args:std.args;
i=log:std.log;
f=main():i64{
  let a=mt args.get(1 as u64) {$ok:v v;$err:e "none"};
  (log.info(a;@()));
  <0
};'
mkproj bad failer 'm=main;
f=main():i64{
  <3
};'
mkproj cerr cerr 'm=main;
f=main():i64{
  <undefinedname
};'

echo "=== ooke run / build --cli report exit status (134.45) ==="

(cd "$tmp" && "$BIN" run good marker-134-45) >"$tmp/out" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && ! grep -q 'tkc error\|compilation failed' "$tmp/out"
then ok "ok: a program exiting 0 compiles, runs, and ooke run exits 0"
else bad "ok: rc=$rc"; fi
if grep -q 'running good/build/hello' "$tmp/out" && grep -q 'marker-134-45' "$tmp/out"
then ok "args: the program ran and received its argument"
else bad "args: no run or no argument"; fi

rm -rf "$tmp/good/build"
(cd "$tmp/good" && "$BIN" run) >"$tmp/out" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ -x "$tmp/good/build/hello" ] && grep -q 'running' "$tmp/out"
then ok "dot: ooke run with no path, inside the project, exits 0"
else bad "dot: rc=$rc"; fi

(cd "$tmp" && "$BIN" run bad) >"$tmp/out" 2>&1; rc=$?
if [ "$rc" -eq 3 ] && grep -q 'running bad/build/failer' "$tmp/out"
then ok "fails: a program exiting 3 makes ooke run exit 3"
else bad "fails: rc=$rc"; fi

(cd "$tmp" && "$BIN" run cerr) >"$tmp/out" 2>&1; rc=$?
if [ "$rc" -ne 0 ] && grep -q 'tkc error: .*E3011' "$tmp/out" && ! grep -q 'running' "$tmp/out"
then ok "tkc: a compile error makes ooke run exit non-zero ($rc) with tkc's diagnostic"
else bad "tkc: rc=$rc"; fi

rm -rf "$tmp/good/build"
(cd "$tmp" && "$BIN" build --cli good) >"$tmp/out" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ -x "$tmp/good/build/hello" ] && grep -q 'built: good/build/hello' "$tmp/out"
then ok "build: ooke build --cli exits 0 and writes build/hello"
else bad "build: rc=$rc"; fi

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
