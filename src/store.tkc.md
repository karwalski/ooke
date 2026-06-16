---
source_file: "store.tk"
source_hash: "fef9271e2768bda3336229a7f53327a3ba8a4756b9a002796f701fde8e71060d"
compiler_version: "0.3.9"
generated_at: "2026-06-15T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.store`

The ooke content store. Parses Markdown-with-front-matter and JSON content
files into a flat `$content` record, builds SQLite DDL, and reads/writes
content from either a flat-file backend (one file per item) or a SQLite
backend. It is the persistence layer loke and the build/serve pipelines read
content through.

**Imports:**
- `std.file` (alias `file`) — read content files and list directories.
- `std.str` (alias `str`) — string slicing, splitting, trimming, prefix/suffix
  tests, indexof, concatenation.
- `std.path` (alias `path`) — join content-directory and content-type segments.
- `std.json` (alias `json`) — decode JSON content and read typed keys.
- `std.db` (alias `db`) — SQLite query/exec; also brings the `row.*` typed
  column accessors into scope.

## Types

### `$content`

A single piece of CMS content, flattened. The well-known fields (`slug`,
`type`, `title`, `body`) are hoisted to top-level columns; `meta` holds the
full key/value front-matter map.

| Field | Type | Description |
|-------|------|-------------|
| `slug` | `$str` | URL slug. Empty string when absent. |
| `type` | `$str` | Content type. Defaults to `"page"`. |
| `title` | `$str` | Display title. Empty string when absent. |
| `meta` | `@($str:$str)` | All parsed front-matter key/value pairs. |
| `body` | `$str` | The content body (Markdown source or empty for JSON). |

### `$storeerr`

Error type for the fallible store functions.

| Field | Type | Description |
|-------|------|-------------|
| `msg` | `$str` | Human-readable failure description. |

## Functions

### `storedefault(): $content`

**Purpose:** Construct the canonical empty `$content` used as a total fallback
when a parse fails.

**Parameters:** None.

**Returns:** `$content` — `slug=""`, `type="page"`, `title=""`, empty `meta`,
`body=""`.

**Logic:** Return a `$content` record literal with the documented empty/default
field values.

**Error handling:** None.

### `storeparsefront(src: $str): $content!$storeerr`

**Purpose:** Parse a Markdown document with optional YAML-style `---` front
matter into a `$content`.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `src` | `$str` | Raw file contents. |

**Returns:** `$content!$storeerr` — the parsed content. In practice this
function never raises `$storeerr`; `str.slice` failures fall back to `""`.

**Logic:**

1. If `src` does not start with the opener `"---\n"`, treat the whole input as
   body: return `$content` with empty slug/title, `type="page"`, empty `meta`,
   `body:src`.
2. Otherwise slice off the first 4 bytes (the opener) via
   `str.slice(src;4;str.len(src))`, matched `{$ok:v v;$err:e ""}`.
3. Find the closer `"\n---\n"` with `str.indexof`. If not found (`<0`), return
   the no-front-matter content (`body:src`) as in step 1.
4. Slice the front-matter region `[0, closepos)` as `fmraw`; compute
   `bodystart = (closepos + 5) as u64`; slice and `str.trim` the remainder as
   the body. Each slice is matched `{$ok:v v;$err:e ""}`.
5. Split `fmraw` on `"\n"`. Initialise a mutable `meta` map, mutable
   `slug=""`, `ctype="page"`, `ctitle=""`.
6. For each line (index `0` to `lines.len-1`): trim it, split on `":"`. The
   guard is the original reference predicate `if(!kv.len<2)`. When it holds,
   trim `kv.get(0)` as `k` and `kv.get(1)` as `v`; if `k` equals `"slug"` /
   `"type"` / `"title"` assign the corresponding mutable; in all cases
   `meta=meta.set(k;v)`.
7. Return `$content{slug;type:ctype;title:ctitle;meta;body:bodyraw}`.

**Error handling:** Slice failures are absorbed to `""`. The `!$storeerr`
return is for signature compatibility; no error is actually produced.

### `storetryparse(src: $str): $content`

**Purpose:** Infallible wrapper over `storeparsefront`.

**Parameters:** `src: $str` — raw Markdown file contents.

**Returns:** `$content` — the parsed content, or `storedefault()` on error.

**Logic:** `mt storeparsefront(src) {$ok:c c;$err:e storedefault()}`.

**Error handling:** Any `$storeerr` collapses to `storedefault()`.

### `storeparsejson(src: $str): $content!$storeerr`

**Purpose:** Parse a JSON content document into a `$content`.

**Parameters:** `src: $str` — raw JSON file contents.

**Returns:** `$content!$storeerr` — the parsed content, or `$storeerr` if the
JSON cannot be decoded.

**Logic:**

1. `json.dec(src)!$storeerr` — propagate decode failure as `$storeerr`.
2. Initialise a mutable `meta` map.
3. Read `slug`/`type`/`title` with `json.str(doc;key)`, each matched
   `{$ok:v v;$err:e <default>}` with defaults `""`, `"page"`, `""`.
