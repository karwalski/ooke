# Changelog

Dates are the dates the work was done, not publication dates. Nothing below has
been published; see `docs/RELEASING.md`. Story numbers are toke's tracker
(`toke/docs/progress.md`), which tracks every repository.

## Unreleased

### Fixed

- **An unclosed `{=`, `{!` or `{#` no longer repeats the text before it.**
  `tpllex` emitted the text before an unclosed opener as a raw token, then
  emitted everything from the previous position on as a second raw token, so
  `abc {= x` rendered as `abc abc {= x`. The unclosed tag is now literal text
  from its opener on and the prefix appears once (`abc {= x`). Whether an
  unclosed tag should instead be a `$tplerr`, like an unclosed block (138.29),
  is still an open owner item (register 2.5); this keeps it literal text.
  (toke 127.298)
- **Server tests no longer fail when something else holds their port.** The
  shell tests that start a server picked a port by arithmetic on the shell's
  PID (`20000 + $$ % 20000`) and never checked it was free. On 2026-11-28 the
  `ooke compile` test run by `make check-toke-candidate` failed 11/12 because a
  VS Code helper was listening on the port it derived. A new helper,
  `test/support/freeport.sh`, binds port 0 and reads the free port back, and
  the eleven tests that derived a port use it. The compiled-binary test also
  retries a start that fails with "Address already in use", and its bind cases
  use a port the test's own listener holds instead of the derived port plus
  one. (toke 127.560)

## 3.0.1 — unreleased, on toke 3.2.0

A patch release that ships **before toke 3.3.0** (owner answer R1,
2026-11-15, toke `docs/owner-decisions-2026-11-12.md`). toke 3.3.0 judges a
std call whose interface declares `T!E` as the error union it is, and rejects
an error union read as its value in a condition, `!`, an interpolation, a
std-call argument and an assignment to a `mut` binding (toke 127.319,
127.323; E4031). ooke 3.0.0 has four such reads, so it does not build on
3.3.0. 3.0.1 rewrites them in spellings toke 3.2.0 already accepts, so the
same source builds on both. No behaviour changes.

### Requirements

- Unchanged: **toke 3.2.0 or later** (`mintoke = "3.2.0"`). 3.0.1 also
  builds on toke 3.3.0.

### Changed

- `src/run.tk` (`runwriteraw`): `os.write` returns `i64!oserr`; its result
  is matched (`mt os.write(fd;rest){$ok:v v;$err:e 0}`) before the `n<=0`
  test. A failed write still returns `false`, as it did. (127.319)
- `src/store.tk`: two map lookups passed to `str.eq` are matched first;
  `m.get(k)` is `V!$err` since toke 127.244, and toke 3.3.0 rejects it as a
  std-call argument. In the table-schema loop the key comes from the map's
  own `keys()`, so the lookup always hits. In `storefind` a miss is `false`
  in the match itself (`mt item.meta.get(key){$ok:v str.eq(v;val);$err:e
  false}`), exactly as `str.eq` on the missing value was: an empty-string
  default would have matched an item without the key when `val` is `""`.
  (127.323)
- `src/build.tk`, named with `run.tk` in answer R1, has no such read: every
  `.tk` in the repository passes `make check` on toke 3.2.0 and on the 3.3.0
  checker (toke branch `fix/127.319-std-errunion`), and `make test` passes
  on both.

## 3.0.0 — 2026-11-15, on toke 3.2.0

The first ooke release since 2.0.0. 3.0.0 is rc.2 plus everything below: the
work merged to main after the rc.2 candidate was frozen at `3cc4998`, which
was collected here as "rc.3" and never cut as a candidate of its own. Read
this section, then the rc.2 and rc.1 sections (the rest of the change set
since 2.0.0), then `docs/release-notes-3.0.0.md`, before adopting.

