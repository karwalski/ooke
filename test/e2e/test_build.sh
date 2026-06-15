#!/bin/bash
# 89.1.6 - Build pipeline test
# Runs ooke-toke build and verifies output directory and generated files.

OOKE_DIR=/Users/matthew.watt/tk/toke-ooke
OOKE="$OOKE_DIR/ooke-toke"
PASS=0
FAIL=0

# --- Preflight ---
if [ ! -x "$OOKE" ]; then
  echo "ABORT: ooke-toke binary not found or not executable at $OOKE"
  exit 1
fi

# Determine project directory: prefer testproj/ if it exists
if [ -d "$OOKE_DIR/testproj" ] && [ -f "$OOKE_DIR/testproj/ooke.toml" ]; then
  PROJECT_DIR="$OOKE_DIR/testproj"
  echo "=== Build Pipeline Test (89.1.6) ==="
  echo "Using testproj fixture: $PROJECT_DIR"
elif [ -f "$OOKE_DIR/ooke.toml" ]; then
  PROJECT_DIR="$OOKE_DIR"
  echo "=== Build Pipeline Test (89.1.6) ==="
  echo "Using root project: $PROJECT_DIR"
else
  echo "ABORT: no ooke.toml found in testproj/ or project root"
  exit 1
fi

echo "Binary: $OOKE"
echo ""

# --- Read expected output dir from ooke.toml ---
BUILD_DIR="$PROJECT_DIR/build"

# --- Clean previous build ---
rm -rf "$BUILD_DIR"

# --- Run build ---
echo "Running build..."
cd "$PROJECT_DIR"
BUILD_OUTPUT=$("$OOKE" build 2>&1)
BUILD_RC=$?

if [ $BUILD_RC -ne 0 ]; then
  echo "FAIL: ooke-toke build exited with code $BUILD_RC"
  echo "$BUILD_OUTPUT"
  FAIL=$((FAIL + 1))
else
  echo "PASS: ooke-toke build exited cleanly"
  PASS=$((PASS + 1))
fi

# --- Test: build output directory exists ---
if [ -d "$BUILD_DIR" ]; then
  echo "PASS: build output directory exists ($BUILD_DIR)"
  PASS=$((PASS + 1))
else
  echo "FAIL: build output directory missing ($BUILD_DIR)"
  FAIL=$((FAIL + 1))
  echo ""
  echo "=== Build Tests: $PASS passed, $FAIL failed ==="
  exit $FAIL
fi

# --- Test: index.html was generated ---
if [ -f "$BUILD_DIR/index.html" ]; then
  echo "PASS: index.html was generated"
  PASS=$((PASS + 1))
else
  echo "FAIL: index.html not found in build output"
  FAIL=$((FAIL + 1))
fi

# --- Test: index.html contains <html> structure ---
if grep -q "<html" "$BUILD_DIR/index.html" 2>/dev/null; then
  echo "PASS: index.html contains <html> tag"
  PASS=$((PASS + 1))
else
  echo "FAIL: index.html missing <html> tag"
  FAIL=$((FAIL + 1))
fi

# --- Test: index.html contains <body> ---
if grep -q "<body" "$BUILD_DIR/index.html" 2>/dev/null; then
  echo "PASS: index.html contains <body> tag"
  PASS=$((PASS + 1))
else
  echo "FAIL: index.html missing <body> tag"
  FAIL=$((FAIL + 1))
fi

# --- Test: index.html is non-empty ---
if [ -s "$BUILD_DIR/index.html" ]; then
  echo "PASS: index.html is non-empty"
  PASS=$((PASS + 1))
else
  echo "FAIL: index.html is empty"
  FAIL=$((FAIL + 1))
fi

# --- Test: build directory has reasonable size ---
BUILD_SIZE=$(du -sk "$BUILD_DIR" | cut -f1)
if [ "$BUILD_SIZE" -ge 1 ]; then
  echo "PASS: build directory size ${BUILD_SIZE}KB >= 1KB"
  PASS=$((PASS + 1))
else
  echo "FAIL: build directory size ${BUILD_SIZE}KB seems too small"
  FAIL=$((FAIL + 1))
fi

# --- Summary ---
echo ""
echo "=== Build Tests: $PASS passed, $FAIL failed ==="
exit $FAIL
