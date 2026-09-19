#!/usr/bin/env bash
#
# ooke release packager — story 134.10.
#
# Produces, into dist/, everything a downstream project needs to depend on
# ooke, and nothing that only exists in somebody's working tree:
#
#   ooke-<ver>-src.tar.gz              `git archive` of HEAD — TRACKED files only
#   ooke-<ver>-<platform>.tar.gz       the built binary + the docs to use it
#   ooke-<ver>.manifest.txt            what was built, from what, by what
#   SHA256SUMS
#
# The source tarball is `git archive` and not `tar .` on purpose.  Two defects
# in one week (ooke's test/support, story 134.21; toke's stdlib/vendor, story
# 127.85) were invisible in the working tree and fatal in a fresh clone,
# because the working tree had files a clone does not.  A packager that tars
# the working tree cannot see that class of defect; one that archives the
# index can only ever ship what a clone gets.
#
# Nothing here pushes, tags, publishes or uploads.  See docs/RELEASING.md for
# the single step that does.
#
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

VERSION=$(cat VERSION)
PLATFORM="$(uname -s | tr 'A-Z' 'a-z')-$(uname -m)"
DIST="$ROOT/dist"
STAMP="ooke-$VERSION"

TOKE_ROOT=${TOKE_ROOT:-$(cd "$ROOT/../toke" 2>/dev/null && pwd || echo "")}
TKC=${TKC:-${TOKE_ROOT:+$TOKE_ROOT/toke}}

say() { printf '\n== %s\n' "$*"; }

# ── 1. Refuse to package something unreproducible ───────────────────────────
say "Preflight"
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: the working tree is dirty.  A release must name a commit that" >&2
  echo "       anyone else can check out.  Commit or stash first:" >&2
  git status --short >&2
  exit 1
fi
OOKE_COMMIT=$(git rev-parse HEAD)
OOKE_SHORT=$(git rev-parse --short HEAD)
echo "ooke $VERSION @ $OOKE_SHORT"

[ -n "${TOKE_ROOT:-}" ] && [ -x "${TKC:-}" ] || {
  echo "ERROR: no toke compiler.  Set TOKE_ROOT (and optionally TKC)." >&2
  echo "       See docs/install.md." >&2; exit 1; }

# The floor gate, the type check, and the suite.  A package built from a tree
# whose tests were not run is the thing 134.5 and 134.17 were about.
make --no-print-directory check-versions
make --no-print-directory test 2>&1 | grep -E '^(  (PASS|FAIL)|[0-9]+ passed|  [0-9]+ passed)' | tail -20
TOKE_COMMIT=$(git -C "$TOKE_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown")
TOKE_SHORT=$(git -C "$TOKE_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
TOKE_DATE=$(git -C "$TOKE_ROOT" log -1 --format=%cs 2>/dev/null || echo "unknown")
TKC_SHA=$(shasum -a 256 "$TKC" | awk '{print $1}')

rm -rf "$DIST"; mkdir -p "$DIST"

# ── 2. Source tarball — exactly what a fresh clone gets ─────────────────────
say "Source tarball"
git archive --format=tar --prefix="$STAMP/" HEAD | gzip -9 > "$DIST/$STAMP-src.tar.gz"
echo "$DIST/$STAMP-src.tar.gz  ($(git ls-files | wc -l | tr -d ' ') tracked files)"

# ── 3. Binary tarball ───────────────────────────────────────────────────────
say "Binary tarball ($PLATFORM)"
STAGE="$DIST/$STAMP-$PLATFORM"
mkdir -p "$STAGE"
cp ooke-toke "$STAGE/ooke"
cp VERSION LICENSE README.md "$STAGE/"
cp docs/install.md docs/versioning.md docs/public-api.md \
   docs/release-notes-3.0.0.md CHANGELOG.md "$STAGE/"
tar -czf "$DIST/$STAMP-$PLATFORM.tar.gz" -C "$DIST" "$STAMP-$PLATFORM"
rm -rf "$STAGE"

# ── 4. Manifest ─────────────────────────────────────────────────────────────
say "Manifest"
{
  echo "ooke release manifest"
  echo "built            $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "ooke version     $VERSION"
  echo "ooke commit      $OOKE_COMMIT"
  echo "platform         $PLATFORM"
  echo
  echo "toke commit      $TOKE_COMMIT ($TOKE_DATE)"
  echo "toke compiler    $TKC"
  echo "toke compiler    sha256 $TKC_SHA"
  echo
  echo "declared floor   $(sed -n 's/^mintoke *= *"\(.*\)"/mintoke       \1/p'       ooke.toml)"
  echo "                 $(sed -n 's/^mintokedate *= *"\(.*\)"/mintokedate   \1/p'   ooke.toml)"
  echo "                 $(sed -n 's/^mintokecommit *= *"\(.*\)"/mintokecommit \1/p' ooke.toml)"
} > "$DIST/$STAMP.manifest.txt"
cat "$DIST/$STAMP.manifest.txt"

# ── 5. Checksums ────────────────────────────────────────────────────────────
( cd "$DIST" && shasum -a 256 ./*.tar.gz ./*.manifest.txt > SHA256SUMS )
say "dist/"
ls -la "$DIST"
echo
echo "Nothing has been tagged, pushed or published.  See docs/RELEASING.md."
