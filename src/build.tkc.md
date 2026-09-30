---
source_file: "build.tk"
source_hash: "d3aa8af21c8f97f0e2d06c80a85dee1255894085a7bdf0768b853fff157b90dc"
compiler_version: "3.0.0"
generated_at: "2026-10-01T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.build`

Static-site build for an ooke project. It scans the file-system routes, renders
every static page and every single-`:slug` dynamic page (one output per content
item), skips API routes (request handlers, served only by `ooke serve`),
validates dynamic content against its TOML model, copies the `static/` asset
tree into the output, and emits a `404.html` when an error template exists.
Template and project paths resolve against the project directory, not the
working directory (134.25). Every failure is logged where it happens, naming
the route and the template (134.24, 121.59), because the `$builderr` payload
cannot be read by the caller (RT005, toke 127.78). It
also provides three pure HTML post-processing helpers: output-path derivation,
CSS inlining, and whitespace/comment minification.

**Imports:**
- `std.file` (alias `file`) — read, write, mkdir, copy, isdir, exists, listall.
- `std.log` (alias `log`) — error/warn/info lines naming what failed.
- `std.str` (alias `str`) — concat, join, slice, indexof, len, replace,
  startswith, trimprefix, trimsuffix.
- `std.path` (alias `path`) — join, dir.
- `ooke.config` (alias `cfg`) — provides the `$ookecfg` config record type.
- `ooke.router` (alias `router`) — `routerscan` returns the `@$route` list;
  `routecountdynamic` counts a pattern's dynamic segments.
- `ooke.template` (alias `tpl`) — `tplrenderfile` renders a `.tkt` template.
- `ooke.store` (alias `store`) — `storeallflat` loads a content collection.
- `ooke.validate` (alias `validate`) — model loading, content validation,
  result merge/empty/log; provides the `$modeldef`/`$fielddef` types.

## Types

### `$builderr`

Error type returned by the fallible build functions.

| Field | Type | Description |
|-------|------|-------------|
| `msg` | `$str` | Human-readable failure description. |

### `$buildreport`

Summary of a completed build, returned by `buildrun`.

| Field | Type | Description |
|-------|------|-------------|
| `pagesbuilt` | `i64` | Total HTML pages written (static + dynamic + 404). |
| `assetscopy` | `i64` | Count of static asset files copied. |
| `valerrors` | `i64` | Number of validation errors accumulated. |
| `valwarnings` | `i64` | Number of validation warnings accumulated. |
| `pagesskipped` | `i64` | Pages that failed: a dynamic page whose template failed or rendered empty, a write failure, or a failed 404 template or `404.html` write. `cli.runbuild` fails the build when it is non-zero. |
| `assetsfailed` | `i64` | Static assets that were not copied (121.67). `cli.runbuild` fails the build when it is non-zero. |

### `$assetreport`

Result of `buildcopyassets` (121.67).

| Field | Type | Description |
|-------|------|-------------|
| `copied` | `i64` | Asset files copied into `<outputdir>/static`. |
| `failed` | `i64` | Asset files that could not be copied (each logged at error), or 1 when `static/` could not be listed. |

## Functions

### `buildisstaticpage(r: $route): bool`

`!r.isdynamic && !r.isapi`. Story 134.24: `routerscan` has always set `isapi`
for anything under `pages/api/`, and serve has always read it; the build did
not, so every API route was rendered as a page, found no
`templates/api/<name>.tkt`, and aborted the build (including on `ooke new`'s
own output). Named so it can be asserted directly.

### `buildisdynamicpage(r: $route): bool`

`r.isdynamic && !r.isapi` — `pages/api/[id].tk` is a handler with a path
parameter, not a content-backed section (134.24).

### `buildresolve(projectdir: $str; p: $str): $str`

**Purpose:** Anchor a project-relative path (a route's `templatepath`, or
`[build].output`) to the project directory, so `ooke build <path>` works from
any working directory (story 134.25).

**Returns:** `p` unchanged when it is absolute or when `projectdir` is `""` or
`"."` (so a build run from the project root is unchanged); otherwise
`projectdir` (trailing `/` trimmed) + `"/"` + `p`. A trailing `/` on `p` is
preserved.

### `buildoutputpath(pattern: $str; outputdir: $str): $str`

**Purpose:** Map a route pattern to the on-disk output file path.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `pattern` | `$str` | Route pattern, e.g. `"/"` or `"/about"`. |
| `outputdir` | `$str` | Build output directory. |

**Returns:** `$str` — the output file path.

**Logic:**

1. If `pattern` equals `"/"`, return `str.concat(outputdir; "index.html")`.
2. Otherwise strip a leading `"/"` from `pattern` with `str.trimprefix`, then
   return `path.join(outputdir; path.join(stripped; "index.html"))` — i.e. a
   directory-style URL whose document is `index.html`.

