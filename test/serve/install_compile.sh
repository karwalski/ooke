#!/bin/sh
# Story 134.46: an INSTALLED ooke can `compile`.
#
# 134.45 made `ooke compile` find scripts/gen_app_makefile.sh beside its own
# binary, but every release artefact and the Homebrew formula shipped the
# binary alone, so from an installation the lookup found nothing. This test
# builds an installation the way the release and the formula do -- the tree
# scripts/stage_install.sh lays out, under libexec/, behind a bin/ wrapper
# that sets OOKE_ROOT / TOKE_ROOT / TKC exactly as the formula's
# write_env_script does -- next to a simulated tkc formula (tkc, src/stdlib,
# stdlib under its own libexec/), and compiles a project from a directory
# that holds neither checkout.
#
#   binary-only   the pre-134.46 artefact (binary, no scripts/) refuses to
#                 compile and says why -- the control that shows this test
#                 can tell the two layouts apart
#   installed     the staged installation compiles the project: exit 0 and
#                 an executable build/testproj
#   read-only     the installation is left untouched (nothing written into
#                 libexec/, as a Homebrew Cellar requires)
#
# Usage: test/serve/install_compile.sh [path/to/ooke-toke]   (run by `make test`)
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }
TOKE_ROOT=${TOKE_ROOT:-$ROOT/../toke}
TOKE_ROOT=$(cd "$TOKE_ROOT" 2>/dev/null && pwd) || { echo "error: no toke checkout (set TOKE_ROOT)" >&2; exit 2; }
TKC_SRC=${TKC:-$TOKE_ROOT/toke}
[ -x "$TKC_SRC" ] || { echo "error: no tkc at $TKC_SRC" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-install.XXXXXX") || exit 2
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

echo "=== ooke compile from an installation (134.46) ==="

# Simulated tkc formula (homebrew-toke Formula/tkc.rb): libexec holds tkc,
# src/stdlib and stdlib/.
tk=$tmp/tkc/libexec
mkdir -p "$tk/src" "$tmp/tkc/bin"
cp "$TKC_SRC" "$tk/tkc"
cp -R "$TOKE_ROOT/src/stdlib" "$tk/src/stdlib"
cp -R "$TOKE_ROOT/stdlib" "$tk/stdlib"
ln -s "$tk/tkc" "$tmp/tkc/bin/tkc"

# wrap PREFIX: bin/ooke as Formula/ooke.rb writes it (write_env_script)
wrap() {
  mkdir -p "$1/bin"
  cat > "$1/bin/ooke" <<EOF
#!/bin/bash
export OOKE_ROOT="$1/libexec"
export TOKE_ROOT="$tk"
export TKC="$tmp/tkc/bin/tkc"
exec "$1/libexec/ooke" "\$@"
EOF
  chmod +x "$1/bin/ooke"
}

work=$tmp/work
mkdir -p "$work"

# ── binary-only: the artefact as it was ─────────────────────────────────────
old=$tmp/old
mkdir -p "$old/libexec"; cp "$BIN" "$old/libexec/ooke"; wrap "$old"
cp -R "$ROOT/testproj" "$work/p0" && rm -rf "$work/p0/build"
if (cd "$work" && "$old/bin/ooke" compile p0) >"$tmp/old.out" 2>&1; then
  bad "binary-only: compile exited 0 without scripts/ -- this test cannot see the defect"
elif grep -q 'gen_app_makefile.sh' "$tmp/old.out"; then
  ok "binary-only: compile refuses and names the missing script"
else
  bad "binary-only: compile failed, but not for the missing script"
  tail -5 "$tmp/old.out" | sed 's/^/       /'
fi

# ── installed: the staged tree ──────────────────────────────────────────────
new=$tmp/new
if TOKE_ROOT="$TOKE_ROOT" sh scripts/stage_install.sh "$new/libexec" >"$tmp/stage.out" 2>&1; then
  wrap "$new"
else
  bad "installed: scripts/stage_install.sh failed"; sed 's/^/       /' "$tmp/stage.out"
fi
before=$(cd "$new/libexec" 2>/dev/null && find . -type f | sort | xargs cksum 2>/dev/null)
chmod -R a-w "$new/libexec" 2>/dev/null
cp -R "$ROOT/testproj" "$work/p1" && rm -rf "$work/p1/build"
if (cd "$work" && "$new/bin/ooke" compile p1) >"$tmp/new.out" 2>&1; then
  ok "installed: ooke compile exits 0 from a directory with no checkout"
else
  bad "installed: ooke compile exited non-zero"
  grep -v 'override-module\|warning generated' "$tmp/new.out" | tail -8 | sed 's/^/       /'
fi
if [ -x "$work/p1/build/testproj" ]; then ok "installed: build/testproj written"; else bad "installed: no build/testproj"; fi
after=$(cd "$new/libexec" 2>/dev/null && find . -type f | sort | xargs cksum 2>/dev/null)
if [ -n "$before" ] && [ "$before" = "$after" ]; then
  ok "read-only: the installation is unchanged by compile"
else
  bad "read-only: compile wrote into the installation"
fi

echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
