#!/bin/sh
# Story 134.37: `ooke serve <path>` must serve the project at <path>, and must
# render its pages from the project's templates, from any working directory.
#
# `ooke serve` took no argument and served the current directory, and a
# route's template path ("templates/index.tkt") was rendered against the
# working directory rather than the project -- the defect 134.25 fixed for
# `ooke build`. Served from anywhere but the project root, every page either
# failed to start (no pages/ in the cwd) or came back as the empty-template
# fallback, `<html><body><p>/</p></body></html>`.
#
# This serves a copy of testproj/ three ways and requires "/" to render the
# project's templates/index.tkt, identically, each time:
#   ref       cd <project> && ooke serve
#   parent    cd <parent>  && ooke serve site
#   absolute  cd /         && ooke serve /abs/path
#
# Usage: test/serve/serve_from_parent.sh [path/to/ooke-toke]
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-serve-cwd.XXXXXX") || exit 2
pid=""
cleanup() { [ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

# The marker is text that exists only in testproj/templates/index.tkt.
MARKER="ooke is running"
# A port per run, so a leftover server or a parallel run cannot answer for us.
base=$(( 20000 + ($$ % 20000) ))

W=$tmp/w
mkdir "$W" || exit 2

serve() { # name cwd arg project port
  name=$1; cwd=$2; arg=$3; proj=$4; port=$5
  cp -R "$ROOT/testproj" "$proj" && rm -rf "$proj/build" || return 1
  sed -i.bak "s/^port = .*/port = $port/" "$proj/ooke.toml" && rm -f "$proj/ooke.toml.bak"
  grep -q "^port = $port\$" "$proj/ooke.toml" || { bad "$name: could not set the port"; return 1; }

  if [ -n "$arg" ]; then
    (cd "$cwd" && exec "$BIN" serve "$arg") >"$tmp/$name.log" 2>&1 &
  else
    (cd "$cwd" && exec "$BIN" serve) >"$tmp/$name.log" 2>&1 &
  fi
  pid=$!

  body=""; i=0
  while [ $i -lt 50 ]; do
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    body=$(curl -s --max-time 2 "http://127.0.0.1:$port/" 2>/dev/null) && [ -n "$body" ] && break
    sleep 0.2; i=$((i+1))
  done
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=""

  if [ -n "$body" ]; then ok "$name: server answered on :$port"
  else bad "$name: no answer on :$port"; sed 's/^/       /' "$tmp/$name.log" | tail -5; return 1; fi
  printf '%s' "$body" >"$tmp/$name.html"
  case $body in
    *"$MARKER"*) ok "$name: / rendered from the project's templates/index.tkt" ;;
    *) bad "$name: / did not render templates/index.tkt, got: $(printf '%s' "$body" | head -c 120)" ;;
  esac
}

echo "=== ooke serve from outside the project (134.37) ==="

serve ref      "$W/ref"  ""        "$W/ref"  $base
serve parent   "$W"      site      "$W/site" $((base+1))
serve absolute /         "$W/site4" "$W/site4" $((base+2))

for n in parent absolute; do
  if [ -f "$tmp/ref.html" ] && [ -f "$tmp/$n.html" ] && cmp -s "$tmp/ref.html" "$tmp/$n.html"; then
    ok "$n: / identical to the root serve"
  else
    bad "$n: / differs from the root serve"
  fi
done

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