**Error handling:** None; total function.

### `buildfinish(html: $str; templatesdir: $str; doinlinecss: bool; dominify: bool): $str`

**Purpose:** Apply the `[build]` output transforms to one rendered page. This is
the single place `[build].inlinecss` and `[build].minify` are honoured.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `html` | `$str` | The rendered page. |
| `templatesdir` | `$str` | Templates root, used to resolve stylesheet hrefs. |
| `doinlinecss` | `bool` | `[build].inlinecss` — inline linked stylesheets. |
| `dominify` | `bool` | `[build].minify` — collapse whitespace, strip comments. |

**Returns:** `$str` — the transformed page; `html` unchanged when both flags are
false.

**Logic:** Inlining runs first: it replaces the `<link rel="stylesheet">` with a
`<style>` block, so it must precede minification, which collapses the
whitespace around it.

**Error handling:** None; delegates to the total `buildinlinecss` and
`buildminify`.

**Story 134.20.** Before this function existed both settings were parsed into
`$ookecfg` and read by nothing — `buildminify` and `buildinlinecss` were
defined, documented and unit-tested, but never called on the build path.

### `buildpage(templatepath: $str; pattern: $str; sitename: $str; siteurl: $str; sitelanguage: $str; buildoutput: $str; templatesdir: $str; doinlinecss: bool; dominify: bool): i64!$builderr`

**Purpose:** Render one static page from its template and write it to disk.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `templatepath` | `$str` | Path to the page template (already resolved against the project). |
| `pattern` | `$str` | Route pattern for the page. |
| `sitename` | `$str` | `site.name` context value. |
| `siteurl` | `$str` | `site.url` context value. |
| `sitelanguage` | `$str` | `site.language` context value. |
| `buildoutput` | `$str` | Build output directory. |
| `templatesdir` | `$str` | Templates root for layouts and partials. |
| `doinlinecss` | `bool` | `[build].inlinecss`, passed to `buildfinish`. |
| `dominify` | `bool` | `[build].minify`, passed to `buildfinish`. |

**Returns:** `0`, or `$builderr`.

**Logic:**

1. Build a context map with `"site.name"`, `"site.url"`, `"site.language"`.
2. If `templatepath` does not exist: log at error `build: route <pattern> has
   no template…`, explaining that `pages/a/b.tk` needs `templates/a/b.tkt` and
   naming the expected path; return `$builderr`.
3. Render with `tpl.tplrenderfile(templatepath; ctx; templatesdir)`. On
   failure log `build: route <pattern> — <templatepath> exists but could not be
   rendered; the template's own error is logged above.` and return `$builderr`.
4. `buildfinish` the output; compute `buildoutputpath(pattern; buildoutput)`.
5. `file.mkdir` its parent; on failure log and return `$builderr` naming the
   directory. `file.write` the page; on failure log and return `$builderr`
   naming the file. Return `0`.

**Error handling:** Every failure is logged at error level where it happens
and returned as `$builderr` (story 134.24: a bare `!$builderr` carried a message
nothing printed, so the operator saw only "build failed").

### `buildinlinecssonce(html: $str; templatesdir: $str): $str`

**Purpose:** Inline the **first** `<link rel="stylesheet" href="...">` tag found
in `html`, replacing it with a `<style>...</style>` block containing the CSS file
contents. Idempotent when there is nothing to inline.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `html` | `$str` | Input HTML. |
| `templatesdir` | `$str` | Directory the `href` is resolved against. |

**Returns:** `$str` — the HTML, possibly with one stylesheet link inlined.

**Logic:**

1. Find `pos = str.indexof(html; "<link rel=\"stylesheet\"")`. If `pos < 0`,
   return `html` unchanged.
2. Slice `html` from `pos` to end into `afterlink` (matched `{$ok:v v;$err:e ""}`
   to a string `afterlink2`). If empty, return `html`.
3. Find the `href="` marker (`hrefmarker`) in `afterlink2` at `hrefpos`. If
   `< 0`, return `html`.
4. Compute `start = (hrefpos + 6) as u64` (6 = length of `href="`); slice
   `afterlink2` from `start` to end into `afterhref2`. If empty, return `html`.
5. Find the closing quote `"` at `closequote` in `afterhref2`. If `< 0`, return
   `html`.
6. Slice `afterhref2[0 .. closequote]` to get the href value `hrefval2`; resolve
   the CSS path with `path.join(templatesdir; hrefval2)`.
7. Read the CSS file (`file.read`, matched to `""` on error) into `csscontent`.
   If empty, return `html`.
