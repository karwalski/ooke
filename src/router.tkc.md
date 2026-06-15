---
source_file: "router.tk"
source_hash: "29c4883c3bd9913961075cc6839a124a465157f70568b1bf8ccbf704643c39f5"
compiler_version: "0.3.9"
generated_at: "2026-06-15T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.router`

File-system router for ooke. It scans a `pages/` directory into a list of
`$route` records (deriving the URL pattern, template path, and content-type
namespace for each page file), and matches an incoming request URL against
that list — preferring static routes, then the most-specific dynamic route.

**Imports:**
- `std.file` (alias `file`) — recursive directory listing (`file.listall`); also
  used as the canonical "raise an error" primitive (`file.listall("")` always
  fails, so `(file.listall("")!$routeerr)` is an early-return-with-error idiom).
- `std.str` (alias `str`) — string splitting, trimming, prefix/suffix tests,
  concatenation, bracket matching, length, and substring search.
- `std.path` (alias `path`) — file-extension extraction (`path.ext`).

## Types

### `$route`

One file-system page, resolved to its routing metadata.

| Field | Type | Description |
|-------|------|-------------|
| `pattern` | `$str` | URL pattern, e.g. `/blog/:slug` (dynamic segments are `:name`). |
| `filepath` | `$str` | Source page path under the pages dir. |
| `templatepath` | `$str` | Derived `.tkt` template path. |
| `contenttype` | `$str` | Content-type namespace (parent directory chain), `""` for top-level pages. |
| `isdynamic` | `bool` | True if `pattern` contains a `:` segment. |
| `isapi` | `bool` | True if the file path is under an `api/` directory. |
| `params` | `@$str` | Reserved parameter-name list; always constructed empty (`@()`). |

### `$routematch`

The result of matching a URL against a route.

| Field | Type | Description |
|-------|------|-------------|
| `route` | `$route` | The route that matched. |
| `params` | `@($str:$str)` | Captured dynamic parameters: pattern `:name` segment to URL value. |

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
3. Accumulate a mutable `out` string. For each segment, attempt
   `str.matchbracket(seg)`; matched `{$ok:name ...; $err:e ...}` — a bracketed
   segment `[name]` becomes the dynamic segment `:name`, otherwise the segment
   is kept verbatim. Append `"/" + mapped` to `out`.
4. If `out` ends with `/index`, trim that suffix (index pages map to their
   directory).
5. If the result is empty, return `"/"` (the root). Otherwise return it.

**Error handling:** None; total function.

### `routederivetemplate(filepath: $str; pagesdir: $str): $str`

**Purpose:** Derive the `.tkt` template path for a page file path.

**Parameters:** `filepath`, `pagesdir` as above.

**Returns:** `$str` — `"templates/" + <relative-path-without-.tk> + ".tkt"`.

**Logic:** Strip the `pagesdir` prefix and the `.tk` suffix, then return
`str.concat("templates/"; str.concat(noext; ".tkt"))`.

**Error handling:** None.

### `routederivedtype(filepath: $str; pagesdir: $str): $str`

**Purpose:** Derive the content-type namespace (the parent directory chain) for
a page file path.

**Parameters:** `filepath`, `pagesdir` as above.

**Returns:** `$str` — the slash-joined parent directories, `""` for a top-level
page.

**Logic:**

1. Strip the `pagesdir` prefix and split on `/`.
2. If there is more than one segment, join all segments except the last
   (the filename) with `/` into a mutable `parts` (first segment assigned
   directly, subsequent segments appended as `parts + "/" + seg`); the result is
   `parts`.
3. Otherwise the result stays `""`.
4. Return the result.

**Error handling:** None.

### `routerscan(pagesdir: $str): @$route!$routeerr`

**Purpose:** Recursively scan `pagesdir` and build the route table.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `pagesdir` | `$str` | Pages directory to scan. |

**Returns:** `@$route!$routeerr` — the list of routes, or `$routeerr` if the
directory listing fails.

**Logic:**

1. `file.listall(pagesdir)` recursively, propagating failure as `$routeerr`
   via `!$routeerr`.
2. Initialise a mutable route array `@($route)`.
3. For each listed path whose extension (`path.ext`) is `.tk`:
   a. Derive `pattern` (`routederivepattern`).
   b. Build a `$route` with `templatepath` (`routederivetemplate`),
      `contenttype` (`routederivedtype`), `isdynamic` = `pattern` contains `:`,
      `isapi` = path contains `/api/` or starts with `api/`, and `params:@()`.
   c. Append it to the array.
4. Return the array.

**Error handling:** Only the directory listing can fail; it surfaces as
`$routeerr`.

### `routertrymatch(route: $route; url: $str): $routematch!$routeerr`

**Purpose:** Try to match a single route's `pattern` against `url`, capturing
dynamic parameters.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `route` | `$route` | The route to test. |
| `url` | `$str` | The request URL. |

**Returns:** `$routematch!$routeerr` — the match (with captured params) on
success, or `$routeerr` if the URL does not match the pattern.

**Logic:**

1. Split both `url` and `route.pattern` on `/`.
2. If the segment counts differ, raise an error (`(file.listall("")!$routeerr)`
   — `file.listall("")` always fails, forcing the `!` early-return).