**Why a final and not rc.3** (the owner approved an ooke release alongside
toke 3.2.0 on 2026-11-14; register item 5.2 in toke
`docs/owner-decisions-2026-11-12.md` left "3.0.0 or a new rc" open): the only thing that ever kept
ooke a candidate was its toke dependency -- first no toke version for the v0.4
break (134.15), then a floor commit no toke release contained. toke 3.2.0 is
the first release that contains every floor ooke declares, so `mintoke`
alone is sufficient again; neither rc was published, so a further candidate
would be one more unpublished tag; and loke (138.7, 138.17) and the
`homebrew-toke` formula (132.27, already written for `3.0.0`) are waiting on
a release, not a candidate.

### Requirements

- **toke 3.2.0 or later** (`mintoke = "3.2.0"`). ooke needs toke `db47d591`
  (2026-10-01): `file.realpath` (toke 121.60), and `os.write`'s wrapper in
  `os_glue.c` (toke 121.70), which ooke now links -- without it ooke does not
  link against current toke. toke 3.1.0 lacks both; toke 3.2.0 is the first
  release that contains `db47d591`, so it is the floor, and every toke
  labelled 3.2.0 or later satisfies it. `mintokecommit`/`mintokedate` name
  `ea7ddf22`, the commit toke's `v3.2.0` tag points at, which CI and the
  release workflow clone. See `docs/versioning.md`, "The
  realpath floor" and "The 3.2.0 floor". (121.59, 138.17)

### Changed