8. Find the tag end `>` at `tagend` in `afterlink2`. If `< 0`, return `html`.
9. Slice `afterlink2[0 .. tagend+1]` to get the full `<link...>` tag `fulltag2`.
10. Build `styleblock = "<style>\n" + csscontent + "\n</style>"` and return
    `str.replace(html; fulltag2; styleblock)`.

**Error handling:** Total. Every failure path (no link, empty slice, missing
quote, missing/empty CSS file, no tag end) falls back to returning `html`
unchanged; slice/read results are matched with `{$ok…;$err…}` to defaults.

### `buildinlinecss(html: $str; templatesdir: $str): $str`

**Purpose:** Inline **all** stylesheet links by repeatedly applying
`buildinlinecssonce` until it reaches a fixed point.

**Logic:**

1. `result` is a mutable string initialised to `html`; `running` is a mutable
   bool initialised to `true`.
2. Loop with counter `ii` from `0` while `running`: compute
   `next = buildinlinecssonce(result; templatesdir)`. If `next = result`
   (no change), set `running = false`; otherwise set `result = next`.
3. Return `result`.

**Error handling:** None; delegates to the total `buildinlinecssonce`.

### `buildminify(html: $str): $str`

**Purpose:** Minify HTML by collapsing repeated spaces and stripping HTML
comments.

**Logic:**

1. `s` is a mutable string initialised to `html`; `running` is a mutable bool
   `true`. Loop (`ii`) while `running`: replace `"  "` (two spaces) with `" "`
   (one space) via `str.replace`; if the replacement equals `s` (fixed point),
   set `running = false`; otherwise set `s` to the replacement. This collapses
   every run of spaces down to a single space.
2. `running2` is a mutable bool `true`. Loop (`jj`) while `running2`:
   a. Find `openpos = str.indexof(s; "<!--")`. If `< 0`, stop (`running2=false`).
   b. Slice `s` from `openpos+4` to end into `afteropen2` (match to `""`). If
      empty, stop.
   c. Find `closepos = str.indexof(afteropen2; "-->")`. If `< 0`, stop.
   d. Compute `commentend = openpos + 4 + closepos + 3` (absolute end index past
      `-->`). Slice `before2 = s[0 .. openpos]` and `after2 = s[commentend ..]`,
      and set `s = before2 + after2`, removing one comment per iteration.
3. Return `s`.

**Error handling:** Total. Slice results matched with `{$ok…;$err…}` to `""`.

### `buildcopyassets(projectdir: $str; outputdir: $str): $assetreport`

**Purpose:** Copy the project's `static/` tree into `<outputdir>/static`.

**Logic:**

1. `staticdir = path.join(projectdir; "static")`. If `!file.isdir(staticdir)`,
   return `{copied: 0; failed: 0}`.
2. List all files with `file.listall(staticdir)`. On failure log at error
   `build: could not list the static directory <staticdir>` and return
   `{copied: 0; failed: 1}`.
3. `staticout = trimsuffix(outputdir; "/") + "/static"`. `count` and `failed`
   start at `0`. For each listed `rel`:
   a. `srcpath = path.join(staticdir; rel)`;
      `dstpath = path.join(staticout; rel)`.
   b. mkdir `path.dir(dstpath)`. On failure log at error `build: static asset
      <srcpath> — could not create the directory <dir>` and increment
      `failed`.
   c. Otherwise `file.copy(srcpath; dstpath)`: success increments `count`;
      failure logs at error `build: could not copy <srcpath> to <dstpath>`
      and increments `failed`.
4. Return `{copied: count; failed: failed}`.

**Error handling:** Total. Every failure is logged where it happens and
counted; one bad file does not stop the rest of the tree being copied
(121.67: both results used to be dropped, so a missing asset left the build
at exit 0).

### `buildrun(projectdir: $str; config: $ookecfg): $buildreport!$builderr`

**Purpose:** Run the full static build for a project, returning a summary report.

**Logic:**

1. Derive `pagesdir`, `contentdir`, `templatesdir`, `modelsdir` by joining
   `projectdir` with `"pages"`, `"content"`, `"templates"`, `"models"`;
   `outdir = buildresolve(projectdir; config.buildoutput)` (134.25).
2. `router.routerscan(pagesdir)`; on failure log `build: could not scan the
   pages directory: <pagesdir>` and return `$builderr`.
3. `pagescount`, `skippedcount`, `apicount` start at 0; `allval` at
   `validate.validateempty()`.
4. **Static pass:** for each route, count it in `apicount` if `isapi`; if
   `buildisstaticpage`, `buildpage(buildresolve(projectdir; templatepath);
   pattern; …; outdir; templatesdir; config.buildinlinecss;
   config.buildminify)!$builderr` and increment `pagescount`. If `apicount > 0`,
   log at info that those routes are request handlers served by `ooke serve`
   and not rendered into the static build.
