#!/bin/sh
# emit_deps.sh — ask tkc which toke stdlib C sources and link flags a set of
# toke programs needs (story 121.76).
#
# Usage: scripts/emit_deps.sh TKC STDLIB_DIR [TKC-ARG]... -- FILE.tk...
#
# TKC-ARGs (-I DIR, --max-imports=N) are passed to every tkc run.
#
# ooke used to link a hand-kept list of toke's stdlib C files.  When toke moved
# os.write's wrapper into a new file (os_glue.c, toke 121.70) ooke stopped
# linking against toke main -- `Undefined symbols: _tk_os_write_w` -- until the
# file was added to the list by hand.  The authoritative list is toke's own
# module manifest (src/stdlib_deps.c, toke 127.99), which `tkc --emit-deps`
# prints for one program; toke-website builds from it since 132.105.  This
# script runs it over every module that goes into one binary and prints the
# union, one entry per line, in first-seen order:
#
#   src:<path>        a toke stdlib C source   (<toke>/src/stdlib/...)
#   vendor:<path>     a vendored C source      (<toke>/stdlib/vendor/...)
#   lib:<flag>        a link flag; "-framework X" stays one entry, spelled
#                     lib:-framework@X, so the pair is never split or reordered
#
# Paths are normalised (`a/b/../c` -> `a/c`): tkc spells vendored sources
# through the stdlib directory (src/stdlib/../../stdlib/vendor/...), and one
# file listed under two spellings would be compiled -- and defined -- twice.
#
# Every FILE must type-check far enough for tkc to resolve its imports (pass
# the -I directories and flags its build uses).  Any failure is fatal and names the file:
# a partial list would fail later as a bare undefined symbol, which is the
# defect this script exists to remove.
set -u

tkc=${1:?usage: emit_deps.sh TKC STDLIB_DIR [TKC-ARG]... -- FILE.tk...}
stdlib=${2:?usage: emit_deps.sh TKC STDLIB_DIR [TKC-ARG]... -- FILE.tk...}
shift 2
incs=""
while [ $# -gt 0 ] && [ "$1" != "--" ]; do incs="$incs $1"; shift; done
[ "${1:-}" = "--" ] && shift
[ $# -gt 0 ] || { echo "emit_deps: no toke sources given" >&2; exit 2; }
[ -f "$stdlib/tk_runtime.c" ] || {
  echo "emit_deps: $stdlib is not a toke stdlib directory (no tk_runtime.c)" >&2; exit 2; }

raw=$(mktemp "${TMPDIR:-/tmp}/ooke-emit-deps.XXXXXX") || exit 2
trap 'rm -f "$raw"' EXIT

for f in "$@"; do
  # shellcheck disable=SC2086  # $incs is a word list of tkc arguments
  if ! TKC_STDLIB_DIR="$stdlib" "$tkc" --emit-deps $incs "$f" >>"$raw" 2>/dev/null; then
    echo "emit_deps: '$tkc --emit-deps$incs $f' failed:" >&2
    TKC_STDLIB_DIR="$stdlib" "$tkc" --emit-deps --diag-text $incs "$f" 2>&1 >/dev/null |
      grep -v 'W1001' | head -8 | sed 's/^/    /' >&2
    exit 1
  fi
  echo '@@end' >>"$raw"
done

# Per program: C sources, then `---` and link flags, then (when it imports
# non-std modules) `---` and those modules as <path>.ll.  The flags section is
# printed only when there are flags, so a section is recognised as the module
# list by its .ll lines, not by its position.
awk '
  function norm(p) { while (sub(/\/[^\/.][^\/]*\/\.\.\//, "/", p)) ; return p }
  function put(e) { if (!(e in seen)) { seen[e] = 1; print e } }
  $0 == "@@end" { sec = 0; fw = 0; next }
  $0 == "---"   { sec++; fw = 0; next }
  $0 == ""      { next }
  sec == 0 {
    p = norm($0)
    put((p ~ /\/stdlib\/vendor\// ? "vendor:" : "src:") p)
    next
  }
  fw { put("lib:-framework@" $0); fw = 0; next }
  $0 == "-framework" { fw = 1; next }
  /\.ll$/ { next }
  { put("lib:" $0) }
' "$raw"
