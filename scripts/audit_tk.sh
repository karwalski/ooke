#!/usr/bin/env bash
# audit_tk.sh — story 134.1 evidence harness for toke-ooke.
#
# Runs `tkc --check` and `tkc --lint` over every .tk file in the repo with the
# interface search path the build actually needs (-I src), and prints a
# machine-readable summary. Read-only: it never writes to any source file.
#
# Usage:  scripts/audit_tk.sh [check|lint|all]   (run from the repo root)
# Env:    TKC=/path/to/toke   (default: /Users/matthew.watt/tk/toke/tkc)

set -uo pipefail
TKC="${TKC:-/Users/matthew.watt/tk/toke/tkc}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
MODE="${1:-all}"

files() { find . -name '*.tk' -not -path './.git/*' | sort; }

do_check() {
  echo "=== tkc --check -I src (toke $($TKC --version | awk '{print $2}')) ==="
  local pass=0 fail=0
  for f in $(files); do
    if out=$("$TKC" --check --diag-text -I src "$f" 2>&1); then
      pass=$((pass+1)); printf 'PASS  %s\n' "$f"
    else
      fail=$((fail+1))
      printf 'FAIL  %s  %s\n' "$f" \
        "$(printf '%s' "$out" | grep -Eo '^(error|warning)\[[A-Z][0-9]+\]' | sort | uniq -c | tr -s ' \n' ' ')"
    fi
  done
  echo "--- check: $pass passed, $fail failed"
}

do_lint() {
  echo "=== tkc --lint -I src : diagnostics by code ==="
  for f in $(files); do
    "$TKC" --lint --diag-json -I src "$f" 2>&1
  done | python3 -c '
import sys, json, collections
by_code = collections.Counter(); by_sev = collections.Counter()
per_file = collections.defaultdict(collections.Counter)
for line in sys.stdin:
    line = line.strip()
    if not line.startswith("{"): continue
    try: d = json.loads(line)
    except Exception: continue
    code = d.get("error_code") or d.get("code") or "?"
    sev = d.get("severity", "?")
    by_code[(sev, code)] += 1; by_sev[sev] += 1
    per_file[d.get("file", "?")][(sev, code)] += 1
for (sev, code), n in sorted(by_code.items(), key=lambda kv: (-kv[1], kv[0])):
    print(f"  {n:5d}  {sev:8s} {code}")
print("  ----- by severity: " + ", ".join(f"{s}={n}" for s, n in sorted(by_sev.items())))
print()
print("=== per file ===")
for fn in sorted(per_file):
    items = ", ".join(f"{c}x{n}" for (s, c), n in sorted(per_file[fn].items()))
    print(f"  {sum(per_file[fn].values()):4d}  {fn}  [{items}]")
'
}

case "$MODE" in
  check) do_check ;;
  lint)  do_lint ;;
  all)   do_check; echo; do_lint ;;
  *) echo "usage: $0 [check|lint|all]" >&2; exit 2 ;;
esac
