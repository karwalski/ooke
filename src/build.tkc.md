---
source_file: "build.tk"
source_hash: "00851b2daa2ede5d1bbeaea5ac7bc92cc889e82c5d3e82db60c075a92d64f184"
compiler_version: "0.3.9"
generated_at: "2026-06-16T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.build`

Static-site build for an ooke project. It scans the file-system routes, renders
every static page and every dynamic page (one output per content item),
validates dynamic content against its TOML model, copies the `static/` asset
tree into the output, and emits a `404.html` when an error template exists. It
also provides three pure HTML post-processing helpers: output-path derivation,
CSS inlining, and whitespace/comment minification.

**Imports:**
- `std.file` (alias `file`) — read, write, mkdir, copy, isdir, exists, listall.
- `std.str` (alias `str`) — concat, slice, indexof, len, replace, trimprefix.
- `std.path` (alias `path`) — join, dir.
- `ooke.config` (alias `cfg`) — provides the `$ookecfg` config record type.
- `ooke.router` (alias `router`) — `routerscan` returns the `@$route` list.
- `ooke.template` (alias `tpl`) — `tplrenderfile` renders a `.tkt` template.
- `ooke.store` (alias `store`) — `storeall` loads a content collection.
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

## Functions

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

### `buildpage(templatepath: $str; pattern: $str; sitename: $str; siteurl: $str; sitelanguage: $str; buildoutput: $str; templatesdir: $str): void!$builderr`

**Purpose:** Render one static page from its template and write it to disk.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `templatepath` | `$str` | Path to the page template. |
| `pattern` | `$str` | Route pattern for the page. |
| `sitename` | `$str` | `site.name` context value. |
| `siteurl` | `$str` | `site.url` context value. |
| `sitelanguage` | `$str` | `site.language` context value. |
| `buildoutput` | `$str` | Build output directory. |
| `templatesdir` | `$str` | Templates root for template resolution. |

**Returns:** `void!$builderr`.

**Logic:**

1. Build a context map `@(...)` with keys `"site.name"`, `"site.url"`,
   `"site.language"` bound to the matching parameters.
2. Render the template with `tpl.tplrenderfile(templatepath; ctx; templatesdir)`,
   propagating failure as `$builderr` via `!$builderr`.
3. Compute the output path with `buildoutputpath(pattern; buildoutput)`.
4. Take its parent directory with `path.dir`, create it with `file.mkdir`
   (propagating error), then `file.write` the rendered HTML (propagating error).

**Error handling:** Each fallible step (`tplrenderfile`, `mkdir`, `write`)
propagates as `$builderr` through the `!$builderr` operator.

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

### `buildcopyassets(projectdir: $str; outputdir: $str): i64!$builderr`

**Purpose:** Copy the project's `static/` tree into `<outputdir>/static`.

**Logic:**

1. `staticdir = path.join(projectdir; "static")`. If `!file.isdir(staticdir)`,
   return `0`.
2. List all files with `file.listall(staticdir)` (propagating `$builderr`).
3. `count` is a mutable `0`. Loop `i` from `0` to `files.len`:
   a. `rel = files.get(i)`; `srcpath = path.join(staticdir; rel)`;
      `dstpath = path.join(outputdir + "/static"; rel)`.
   b. mkdir the destination parent (`path.dir(dstpath)`, error matched to a
      bool), copy `srcpath` to `dstpath` (`file.copy`, error matched to a bool).
   c. If the copy succeeded, increment `count`.
4. Return `count`.

**Error handling:** `file.listall` propagates `$builderr`. Per-file `mkdir`/
`copy` failures are absorbed (matched `{$ok:v true;$err:e false}`) so one bad
file does not abort the whole copy.

### `buildrun(projectdir: $str; config: $ookecfg): $buildreport!$builderr`

**Purpose:** Run the full static build for a project, returning a summary report.

**Logic:**

1. Derive `pagesdir`, `contentdir`, `templatesdir`, `modelsdir` by joining
   `projectdir` with `"pages"`, `"content"`, `"templates"`, `"models"`.
