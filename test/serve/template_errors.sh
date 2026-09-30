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
# Story 121.61:
#   404    A templates/errors/404.tkt that fails to render fell back to the
#          default 404 with only an info line. It must log at error level,
#          naming the template; the client still gets the default 404.
#   xss    The empty-template fallback page put the route's path into the
#          HTML unescaped, so a page named /<script>x</script> served a live
#          script element. The path is HTML-escaped now.
#
# Negative controls: a good page in the same project still answers 200 with
# its content, and a project with no broken templates builds with exit 0; a
# good 404 template is served and logs no error; a plain empty-template page
# still shows its path.
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

# leaks BODY -> 0 when the body names a template, a path or the error
leaks() {
  case $1 in *nosuch*|*template*|*.tkt*|*"$tmp"*|*layout*|*partial*) return 0;; esac
  return 1
}

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
mkdir -p "$S/templates/errors"
echo '<p>CUSTOM404</p>' >"$S/templates/errors/404.tkt"

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
# The good 404 template is registered. (Whether its body is then served for an
# unknown path is toke's: http.setnotfound's body is used only inside the
# static-route dispatcher, so the router's own "Not Found" answers unrouted
# paths -- reported with 121.61, not asserted here.)
grep -q "custom 404 registered from templates/errors/404.tkt" "$tmp/serve.log" \
  && ok "control: a good templates/errors/404.tkt renders and is registered" \
  || bad "control: the good 404 template was not registered"
grep '"level":"error"' "$tmp/serve.log" | grep -q "errors/404.tkt" \
  && bad "control: a good 404 template logged an error: $(grep 'errors/404.tkt' "$tmp/serve.log" | head -1)" \
  || ok "control: a good 404 template logs no error"

# ── serve: broken 404 template, empty-template fallback (121.61) ───────────
echo "=== serve logs a broken 404 template as an error; the fallback page escapes its path (121.61) ==="
port2=$((port + 1))
F=$tmp/fallback
mkproj "$F" "$port2" || exit 2
mkdir -p "$F/templates/errors"
printf '%s\n' '{! layout("nosuchlayout") !}x' >"$F/templates/errors/404.tkt"
# A page whose name is markup. pages/<script>x</script>.tk is the file
# "script>.tk" in the directory "<script>x<", so its route is /<script>x</script>.
# Its template renders to nothing, which is what serves the fallback page.
xss='<script>x</script>'
mkdir -p "$F/pages/<script>x<" "$F/templates/<script>x<"
echo 'm=page.x;' >"$F/pages/$xss.tk"
: >"$F/templates/$xss.tkt"
echo 'm=page.x;' >"$F/pages/plain.tk"
: >"$F/templates/plain.tkt"

(cd "$F" && exec "$BIN" serve) >"$tmp/fallback.log" 2>&1 &
pid=$!
up=""; i=0
while [ $i -lt 50 ]; do
  kill -0 "$pid" 2>/dev/null || break
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$port2/" 2>/dev/null)
  [ "$code" = "200" ] && { up=1; break; }
  sleep 0.2; i=$((i+1))
done
if [ -z "$up" ]; then
  bad "serve: no answer on :$port2"; sed 's/^/       /' "$tmp/fallback.log" | tail -8
else
  # curl sends < and > as they are; toke matches a static route on the raw path.
  code=$(curl -s -o "$tmp/body" -w '%{http_code}' --max-time 3 "http://127.0.0.1:$port2/$xss")
  body=$(cat "$tmp/body" 2>/dev/null)
  if [ "$code" != "200" ]; then bad "/$xss answered $code, want 200 (the empty-template fallback)"
  else
    case $body in *"$xss"*) bad "the fallback page carries the path unescaped: $body";;
      *) ok "the fallback page does not carry /$xss as markup";; esac
    case $body in *'/&lt;script&gt;x&lt;/script&gt;'*) ok "the fallback page shows the path HTML-escaped";;
      *) bad "the fallback page does not show the escaped path: $body";; esac
  fi
  code=$(curl -s -o "$tmp/body" -w '%{http_code}' --max-time 3 "http://127.0.0.1:$port2/plain")
  body=$(cat "$tmp/body" 2>/dev/null)
  [ "$code" = "200" ] && [ "$body" = '<html><body><p>/plain</p></body></html>' ] \
    && ok "control: a plain empty-template page still shows its path" \
    || bad "control: /plain answered $code: $body"
  code=$(curl -s -o "$tmp/body" -w '%{http_code}' --max-time 3 "http://127.0.0.1:$port2/nosuchpage")
  body=$(cat "$tmp/body" 2>/dev/null)
  [ "$code" = "404" ] && ! leaks "$body" \
    && ok "a broken 404 template still answers the default 404 ($(printf '%s' "$body" | head -c 40))" \
    || bad "broken 404 template: /nosuchpage answered $code: $(printf '%s' "$body" | head -c 120)"
fi
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=""

grep '"level":"error"' "$tmp/fallback.log" | grep -q "errors/404.tkt" \
  && ok "a broken 404 template is logged at error level, naming templates/errors/404.tkt" \
  || { bad "no error-level log line names the broken 404 template"; grep -i 404 "$tmp/fallback.log" | sed 's/^/       /'; }
grep '"level":"info"' "$tmp/fallback.log" | grep -q "404 template render failed" \
  && bad "the broken 404 template is still reported at info level" \
  || ok "the broken 404 template is not reported at info level"

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

