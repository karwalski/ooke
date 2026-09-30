---
source_file: "router.tk"
source_hash: "784bc08ce7db16820231f3cf58902a1566b99d0d29af7d1973c9a7d3a55a6a94"
compiler_version: "3.0.0"
generated_at: "2026-10-01T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.router`

File-system router for ooke. It scans a `pages/` directory into a list of
`$route` records (deriving the URL pattern, template path, and content-type
namespace for each page file), and matches an incoming request URL against
that list — preferring static routes, then the most-specific dynamic route.
`ooke serve` and `ooke build` use `routerscan`; `routermatch` is the matcher.

**Imports:**
- `std.file` (alias `file`) — `file.isdir` (the pages-dir guard), recursive
  listing (`file.listall`), and `file.listall("")` as an error-raising idiom
  (see Notes).
- `std.str` (alias `str`) — split, trim prefix/suffix, prefix/suffix tests,
  join, concat, `matchbracket`, `contains`, `eq`.
- `std.path` (alias `path`) — file-extension extraction (`path.ext`).

## Types

### `$route`

One file-system page, resolved to its routing metadata.

| Field | Type | Description |
|-------|------|-------------|
| `pattern` | `$str` | URL pattern, e.g. `/blog/:slug` (dynamic segments are `:name`). |
| `filepath` | `$str` | The page file path as listed (under the pages dir). |
| `templatepath` | `$str` | Derived `templates/<rel>.tkt` path, project-relative. |
| `contenttype` | `$str` | Content-type namespace (parent directory chain), `""` for top-level pages. |
| `isdynamic` | `bool` | True if `pattern` contains a `:`. |
| `isapi` | `bool` | True if the file path contains `/api/` or starts with `api/`. |
| `params` | `@$str` | Reserved; always constructed empty (`@()`). |

### `$routematch`

The result of matching a URL against a route.

| Field | Type | Description |
|-------|------|-------------|
| `route` | `$route` | The route that matched. |
| `params` | `@($str:$str)` | Captured dynamic parameters: `:name` segment → URL value. |

### `$routeerr`

Error type for the fallible router functions.

| Field | Type | Description |
|-------|------|-------------|
| `msg` | `$str` | Human-readable failure description. |

## Functions

### `routederivepattern(filepath: $str; pagesdir: $str): $str`

**Purpose:** Derive the URL pattern for a page file path.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `filepath` | `$str` | Page file path (under `pagesdir`). |
| `pagesdir` | `$str` | Pages directory prefix to strip. |

**Returns:** `$str` — the URL pattern.

**Logic:**

1. Strip the `pagesdir` prefix, then the trailing `.tk` suffix.
2. Split the remainder on `/` into segments.
3. For each segment, `str.matchbracket(seg)` matched `{$ok:name ...; $err:e ...}`:
   a bracketed segment `[name]` becomes `:name`, otherwise the segment is kept
   verbatim. Append `"/" + mapped` to a mutable `out` (`str.join`).
4. If `out` ends with `/index`, trim that suffix (index pages map to their
   directory).
5. If the result is empty, return `"/"`; otherwise return it.

**Error handling:** None; total function. Segments are not escaped: a file
name's characters (quotes, backslashes, markup) reach the pattern as written.

### `routederivetemplate(filepath: $str; pagesdir: $str): $str`

**Purpose:** Derive the `.tkt` template path for a page file path.

**Returns:** `$str` — `str.join("";@("templates/"; noext; ".tkt"))`, where
`noext` is `filepath` without the `pagesdir` prefix and the `.tk` suffix. The
path is project-relative; callers anchor it (`build.buildresolve`).

**Error handling:** None.

### `routederivedtype(filepath: $str; pagesdir: $str): $str`

**Purpose:** Derive the content-type namespace (the parent directory chain) for
a page file path.

**Returns:** `$str` — the `/`-joined parent directories of the relative path,
`""` for a top-level page.

**Logic:** Strip the `pagesdir` prefix and split on `/`. If there is more than
one segment, join all but the last with `/` (first assigned directly, the rest
appended as `parts + "/" + seg`). Otherwise `""`.

**Error handling:** None.

### `routerscan(pagesdir: $str): @$route!$routeerr`

**Purpose:** Recursively scan `pagesdir` and build the route table.

**Parameters:** `pagesdir: $str` — the pages directory to scan.

**Returns:** `@$route!$routeerr` — the routes, or `$routeerr`.

**Logic:**

