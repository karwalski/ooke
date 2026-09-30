#!/bin/sh
# check_companions.sh — story 121.63: every src/*.tkc.md describes the source
# it names.
#
# A companion's front matter carries `source_hash`, the SHA-256 of the .tk it
# documents. Nothing checked it, and 9 of 13 companions had drifted from their
# source unnoticed. This fails, listing each stale companion, when a
# source_hash does not match its source, when a companion names a source that
# does not exist, or when it has no source_hash.
#
# Skipped: companions of GENERATED sources (src/_*.tk, e.g. _handlers.tk from
# pages/ and _floor.tk from ooke.toml). Those files are build output, not
# tracked, and their content depends on the project, so no fixed hash can
# match them.
#
# Refresh a companion: update its text to the source, then set
#   source_hash: "<shasum -a 256 src/<m>.tk>"
#
# Usage: scripts/check_companions.sh [srcdir]     (default: src)
set -u

cd "$(dirname "$0")/.." || exit 2
SRCDIR=${1:-src}

if command -v shasum >/dev/null 2>&1; then
  sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
elif command -v sha256sum >/dev/null 2>&1; then
  sha() { sha256sum "$1" | cut -d' ' -f1; }
else
  echo "error: need shasum or sha256sum" >&2; exit 2
fi

echo "=== companion source_hash check ($SRCDIR/*.tkc.md) ==="
ok=0; stale=0; skipped=0
for md in "$SRCDIR"/*.tkc.md; do
  [ -f "$md" ] || continue
  src=$(sed -n 's/^source_file: *"\(.*\)"$/\1/p' "$md" | head -1)
  want=$(sed -n 's/^source_hash: *"\([0-9a-f]*\)"$/\1/p' "$md" | head -1)
  [ -n "$src" ] || src=$(basename "$md" .tkc.md).tk
  case $src in _*) skipped=$((skipped+1)); continue ;; esac
  if [ ! -f "$SRCDIR/$src" ]; then
    echo "  STALE $md: its source $SRCDIR/$src does not exist"; stale=$((stale+1)); continue
  fi
  if [ -z "$want" ]; then
    echo "  STALE $md: no source_hash"; stale=$((stale+1)); continue
  fi
  got=$(sha "$SRCDIR/$src")
  if [ "$got" = "$want" ]; then
    ok=$((ok+1))
  else
    echo "  STALE $md: source_hash ${want%"${want#????????????}"}… but $SRCDIR/$src is ${got%"${got#????????????}"}…"
    stale=$((stale+1))
  fi
done
echo "  $ok current, $stale stale, $skipped skipped (generated source)"
if [ "$stale" -gt 0 ]; then
  echo "  Refresh each stale companion to its source and set its source_hash." >&2
  exit 1
fi