5. **Dynamic pass:** for each route, `isdyn2 = buildisdynamicpage(route)` and
   `dyncount = router.routecountdynamic(pattern)`.
   - `dyncount > 1 && isdyn2`: warn that the route cannot be built statically
     (the builder resolves exactly one `:slug` backed by a literal content
     directory); it is served dynamically only.
   - `isdyn2 && dyncount == 1`: load `col = store.storeallflat(contentdir;
     contenttype)` (empty on error) and `model = validate.validateloadmodel(
     modelsdir; contenttype)` (an empty `$modeldef` on error;
     `hasmodel = model.fields.len > 0`). For each item:
     a. An empty `slug` warns `not published` (a `.json` item must carry a
        `slug` key); the item is not written, so it cannot overwrite the
        section index.
     b. If `hasmodel`, validate it (`validatecontent(model; meta;
        "<ctype>/<slug>.md")`) and merge into `allval`.
     c. Render `tpl.tplrenderfile(buildresolve(projectdir; templatepath); ctx;
        templatesdir)` with `site.*`, `slug`, `body`, `title`, then
        `buildfinish`.
     d. Render failed (and slug non-empty): log at error naming the route, slug
        and template (121.59), `skippedcount += 1`. Else empty output: log
        `build: render produced no output for <templatepath> slug=<slug>`,
        `skippedcount += 1`.
     e. Non-empty output and slug: substitute `:slug` in the pattern, write to
        `buildoutputpath(…; outdir)`. mkdir the parent first: if that fails,
        log at error `build: route <pattern> slug=<slug> — could not create
        the output directory <dir>` and increment `skippedcount` (121.66; the
        result was ignored and the failure surfaced as "write failed").
        Otherwise write; success increments `pagescount`, failure logs
        `build: write failed for <outpath>` and increments `skippedcount`.
6. `validate.validatelogresult(allval)`.
7. `assets = buildcopyassets(projectdir; outdir)`.
8. **404 pass:** if `templates/errors/404.tkt` exists, render it with
   `site.*` and `"request.path":"(unknown)"`. A failed render logs at error
   naming the template and increments `skippedcount` (121.59: it used to be
   skipped silently, shipping no `404.html`). A non-empty result goes through
   `buildfinish` and is written to `outdir + "404.html"`, after making
   `outdir` (a site with no other page has not made it yet). Success
   increments `pagescount`; a failed mkdir or write logs at error naming the
   directory or `404.html` and increments `skippedcount` (121.67: the write
   result was dropped, so the build exited 0 with no `404.html`).
9. Return `$buildreport{pagesbuilt; assetscopy = assets.copied; valerrors;
   valwarnings; pagesskipped; assetsfailed = assets.failed}`.

**Error handling:** A failed route scan and any failed static page return
`$builderr` (each logged first). Dynamic pages and the 404 page are counted in
`pagesskipped` instead, so the build reports every failed page and
`cli.runbuild` then fails it; asset copy failures are counted in
`assetsfailed`, which fails the build the same way (121.67).

## Control Flow

`buildrun` is the orchestrating entry point. It runs two route loops (static
then dynamic), a validation log, an asset copy, and an optional 404 emission,
accumulating `pagescount`, `skippedcount` and a merged `$valresult` across
them. The pure
helpers `buildoutputpath`, `buildinlinecss(once)`, and `buildminify` are
standalone: `buildoutputpath` is called by both `buildpage` and the dynamic
pass; `buildinlinecss` and `buildminify` are fixed-point loops that repeatedly
apply a single-step transform until the string stops changing.

## Notes

- **Canonical result form.** All `mt … {…}` match arms use the spec-canonical
  `$ok`/`$err` variant names (toke-spec-prompt.md: "Variants are `$lowercase`").
  The previous source used non-canonical `Ok`/`Err`; both compile, but `$ok`/
  `$err` is the spec form (Track B 113.B.9).
- **Failures are logged at the point of failure.** `std.log` is imported for
  this (134.24): the `$builderr` payload cannot be read by `cli.runbuild`
  (RT005, toke 127.78), so the route, template and reason are logged here.
- **A failed page fails the build.** A static page returns `$builderr`; a
  dynamic or 404 page is counted in `pagesskipped`, which `cli.runbuild` treats
  as failure (121.59).
- **Unit-testable surface.** `buildoutputpath`, `buildminify`, and the
  no-stylesheet / inline / missing-file paths of `buildinlinecss`,
  `buildresolve`, `buildisstaticpage` and `buildisdynamicpage` are pure (or
  filesystem-local) and are covered directly. `buildpage`/`buildrun`/
  `buildcopyassets` need a project directory on disk and are exercised end-to-end
  rather than as unit tests.