1. If `!file.isdir(pagesdir)`, return `$routeerr{msg:"no pages dir: " +
   pagesdir}` (story 134.14; see Error handling).
2. `file.listall(pagesdir)!$routeerr`.
3. For each listed path whose `path.ext` is `.tk`: derive `pattern`; build a
   `$route` with `filepath` = the path, `templatepath`
   (`routederivetemplate`), `contenttype` (`routederivedtype`), `isdynamic` =
   `pattern` contains `:`, `isapi` = path contains `/api/` or starts with
   `api/`, and `params:@()`; append it.
4. Return the array.

**Error handling:** A missing pages directory is this module's own
`$routeerr`. It used to be the propagated `file.listall` failure, but `!` on a
stdlib call returns the 0 sentinel without setting the current error, so the
caller's `mt` took the `$ok` arm, bound a null array and segfaulted on `.len`
— which is why `ooke serve` and `ooke build` died with signal 11 on a project
with no `pages/` (134.14).

### `routertrymatch(route: $route; url: $str): $routematch!$routeerr`

**Purpose:** Try to match one route's `pattern` against `url`, capturing
dynamic parameters.

**Returns:** `$routematch!$routeerr` — the match (with captured params), or
`$routeerr` if the URL does not match.

**Logic:**

1. Split `url` and `route.pattern` on `/`.
2. If the segment counts differ, raise with `(file.listall("")!$routeerr)`.
3. For each pattern segment `pseg` and URL segment `useg`:
   - `pseg` starts with `:` — `captures.set(str.trimprefix(pseg;":"); useg)`.
   - otherwise, if `!str.eq(pseg;useg)`, raise with
     `(file.listall("")!$routeerr)`.
4. Return `$routematch{route:route; params:captures}`.

**Error handling:** A segment-count mismatch or a differing static segment
raises through the `file.listall("")` idiom (see Notes).

### `routecountdynamic(pattern: $str): i64`

**Purpose:** Count the `:`-prefixed segments of a pattern — the specificity
score (fewer = more specific).

**Logic:** Split on `/`, count segments starting with `:`, return the count.

**Error handling:** None.

### `routermatch(routes: @$route; url: $str): $routematch!$routeerr`

**Purpose:** Match `url` against the full route table, preferring static routes
and then the dynamic route with the fewest dynamic segments.

**Returns:** `$routematch!$routeerr` — the chosen match, or `$routeerr` if
nothing matches.

**Logic:**

1. `normurl`: `url` with a trailing `/` trimmed, unless `url` is `"/"`.
2. Build a sentinel `defroute` (all fields empty/false) and `defmatch`; set
   `foundmatch=defmatch`, `foundidx=-1`.
3. **Static pass:** for each non-dynamic route, while nothing is found, call
   `routertrymatch` matched `{$ok:m m; $err:e defmatch}`; a non-empty
   `route.pattern` is a real match — record it and its index.
4. **Dynamic pass:** `bestdyncount=999`. For each dynamic route, if nothing was
   found or the current best is dynamic, try it; on a real match whose
   `routecountdynamic` is below `bestdyncount`, adopt it and record the count.
5. If `foundidx<0`, raise with `(file.listall("")!$routeerr)`.
6. Return `foundmatch`.

**Error handling:** No matching route yields `$routeerr` through the idiom.

## Control Flow

`routerscan` builds the table; `routermatch` is the request-time entry point,
delegating per-route tests to `routertrymatch` and specificity to
`routecountdynamic`. The three `routederive*` helpers are pure string
transforms used by `routerscan`.

Matching is two-phase: static routes win outright; among dynamic routes the one
with the fewest `:` segments wins, so `/docs/about/:slug` beats
`/docs/:section/:slug` for `/docs/about/overview`.

## Notes

- **Canonical result form.** Match arms use `$ok`/`$err`.
- **Error idiom.** `(file.listall("")!$routeerr)` raises `$routeerr` on the
  assumption that listing the empty path fails. `ooke.store` dropped the same
  idiom (story 127.127) because it does not always fail; `routerscan` stopped
  relying on a propagated stdlib failure for the pages-dir case (134.14). The
  three uses in `routertrymatch` and `routermatch` remain.
- **String equality.** Static segments are compared with `str.eq`. (An earlier
  version compared length plus `str.indexof` to dodge a compiler bug in `=` on
  two dynamic strings; that workaround is gone.)
- **`isapi` tests the listed path**, which begins with `pagesdir`; it is not
  made relative first.
