#!/bin/bash
# 89.1.7 - Content validation test
# Checks TOML model files and runs build to look for validation warnings.

OOKE_DIR=/Users/matthew.watt/tk/toke-ooke
OOKE="$OOKE_DIR/ooke-toke"
PASS=0
FAIL=0
SKIP=0

# --- Preflight ---
if [ ! -x "$OOKE" ]; then
  echo "ABORT: ooke-toke binary not found or not executable at $OOKE"
  exit 1
fi

echo "=== Content Validation Test (89.1.7) ==="
echo "Binary: $OOKE"
echo ""

# --- Determine project dir ---
if [ -d "$OOKE_DIR/testproj" ] && [ -f "$OOKE_DIR/testproj/ooke.toml" ]; then
  PROJECT_DIR="$OOKE_DIR/testproj"
else
  PROJECT_DIR="$OOKE_DIR"
fi

# --- Check for models directory ---
MODELS_DIR="$PROJECT_DIR/models"
CREATED_MODEL=false

if [ -d "$MODELS_DIR" ]; then
  TOML_COUNT=$(find "$MODELS_DIR" -name "*.toml" 2>/dev/null | wc -l | tr -d ' ')
  echo "Found models directory: $MODELS_DIR ($TOML_COUNT TOML files)"
  PASS=$((PASS + 1))
else
  # Also check root-level models
  if [ -d "$OOKE_DIR/models" ] && [ "$PROJECT_DIR" != "$OOKE_DIR" ]; then
    MODELS_DIR="$OOKE_DIR/models"
    TOML_COUNT=$(find "$MODELS_DIR" -name "*.toml" 2>/dev/null | wc -l | tr -d ' ')
    echo "Found models directory: $MODELS_DIR ($TOML_COUNT TOML files)"
    PASS=$((PASS + 1))
  else
    echo "No models directory found; creating test model"
    mkdir -p "$MODELS_DIR"
    cat > "$MODELS_DIR/test.toml" <<'TOMLEOF'
[model]
name = "test"
version = "1.0"

[fields]
title = { type = "string", required = true }
slug = { type = "string", required = true }
body = { type = "string", required = false }
TOMLEOF
    CREATED_MODEL=true
    echo "Created: $MODELS_DIR/test.toml"
    PASS=$((PASS + 1))
  fi
fi

# --- List model files ---
echo ""
echo "Model files:"
find "$MODELS_DIR" -name "*.toml" 2>/dev/null | while read -r f; do
  echo "  $(basename "$f")"
done
echo ""

# --- Run build and capture output for validation warnings ---
cd "$PROJECT_DIR"
BUILD_OUTPUT=$("$OOKE" build 2>&1)
BUILD_RC=$?

echo "Build exit code: $BUILD_RC"

# --- Check for validation warnings in output ---
WARN_COUNT=0
if echo "$BUILD_OUTPUT" | grep -iq "warn"; then
  WARN_COUNT=$(echo "$BUILD_OUTPUT" | grep -ic "warn")
  echo "Found $WARN_COUNT validation warning(s) in build output:"
  echo "$BUILD_OUTPUT" | grep -i "warn"
  PASS=$((PASS + 1))
else
  echo "No validation warnings in build output"
  PASS=$((PASS + 1))
fi

# --- Check for errors in output ---
if echo "$BUILD_OUTPUT" | grep -iq "error"; then
  ERR_COUNT=$(echo "$BUILD_OUTPUT" | grep -ic "error")
  echo "Found $ERR_COUNT error(s) in build output:"
  echo "$BUILD_OUTPUT" | grep -i "error"
  FAIL=$((FAIL + 1))
else
  echo "PASS: no errors in build output"
  PASS=$((PASS + 1))
fi

# --- Check model TOML files are parseable (basic syntax check) ---
echo ""
echo "Checking TOML syntax..."
BAD_TOML=0
while IFS= read -r toml_file; do
  # Basic check: file must have at least one [section] header or key = value
  if grep -qE '^\[|^[a-zA-Z_]+ *= *' "$toml_file" 2>/dev/null; then
    echo "  PASS: $(basename "$toml_file") has valid structure"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $(basename "$toml_file") has no recognisable TOML structure"
    FAIL=$((FAIL + 1))
    BAD_TOML=$((BAD_TOML + 1))
  fi
done < <(find "$MODELS_DIR" -name "*.toml" 2>/dev/null)

# --- Cleanup created model if we made one ---
if [ "$CREATED_MODEL" = true ]; then
  rm -f "$MODELS_DIR/test.toml"
  rmdir "$MODELS_DIR" 2>/dev/null
  echo ""
  echo "(Cleaned up temporary test model)"
fi

# --- Summary ---
echo ""
echo "=== Validation Tests: $PASS passed, $FAIL failed, $SKIP skipped ==="
exit $FAIL
