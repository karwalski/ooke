#!/bin/sh
# stage_install.sh — lay out an ooke installation tree (story 134.46).
#
# Usage: scripts/stage_install.sh <dest>      (run after `make`)
#
# `ooke compile` runs scripts/gen_app_makefile.sh, which needs ooke's Makefile
# (`make print-build-vars`, the single source of the build variables), the
# module sources and interfaces under src/ (page handlers compile with
# `-I $(OOKE_DIR)/src`), and ooke's compiled modules under src/ooke/ (linked
# into the app). 134.45 made ooke find the script beside its own binary, but
# every release artefact shipped the binary alone, so an installed ooke could
# not compile. This script is the one definition of what an installation
# holds; the release workflow, scripts/package_release.sh and the install
# test all call it, so they cannot drift apart.
#
# Layout of <dest>:
#   ooke                          the binary
#   Makefile                      for `make print-build-vars`
#   scripts/gen_app_makefile.sh   run by `ooke compile`
#   scripts/gen_handlers.sh       run by gen_app_makefile.sh
#   scripts/emit_deps.sh          run by the Makefile: the stdlib C sources
#                                 and link flags, from tkc --emit-deps (121.76)
#   src/*.tk, src/*.tki           module sources and interfaces (tkc writes
#                                 each as src/ooke.<mod>.tki)
#   src/ooke/                     compiled modules (LLVM IR)
#
# The compiled modules are shipped rather than rebuilt at compile time: the
# generated Makefile.serve rebuilds them only when one is MISSING, which would
# write into the installation (a Homebrew Cellar) and need ooke's own
# ooke.toml and pages/, which an installation deliberately does not carry
# (134.10).
set -eu
cd "$(dirname "$0")/.."
dest=${1:?usage: scripts/stage_install.sh <dest>}

[ -x ooke-toke ] || { echo "stage_install: no ooke-toke binary (run make first)" >&2; exit 1; }
mods=$(make -s --no-print-directory print-build-vars TOKE_ROOT="${TOKE_ROOT:-../toke}" \
       | sed -n 's/^OOKE_LL="\(.*\)"$/\1/p')
[ -n "$mods" ] || { echo "stage_install: print-build-vars gave no OOKE_LL" >&2; exit 1; }
for m in $mods; do
  [ -f "$m" ] || {
    echo "stage_install: compiled module $m is missing -- run make first" >&2; exit 1; }
done

mkdir -p "$dest/scripts" "$dest/src/ooke"
cp ooke-toke "$dest/ooke"
chmod +x "$dest/ooke"
cp Makefile "$dest/"
cp scripts/gen_app_makefile.sh scripts/gen_handlers.sh scripts/emit_deps.sh "$dest/scripts/"
chmod +x "$dest/scripts/"*.sh
cp src/*.tk src/*.tki "$dest/src/"
for m in $mods; do cp "$m" "$dest/src/ooke/"; done
echo "stage_install: $dest ($(echo $mods | wc -w | tr -d ' ') compiled modules)"