4. For each of `slug`/`type`/`title`, if its string length `>0`, record it in
   `meta` under the same key name.
5. Return `$content{slug;type:ctype;title:ctitle;meta;body:""}` (JSON content
   carries no body).

**Error handling:** Only `json.dec` raises `$storeerr`. Key reads are total
(fall back to defaults).

### `storetryparsejson(src: $str): $content`

**Purpose:** Infallible wrapper over `storeparsejson`.

**Parameters:** `src: $str` — raw JSON file contents.

**Returns:** `$content` — parsed content, or `storedefault()` on decode error.

**Logic:** `mt storeparsejson(src) {$ok:c c;$err:e storedefault()}`.

### `storesqlcreate(modelname: $str; fields: @($str:$str)): $str`

**Purpose:** Build the SQLite `CREATE TABLE` DDL for a content type.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `modelname` | `$str` | Table name. |
| `fields` | `@($str:$str)` | Field-name → field-type map (model schema). |

**Returns:** `$str` — a `CREATE TABLE IF NOT EXISTS <modelname>(...)` statement
with the base columns `id INTEGER PRIMARY KEY`, `slug TEXT UNIQUE`,
`body TEXT`.

**Logic:** Concatenate `"CREATE TABLE IF NOT EXISTS "`, `modelname`, and the
base column list `"(id INTEGER PRIMARY KEY;slug TEXT UNIQUE;body TEXT)"`.

**Error handling:** None.

**Workaround (Track B — see Notes):** The reference also appended one column
per `fields` entry (`bool`/`int` → `INTEGER`, else `TEXT`) by iterating
`fields.keys`. Map key enumeration (`map.keys`) is not implemented in the
current compiler/stdlib, so that loop crashes. This build emits only the base
columns; `fields` is accepted (signature preserved) but unused until the gap is
closed.

### `storeallsql(contenttype: $str): @$content!$storeerr`

**Purpose:** Load all rows of a content type from the SQLite backend.

**Parameters:** `contenttype: $str` — the table name to select from.

**Returns:** `@$content!$storeerr` — array of content rows, or `$storeerr` on a
DB error.

**Logic:**

1. Build `"SELECT id,slug,title,type,body FROM " + contenttype` via
   `str.concat`.
2. `db.many(sql;@())!$storeerr` — run the query (empty parameter array),
   propagating DB errors.
3. For each returned `Row` (index `0` to `rows.len-1`): read `slug`, `type`,
   `title`, `body` with `row.str(r;key)`, each matched `{$ok:s s;$err:e
   <default>}` (defaults `""`, `"page"`, `""`, `""`). Build a fresh `meta` map,
   recording `slug`/`type`/`title` when non-empty. Append
   `$content{slug;type:ctype;title:ctitle;meta;body}` to the results.
4. Return the results array.

**Error handling:** `db.many` raises `$storeerr`; per-column reads are total.

### `storewrite(contenttype: $str; content: $content): bool!$storeerr`

**Purpose:** Upsert one `$content` into a SQLite table — UPDATE when a row with
the same slug exists, otherwise INSERT.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `contenttype` | `$str` | Target table name. |
| `content` | `$content` | The content to persist. |

**Returns:** `bool!$storeerr` — `true` on success, `$storeerr` on DB error.

**Logic:**

1. Build `"SELECT id FROM " + contenttype + " WHERE slug=?"` (two `str.concat`
   steps; the second rebinds `check`).
2. Run `db.one(check;@(content.slug))` and match it `{$ok:r true;$err:e false}`
   into `found` — a returned row means the slug exists.
3. If `found`: build `"UPDATE <ct> SET title=?,type=?,body=? WHERE slug=?"`,
   run `db.exec(sql;@(title;type;body;slug))!$storeerr`, return `true`.
4. Else: build `"INSERT INTO <ct>(slug,title,type,body) VALUES(?,?,?,?)"`, run
   `db.exec(sql;@(slug;title;type;body))!$storeerr`, return `true`.

**Error handling:** `db.exec` raises `$storeerr`. The existence probe absorbs
the not-found error into `found=false`.

### `storeallflat(contentdir: $str; contenttype: $str): @$content!$storeerr`

**Purpose:** Load all content of a type from the flat-file backend by reading
every `.md`/`.json` file under `<contentdir>/<contenttype>`.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `contentdir` | `$str` | Root content directory. |
| `contenttype` | `$str` | Sub-directory (content type) to list. |

**Returns:** `@$content!$storeerr` — parsed content, or `$storeerr` if the
directory listing fails.

**Logic:**

1. `dir = path.join(contentdir;contenttype)`.
2. `file.listall(dir)!$storeerr` — list files, propagating listing failure.
3. For each file (index `0` to `files.len-1`):
   - If it ends with `".md"`: read `path.join(dir;fpath)` matched
     `{$ok:s s;$err:e ""}`; if the source length `>0`, append
     `storetryparse(src)`.
   - Else if it ends with `".json"`: read it the same way; if non-empty,
     append `storetryparsejson(src)`.
   - Otherwise skip.
