#!/bin/sh
# Story 134.44: `ooke compile` builds a per-app serve binary that serves, and a
# port that cannot be bound fails `serve` with a non-zero exit.
#
#   compile   `ooke compile <copy of testproj>` exits 0 and writes build/testproj
#             (it could not before: the generated main used pre-v0.4 match arms
#             and a function that is not in ooke.config, the generated Makefile
#             could not link, and main.tk read process.wait as a result, so it
#             reported "Makefile generation failed" for every project)
#   serves    the binary answers GET / from the app's page handler and echoes a
#             POST to /api/hello — a handler ooke's own binary does not have, so
#             the answer proves the app's pages were compiled in
#   [log]     it writes the [log] access file (134.40), as `ooke serve` does
#   config    a malformed ooke.toml is refused (134.42), as `ooke serve` does
#   locate    the script is found beside the binary (by path or on $PATH) or
#             under $OOKE_ROOT, never in the cwd (134.45)
#   bind      with the port held by another listener, both `ooke serve` and the
#             compiled binary exit non-zero and say so (134.40's $serveerr on a
#             failed listen; no test covered it), with 1 worker and with 4
#
# Usage: test/serve/compile_app.sh [path/to/ooke-toke]   (run by `make test`)
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required (it holds the port for the bind test)" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-compile.XXXXXX") || exit 2
pid=""; holder=""
cleanup() {
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  [ -n "$holder" ] && kill "$holder" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

MARKER="ooke is running"
UA="ooke-134-44-probe"
port=$(( 20000 + ($$ % 20000) ))

# setport FILE PORT WORKERS
setport() {
  awk -v port="$2" -v w="$3" '
    /^port = /    { print "port = " port; next }
    /^workers = / { print "workers = " w; next }
    /^\[log\]/    { skip=1; next }
    /^\[/         { skip=0 }
    skip          { next }
    { print }
    END { print ""; print "[log]"; print "access = \"logs/access.log\"" }
  ' "$ROOT/testproj/ooke.toml" >"$1"
}

echo "=== ooke compile, and serve on a port it cannot bind (134.44) ==="

proj=$tmp/proj
cp -R "$ROOT/testproj" "$proj" && rm -rf "$proj/build" || exit 2
setport "$proj/ooke.toml" "$port" 1

# ── compile ─────────────────────────────────────────────────────────────────
# Story 134.45: run from the project's PARENT, naming it by a relative path.
# ooke compile ran scripts/gen_app_makefile.sh relative to the cwd, so this
# failed anywhere but the ooke checkout; it now finds the script beside the
# binary. $tmp holds no scripts/ directory, so a cwd lookup cannot pass.
if (cd "$tmp" && "$BIN" compile proj) >"$tmp/compile.out" 2>&1; then
  ok "compile: ooke compile exits 0 (run from the project's parent)"
else
  bad "compile: ooke compile exited non-zero"
  grep -v 'override-module\|warning generated' "$tmp/compile.out" | tail -8 | sed 's/^/       /'
fi
app=$proj/build/testproj
if [ -x "$app" ]; then ok "compile: build/testproj written"; else bad "compile: no build/testproj"; fi
if grep -q 'cli.runserve' "$proj/_serve_main.tk" 2>/dev/null && \
   ! grep -q '{Ok:\|;Err:\|cfgdefault' "$proj/_serve_main.tk" 2>/dev/null
then ok "compile: the generated main runs cli.runserve (no Ok:/Err: arms, no cfgdefault)"
else bad "compile: the generated main is not the runserve path"; fi

# ── serves ──────────────────────────────────────────────────────────────────
if [ -x "$app" ]; then
  (cd "$proj" && exec "$app" .) >"$tmp/app.out" 2>"$tmp/app.err" &
  pid=$!
  i=0; up=1
  while [ $i -lt 50 ]; do
    kill -0 "$pid" 2>/dev/null || { up=0; break; }
    curl -s --max-time 2 -o /dev/null "http://127.0.0.1:$port/" 2>/dev/null && break
    sleep 0.2; i=$((i+1))
  done
  [ $i -ge 50 ] && up=0
  if [ $up -eq 1 ]; then
    body=$(curl -s --max-time 2 -A "$UA" "http://127.0.0.1:$port/")
    case $body in *"$MARKER"*) ok "serves: GET / renders the app's index page" ;;
                  *) bad "serves: GET / lacks the marker" ;; esac
    echo=$(curl -s --max-time 2 -A "$UA" -X POST -d "echo-134-44" "http://127.0.0.1:$port/api/hello")
    if [ "$echo" = "echo-134-44" ]; then ok "serves: POST /api/hello answered by the app's handler"
    else bad "serves: POST /api/hello returned '$echo'"; fi
    sleep 0.3
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=""
    if grep -q "\"GET / HTTP/1.1\" 200 .*\"$UA\"" "$proj/logs/access.log" 2>/dev/null
    then ok "[log]: the request is in the configured access log"
    else bad "[log]: no access line in logs/access.log"; fi
  else
    bad "serves: the compiled binary did not start"; tail -5 "$tmp/app.err" | sed 's/^/       /'
    kill "$pid" 2>/dev/null; pid=""
  fi

  # ── config ──────────────────────────────────────────────────────────────────
  cp "$proj/ooke.toml" "$tmp/good.toml"
  printf '[server\nport = \n' >"$proj/ooke.toml"
  (cd "$proj" && "$app" .) >"$tmp/cfg.out" 2>"$tmp/cfg.err"; rc=$?
  if [ "$rc" -ne 0 ] && grep -q "not valid TOML" "$tmp/cfg.err"
  then ok "config: a malformed ooke.toml is refused ($rc)"
  else bad "config: malformed ooke.toml gave rc=$rc"; tail -3 "$tmp/cfg.err" | sed 's/^/       /'; fi
  cp "$tmp/good.toml" "$proj/ooke.toml"
