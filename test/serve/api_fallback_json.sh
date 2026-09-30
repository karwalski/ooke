#!/bin/sh
# Story 121.63: the API fallback body is JSON-encoded.
#
# An API page with no handler is served {"status":"ok","endpoint":"<path>"}.
# The path is the route derived from a file name under pages/api/, and it was
# spliced into the body as it was, so a page named  a"b\c  produced
# {"status":"ok","endpoint":"/api/a"b\c"} -- not JSON, and a name could inject
# keys of its own. The path is now encoded with std.json's json.enc.
#
# Checks: the body for such a page parses as JSON and its "endpoint" reads back
# as the route exactly. Negative control: a plain page's body is unchanged,
# byte for byte.
#
# Usage: test/serve/api_fallback_json.sh [path/to/ooke-toke]
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required (to parse the JSON back)" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-apijson.XXXXXX") || exit 2
pid=""
cleanup() { [ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

pass=0; fail=0
ok()  { printf "  PASS %s\n" "$1"; pass=$((pass+1)); }
bad() { printf "  FAIL %s\n" "$1"; fail=$((fail+1)); }

port=$(( 20000 + (($$ + 7919) % 20000) ))

P=$tmp/proj
mkdir -p "$P/pages/api" "$P/templates" "$P/content" || exit 2
cat >"$P/ooke.toml" <<EOF
[site]
name = "apijson"
url = ""
language = "en"

[build]
output = "build/"
minify = false
inlinecss = false

[server]
port = $port
workers = 2
EOF
echo 'm=page.index;' >"$P/pages/index.tk"
echo '<p>INDEX</p>' >"$P/templates/index.tkt"
# The hostile name: a double quote and a backslash.
odd='a"b\c'
echo 'm=page.x;' >"$P/pages/api/$odd.tk"
echo 'm=page.x;' >"$P/pages/api/plain.tk"

echo "=== the API fallback body is JSON, whatever the page is called (121.63) ==="
(cd "$P" && exec "$BIN" serve) >"$tmp/serve.log" 2>&1 &
pid=$!
up=""; i=0
while [ $i -lt 50 ]; do
  kill -0 "$pid" 2>/dev/null || break
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$port/" 2>/dev/null)
  [ "$code" = "200" ] && { up=1; break; }
  sleep 0.2; i=$((i+1))
done

# endpoint FILE -> prints the parsed "endpoint", or exits non-zero if FILE is
# not a JSON object with status "ok" and a string endpoint.
endpoint() {
  python3 - "$1" <<'PY'
import json, sys
with open(sys.argv[1], "rb") as f:
    d = json.loads(f.read().decode("utf-8"))
assert isinstance(d, dict) and d.get("status") == "ok" and isinstance(d.get("endpoint"), str), d
assert sorted(d.keys()) == ["endpoint", "status"], d
sys.stdout.write(d["endpoint"])
PY
}

if [ -z "$up" ]; then
  bad "serve: no answer on :$port"; sed 's/^/       /' "$tmp/serve.log" | tail -8
else
  # -g --path-as-is: send the quote and backslash as they are (no globbing, no
  # path normalisation); the static route is matched on the raw path.
  code=$(curl -s -g --path-as-is -o "$tmp/odd" -w '%{http_code}' --max-time 3 "http://127.0.0.1:$port/api/$odd")
  if [ "$code" != "200" ]; then
    bad "/api/$odd answered $code, want 200 (body: $(head -c 120 "$tmp/odd" 2>/dev/null))"
  elif got=$(endpoint "$tmp/odd" 2>"$tmp/odd.err"); then
    ok "/api/$odd: the fallback body parses as JSON ($(cat "$tmp/odd"))"
    [ "$got" = "/api/$odd" ] \
      && ok "/api/$odd: its endpoint reads back as the route exactly" \
      || bad "/api/$odd: endpoint reads back as [$got], want [/api/$odd]"
  else
    bad "/api/$odd: the fallback body is not valid JSON: $(cat "$tmp/odd")"
    sed 's/^/       /' "$tmp/odd.err" | tail -2
  fi

  code=$(curl -s -o "$tmp/plain" -w '%{http_code}' --max-time 3 "http://127.0.0.1:$port/api/plain")
  body=$(cat "$tmp/plain" 2>/dev/null)
  [ "$code" = "200" ] && [ "$body" = '{"status":"ok","endpoint":"/api/plain"}' ] \
    && ok "control: a plain API page's body is unchanged ($body)" \
    || bad "control: /api/plain answered $code: $body"
fi
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=""

echo "  $pass passed, $fail failed"
[ "$fail" = "0" ]