4. Return the results array.

**Error handling:** Only `file.listall` raises `$storeerr`; individual file
reads absorb errors to `""` (skipped).

### `storeall(contentdir: $str; contenttype: $str; backend: $str): @$content!$storeerr`

**Purpose:** Backend-dispatching loader.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `contentdir` | `$str` | Root content directory (flat backend). |
| `contenttype` | `$str` | Content type / table name. |
| `backend` | `$str` | `"sqlite"` or anything else (flat). |

**Returns:** `@$content!$storeerr` — the loaded content.

**Logic:** If `backend = "sqlite"` return `storeallsql(contenttype)!$storeerr`;
otherwise return `storeallflat(contentdir;contenttype)!$storeerr`.

**Error handling:** Propagates the chosen backend's `$storeerr`.

### `storeslug(col: @$content; slug: $str): $content!$storeerr`

**Purpose:** Find the first content in `col` whose `slug` equals `slug`.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `col` | `@$content` | Content collection to search. |
| `slug` | `$str` | Slug to match. |

**Returns:** `$content!$storeerr` — the matching content, or a `$storeerr` when
none matches.

**Logic:** Loop `i` from `0` to `col.len-1`; for each `item=col.get(i)`, if
`item.slug = slug` short-return `item`. If the loop completes with no match,
evaluate `(file.listall("")!$storeerr)` — listing the empty path fails, so the
`!` operator returns the `$storeerr` "not found" result.

**Error handling:** The not-found path deliberately produces a `$storeerr` by
propagating a guaranteed `file.listall("")` failure (the reference's idiom).

### `storefind(col: @$content; key: $str; val: $str): $content!$storeerr`

**Purpose:** Intended to find the first content whose `meta[key]` equals `val`.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `col` | `@$content` | Content collection to search. |
| `key` | `$str` | Meta key to compare. |
| `val` | `$str` | Required value. |

**Returns:** `$content!$storeerr` — in this build it always returns the
not-found `$storeerr`.

**Logic:** Evaluate `(file.listall("")!$storeerr)` directly, propagating the
guaranteed failure as the not-found `$storeerr`.

**Workaround (Track B — see Notes):** The reference looped over `col` and read
`item.meta.get(key)` to compare against `val`. Reading a map stored in a struct
field is a compiler bug: the field access is mis-typed as array indexing
(`tk_array_get_w` / "cannot index into 'map'"), which crashes at runtime. Until
that is fixed, `storefind` cannot read `$content.meta`, so it returns the
not-found error rather than crashing. The signature is preserved for callers.

## Control Flow

There is no `main`; this is a library module. The flat path is the primary
entry: `storeall(..."flat")` → `storeallflat` → `file.listall` + per-file
`storetryparse`/`storetryparsejson`, which wrap the fallible
`storeparsefront`/`storeparsejson`. The SQLite path is `storeall(..."sqlite")`
→ `storeallsql`, with `storewrite` for upserts and `storesqlcreate` for DDL.
`storeslug`/`storefind` are post-load lookups over an already-loaded
collection. `storedefault` is the shared total fallback for the `try*`
wrappers.

## Notes

- **Canonical result form.** All match arms use the spec-canonical `$ok`/`$err`
  variant names. The previous source mixed non-canonical `Ok`/`Err` with
  `$ok`/`$err`; this rebuild is uniformly `$ok`/`$err`.
- **Map values returned by `map.get` are raw, not results.** For a map *local*
  or *parameter*, `m.get(k)` lowers to `tk_map_get` and yields the stored value
  directly (no `$ok`/`$err` wrapper). The reference matched these with
  `mt ...{$ok..;$err..}`, which mis-reads the raw value as a tagged union and
  crashes. `storesqlcreate` no longer does this.
- **Track B — `map.keys` not implemented.** The compiler emits no accessor for
  map key enumeration (the `tk_map_keys_w` glue exists but is never wired), so
  iterating `fields.keys` crashes. `storesqlcreate` therefore emits only the
  base columns. (Track B: expose `map.keys`.)
- **Track B — struct-field map reads are broken.** Accessing a map that lives
  in a struct field via `.get` is mis-compiled as array indexing
  (type error "cannot index into 'map'" / `tk_array_get_w` at runtime,
  segfault). This blocks any read of `$content.meta`, so `storefind` is reduced
  to the not-found path. (Track B: treat struct-field maps as maps in `.get`.)
  Building/storing non-empty `meta` is unaffected; only reading it back out of
  a `$content` is broken.
- **Not-found is signalled via `file.listall("")`.** `storeslug`/`storefind`
  reproduce the reference idiom of forcing a `$storeerr` by propagating a
  guaranteed `file.listall("")` failure — preserved for behavioural parity.
- **Build harness.** ooke `.tki` interface files are gitignored, so a fresh
  worktree has none and cross-module imports fail until each `src/*.tk` is run
  through `tkc --emit-interface --out <mod>` (matching `scripts/testmod.sh`'s
  module-compile step). Regenerate them before linking.
