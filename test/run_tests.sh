#!/usr/bin/env bash
#
# ooke test runner — compiles and executes every test/*/test_*.tk (story 134.5).
#
# Before 134.5 this script existed but had never been run: its hand-copied list
# of stdlib C sources had drifted from the Makefile's (capabilities.c and
# image.c were missing), so every one of the 12 tests failed to link and was
# reported as "SKIP", and `make test-run` was a TODO that printed nothing.
#
# Two rules follow from that, and they are the point of this file:
#
#   1. NOTHING about the build is restated here. The compiler, the stdlib and
#      vendor source lists, the flags and the ooke module IR all come from
#      `make print-build-vars`, so the suite cannot silently drift from the
#      binary it is meant to test (defect D24).
#   2. A test that will not compile or will not link is a FAILURE, not a skip.
#      The exit status is the number of tests that did not pass.
#
# Usage:  test/run_tests.sh [name ...]      # no names = every test
#
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2
ROOT=$(pwd)

OBJ_DIR="$ROOT/build/testobj"
LIB="$ROOT/build/libookestd.a"
BIN_DIR="$ROOT/build/testbin"

# ── Build configuration, taken from the Makefile ────────────────────────────
vars=$(make -s --no-print-directory print-build-vars) || {
  echo "error: 'make print-build-vars' failed — cannot determine the build configuration" >&2
  exit 2
}
eval "$vars"

: "${TKC:?}" "${CFLAGS:?}" "${LIBS:?}" "${STDLIB_SRCS:?}" "${VENDOR_SRCS:?}" "${OOKE_LL:?}"

# std.test is a dependency of the TESTS, not of ooke, so it is named here and
# nowhere else. Everything above comes from the Makefile.
TEST_ONLY_SRCS="$TOKE_STDLIB/tk_test.c $TOKE_STDLIB/test_glue.c"

# ── 1. ooke module IR ───────────────────────────────────────────────────────
# The tests import ooke.* and link against the same IR the binary links.
if ! make -s --no-print-directory $OOKE_LL; then
  echo "error: could not build the ooke module IR (make $OOKE_LL)" >&2
  exit 2
fi

# ── 2. stdlib + vendor archive, built once and reused by every test ─────────
# Linking ~80 C files per test made the suite too slow to run, which is part of
# why it never was. Compile each translation unit once, cache it in build/,
# and archive.
mkdir -p "$OBJ_DIR" "$BIN_DIR"
objs=()
stale=()
for src in $STDLIB_SRCS $VENDOR_SRCS $TEST_ONLY_SRCS; do
  obj="$OBJ_DIR/$(echo "${src#$ROOT/}" | tr '/' '_' | sed 's/\.c$/.o/')"
  objs+=("$obj")
  if [ ! -f "$obj" ] || [ "$src" -nt "$obj" ]; then
    stale+=("$src|$obj")
  fi
done

if [ ${#stale[@]} -gt 0 ]; then
  echo "=== Compiling ${#stale[@]} C translation unit(s) for the test archive ==="
  printf '%s\n' "${stale[@]}" |
    CFLAGS="$CFLAGS" xargs -P "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" -I{} \
      bash -c 'IFS="|" read -r s o <<< "{}"; clang $CFLAGS -c "$s" -o "$o"' || {
        echo "error: stdlib/vendor compile failed" >&2; exit 2; }
fi
rm -f "$LIB"
ar rcs "$LIB" "${objs[@]}" || exit 2

# ── 3. Compile, link and run each test ──────────────────────────────────────
if [ $# -gt 0 ]; then
  tests=()
  for n in "$@"; do tests+=("test/$n/test_$n.tk"); done
else
  tests=(test/*/test_*.tk)
fi

pass=0; fail=0
failed_names=()

for f in "${tests[@]}"; do
  bn=$(basename "$f" .tk)
  ll="$BIN_DIR/$bn.ll"
  exe="$BIN_DIR/$bn"
  log="$BIN_DIR/$bn.log"

  # Compile from src/ so `i=…:ooke.*` imports resolve against the .tki files.
  if ! (cd "$ROOT/src" && "$TKC" --emit-llvm "../$f" --out "$ll") >"$log" 2>&1; then
    printf "  FAIL %-24s (codegen)\n" "$bn"; sed 's/^/       /' "$log" | head -5
    fail=$((fail+1)); failed_names+=("$bn:codegen"); continue
  fi

  if ! clang -x ir "$ll" $OOKE_LL -x none "$LIB" \
        $LDFLAGS $LIBS -o "$exe" >"$log" 2>&1; then
    printf "  FAIL %-24s (link)\n" "$bn"
    grep -v '\-Woverride-module\|warning generated' "$log" | sed 's/^/       /' | head -8
    fail=$((fail+1)); failed_names+=("$bn:link"); continue
  fi

  output=$("$exe" 2>&1); rc=$?

  # std.test assertions are advisory: tk_test_assert_*() prints
  # `DIAGNOSTIC: kind=assertion_failed` to stderr and RETURNS a bool. Every
  # ooke test calls them as bare statements — `(test.eq(a;b));` — and then
  # returns `<true` regardless, so a failed assertion never reached the exit
  # status. Before 134.5 that meant the whole suite could have been green with
  # every assertion in it failing. The runner therefore fails a test on a
  # printed assertion failure as well as on a non-zero exit.
  asserts=$(printf '%s' "$output" | grep -cE 'kind=assertion_failed|^ASSERT(_[A-Z]+)? FAILED|^FAIL: ')

  if [ "$rc" -eq 0 ] && [ "$asserts" -eq 0 ]; then
    printf "  PASS %-24s\n" "$bn"; pass=$((pass+1))
  else
    if [ "$rc" -ne 0 ]; then
      printf "  FAIL %-24s (exit=%d, %s failed assertion(s))\n" "$bn" "$rc" "$asserts"
      failed_names+=("$bn:run($rc)")
    else
      printf "  FAIL %-24s (%s failed assertion(s), exit 0)\n" "$bn" "$asserts"
      failed_names+=("$bn:assert($asserts)")
    fi
    printf '%s\n' "$output" | grep -E 'kind=assertion_failed|^ASSERT(_[A-Z]+)? FAILED|^FAIL: ' | head -6 | sed 's/^/       /'
    fail=$((fail+1))
  fi
done

echo "---"
echo "$pass passed, $fail failed, of $((pass+fail))"
if [ $fail -gt 0 ]; then
  printf '%s\n' "failed: ${failed_names[*]}"
fi
exit $(( fail > 0 ? 1 : 0 ))
