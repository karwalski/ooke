#!/bin/sh
# handler_pages.sh — list the handler pages gen_handlers.sh puts in the
# registry, one per line as  file|name|module  (story 134.47).
#
#   file    the page, as found under PAGES_DIR
#   name    the registry's alias for it, formed exactly as gen_handlers.sh
#           forms it (path under PAGES_DIR, no .tk, slashes dropped)
#   module  the page's m= module path
#
# ooke's Makefile reads this to compile the pages the registry imports.
#
# Usage: ./scripts/handler_pages.sh [pages_dir]
PAGES_DIR="${1:-pages}"
[ -d "$PAGES_DIR" ] || exit 0
for f in $(find "$PAGES_DIR" -name '*.tk' -type f | sort); do
  grep -q -e 'f=get(' -e 'f=post(' "$f" 2>/dev/null || continue
  n=$(echo "$f" | sed "s|^${PAGES_DIR}||; s|\.tk$||; s|^/||; s|/||g")
  [ -n "$n" ] || n=index
  m=$(grep '^m=' "$f" | head -1 | sed 's/m=//; s/;.*//')
  echo "$f|$n|$m"
done
