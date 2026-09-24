#!/bin/sh
# Story 134.25: `ooke build <path>` must work from any working directory.
#
# A route's template path and [build].output are project-relative, but they
# used to be resolved against the directory `ooke build` ran in, and the <path>
# argument itself was read and then ignored. So a downstream consumer or a CI
# job driving the build from a parent directory either failed on the first
# template or had the site written into its own directory.
#
# This builds a copy of testproj/ four ways and requires all four to produce
# the same tree, in the project, and nothing in the caller's directory:
#   ref       cd <project> && ooke build           (the one that always worked)
#   parent    cd <parent>  && ooke build site
#   sibling   cd <sibling> && ooke build ../site3
#   absolute  cd /         && ooke build /abs/path
#
# Usage: test/build/build_from_parent.sh [path/to/ooke-toke]
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-cwd.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

# Projects live under $W; logs stay in $tmp so they never count as output.
W=$tmp/w
mkdir "$W" "$W/sibling" || exit 2
for d in ref site site3 site4; do
  cp -R "$ROOT/testproj" "$W/$d" && rm -rf "$W/$d/build"
done

echo "=== ooke build from outside the project (134.25) ==="

(cd "$W/ref" && "$BIN" build) >"$tmp/ref.log" 2>&1 \
  && ok "reference build from the project root" \
  || { bad "reference build from the project root"; sed 's/^/       /' "$tmp/ref.log" | tail -5; }

run() { # name cwd arg project
  name=$1; cwd=$2; arg=$3; proj=$4
  before=$(ls -A "$cwd")
  if (cd "$cwd" && "$BIN" build "$arg") >"$tmp/$name.log" 2>&1; then
    ok "$name: exit 0"
  else
    bad "$name: exit non-zero"; sed 's/^/       /' "$tmp/$name.log" | tail -5
  fi
  if [ -f "$proj/build/index.html" ]; then ok "$name: site written inside the project"
  else bad "$name: no $proj/build/index.html"; fi
  if [ "$(ls -A "$cwd")" = "$before" ]; then ok "$name: nothing written to the working directory"
  else bad "$name: the working directory changed: $(ls -A "$cwd" | tr '\n' ' ')"; fi
  if diff -r "$W/ref/build" "$proj/build" >/dev/null 2>&1; then ok "$name: output identical to the root build"
  else bad "$name: output differs from the root build"; fi
}

run parent   "$W"         site       "$W/site"
run sibling  "$W/sibling" ../site3   "$W/site3"
run absolute /            "$W/site4" "$W/site4"

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