- **An unknown directive, a stray `{! end !}` and an unclosed block are
  template errors.** Each rendered as `$ok` with nothing logged: a directive
  the engine does not know (`{! frobnicate !}`, `{! endblock !}`) was dropped,
  an `end` with no open block was ignored, and a block still open at the end
  of the template was discarded with its content, so the page shipped with a
  hole in it. Each is now a `$tplerr`, logged at error level where it is
  raised ("template: unknown directive "NAME" (known: …)", "template:
  {! end !} with no open block", "template: block "NAME" is never closed
  with {! end !}"). An unknown directive inside a block is reported even if
  no layout yields the block. **Behaviour change:** a template with any of
  these now fails `ooke build` and answers 500 from `ooke serve` (121.59).
  The known directives are `layout`, `block`, `end`, `var`, `yield`,
  `partial` and `island`. (138.29, loke O-4)
- **`{= x =}` is escaped for where it sits in the HTML, not only as HTML
  text** (121.58, a port of toke's 121.37 context tracker). A value at the
  start of `href`/`src`/`action` (and other URL attributes) with a scheme
  other than `http`, `https` or `mailto` becomes `#ZtokeZ`; URL values are
  percent-encoded, as a component after `?` or `#`. In `<script>` or an `on*`
  attribute a value in code becomes a quoted JS string (`"…"`) and one inside
  a string is `\u00HH`-escaped. In `<style>` or `style=` a value in code is
  kept only if it is `[A-Za-z0-9 #%.,_-]`, else `ZtokeZ`. Unquoted attribute
  values and tag/attribute-name positions are escaped too. `|escape`,
  `|upper`, `|lower` and `|trim` escape for the context; `|raw` and `|md` are
  unchanged. A template that put a value in a URL, script or style position
  now gets different text: `<script>var n={= n =};</script>` renders
  `var n="3";`, a string, where it rendered `var n=3;`.
- **Blocks are rendered where the layout yields them**, so a block's values
  are escaped for that place and a block's islands are detected as before;
  the islands script is appended once per page. `$block` holds tokens
  (`toks`), not rendered text (`content`). (121.58)

### Fixed

- **A toke-side stdlib file split no longer breaks ooke's link.** The Makefile
  linked a hand-kept list of toke's stdlib C files, so when toke 121.70 moved
  `os.write`'s wrapper into a new `os_glue.c`, ooke stopped linking against
  toke main until the file was added by hand. The ooke binary, the unit tests
  (`test/run_tests.sh`, which also named std.test's C files by hand) and an
  `ooke compile` app now take their stdlib and vendor C sources and link flags
  from `tkc --emit-deps` over the modules they link (`scripts/emit_deps.sh`),
  as toke-website does; `-framework` pairs stay paired and are Darwin-only.
  `make print-build-vars` prints the derived lists. New
  `make check-toke-candidate TOKE_CANDIDATE=<toke>` builds ooke, its tests and
  a compiled app against a candidate toke tree; see `docs/RELEASING.md`.
  (121.76)
- **`{! partial("…") !}` and `{! layout("…") !}` cannot leave `templates/`.**
  A name was joined straight into the path, so `partial("../secret")` rendered
  `templates/../secret.tkt` into the page. A name with a `..`, `.` or empty
  segment, a leading `/`, or a backslash is now refused with a logged template
  error; `partials/header` still works. (121.57)
- **A symlink inside `templates/` cannot lead a partial or layout outside
  it.** The 121.57 name rule is lexical, so `partial("inc/secret")` passed it
  and, with `templates/inc` a symlink to a directory elsewhere, rendered that
  file into the page. The path and the templates root are now resolved with
  toke's `file.realpath`, and the render is refused with a logged template
  error unless the path is inside the root (root plus `/`, so a sibling
  `templatesx/` is outside). Symlinks that stay inside `templates/` work, and
  the resolved path is what is read -- **behaviour change:** a symlinked
  partial or layout *file* whose target is inside `templates/` now renders
  (121.59 made it an error); one pointing outside is still refused.
  **Needs toke `db47d591` or later, first released in toke 3.2.0.**
  (121.59)
- A partial or layout that includes itself fails the render with an error
  after 32 levels instead of overflowing the stack. (121.58)
- **A page whose template fails to render answers 500, not an empty 200.**
  `ooke serve` turned a template error into `""` and served the empty-template
  fallback page (200), or skipped a content page (404). The route now answers
  500 with the body `500 Internal Server Error` -- no template name, path or
  error reaches the client -- and the server log names the route, the template
  and the error. (121.59)
- **`ooke build` fails, naming the template, when a template fails.** A
  content page's template error was reported only as "render produced no
  output"; it now names the template and points at the logged error. A broken
  `templates/errors/404.tkt` was skipped silently (exit 0, no `404.html`); it
  now fails the build. (121.59)
- **A missing partial is an error**, as a missing layout already was.
  `{! partial("nosuch") !}` rendered as nothing, with no error and no log. A
  partial file that exists but cannot be read is an error too, and a template, layout or
  partial read failure is now logged. An empty partial file still renders as
  nothing. **Behaviour change:** a site that referenced a partial it does not
  have now fails `build` and answers 500 under `serve`. (121.59)
- **A `templates/errors/404.tkt` that fails to render is logged as an error
  under `serve`**, naming the template; it was an info line. The client still
  gets the default 404. A 404 template that renders to nothing is a warning.
  (121.61)
- **The empty-template fallback page escapes its path.** A page whose
  template renders to nothing is served as `<p>` + its path; the path went in
  as written, so a page file named `<script>x</script>` served a live script
  element. It is HTML-escaped now. (121.61)
- `src/serve.tkc.md` and `src/template.tkc.md` describe the current code
  (host binding, `[log]`/`[tls]`/CORS checks, the 500 path; the context
  tracker, escapers and name confinement). (121.61)
- **The API fallback body is valid JSON whatever the page is called.** An
  API page with no handler answers `{"status":"ok","endpoint":"<path>"}`; the
  path, taken from a file name under `pages/api/`, went in as written, so a
  page named `a"b\c` answered `{"status":"ok","endpoint":"/api/a"b\c"}`, which
  is not JSON (and a name could add keys). The path is now encoded with
  `std.json`'s `json.enc`. A plain name's body is unchanged. (121.63)
- **The cached render path logs a missing or unreadable template**, as
  `tplrenderfile` has since 121.59. `tplrenderfilecached` and `tplcacheget`
  returned the error with no log line; all three now read through one
  function, `tplreadsource`, which logs `template: no template file: <path>`
  or `template: template file could not be read: <path>`. Neither is used by
  `ooke build` or `ooke serve` today. (121.63)
- The companions of `build`, `cli`, `config`, `main`, `repair`, `router`,
  `run`, `store` and `validate` (`src/*.tkc.md`) describe the current code;
  each had drifted from its source. (121.63)
- **`make test` checks the companions.** `scripts/check_companions.sh`
  (`make test-companions`) fails, listing each stale one, when a
  `src/*.tkc.md` `source_hash` does not match its source, or names a source
  that does not exist. Companions of generated sources (`src/_*.tk`) are
  skipped. (121.63)
- **A content file's front matter keeps values that contain `:`, and a blank
  line in it no longer kills the build.** Each line was split on every `:`
  and only the second piece kept, so `url: https://x.io` read `https`,
  `time: 12:30` read `12` and `title: Part 1: Intro` read `Part 1`. A line
  with no `:` -- a blank line, or a stray word -- read past the end of the
  split and the process died with RT003 (`ooke build` and `ooke serve` both
  parse content through it). The key is now what precedes the first `:` and
  the value everything after it; a line with no `:` is skipped. (121.66;
  132.148 below moves the split to the first `: `)
- `store.storewrite` no longer turns a failed existence check into an
  INSERT. Its `SELECT id … WHERE slug=?` was read as "not found" on any
  error, so on a table without an `id` column every write of an existing slug
  added a duplicate row. The check is a `COUNT`, and its failure is returned
  as an error. Nothing in `ooke build` or `ooke serve` calls it. (121.66)
- **`ooke repair <file>` exits by tkc's verdict.** It counted lines on
  `tkc --check`'s stderr, ignored tkc's exit status, and returned the count as
  its own exit status: 256 diagnostics exited 0, a tkc that failed without
  printing read as clean (0), and a warning alone read as broken. It now
  exits 0 when tkc accepts the file (warnings are reported, not counted) and
  1 when it does not; a silent tkc failure is logged as an error. (121.66)
- `ooke run` and `ooke build --cli` log their failures -- a missing entry
  point, a tkc that fails or cannot be spawned, no output binary, "compilation
  failed" -- at error level. They were info records. (121.66)
- **`VERSION` is the one place ooke's version is written.** `ooke --version`
  printed a literal in `src/cli.tk` that every release bumped by hand beside
  `VERSION`. The Makefile now generates `floor.ookeversion()` from `VERSION`
  into `src/_floor.tk`, and `make check-ooke-version` fails if `src/cli.tk`
  hard-codes a version again or if `VERSION` is not a plain version string.
  The printed text is unchanged. (121.66)
- `ooke gen --help` lists all four types `ooke gen` makes -- `page`, `type`,
  `api`, `island`; it listed two. (121.66)
- **`ooke new` and `ooke gen` fail when they cannot write.** They discarded
  every mkdir and write result, then logged `Created …` and exited 0:
  `ooke gen page x` outside a project, or either command in a directory it
  cannot write, reported success and wrote nothing. The first failure now
  logs `could not write <path>` (or `could not create directory <path>`) at
  error and exits 1. (121.66)
- `ooke build` names the output directory it could not create for a
  content-backed page (`pages/blog/[slug].tk`), as it already did for a
  static page. The result of that mkdir was ignored, so the failure was
  reported as `write failed for …/index.html`. The build fails either way.
  (121.66)
- `ooke serve` warns about `[log] maxlines` / `maxagedays` set to a string
  or a boolean (`maxlines = "5"`), not only to an integer; they are ignored
  either way. A float or array value is still not noticed -- std.toml cannot
  test for a key or read a float. (121.66)
- **A page under a nested `api/` directory is a page.** A route was an API
  route if its path held `/api/` anywhere, so `pages/docs/api/intro.tk` was
  neither built nor served as a page, and the build said it was a handler
  "under pages/api/". Only `pages/api/` makes API routes now. (121.66)
- **`ooke build` fails, naming the file, when a static asset cannot be
  copied.** Both the mkdir and the copy of each `static/` file were matched
  to a bool and dropped: the asset was missing from the site, `assets copied`
  was one lower, and the build exited 0. Each failure is now logged at error
  naming the asset (or the directory it could not create), the rest of
  `static/` is still copied, and the build ends with `assets not copied: <n>
  — build failed` and exits 1. `buildcopyassets` returns an `$assetreport`
  (`copied`, `failed`) and `$buildreport` gains `assetsfailed`. (121.67)
- **`ooke build` fails, naming it, when `404.html` cannot be written.** The
  write result was dropped, so the build exited 0 with no `404.html`. On a
  site whose only output is the 404 page this was every build: the output
  directory had not been made yet, so the write always failed. The directory
  is now made first, and a failed mkdir or write is logged at error and
  counted in `pages skipped`, failing the build. (121.67)
- `store.storesqlcreate` always makes the `title` and `type` columns that
  `storewrite` writes and `storeallsql` reads. It made them only when the
  model declared them, so on any other model every `storewrite` failed with
  `no such column: title`. A model field named `id`, `slug`, `title`, `type`
  or `body` (in any case) is no longer declared a second time, which SQLite
  refused. Nothing in `ooke build` or `ooke serve` calls it. (121.67)
- **A key outside its table is not read as that table's.** Every
  `ooke.toml` table ooke reads (`[site]`, `[build]`, `[server]`, `[log]`,
  `[paths]`, `[tls]`) fell back to the root table when it was absent, so a
  top-level `maxlines = 5` made `ooke serve` warn about a `[log]` rotation
  key, and a top-level `port`, `name`, `access`, `output` or `cert` configured
  the server, site, log, build or TLS. An absent table is now empty and its
  keys take their defaults. **Behaviour change** for an `ooke.toml` that
  relied on top-level keys: put them in their table. (121.67)
- **`ooke run` passes the program's stdout through.** It was captured and
  logged as a JSON info record on stderr -- `{"level":"info","msg":"line
  one\nline two\n",…}` -- so `ooke run app | jq` or `> out.txt` got nothing.
  The program's stdout is now written to ooke's stdout unchanged, once the
  program exits (std.process captures it; it is not streamed). The program's
  stderr is still logged as an info record. **Behaviour change** for anything
  that read a program's output from `ooke run`'s stderr. (121.67)
- **`ooke run` / `ooke build --cli` read `name` and `entry` only from
  `[package]`.** Without a `[package]` table the root table was read, so a
  top-level `name` named the binary and a top-level `entry` the entry point.
  A missing `[package]` is now empty, as every other table is (121.67), and
  the defaults `app` and `src/main.tk` apply. **Behaviour change** for an
  `ooke.toml` that set them at the top level: put them under `[package]`.
  (121.69)
- **`ooke run` passes the program's stderr through.** It was logged as one
  JSON info record, so a program's own JSON log lines arrived escaped inside
  ooke's `msg` -- `{"level":"info","msg":"{\"level\":\"info\",…}\n",…}`.
  The program's stderr is now written to ooke's stderr byte for byte, with
  nothing added (a last line with no newline gets none), after its stdout
  and once the program exits. **Behaviour change** for anything that parsed
  the wrapped record. (121.69)
- `ooke build` prints both `pages skipped: <n>` and `assets not copied: <n>`
  when a build lost both. It returned after the first, so the asset summary
  was missing (the assets were still named in their own errors, and the build
  still failed). (121.69)
- **A quoted front-matter value loses its quotes.** `title: "Canonical facts:
  how toke is described"` rendered as a page titled `"Canonical facts` on
  toke-website. A value wrapped in a matching
  pair of double or single quotes is unquoted, reading the YAML escapes inside
  them (`\\` and `\"` in double quotes, `''` in single), and the key now ends at
  the first `: ` (or a `:` that ends the line), so `url: https://x.io` keeps
  its scheme as before. **Behaviour change** for a site that relied on the
  quotes appearing in its output. (132.148, `c13ed7d`)
- A test, not ooke: `test_store`'s `countslug`/`titleof` leave from
  `db.one`'s `$err` arm instead of comparing the `$ok` row with `0`, which
  toke 138.33 (typed std-record payloads) makes E4031. Results unchanged.
  (138.33, `23629b7`)

### Performance

- **The template lexer no longer copies the rest of the template per tag.**
  `tpllex` re-sliced the unscanned tail twice per tag, and toke frees none of
  it (toke 127.299). It scans by index now. 20 renders of a 70 KB page: peak
  RSS 184.2 MB -> 13.0 MB (lex+render), output byte-identical. Tokens are
  unchanged, including the unclosed-tag duplication (toke 127.298, an open
  owner item, register 2.5). (127.257, `e2e3422`)

### Project

- `LICENSE` names the holder, Matthew Watt (licence audit 2026-11-09,
  `95adaba`); the README states the rc status, the toke floor, a real API
  handler and `[server] host`, and `docs/install.md` has the right clone URL
  (docs review 2026-11-12, `eb05b08`); the unused `scripts/testmod.sh` is
  archived (121.83, `815d704`).

### Commits since rc.2

44 commits on main after `v3.0.0-rc.2` (`c414e4d`), merges not counted, by
story:

- 121.57 partial/layout names stay in `templates/`: `4b96784`, `41387b9`
- 121.58 context-aware `{= x =}` escaping: `442cdeb`, `362d3b8`
- 121.59 template errors fail the build / answer 500; `file.realpath`
  confinement; the `db47d591` floor: `8e317a7`, `90e8e3d`, `f0ac685`,
  `b908a7d`, `e23ffb0`
- 121.61 serve fallbacks, 404 template, companions: `0948dfb`, `29778a0`,
  `64cb1e4`
- 121.63 API fallback JSON, cached-render logging, companions gate:
  `3a8f336`, `6f2eaeb`, `05f8d69`, `719e82b`
- 121.66 front matter, store, repair, run/build logging, `VERSION` as the one
  version, `gen`/`new` failures, `pages/api/` routing: `b095de7`, `caf92ce`,
  `6a73220`, `212263c`, `fa1437b`, `b965373`, `a8b91f3`, `352f9c2`,
  `956587b`, `ac56161`
- 121.67 asset and 404 write failures, `storesqlcreate`, absent tables,
  `ooke run` stdout: `3d575ac`, `4b44cee`, `77a33ca`, `b283b77`, `405918e`
- 121.69 `[package]`, `ooke run` stderr, both build summaries: `b77a258`,
  `04d5911`, `d17873b`
- 121.76 link lists from `tkc --emit-deps`; `check-toke-candidate`:
  `e2ef159`, `ff4b50a`
- 121.83 archive `testmod.sh`: `815d704`
- 127.257 template lexer by index: `e2e3422`
- 138.29 unknown directive / stray `end` / unclosed block are `$tplerr`:
  `26c8c16`
- 138.30 changelog names the `raw` filter: `d4c9bcb`
- 138.33 test_store under typed std-record payloads: `23629b7`
- 132.148 front-matter quotes: `c13ed7d`
- licence holder: `95adaba`; README/install review (R3): `eb05b08`
- the release itself (VERSION 3.0.0, `mintoke = "3.2.0"`, these notes): on
  `release/3.0.0`

## 3.0.0-rc.2 — unreleased (prepared 2026-09-28, story 138.7)

Second release candidate. **Why a new candidate:** rc.1's `src/store.tk` no
longer compiles on current toke — two functions end in an error propagation
with no `<`, which toke made a hard error (E4071) after rc.1 was cut. main
already carried the fix (127.127); rc.1 did not (loke handoff 2026-09-27, O-1).
Read `docs/release-notes-3.0.0.md` before adopting.

### Breaking, relative to rc.1

- **The toke floor is toke `3.1.0` (2026-09-30).** toke 3.0.0 is not enough:
  ooke's suite fails on it (11 of 12) because toke 3.0.0 lowers `.set` on a
  map-typed struct field as an array `.set`, so ooke's template cache never
  stores (toke 127.226, fixed in `cee7cc0`), and `[server] host` (below)
  calls toke's host-binding serve functions (toke 138.1, `668caa6`). rc.2 was
  prepared against the commit `668caa6` (138.7); toke 3.1.0 is the first toke
  release that contains it, so `mintoke = "3.1.0"` is now sufficient on its
  own. `mintokecommit`/`mintokedate` name toke's 3.1.0 version commit
  (`216965f`) and stay only because CI clones toke at that commit until the
  `v3.1.0` tag is published. `make test` passes on toke 3.1.0: every target,
  suite 12/12. (138.7, 138.17)
- **`ooke serve` listens on 127.0.0.1 unless `[server] host` says otherwise.**
  It used to listen on every interface, with no setting to change it. A
  deployment that must be reachable from other machines sets
  `host = "0.0.0.0"`. The start log says when a server is loopback-only and
  names the setting. Why loopback is ooke's default although toke's port-only
  functions keep every interface: `docs/logging-and-tls.md`, "Bind address".
  `ooke new` writes `host = "127.0.0.1"` explicitly. (138.7, loke O-3)

### Fixed since rc.1

- **`src/store.tk` compiles on current toke**: `storeslug`/`storefind` return
  an explicit not-found error instead of ending in a bare propagation. (127.127)
- **An app with more than 31 handler pages compiles.** The generated handler
  registry imports every page plus `std.http`, which hit toke's default cap of
  32 imports per module (E9010). `ooke compile` now passes
  `--max-imports=<count>` for that one module when it is needed; a 40-page app
  is in the suite. (138.7, loke O-2)
- `ooke compile` builds a per-app binary that runs the same `cli.runserve` as
  `ooke serve` (134.44), finds its script beside the binary rather than in the
  cwd (134.45), and works from an installation, not only a checkout (134.46).
- `ooke serve` applies `[log]` and `[tls]` (134.40); `ooke build <path>` and
  `ooke serve <path>` work from any working directory (134.25, 134.37).
- A malformed `ooke.toml` fails `build` and `serve` instead of silently using
  defaults (134.42); `--version` prints `ooke <VERSION>` on stdout (134.43).
- `ooke run` and `build --cli` compare `process.wait`'s exit status (134.45).
- Every page at any depth under `pages/` is a prerequisite of the handler
  registry (134.37); `src/_handlers.tk` is untracked build output (134.22);
  `ooke new`'s `[requires]` is generated from `ooke.toml` (134.35).
- `logaccessformat` is documented under its real name (134.23).
- `[server].workers` is honoured under TLS: `ooke serve` starts that many TLS
  workers instead of one per CPU (134.47).
- ooke's own handler pages under `pages/` are compiled and linked by its
  Makefile, at any depth (134.47).
- `package_release.sh` prints every suite summary and FAIL line, records the
  totals in the manifest, and stops on a failing suite (134.47).
- The template cache test proves a stored entry is served, not re-read
  (127.226) — the test that fails on toke 3.0.0.
- `[server] admin = true` refuses to start and names the key: ooke has no
  admin interface and no authentication to put one behind, and the setting
  used to be read by nothing. `admin = false` is ignored with a warning; the
  README says what ooke does not do for you. (121.25)
- `[server] corsorigins` is checked before it reaches `http.setcors`: `""`
  (off), exactly `"*"` (with a warning), or a list of `http`/`https`
  `scheme://host[:port]` entries; anything else refuses to start, naming the
  entry. A malformed entry used to start, log "CORS enabled" and match no
  browser's Origin. (121.25)
- Table and column names in `store.tk` must be SQL identifiers
  (`[A-Za-z_][A-Za-z0-9_]*`); `storesqlcreate` returns `!$storeerr`. They were
  spliced into SQL unchecked. (121.25)
- A test pins that `/static` serves `static/` and nothing else of the
  project. (121.25)

## 3.0.0-rc.1 — unreleased (prepared 2026-09-19, story 134.10)

Release **candidate**, not a release — because toke has never cut a version for
the v0.4 break (story 134.15, owner decision), so this release can only pin its
one hard dependency as a git commit. Read `docs/release-notes-3.0.0.md` before
adopting.

### Breaking, relative to 2.0.0

The version loke was written against is **2.0.0** (2026-06-21). Everything here
breaks a 2.0.0-era consumer.

- **toke v0.4 syntax is now required of your code too.** ooke's sources moved to
  `==` for equality and expression-oriented `if`; so must the `pages/*.tk` and
  modules in your project. 2.0.0-era sources do not compile.
- **Templates escape by default** (toke ADR-0011). A template that relied on raw
  interpolation now emits escaped text. Use the `raw` filter,
  `{= key | raw =}`. This changes output rather than failing, so it will not
  announce itself.
- **A capability grant set is baked into the binary with `enforce = true`**
  (toke ADR-0010).
- **The toke floor is a commit, not a version.** `ooke.toml [requires]` gained
  `mintokedate` and `mintokecommit`; `mintoke` alone is not enforceable while
  toke's VERSION is frozen at 2.8.0 (story 134.15).
- **`ooke new` writes a `[requires]` block** into every scaffolded project.
  Previously it wrote no floor at all.
- **No-underscore naming** for configuration keys and stdlib call names, imposed
  by toke's Profile-1 character set.
- **`[store].backend` is gone, and `$ookecfg` lost its `storebackend` field.**
  The key was documented as `"flat"` or `"sqlite"` "with automatic migration",
  parsed, and then read by nothing: build and serve always used the flat-file
  store. No SQLite content backend exists to select — nothing opens a database,
  creates its tables or migrates content into it. An `ooke.toml` that still has
  a `[store]` table loads unchanged; the table is ignored. Code importing
  `ooke.config` that read `storebackend` no longer compiles. (134.34)

### Fixed

- **The test suite had never run.** All 12 tests were reported `SKIP (link)` and
  the runner exited 0. Now 12/12 — and the runner takes its build configuration
  from `make print-build-vars` rather than a hand-copied list, which is how it
  drifted out of linkability unnoticed. (134.5)
- **157 assertions were inert.** `test.eq` results were computed and discarded,
  so tests could not fail. Now 187 live assertions, each proved able to fail by
  mutating one expectation per file and confirming all 11 files go red. (134.17)
- **`ooke serve` segfaulted** on a missing `pages/` directory, and did not honour
  SIGTERM. Exit 139, `EXC_BAD_ACCESS`. (134.14)
- **`serve` swallowed a `routerscan` error** into an empty route set and served
  nothing rather than refusing to start. (134.18)
- **`ooke serve --help` started a server** instead of printing help. Help is now
  answered before dispatch for every command in all three spellings. (134.19)
- **Two configuration flags were parsed and never used.** Wired, not removed.
  (134.20)
- **Reproducible site builds** — the 132.20 blocker, root-caused to toke 127.58.
  (134.8)
- **A clone could not run the tests**: `test/support/` was untracked, so every
  fresh clone died on a `make` error that named the file but not the cause.
  Tracked now, with a preflight that fails by name. (134.21)
- **`tkc --check` coverage 28/30 → 30/30**; lint warnings 96 → 2, errors 0;
  all 63 string-concatenation chains converted to the canonical form.
  (134.2, 134.3)
- **`ooke build` aborted on any project containing an API route**, and `ooke
  new` scaffolded one — so the first thing an adopter did produced a project
  that could not be built. `routerscan` set an is-API flag the build never
  read, and the CLI wrapper discarded the error and logged the single word
  "build failed". Both halves fixed, and API routes are now reported as
  deliberately excluded from the static build. (134.24)
- **`ooke new` scaffolded one template where the route it also scaffolds needs
  two**, and that template used `{{title}}`/`{{content}}` — not ooke template
  syntax — so both would have reached the browser verbatim. It now writes
  `base.tkt` and `index.tkt`. (134.24)
- **The version gate was decorative** — it compared major versions only,
  restated the floor in a second place, and was a prerequisite of nothing. It
  now reads `ooke.toml` as the single source of truth and gates `make` and
  `make test`. `ooke --version` and `VERSION` had also disagreed for three
  months; that is now a build failure. (134.7)

### Changed

- Templates render into a string builder rather than a concat chain; 15.4%
  memory reduction, measured. A template cache was implemented, measured and
  **rejected**. (134.4)
- `TOKE_ROOT` and `TKC` are overridable (`?=`) instead of absolute paths into
  one developer's home directory. Nobody else could build ooke before this.
  (134.16)

### Known defects

See `docs/release-notes-3.0.0.md`. The short list: **134.15** (toke has no
usable released version — you must pin a commit), 134.22 and 134.23 (both
minor), and the caveats on ooke's internal module surface (134.11).

## 2.0.0 — 2026-06-21

The pure-toke rebuild (Epic 113): ooke re-implemented as 100% toke, with the
native glue pushed down into a reusable toke core (ADR-0005).