2. `routes = router.routerscan(pagesdir)` (propagating `$builderr`).
3. `pagescount` is a mutable `0`; `allval` is a mutable `$valresult` initialised
   to `validate.validateempty()`.
4. **Static pass:** loop `i` over routes; for each non-dynamic route
   (`!routes.get(i).isdynamic`), call `buildpage(...)` (propagating `$builderr`)
   and increment `pagescount`.
5. **Dynamic pass:** loop `j` over routes; for each dynamic route
   (`routes.get(j).isdynamic`):
   a. `ctype = routes.get(j).contenttype`.
   b. Load the collection `col = store.storeall(contentdir; ctype; "flat")`
      (matched to empty `@()` on error).
   c. Load `model = validate.validateloadmodel(modelsdir; ctype)`, matched on
      error to an empty `$modeldef{name:""; fields:@($fielddef)}`. Set
      `hasmodel = model.fields.len > 0`.
   d. Loop `k` over `col`: read `slug`, `body`, `title` from `col.get(k)`. If
      `hasmodel`, build `fpath = ctype + "/" + slug + ".md"`, validate
      `validate.validatecontent(model; col.get(k).meta; fpath)` into `vr`, and
      merge `allval = validate.validatemerge(allval; vr)`. Build a context map
      with `site.*`, `slug`, `body`, `title`. Render
      `tpl.tplrenderfile(routes.get(j).templatepath; ctx; templatesdir)` (matched
      to `""` on error). If the rendered HTML is non-empty: substitute `:slug`
      with `slug` in the route pattern via `str.replace`, compute the output path
      with `buildoutputpath`, mkdir its parent, `file.write` (error matched to a
      bool), and increment `pagescount` on success.
6. Log validation with `validate.validatelogresult(allval)` (statement call).
7. `assetscount = buildcopyassets(projectdir; config.buildoutput)`, matched to
   `0` on error.
8. **404 pass:** `notfoundtpl = path.join(templatesdir; "errors/404.tkt")`. If
   `file.exists(notfoundtpl)`, build a context including
   `"request.path":"(unknown)"`, render it (matched to `""`), and if non-empty
   write it to `config.buildoutput + "404.html"`, incrementing `pagescount` on
   success.
9. Return `$buildreport{pagesbuilt:pagescount; assetscopy:assetscount;
   valerrors:allval.errors.len; valwarnings:allval.warnings.len}`.

**Error handling:** `routerscan`, each static `buildpage`, propagate `$builderr`
via `!$builderr`. All dynamic-pass steps, asset copy, and the 404 pass are total
(matched to defaults) so a single content/template/write failure degrades that
one page rather than aborting the build.

## Control Flow

`buildrun` is the orchestrating entry point. It runs two route loops (static
then dynamic), a validation log, an asset copy, and an optional 404 emission,
accumulating `pagescount` and a merged `$valresult` across them. The pure
helpers `buildoutputpath`, `buildinlinecss(once)`, and `buildminify` are
standalone: `buildoutputpath` is called by both `buildpage` and the dynamic
pass; `buildinlinecss` and `buildminify` are fixed-point loops that repeatedly
apply a single-step transform until the string stops changing.

## Notes

- **Canonical result form.** All `mt … {…}` match arms use the spec-canonical
  `$ok`/`$err` variant names (toke-spec-prompt.md: "Variants are `$lowercase`").
  The previous source used non-canonical `Ok`/`Err`; both compile, but `$ok`/
  `$err` is the spec form (Track B 113.B.9).
- **Dropped the unused `std.log` import** the reference module carried; no `log.`
  call exists in this module (validation logging goes through
  `validate.validatelogresult`).
- **loke parity.** Signatures and observable behaviour match the reference: page
  counts, asset counts, and validation totals in `$buildreport` are computed
  identically, and per-item failures degrade gracefully rather than aborting.
- **Unit-testable surface.** `buildoutputpath`, `buildminify`, and the
  no-stylesheet / inline / missing-file paths of `buildinlinecss` are pure (or
  filesystem-local) and are covered directly. `buildpage`/`buildrun`/
  `buildcopyassets` need a project directory on disk and are exercised end-to-end
  rather than as unit tests.
