#!/bin/bash
# testmod.sh — compile + link + RUN ooke tests against current toke core.
#
# Usage:
#   scripts/testmod.sh            # run every test/*/test_*.tk
#   scripts/testmod.sh config     # run only test/config/test_config.tk
#
# Compiles all src/*.tk modules (except main.tk, whose f=main collides with the
# test's f=main) to IR, then for each requested test compiles it, links against
# the module IRs + the full toke stdlib C + vendored C, and runs it.
# Exit 0 iff all requested tests pass. No C lives here — we only LINK toke core.
set -o pipefail

TKC=/Users/matthew.watt/tk/toke/toke
ROOT=/Users/matthew.watt/tk/toke
S="$ROOT/src/stdlib"; V="$ROOT/stdlib/vendor"
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP=/tmp/ooke_pure; mkdir -p "$TMP"

CFLAGS="-O1 -Wno-implicit-function-declaration -Wno-pedantic -D_GNU_SOURCE -DTK_HAVE_OPENSSL"
INC="-I $S -I $V/cmark/src -I $V/tomlc99 -I/opt/homebrew/include"
LD="-L/opt/homebrew/lib -lm -lz -lssl -lcrypto -lsqlite3"
STDLIB_C="$S/tk_runtime.c $S/args.c $S/args_glue.c $S/str.c $S/str_glue.c \
  $S/collections.c $S/collections_glue.c $S/toml.c $S/toml_glue.c \
  $S/file.c $S/file_glue.c $S/path.c $S/path_glue.c $S/io_glue.c \
  $S/env.c $S/env_glue.c $S/crypto.c $S/crypto_glue.c $S/tk_time.c $S/time_glue.c \
  $S/log.c $S/log_glue.c $S/json.c $S/json_glue.c $S/encoding.c $S/encoding_glue.c \
  $S/md.c $S/md_glue.c $S/math.c $S/math_glue.c $S/process.c $S/process_glue.c \
  $S/http.c $S/http2.c $S/net.c $S/ws.c $S/router.c $S/acme.c $S/proxy.c $S/cache.c \
  $S/content.c $S/metrics.c $S/server_ops.c $S/ws_server.c $S/hooks.c \
  $S/tk_web_glue.c $S/tk_test.c $S/test_glue.c $S/db.c $S/db_glue.c \
  $S/csv.c $S/csv_glue.c $S/template.c $S/template_glue.c $S/auth.c $S/encrypt.c \
  $S/html.c $S/svg.c $S/canvas.c $S/chart.c $S/dashboard.c $S/dataframe.c \
  $S/analytics.c $S/ml.c $S/llm.c $S/llm_tool.c $S/sse.c $S/toon.c $S/yaml.c \
  $S/i18n.c $S/sys.c $S/mem.c $S/os.c $S/task.c"
VENDOR_C="$V/tomlc99/toml.c $(ls $V/cmark/src/*.c | grep -v main.c | tr '\n' ' ')"

# 0. Cross-module imports (build/serve/cli → siblings) resolve via the
# src/ooke.<mod>.tki interface files. These are committed (113.B.16) because
# `--emit-interface` is currently unreliable on several modules (113.B.19);
# they are signature-stable so they resolve imports correctly. If absent
# (e.g. a brand-new module), regenerate that module's .tki standalone:
#   cd src && tkc --emit-interface --emit-llvm --out ooke/<mod> <mod>.tk
cd "$REPO/src" || exit 2

# 1. Compile every module (except main) to IR. A module that fails to compile
# is SKIPPED with a warning (not a hard error) — e.g. not-yet-rebuilt modules.
# A test that genuinely needs a skipped module will then fail at the link step.
MODS=""
for f in *.tk; do
  [ "$f" = "main.tk" ] && continue
  bn="${f%.tk}"
  if ! $TKC --emit-llvm "$f" --out "$TMP/mod_$bn.ll" 2>"$TMP/mod_$bn.err"; then
    echo "  warn: module $f does not compile (skipping; rebuild pending?)"; continue
  fi
  MODS="$MODS $TMP/mod_$bn.ll"
done

# 2. Run requested tests.
pass=0; fail=0
for tf in "$REPO"/test/*/test_*.tk; do
  bn=$(basename "$tf" .tk)
  if [ -n "$1" ] && [ "$bn" != "test_$1" ]; then continue; fi
  if ! $TKC --emit-llvm "$tf" --out "$TMP/$bn.ll" 2>"$TMP/$bn.err"; then
    echo "  FAIL $bn (test codegen)"; head -3 "$TMP/$bn.err"; fail=$((fail+1)); continue
  fi
  if ! clang $CFLAGS $INC -x ir "$TMP/$bn.ll" $MODS -x c $STDLIB_C $VENDOR_C $LD -o "$TMP/$bn" 2>"$TMP/$bn.link.err"; then
    echo "  FAIL $bn (link)"; tail -4 "$TMP/$bn.link.err"; fail=$((fail+1)); continue
  fi
  out=$("$TMP/$bn" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then echo "  PASS $bn"; pass=$((pass+1));
  else echo "  FAIL $bn (exit=$rc)"; echo "$out" | grep -iE "fail|assert|expect" | head -3 | sed 's/^/       /'; fail=$((fail+1)); fi
done
echo "--- $pass passed, $fail failed"
exit $((fail))
