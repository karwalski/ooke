#!/bin/bash
# ooke test runner — compiles and executes all test .tk files
# Requires: make all has been run (ooke modules compiled to src/ooke/)
set -o pipefail

TKC="/Users/matthew.watt/tk/toke/toke"
TOKE_ROOT="/Users/matthew.watt/tk/toke"
TOKE_STDLIB="$TOKE_ROOT/src/stdlib"
TOKE_VENDOR="$TOKE_ROOT/stdlib/vendor"
OOKE_DIR="src/ooke"
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"

# All ooke IR modules
OOKE_MODS="$OOKE_DIR/config $OOKE_DIR/store $OOKE_DIR/router $OOKE_DIR/template \
  $OOKE_DIR/validate $OOKE_DIR/repair $OOKE_DIR/run $OOKE_DIR/build $OOKE_DIR/serve \
  $OOKE_DIR/apihealth $OOKE_DIR/handlers"

# Stdlib C sources needed
STDLIB_C="\
  $TOKE_STDLIB/tk_runtime.c $TOKE_STDLIB/args.c \
  $TOKE_STDLIB/str.c $TOKE_STDLIB/str_glue.c \
  $TOKE_STDLIB/collections.c $TOKE_STDLIB/collections_glue.c \
  $TOKE_STDLIB/toml.c $TOKE_STDLIB/toml_glue.c \
  $TOKE_STDLIB/file.c $TOKE_STDLIB/file_glue.c \
  $TOKE_STDLIB/path.c $TOKE_STDLIB/path_glue.c \
  $TOKE_STDLIB/io_glue.c \
  $TOKE_STDLIB/env.c $TOKE_STDLIB/env_glue.c \
  $TOKE_STDLIB/crypto.c $TOKE_STDLIB/crypto_glue.c \
  $TOKE_STDLIB/tk_time.c $TOKE_STDLIB/time_glue.c \
  $TOKE_STDLIB/log.c $TOKE_STDLIB/log_glue.c \
  $TOKE_STDLIB/json.c $TOKE_STDLIB/json_glue.c \
  $TOKE_STDLIB/encoding.c $TOKE_STDLIB/encoding_glue.c \
  $TOKE_STDLIB/md.c $TOKE_STDLIB/md_glue.c \
  $TOKE_STDLIB/math.c $TOKE_STDLIB/math_glue.c \
  $TOKE_STDLIB/process.c $TOKE_STDLIB/process_glue.c \
  $TOKE_STDLIB/http.c $TOKE_STDLIB/http2.c \
  $TOKE_STDLIB/net.c $TOKE_STDLIB/ws.c $TOKE_STDLIB/router.c \
  $TOKE_STDLIB/acme.c $TOKE_STDLIB/proxy.c $TOKE_STDLIB/cache.c \
  $TOKE_STDLIB/content.c $TOKE_STDLIB/security.c $TOKE_STDLIB/metrics.c \
  $TOKE_STDLIB/server_ops.c $TOKE_STDLIB/ws_server.c $TOKE_STDLIB/hooks.c \
  $TOKE_STDLIB/tk_web_glue.c \
  $TOKE_STDLIB/tk_test.c $TOKE_STDLIB/test_glue.c \
  $TOKE_STDLIB/db.c $TOKE_STDLIB/db_glue.c \
  $TOKE_STDLIB/csv.c $TOKE_STDLIB/csv_glue.c \
  $TOKE_STDLIB/template.c $TOKE_STDLIB/template_glue.c \
  $TOKE_STDLIB/auth.c $TOKE_STDLIB/encrypt.c \
  $TOKE_STDLIB/html.c $TOKE_STDLIB/svg.c $TOKE_STDLIB/canvas.c \
  $TOKE_STDLIB/chart.c $TOKE_STDLIB/dashboard.c \
  $TOKE_STDLIB/dataframe.c $TOKE_STDLIB/analytics.c \
  $TOKE_STDLIB/ml.c $TOKE_STDLIB/llm.c $TOKE_STDLIB/llm_tool.c \
  $TOKE_STDLIB/sse.c $TOKE_STDLIB/toon.c $TOKE_STDLIB/yaml.c \
  $TOKE_STDLIB/i18n.c $TOKE_STDLIB/sys.c $TOKE_STDLIB/mem.c \
  $TOKE_STDLIB/os.c $TOKE_STDLIB/task.c"

VENDOR_C="$TOKE_VENDOR/tomlc99/toml.c $(ls $TOKE_VENDOR/cmark/src/*.c | grep -v main.c | tr '\n' ' ')"

CFLAGS="-O1 -Wno-implicit-function-declaration -Wno-pedantic -D_GNU_SOURCE -DTK_HAVE_OPENSSL"
INCLUDES="-I $TOKE_STDLIB -I $TOKE_VENDOR/cmark/src -I $TOKE_VENDOR/tomlc99 -I/opt/homebrew/include"
LDFLAGS="-L/opt/homebrew/lib -lm -lz -lssl -lcrypto -lsqlite3"

pass=0; fail=0; skip=0

cd "$(dirname "$0")/.."

for f in test/*/test_*.tk; do
  bn=$(basename "$f" .tk)

  # 1. Compile test to IR (from src/ so imports resolve)
  cd /Users/matthew.watt/tk/toke-ooke/src
  if ! $TKC --emit-llvm "../$f" --out "/tmp/${bn}.ll" 2>/dev/null; then
    printf "  SKIP %-30s (codegen)\n" "$bn"; skip=$((skip+1)); cd /Users/matthew.watt/tk/toke-ooke; continue
  fi
  cd /Users/matthew.watt/tk/toke-ooke

  # 2. Link test IR + all ooke modules + stdlib
  if ! clang $CFLAGS $INCLUDES -x ir "/tmp/${bn}.ll" $OOKE_MODS \
    -x c $STDLIB_C $VENDOR_C $LDFLAGS -o "/tmp/${bn}" 2>/dev/null; then
    printf "  SKIP %-30s (link)\n" "$bn"; skip=$((skip+1)); continue
  fi

  # 3. Run
  output=$("/tmp/${bn}" 2>&1)
  rc=$?
  if [ $rc -eq 0 ]; then
    printf "  PASS %-30s\n" "$bn"; pass=$((pass+1))
  else
    printf "  FAIL %-30s (exit=%d)\n" "$bn" "$rc"; fail=$((fail+1))
    echo "$output" | grep -i "fail\|assert" | head -3 | sed 's/^/       /'
  fi
  rm -f "/tmp/${bn}.ll" "/tmp/${bn}"
done

echo "---"
echo "$pass passed, $fail failed, $skip skipped"
exit $((fail + skip))