3. Initialise a mutable map `captures` of type `@($str:$str)`.
4. For each segment index, with `pseg` (pattern) and `useg` (url):
   - If `pseg` starts with `:`, it is a dynamic segment: store
     `captures.set(str.trimprefix(pseg;":"); useg)`.
   - Otherwise the static segments must be equal. Equality is computed as
     `samelen = str.len(pseg)=str.len(useg)` AND `samebody = str.len(pseg)=0 ||
     str.indexof(pseg;useg)=0`; if not `(samelen && samebody)`, raise an error.
     (See Notes — this length+`indexof` test replaces a direct `pseg=useg`
     comparison to dodge a compiler bug where `=` compares two
     dynamically-allocated strings by identity, Track B.)
5. Return `$routematch{route:route; params:captures}`.

**Error handling:** A segment-count mismatch or a non-matching static segment
yields `$routeerr` via the `file.listall("")` early-return idiom.

### `routecountdynamic(pattern: $str): i64`

**Purpose:** Count the dynamic (`:name`) segments in a pattern, used as a
specificity score (fewer dynamic segments = more specific).

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `pattern` | `$str` | A route pattern. |

**Returns:** `i64` — the number of `:`-prefixed segments.

**Logic:** Split `pattern` on `/`; initialise a mutable `count` to `0`; for each
segment that starts with `:`, increment `count`; return `count`.

**Error handling:** None.

### `routermatch(routes: @$route; url: $str): $routematch!$routeerr`

**Purpose:** Match `url` against the full route table, preferring static routes
and then the most-specific (fewest dynamic segments) dynamic route.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `routes` | `@$route` | The route table. |
| `url` | `$str` | The request URL. |

**Returns:** `$routematch!$routeerr` — the chosen match, or `$routeerr` if
nothing matches.

**Logic:**

1. Normalise `url` into a mutable `normurl`: if it ends with `/` and is not the
   root `"/"`, trim the trailing slash.
2. Build a sentinel `defroute` (all fields empty/false) and `defmatch`
   (`$routematch` with empty params), used as the `$err` arm placeholder.
   Initialise mutable `foundmatch=defmatch` and `foundidx=-1`.
3. **Static pass:** for each route, if it is not dynamic and nothing has been
   found yet (`foundidx<0`), call `routertrymatch`; matched
   `{$ok:m m; $err:e defmatch}`. If the unwrapped value's `route.pattern` is
   non-empty (i.e. a real match, not the sentinel), set `foundmatch` and
   `foundidx`.
4. **Dynamic pass:** initialise `bestdyncount=999`. For each dynamic route, if
   nothing was found or the current best is itself dynamic, call
   `routertrymatch`; on a real match, compute `routecountdynamic(r.pattern)` and
   if it is lower than `bestdyncount`, adopt this route and record its count
   (most-specific wins).
5. If `foundidx<0`, raise `$routeerr` (the `file.listall("")` idiom).
6. Return `foundmatch`.

**Error handling:** No matching route yields `$routeerr`.

## Control Flow

`routerscan` is the table-builder (offline); `routermatch` is the request-time
entry point. `routermatch` delegates per-route testing to `routertrymatch`,
which delegates parameter naming to nothing further (it inlines the capture).
`routecountdynamic` is the specificity comparator used only by `routermatch`'s
dynamic pass. The three `routederive*` helpers are pure string transforms used
by `routerscan`.

Matching is two-phase: static routes win outright; among dynamic routes the one
with the fewest `:` segments is selected, so `/docs/about/:slug` beats
`/docs/:section/:slug` for `/docs/about/overview`.

## Notes

- **Canonical result form.** Match arms use the spec-canonical `$ok`/`$err`
  variant names (toke-spec-prompt.md: "Variants are `$lowercase`"). The previous
  source used non-canonical `Ok`/`Err`; both compile, but `$ok`/`$err` is the
  spec form (Track B 113.B.9).
- **Error idiom.** `(file.listall("")!$routeerr)` is the deliberate way to raise
  `$routeerr` from inside a function: `file.listall("")` always fails, so the
  `!` operator early-returns the error. Behaviour is unchanged from the
  reference.
- **String-equality workaround (Track B compiler-bug).** The reference compared
  static segments with `pseg=useg`. The `=` operator on two *dynamically
  allocated* strings (here both produced by `str.split`) compares by identity,
  not content, so it returns false even for equal contents — which made every
  match fail. This module instead tests equality as
  `str.len(a)=str.len(b) && (str.len(a)=0 || str.indexof(a;b)=0)`, which is
  behaviourally identical to value equality for these segments and is not
  fragile (it is the documented content-comparison fallback). Comparisons of a
  dynamic string against a *literal* (e.g. `pattern=""`, `path.ext(p)=".tk"`)
  are unaffected and use `=` directly.
- **Cross-module map field is not readable by consumers (Track B compiler-bug).**
  The emitted `ooke.router.tki` collapses the field types `params:@($str:$str)`
  and `params:@$str` to a bare `@`, losing the map key/value (and array element)
  types. A consuming module that reads `$routematch.params.get(key)` therefore
  has `.get` compiled as *array* indexing against a *map* pointer and crashes at
  runtime. This is purely a toke-core interface-emit/import bug — the runtime
  map itself is correct in-module (`captures.set`/`captures.get` work). Until it
  is fixed in toke core, callers (and tests) can rely on match success/failure
  and the non-map fields (`route.pattern`, etc.) but cannot read captured
  parameter *values* across the module boundary. The router's behaviour and
  signatures are unchanged; the bug is in interface type fidelity, not here.
- **Dropped nothing functional from the reference.** Intermediate `let`
  bindings that were used exactly once were inlined for token efficiency; the
  observable behaviour and all signatures are identical to the parity reference.
