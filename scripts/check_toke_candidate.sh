#!/bin/sh
# check_toke_candidate.sh — does ooke still build, link and pass its unit tests
# against a candidate toke?  (story 121.76)
#
# Usage: scripts/check_toke_candidate.sh <toke-dir>
#        make check-toke-candidate TOKE_CANDIDATE=<toke-dir>
#
# <toke-dir> is a toke checkout with its compiler built (<toke-dir>/toke):
# a branch about to merge, a release candidate, a scratch tree.  Run it before
# merging a toke change that adds, moves or splits a stdlib C file -- the class
# of change that broke ooke's link in 121.70 (os_glue.c).
#
# ooke's committed HEAD is checked out into a temporary worktree, so this
# checkout's build output is not touched and uncommitted edits are not tested.
# It builds the ooke binary, links and runs every unit test (test/run_tests.sh)
# and builds a per-app binary with `ooke compile` (test/serve/compile_app.sh):
# the three link paths, all of which take their stdlib C sources from the
# candidate's `tkc --emit-deps`.  It does not run the toke floor gate
# (check-versions): a candidate branch need not contain the floor commit yet.
set -eu

cd "$(dirname "$0")/.."
cand=${1:?usage: scripts/check_toke_candidate.sh <toke-dir>}
toke=$(cd "$cand" && pwd) || { echo "check_toke_candidate: no directory $cand" >&2; exit 2; }
[ -x "$toke/toke" ] || {
  echo "check_toke_candidate: $toke/toke is not built -- run 'make -C $toke' first" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "check_toke_candidate: needs a git checkout of ooke (it tests HEAD in a worktree)" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-candidate.XXXXXX")
wt="$tmp/ooke"
cleanup() {
  git worktree remove --force "$wt" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

git worktree add --detach "$wt" HEAD >/dev/null 2>&1
echo "=== ooke $(git rev-parse --short HEAD) against toke $(git -C "$toke" rev-parse --short HEAD 2>/dev/null || echo '(not git)') at $toke ==="

echo "--- 1/3 ooke binary"
make -s -C "$wt" --no-print-directory TOKE_ROOT="$toke" ooke-toke >"$tmp/build.log" 2>&1 || {
  grep -v 'override-module\|warning generated\|"severity":"warning"' "$tmp/build.log" | tail -20 >&2
  echo "FAIL: ooke does not build against $toke" >&2; exit 1; }
echo "  ok"

echo "--- 2/3 unit tests (link + run)"
(cd "$wt" && TOKE_ROOT="$toke" test/run_tests.sh) || {
  echo "FAIL: ooke's unit tests do not link or pass against $toke" >&2; exit 1; }

echo "--- 3/3 per-app binary (ooke compile)"
(cd "$wt" && TOKE_ROOT="$toke" TKC="$toke/toke" test/serve/compile_app.sh ./ooke-toke) || {
  echo "FAIL: 'ooke compile' does not produce a working binary against $toke" >&2; exit 1; }

echo "OK: ooke builds, links and passes against $toke"
