#!/bin/sh
# Stories 134.42 and 134.43: two CLI contracts from docs/public-api.md §1.1.
#
#   134.43  `ooke --version` prints `ooke <VERSION>` on STDOUT, and nothing on
#           stderr. It used to emit a JSON log record on stderr.
#   134.42  A present-but-malformed ooke.toml is an error for both `ooke build`
#           and `ooke serve`: non-zero exit, a message naming the file, and no
#           fallback to defaults -- build writes nothing, serve binds nothing.
#           Both used to carry on silently with default settings.
#
# Usage: test/cli/cli_contract.sh [path/to/ooke-toke]
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-cli.XXXXXX") || exit 2
pid=""
cleanup() { [ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

echo "=== CLI contract (134.42, 134.43) ==="

# ── 134.43: --version ─────────────────────────────────────────────────────
want="ooke $(cat VERSION)"
"$BIN" --version >"$tmp/v.out" 2>"$tmp/v.err"; rc=$?
[ $rc -eq 0 ] && ok "--version exits 0" || bad "--version exits $rc"
got=$(cat "$tmp/v.out")
[ "$got" = "$want" ] && ok "--version stdout is exactly '$want'" \
                     || bad "--version stdout is '$got', want '$want'"
[ ! -s "$tmp/v.err" ] && ok "--version writes nothing to stderr" \
                      || bad "--version wrote to stderr: $(head -c 200 "$tmp/v.err")"

# ── 134.42: malformed ooke.toml ───────────────────────────────────────────
mkproj() { # dir
  cp -R "$ROOT/testproj" "$1" && rm -rf "$1/build" || return 1
  printf '[site\nname = \n' >"$1/ooke.toml"
}

P=$tmp/buildproj
mkproj "$P" || exit 2
"$BIN" build "$P" >"$tmp/b.log" 2>&1; rc=$?
[ $rc -ne 0 ] && ok "build: malformed ooke.toml exits non-zero ($rc)" \
              || bad "build: malformed ooke.toml exits 0"
grep -q "ooke.toml could not be read or is not valid TOML" "$tmp/b.log" \
  && ok "build: the error names ooke.toml" \
  || bad "build: no error naming ooke.toml: $(head -c 300 "$tmp/b.log")"
[ ! -e "$P/build" ] && ok "build: nothing written (no fallback to output build/)" \
                    || bad "build: wrote $P/build using default settings"

S=$tmp/serveproj
mkproj "$S" || exit 2
"$BIN" serve "$S" >"$tmp/s.log" 2>&1 &
pid=$!
i=0; alive=1
while [ $i -lt 50 ]; do
  kill -0 "$pid" 2>/dev/null || { alive=0; break; }
  sleep 0.1; i=$((i+1))
done
if [ $alive -eq 1 ]; then
  bad "serve: still running 5s after start on a malformed ooke.toml (fell back to defaults)"
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=""
else
  wait "$pid"; rc=$?; pid=""
  [ $rc -ne 0 ] && ok "serve: malformed ooke.toml exits non-zero ($rc)" \
                || bad "serve: malformed ooke.toml exits 0"
fi
grep -q "ooke.toml could not be read or is not valid TOML" "$tmp/s.log" \
  && ok "serve: the error names ooke.toml" \
  || bad "serve: no error naming ooke.toml: $(head -c 300 "$tmp/s.log")"

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
