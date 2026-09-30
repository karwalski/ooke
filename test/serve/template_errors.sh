#!/bin/sh
# Story 121.59: a template that fails to render is a failure the user can see.
#
#   serve  A page whose template fails answered 200 -- an empty-template
#          fallback page, or nothing at all for a content page -- and the
#          only trace was a log line. It must answer 500 with a short generic
#          body that names no template, path or error, and the server log
#          must name the route and the template.
#   build  A content page's template error was reported only as "render
#          produced no output", and a broken 404 template was skipped without
#          a word, exit 0, no 404.html. Both must fail the build (non-zero)
#          and the log must name the template and the error.
#   partial  {! partial("nosuch") !} rendered as nothing with no error and no
#          log, while a missing layout was an error. It is an error now.
#
# Negative controls: a good page in the same project still answers 200 with
# its content, and a project with no broken templates builds with exit 0.
#
# Usage: test/serve/template_errors.sh [path/to/ooke-toke]
set -u

cd "$(dirname "$0")/../.." || exit 2
ROOT=$(pwd)
BIN=${1:-$ROOT/ooke-toke}
case $BIN in /*) ;; *) BIN=$ROOT/$BIN ;; esac
[ -x "$BIN" ] || { echo "error: no ooke binary at $BIN (run make first)" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ooke-tplerr.XXXXXX") || exit 2
pid=""
cleanup() { [ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

pass=0; fail=0
ok()  { echo "  PASS $1"; pass=$((pass+1)); }
bad() { echo "  FAIL $1"; fail=$((fail+1)); }

port=$(( 20000 + ($$ % 20000) ))

# mkproj DIR PORT -- a project with one good page and nothing else.
mkproj() {
  d=$1
  mkdir -p "$d/pages" "$d/templates" "$d/content" || return 1
  cat >"$d/ooke.toml" <<EOF
[site]
name = "tplerr"
url = ""
language = "en"

[build]
output = "build/"
minify = false
inlinecss = false

[server]
port = $2
workers = 2
EOF
  echo 'm=page.index;' >"$d/pages/index.tk"
  echo '<p>GOODPAGE</p>' >"$d/templates/index.tkt"
}

# page DIR NAME TEMPLATE-SOURCE -- add pages/NAME.tk rendered by templates/NAME.tkt
page() {
  mkdir -p "$(dirname "$1/pages/$2")" "$(dirname "$1/templates/$2")"
  echo "m=page.x;" >"$1/pages/$2.tk"
  printf '%s\n' "$3" >"$1/templates/$2.tkt"
}

# A content section whose page template is broken: /blog/one is rendered from
# templates/blog/[slug].tkt for content/blog/one.md.
blog() {
  mkdir -p "$1/pages/blog" "$1/templates/blog" "$1/content/blog"
  echo "m=page.blog;" >"$1/pages/blog/[slug].tk"
  printf '%s\n' "$2" >"$1/templates/blog/[slug].tkt"
  printf -- '---\ntitle: One\nslug: one\n---\nbody\n' >"$1/content/blog/one.md"
}

# ── serve ──────────────────────────────────────────────────────────────────
echo "=== serve answers 500 for a template that fails to render (121.59) ==="
S=$tmp/serve
mkproj "$S" "$port" || exit 2
page "$S" broken '{! layout("nosuchlayout") !}x'
page "$S" nopartial 'a{! partial("nosuchpartial") !}b'
blog "$S" '{! layout("nosuchlayout") !}{= body =}'

(cd "$S" && exec "$BIN" serve) >"$tmp/serve.log" 2>&1 &
pid=$!
up=""; i=0
while [ $i -lt 50 ]; do
  kill -0 "$pid" 2>/dev/null || break
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$port/" 2>/dev/null)
  [ "$code" = "200" ] && { up=1; break; }
  sleep 0.2; i=$((i+1))
done

if [ -z "$up" ]; then
  bad "serve: no answer on :$port"; sed 's/^/       /' "$tmp/serve.log" | tail -8
else
  # fetch PATH -> sets code and body
  fetch() {
    code=$(curl -s -o "$tmp/body" -w '%{http_code}' --max-time 3 "http://127.0.0.1:$port$1")
    body=$(cat "$tmp/body" 2>/dev/null)
  }
  fetch /
  [ "$code" = "200" ] && case $body in *GOODPAGE*) true;; *) false;; esac \
    && ok "control: a good page in the same project answers 200 with its content" \
    || bad "control: / answered $code: $(printf '%s' "$body" | head -c 80)"

  # leaks BODY -> 0 when the body names a template, a path or the error
  leaks() {
    case $1 in *nosuch*|*template*|*.tkt*|*"$S"*|*layout*|*partial*) return 0;; esac
    return 1
  }
  for p in /broken /nopartial /blog/one; do
    fetch $p
    if [ "$code" = "500" ]; then ok "$p answers 500"
    else bad "$p answered $code, want 500 (body: $(printf '%s' "$body" | head -c 80))"; fi
    if [ -n "$body" ] && ! leaks "$body"; then ok "$p: the 500 body is generic ($(printf '%s' "$body" | head -c 40))"
    else bad "$p: the 500 body is empty or leaks template detail: $(printf '%s' "$body" | head -c 120)"; fi
  done
fi
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=""

grep -q "no layout template" "$tmp/serve.log" \
  && ok "serve log carries the template error (no layout template)" \
  || bad "serve log does not carry the layout error"
grep -q "no partial template" "$tmp/serve.log" \
  && ok "serve log carries the missing-partial error" \
  || bad "serve log does not carry the missing-partial error"
grep "answering 500" "$tmp/serve.log" | grep -q "templates/broken.tkt" \
  && ok "serve log names the route's template for the 500" \
  || bad "serve log does not name templates/broken.tkt beside the 500"

# ── build ──────────────────────────────────────────────────────────────────
echo "=== build fails, naming the template, for a template that fails (121.59) ==="
# build NAME DIR -> rc in $rc, log in $tmp/NAME.log
build() {
  (cd "$2" && exec "$BIN" build) >"$tmp/$1.log" 2>&1
  rc=$?
}

B0=$tmp/b-good; mkproj "$B0" "$port"
page "$B0" partials/empty ''
page "$B0" withpartial 'a{! partial("partials/empty") !}b'
build good "$B0"
[ "$rc" = "0" ] && ok "control: a project with no broken template builds (exit 0; an empty partial is not an error)" \
  || { bad "control: good project build exited $rc"; tail -5 "$tmp/good.log" | sed 's/^/       /'; }

B1=$tmp/b-blog; mkproj "$B1" "$port"
blog "$B1" '{! layout("nosuchlayout") !}{= body =}'
build blog "$B1"
[ "$rc" != "0" ] && ok "a content page's broken template fails the build (exit $rc)" || bad "broken content-page template: build exited 0"
grep -q 'template .*blog/\[slug\].tkt could not be rendered' "$tmp/blog.log" \
  && ok "the build log names templates/blog/[slug].tkt as the template that failed" \
  || { bad "the build log does not name the failed template"; tail -5 "$tmp/blog.log" | sed 's/^/       /'; }
grep -q "no layout template" "$tmp/blog.log" && ok "the build log carries the template's error" || bad "the build log lacks the template error"

B2=$tmp/b-404; mkproj "$B2" "$port"
mkdir -p "$B2/templates/errors"
printf '%s\n' '{! layout("nosuchlayout") !}x' >"$B2/templates/errors/404.tkt"
build nf "$B2"
[ "$rc" != "0" ] && ok "a broken 404 template fails the build (exit $rc)" || bad "broken 404 template: build exited 0"
grep -q 'template .*errors/404.tkt could not be rendered' "$tmp/nf.log" \
  && ok "the build log names templates/errors/404.tkt" \
  || { bad "the build log does not name the 404 template"; tail -5 "$tmp/nf.log" | sed 's/^/       /'; }

B3=$tmp/b-partial; mkproj "$B3" "$port"
page "$B3" nopartial 'a{! partial("nosuchpartial") !}b'
build partial "$B3"
[ "$rc" != "0" ] && ok "a missing partial fails the build (exit $rc)" || bad "missing partial: build exited 0"
grep -q "no partial template: .*nosuchpartial.tkt" "$tmp/partial.log" \
  && ok "the build log names the missing partial" \
  || { bad "the build log does not name the missing partial"; tail -5 "$tmp/partial.log" | sed 's/^/       /'; }

# A partial that is a symlink is refused, not rendered as nothing: std.file
# does not follow a final symlink (AMB-07), and the read failure is now an
# error. (A symlinked DIRECTORY inside templates/ is not caught -- 121.59
# part 3, blocked on a realpath in std.file / std.path.)
B4=$tmp/b-symlink; mkproj "$B4" "$port"
mkdir -p "$B4/templates/partials"
echo 'OUTSIDE' >"$tmp/outside.tkt"
ln -s "$tmp/outside.tkt" "$B4/templates/partials/link.tkt"
page "$B4" linked 'a{! partial("partials/link") !}b'
build symlink "$B4"
[ "$rc" != "0" ] && ok "a partial that is a symlink fails the build (exit $rc)" || bad "symlinked partial: build exited 0"
grep -rq OUTSIDE "$B4/build" 2>/dev/null && bad "the symlink target was rendered into the site" \
  || ok "the symlink target was not rendered into the site"

echo "  $pass passed, $fail failed"
[ "$fail" = "0" ]