# A partial that is a symlink pointing outside templates/ is refused, not
# rendered as nothing (121.59 part 3 resolves it with file.realpath).
B4=$tmp/b-symlink; mkproj "$B4" "$port"
mkdir -p "$B4/templates/partials"
echo 'OUTSIDE' >"$tmp/outside.tkt"
ln -s "$tmp/outside.tkt" "$B4/templates/partials/link.tkt"
page "$B4" linked 'a{! partial("partials/link") !}b'
build symlink "$B4"
[ "$rc" != "0" ] && ok "a partial that is a symlink fails the build (exit $rc)" || bad "symlinked partial: build exited 0"
grep -rq OUTSIDE "$B4/build" 2>/dev/null && bad "the symlink target was rendered into the site" \
  || ok "the symlink target was not rendered into the site"

# ── symlinked directories (121.59 part 3) ──────────────────────────────────
# The 121.57 name rule is lexical: partial("inc/secret") passes it, and when
# templates/inc is a symlink to a directory outside templates/, the read left
# the templates directory. The resolved path must lie inside the resolved
# templates root (root + "/", not a bare prefix), or the render is refused.
echo "=== a symlinked directory cannot lead a partial/layout outside templates/ (121.59) ==="
B5=$tmp/b-symdir-out; mkproj "$B5" "$port"
mkdir -p "$tmp/outdir"
echo 'OUTSIDEDIR' >"$tmp/outdir/secret.tkt"
ln -s "$tmp/outdir" "$B5/templates/inc"
page "$B5" leak 'a{! partial("inc/secret") !}b'
build symdirout "$B5"
[ "$rc" != "0" ] && ok "a partial through a symlinked directory outside templates/ fails the build (exit $rc)" \
  || bad "partial through an outside symlinked directory: build exited 0"
grep -rq OUTSIDEDIR "$B5/build" 2>/dev/null && bad "the outside partial was rendered into the site" \
  || ok "the outside partial was not rendered into the site"
grep -q 'refused partial name .*inc/secret.*: it resolves outside the templates directory' "$tmp/symdirout.log" \
  && ok "the build log names the refused partial" \
  || { bad "the build log does not name the refused partial"; tail -5 "$tmp/symdirout.log" | sed 's/^/       /'; }

B6=$tmp/b-symdir-layout; mkproj "$B6" "$port"
echo '<html>OUTSIDELAYOUT{! yield("main") !}</html>' >"$tmp/outdir/base.tkt"
ln -s "$tmp/outdir" "$B6/templates/lay"
page "$B6" leaklayout '{! layout("lay/base") !}{! block("main") !}x{! end !}'
build symdirlayout "$B6"
[ "$rc" != "0" ] && ok "a layout through a symlinked directory outside templates/ fails the build (exit $rc)" \
  || bad "layout through an outside symlinked directory: build exited 0"
grep -rq OUTSIDELAYOUT "$B6/build" 2>/dev/null && bad "the outside layout was rendered into the site" \
  || ok "the outside layout was not rendered into the site"

# A sibling whose name extends the root's (templatesx/) is outside: the check
# is a prefix plus a separator.
B7=$tmp/b-symdir-sibling; mkproj "$B7" "$port"
mkdir -p "$B7/templatesx"
echo 'SIBLING' >"$B7/templatesx/p.tkt"
ln -s "$B7/templatesx" "$B7/templates/sib"
page "$B7" sib 'a{! partial("sib/p") !}b'
build symdirsib "$B7"
[ "$rc" != "0" ] && ok "a symlink into a sibling templatesx/ is outside templates/ (exit $rc)" \
  || bad "symlink into sibling templatesx/: build exited 0"
grep -rq SIBLING "$B7/build" 2>/dev/null && bad "the sibling partial was rendered into the site" \
  || ok "the sibling partial was not rendered into the site"

# Negative controls: a symlinked directory that stays inside templates/, and a
# plain nested name, still render.
B8=$tmp/b-symdir-in; mkproj "$B8" "$port"
mkdir -p "$B8/templates/partials/real"
echo 'INSIDEPARTIAL' >"$B8/templates/partials/real/hdr.tkt"
ln -s "real" "$B8/templates/partials/alias"
echo 'NESTEDPARTIAL' >"$B8/templates/partials/real/nested.tkt"
page "$B8" viaalias 'a{! partial("partials/alias/hdr") !}b'
echo 'FILELINKPARTIAL' >"$B8/templates/partials/real/target.tkt"
ln -s "real/target.tkt" "$B8/templates/partials/filelink.tkt"
page "$B8" nested 'a{! partial("partials/real/nested") !}b'
page "$B8" viafilelink 'a{! partial("partials/filelink") !}b'
build symdirin "$B8"
[ "$rc" = "0" ] && ok "a project using an inside symlinked directory builds (exit 0)" \
  || { bad "inside symlinked directory: build exited $rc"; tail -5 "$tmp/symdirin.log" | sed 's/^/       /'; }
grep -rq INSIDEPARTIAL "$B8/build" 2>/dev/null && ok "a partial through a symlinked directory inside templates/ renders" \
  || bad "the inside-symlink partial did not render"
grep -rq NESTEDPARTIAL "$B8/build" 2>/dev/null && ok "a plain nested partial name renders" \
  || bad "the plain nested partial did not render"
grep -rq FILELINKPARTIAL "$B8/build" 2>/dev/null && ok "a symlinked partial file whose target is inside templates/ renders (the resolved path is read)" \
  || bad "the inside file-symlink partial did not render"

echo "  $pass passed, $fail failed"
[ "$fail" = "0" ]
