#!/bin/sh
# gen_handlers.sh — Scan pages/*.tk, generate handler registration module.
#
# Convention: pages/api/health.tk exports f=get(req:i64):i64 and/or f=post(req:i64):i64
# Generated _handlers.tk imports each page module and registers handlers.
#
# Usage: ./scripts/gen_handlers.sh <pages_dir> <output_file>

set -e

PAGES_DIR="${1:-pages}"
OUTPUT="${2:-src/_handlers.tk}"

HANDLERS=""
for tkfile in $(find "$PAGES_DIR" -name '*.tk' -type f | sort); do
  has_get=0
  has_post=0
  grep -q 'f=get(' "$tkfile" 2>/dev/null && has_get=1
  grep -q 'f=post(' "$tkfile" 2>/dev/null && has_post=1

  if [ "$has_get" -eq 1 ] || [ "$has_post" -eq 1 ]; then
    rel=$(echo "$tkfile" | sed "s|^${PAGES_DIR}||; s|\.tk$||")
    pattern=$(echo "$rel" | sed 's|/index$||')
    [ -z "$pattern" ] && pattern="/"
    modname=$(echo "$rel" | sed 's|^/||; s|/||g')
    [ -z "$modname" ] && modname="index"

    modpath=$(grep '^m=' "$tkfile" | head -1 | sed 's/m=//; s/;//')
    HANDLERS="$HANDLERS $tkfile|$pattern|$modname|$has_get|$has_post|$modpath"
  fi
done

cat > "$OUTPUT" << 'HEADER'
m=ooke.handlers;
i=http:std.http;
HEADER

for entry in $HANDLERS; do
  IFS='|' read -r tkfile pattern modname has_get has_post modpath << EOF
$entry
EOF
  echo "i=${modname}:${modpath};" >> "$OUTPUT"
done

for entry in $HANDLERS; do
  IFS='|' read -r tkfile pattern modname has_get has_post modpath << EOF
$entry
EOF
  if [ "$has_get" -eq 1 ]; then
    echo "" >> "$OUTPUT"
    echo "f=h${modname}get(req:i64):i64{" >> "$OUTPUT"
    echo "  <${modname}.get(req)" >> "$OUTPUT"
    echo "};" >> "$OUTPUT"
  fi
  if [ "$has_post" -eq 1 ]; then
    echo "" >> "$OUTPUT"
    echo "f=h${modname}post(req:i64):i64{" >> "$OUTPUT"
    echo "  <${modname}.post(req)" >> "$OUTPUT"
    echo "};" >> "$OUTPUT"
  fi
done

echo "" >> "$OUTPUT"
echo "f=registerall():@\$str{" >> "$OUTPUT"
echo "  let paths=mut.@(\$str);" >> "$OUTPUT"

for entry in $HANDLERS; do
  IFS='|' read -r tkfile pattern modname has_get has_post modpath << EOF
$entry
EOF
  if [ "$has_get" -eq 1 ]; then
    echo "  (http.get(\"${pattern}\";&h${modname}get));" >> "$OUTPUT"
    echo "  paths=paths.append(\"${pattern}\");" >> "$OUTPUT"
  fi
  if [ "$has_post" -eq 1 ]; then
    echo "  (http.post(\"${pattern}\";&h${modname}post));" >> "$OUTPUT"
  fi
done

echo "  <paths" >> "$OUTPUT"
echo "};" >> "$OUTPUT"

echo "Generated: $OUTPUT ($(echo $HANDLERS | wc -w | tr -d ' ') handler modules)"
