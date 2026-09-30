#!/bin/sh
# Story 121.66 (j, k): `ooke gen` and `ooke new` tell the truth.
#
#   help      `ooke gen --help` lists every type cligen makes: page, type,
#             api, island (it listed page, type)                          (j)
#   nopages   `ooke gen page x` where there is no pages/ exits non-zero,
#             names pages/x.tk and does not say "Created"                  (k)
#   readonly  in a directory it cannot write, gen type/api/island/spec and
#             `ooke new` each exit non-zero without "Created"              (k)
#   controls  in a writable project the same commands exit 0, say
#             "Created" and write their files
#
# All of (k) used to log "Created ..." and exit 0 having written nothing.
#
# Usage: test/cli/gen_scaffold.sh [path/to/ooke-toke]   (run by `make test`)
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-gen.XXXXXX") || exit 2
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); tail -3 "$tmp/out" | cut -c1-200 | sed 's/^/       /'; }

echo "=== ooke gen / new report what they did (121.66 j, k) ==="

"$BIN" gen --help >"$tmp/out" 2>&1
line=$(grep 'types:' "$tmp/out")
case $line in
  *page*type*api*island*) ok "help: gen --help lists page, type, api, island" ;;
  *) bad "help: gen --help types line is: $line" ;;
esac

# ── (k) ───────────────────────────────────────────────────────────────────
created() { grep -q '"msg":"Created' "$tmp/out"; }

mkdir -p "$tmp/empty"
(cd "$tmp/empty" && "$BIN" gen page foo) >"$tmp/out" 2>&1; rc=$?
if [ $rc -ne 0 ] && ! created && grep -q 'could not write pages/foo.tk' "$tmp/out" && [ ! -e "$tmp/empty/pages/foo.tk" ]
then ok "nopages: gen page with no pages/ exits $rc, names pages/foo.tk, no Created"
else bad "nopages: rc=$rc"; fi

mkdir -p "$tmp/ro"; chmod 555 "$tmp/ro"
if ( : >"$tmp/ro/probe" ) 2>/dev/null; then
  rm -f "$tmp/ro/probe"
  echo "  SKIP readonly: $tmp/ro is writable (running as root?)"
else
  for c in "gen type t" "gen api a" "gen island i" "gen spec stack i64" "new proj"; do
    (cd "$tmp/ro" && "$BIN" $c) >"$tmp/out" 2>&1; rc=$?
    if [ $rc -ne 0 ] && ! created && grep -q '"level":"error".*could not' "$tmp/out"
    then ok "readonly: ooke $c exits $rc with an error, no Created"
    else bad "readonly: ooke $c: rc=$rc"; fi
  done
fi
chmod 755 "$tmp/ro"

mkdir -p "$tmp/w/pages"
for c in "gen page p:pages/p.tk" "gen type t:models/t.toml" "gen api a:pages/api/a.tk" \
         "gen island i:islands/i.tk" "gen spec stack i64:stacki64.tk" "new proj:proj/templates/index.tkt"; do
  cmd=${c%%:*}; file=${c#*:}
  (cd "$tmp/w" && "$BIN" $cmd) >"$tmp/out" 2>&1; rc=$?
  if [ $rc -eq 0 ] && created && [ -s "$tmp/w/$file" ]
  then ok "control: ooke $cmd exits 0, says Created, writes $file"
  else bad "control: ooke $cmd: rc=$rc"; fi
done

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
