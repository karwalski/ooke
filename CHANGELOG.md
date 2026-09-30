# Changelog

Dates are the dates the work was done, not publication dates. Nothing below has
been published; see `docs/RELEASING.md`.

## 3.0.0-rc.3 — unreleased (main, after rc.2 was frozen at 3cc4998)

Not in rc.2. Template safety work merged after the rc.2 candidate was frozen.

### Changed

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

- **`{! partial("…") !}` and `{! layout("…") !}` cannot leave `templates/`.**
  A name was joined straight into the path, so `partial("../secret")` rendered
  `templates/../secret.tkt` into the page. A name with a `..`, `.` or empty
  segment, a leading `/`, or a backslash is now refused with a logged template
  error; `partials/header` still works. (121.57)
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
  partial file that exists but cannot be read (for one, a symlink: std.file
  does not follow a final symlink) is an error too, and a template, layout or
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
  the value everything after it; a line with no `:` is skipped. (121.66)
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

## 3.0.0-rc.2 — unreleased (prepared 2026-09-28, story 138.7)

Second release candidate. **Why a new candidate:** rc.1's `src/store.tk` no
longer compiles on current toke — two functions end in an error propagation
with no `<`, which toke made a hard error (E4071) after rc.1 was cut. main
already carried the fix (127.127); rc.1 did not (loke handoff 2026-09-27, O-1).
Read `docs/release-notes-3.0.0.md` before adopting.

### Breaking, relative to rc.1

- **The toke floor moved to `3.0.0` + `668caa6` (2026-09-28).** toke has now
  cut `3.0.0`, but ooke's suite fails on it (11 of 12): toke 3.0.0 lowers
  `.set` on a map-typed struct field as an array `.set`, so ooke's template
  cache never stores (toke 127.226, fixed in `cee7cc0`). And `[server] host`
  (below) calls toke's host-binding serve functions (toke 138.1, `668caa6`).
  `mintoke = "3.0.0"` is necessary, not sufficient, so the commit/date pair
  stays until a toke release contains `668caa6`. (138.7)
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
  interpolation now emits escaped text. Use `{{raw ...}}`. This changes output
  rather than failing, so it will not announce itself.
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