fi

# ── locate (134.45) ─────────────────────────────────────────────────────────
# Where ooke compile looks for scripts/gen_app_makefile.sh, shown with a stub
# script that only records that it ran and fails (so nothing is built):
#   beside the binary, when the binary is named by a path or found on $PATH;
#   $OOKE_ROOT/scripts when set; and a clear error when there is none.
inst=$tmp/inst; mkdir -p "$inst/scripts" "$tmp/else/scripts" "$tmp/cwd/scripts" || exit 2
cp "$BIN" "$inst/ooke-toke" || exit 2
for d in "$inst" "$tmp/else" "$tmp/cwd"; do
  printf '#!/bin/sh\necho "stub:%s" >"%s/ran"\nexit 7\n' "$d" "$d" >"$d/scripts/gen_app_makefile.sh"
done
# stubran LABEL DIR -> the stub in DIR ran, no other stub did, and ooke
# compile failed naming it
stubran() {
  nran=$(ls "$tmp/inst/ran" "$tmp/else/ran" "$tmp/cwd/ran" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$rc" -ne 0 ] && [ -f "$2/ran" ] && [ "$nran" -eq 1 ] && grep -q "Makefile generation failed: .*gen_app_makefile.sh" "$tmp/loc.out"
  then ok "locate: $1"; else bad "locate: $1 (rc=$rc)"; tail -3 "$tmp/loc.out" | sed 's/^/       /'; fi
  rm -f "$tmp/inst/ran" "$tmp/else/ran" "$tmp/cwd/ran"
}
# $tmp/cwd has a scripts/ of its own: the old cwd lookup would run that one.
(cd "$tmp/cwd" && env -u OOKE_ROOT "$inst/ooke-toke" compile ../proj) >"$tmp/loc.out" 2>&1; rc=$?
stubran "an absolute binary path finds scripts/ beside the binary, not the cwd's" "$inst"
(cd "$tmp/cwd" && env -u OOKE_ROOT PATH="$inst:$PATH" ooke-toke compile ../proj) >"$tmp/loc.out" 2>&1; rc=$?
stubran "a binary found on PATH finds scripts/ beside it" "$inst"
(cd "$tmp/cwd" && OOKE_ROOT="$tmp/else" "$inst/ooke-toke" compile ../proj) >"$tmp/loc.out" 2>&1; rc=$?
stubran "OOKE_ROOT overrides the binary's directory" "$tmp/else"
mkdir -p "$tmp/bare" && cp "$BIN" "$tmp/bare/ooke-toke" || exit 2
(cd "$tmp/cwd" && env -u OOKE_ROOT "$tmp/bare/ooke-toke" compile ../proj) >"$tmp/loc.out" 2>&1; rc=$?
if [ "$rc" -ne 0 ] && grep -q "cannot find scripts/gen_app_makefile.sh" "$tmp/loc.out" && [ ! -f "$tmp/cwd/ran" ]
then ok "locate: no script beside the binary is a clear error ($rc), not the cwd's"
else bad "locate: missing script gave rc=$rc"; tail -3 "$tmp/loc.out" | sed 's/^/       /'; fi

# ── bind ────────────────────────────────────────────────────────────────────
# Another process holds the port (without SO_REUSEPORT, so the server cannot
# share it). The server must stop, non-zero, naming the port.
bport=$((port + 1))
python3 -c "
import socket, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', $bport)); s.listen(); print('held', flush=True); time.sleep(120)
" >"$tmp/holder.out" 2>&1 &
holder=$!
i=0; while [ $i -lt 50 ] && ! grep -q held "$tmp/holder.out" 2>/dev/null; do sleep 0.1; i=$((i+1)); done
grep -q held "$tmp/holder.out" || bad "bind: could not hold port $bport for the test"

# bindfails LABEL WORKERS CMD... -> must exit non-zero within 10s, naming the port
bindfails() {
  label=$1; w=$2; shift 2
  setport "$proj/ooke.toml" "$bport" "$w"
  (cd "$proj" && exec "$@") >"$tmp/bind.out" 2>"$tmp/bind.err" &
  pid=$!
  i=0; while [ $i -lt 50 ] && kill -0 "$pid" 2>/dev/null; do sleep 0.2; i=$((i+1)); done
  if kill -0 "$pid" 2>/dev/null; then
    bad "bind: $label ($w worker(s)) kept running on a port it could not bind"
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=""; return
  fi
  wait "$pid"; rc=$?; pid=""
  if [ "$rc" -ne 0 ] && grep -q "server stopped with an error on port $bport" "$tmp/bind.err"
  then ok "bind: $label ($w worker(s)) exits non-zero ($rc), naming port $bport"
  else bad "bind: $label ($w worker(s)) rc=$rc"; tail -3 "$tmp/bind.err" | sed 's/^/       /'; fi
}
bindfails "ooke serve" 1 "$BIN" serve
bindfails "ooke serve" 4 "$BIN" serve
if [ -x "$app" ]; then
  bindfails "compiled binary" 1 "$app" .
fi
kill "$holder" 2>/dev/null; holder=""

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
