#!/bin/sh
# Story 121.25 (audit 120.14, OOK-01): `ooke serve` exposes static/ at
# /static/* and nothing else of the project.
#
# The audit read `http.servedir("/static";projectdir)` in serve.tk as mounting
# the whole PROJECT at /static, so that /static/ooke.toml or
# /static/pages/index.tk would be downloadable, and proposed
# `http.servedir("/static";path.join(projectdir;"static"))`.  Its verifier
# refuted the reachability, and this test measures why: toke's servedir keeps
# the URL prefix when it maps a path to a file (tk_web_glue.c staticdir_handler
# builds root + request path), so /static/x is <projectdir>/static/x.  The
# call is right as written, and the audit's "fix" would serve
# <projectdir>/static/static/x -- every asset a 404.
#
# What this pins, against a copy of testproj with a static/ directory:
#   asset      GET /static/site.css is 200 with the file's bytes
#   config     GET /static/ooke.toml is not 200 (the project's config is not
#              under static/)
#   source     GET /static/pages/index.tk is not 200
#   root       GET /ooke.toml is not 200 (nothing is mounted at /)
#   dotdot     GET /static/../ooke.toml (sent as-is) is not 200
#   encoded    GET /static/%2e%2e/ooke.toml is not 200
#
# Negative controls (2026-09-29, recorded in the 121.25 report):
#   serve.tk mounting `http.servedir("/";projectdir)` -> "root" fails (200);
#   the audit's `path.join(projectdir;"static")` -> "asset" fails (404).
#
# Usage: test/serve/static_mount.sh [path/to/ooke-toke]   (run by `make test`)
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-static.XXXXXX") || exit 2
pid=""
cleanup() { [ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

port=$(( 20000 + (($$ + 7919) % 20000) ))
proj=$tmp/proj
cp -R "$ROOT/testproj" "$proj" && rm -rf "$proj/build" || exit 2
mkdir -p "$proj/static" || exit 2
printf 'body{color:#123}\n' >"$proj/static/site.css"
awk -v port="$port" '
  /^port = /    { print "port = " port; next }
  /^workers = / { print "workers = 1"; next }
  { print }
' "$ROOT/testproj/ooke.toml" >"$proj/ooke.toml"

(cd "$proj" && exec "$BIN" serve) >"$tmp/out" 2>"$tmp/err" &
pid=$!
up=0; i=0
while [ $i -lt 50 ]; do
  kill -0 "$pid" 2>/dev/null || break
  if curl -s -o /dev/null "http://127.0.0.1:$port/static/site.css"; then up=1; break; fi
  sleep 0.2; i=$((i+1))
done

echo "=== ooke serve mounts static/ at /static and nothing else (121.25 OOK-01) ==="
if [ "$up" != 1 ]; then
  bad "serve did not come up on port $port"; sed 's/^/      | /' "$tmp/err" | tail -5
  echo "  $pass passed, $fail failed"; exit 1
fi

# code PATH : the HTTP status for PATH, sent exactly as written
code() { curl -s --path-as-is -o "$tmp/body" -w '%{http_code}' "http://127.0.0.1:$port$1"; }

c=$(code /static/site.css)
if [ "$c" = 200 ] && cmp -s "$tmp/body" "$proj/static/site.css"; then ok "asset: /static/site.css 200 with the file's bytes"
else bad "asset: /static/site.css answered $c"; fi

for case in "config /static/ooke.toml" "source /static/pages/index.tk" "root /ooke.toml" \
            "dotdot /static/../ooke.toml" "encoded /static/%2e%2e/ooke.toml"; do
  name=${case%% *}; p=${case#* }
  c=$(code "$p")
  if [ "$c" != 200 ]; then ok "$name: $p answered $c"
  else bad "$name: $p answered 200 -- $(head -c 60 "$tmp/body")"; fi
done

echo "  $pass passed, $fail failed"
[ "$fail" = 0 ]
