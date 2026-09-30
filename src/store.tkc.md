---
source_file: "store.tk"
source_hash: "6a79c45f1d25a30dd7659f20817cba9f54b145310c613e57a5c538911aeb7ae3"
compiler_version: "3.0.0"
generated_at: "2026-10-01T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.store`

The ooke content store. Parses Markdown-with-front-matter and JSON content
files into a flat `$content` record, builds SQLite DDL, and reads/writes
content from either a flat-file backend (one file per item) or a SQLite
backend. The build and serve pipelines read content through `storeallflat`.
Table and column names spliced into SQL are checked as identifiers first
(story 121.25).

**Imports:**
- `std.file` (alias `file`) — read content files, test for and list directories.
- `std.str` (alias `str`) — string slicing, splitting, trimming, prefix/suffix
  tests, indexof, contains, eq, concatenation and join.
- `std.path` (alias `path`) — join content-directory and content-type
  segments; `path.stem` for the slug fallback.
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
6. For each line (index `0` to `lines.len-1`): trim it and split it on
   `":"`. A line with fewer than two pieces (no `":"` at all -- e.g. a blank
   line) is skipped. Otherwise `k` is the trimmed first piece and `v` the
   trimmed remainder: the other pieces re-joined with `":"`, so a value may
   itself hold colons (`url: https://x.io`, `time: 12:30`). If `k` equals
   `"slug"` / `"type"` / `"title"` assign the corresponding mutable; in all
   cases `meta=meta.set(k;v)`. (Story 121.66: the guard was `!kv.len<2`,
   i.e. `(!kv.len)<2`, always true, so a blank line read past the split and
   died with RT003; and only the second piece was kept, truncating values.)
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


### `storeident(name: $str): $str!$storeerr`

**Purpose:** Check that `name` is a SQL identifier before it is spliced into
SQL text (story 121.25, audit OOK-04). SQLite cannot bind an identifier, so
table and column names go into the statement as text, and nothing checked
them: `storesqlcreate("posts(id);DROP TABLE users;--";...)` returned exactly
that text inside a CREATE. The names come from `models/*.toml` and the content
directory today, not from a request, so this is defence in depth.

**Parameters:** `name: $str` — the proposed table or column name.

**Returns:** `$str!$storeerr` — `name` unchanged when it matches
`[A-Za-z_][A-Za-z0-9_]*` (the rule ADR-0011 gives the planned std `db.ident`,
which does not exist yet — toke 124.5); otherwise `$storeerr`.

**Logic:**

1. If `str.len(name)==0`, return `$storeerr{msg:"empty SQL identifier"}`.
2. For each byte position `i`, slice one character `c` (a failed slice reads
   `""`). It is alphabetic when it is one byte long and in
   `A-Za-z_`; a digit when it is one byte long and in `0-9`. If it is neither
   alphabetic nor (`i>0` and a digit), return
   `$storeerr{msg:"not a SQL identifier (want [A-Za-z_][A-Za-z0-9_]*): \"<name>\""}`.
3. Return `name`.

**Error handling:** Returns `$storeerr` for an empty name or any disallowed
byte (including every non-ASCII byte).

### `storesqlcreate(modelname: $str; fields: @($str:$str)): $str!$storeerr`

**Purpose:** Build the SQLite `CREATE TABLE` DDL for a content type.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `modelname` | `$str` | Table name. |
| `fields` | `@($str:$str)` | Field-name → field-type map (model schema). |

**Returns:** `$str!$storeerr` — a
`CREATE TABLE IF NOT EXISTS <modelname>(id INTEGER PRIMARY KEY,slug TEXT UNIQUE,body TEXT,<col> <type>...)`
statement, or `$storeerr` when the table name or a field name is not an
identifier.

**Logic:**

1. Start with `"CREATE TABLE IF NOT EXISTS "` and append
   `storeident(modelname)!$storeerr`.
2. Append `"(id INTEGER PRIMARY KEY,slug TEXT UNIQUE,body TEXT"`.
3. For each key `k` of `fields.keys()` (map order): `ft=fields.get(k)`; the
   column type is `INTEGER` when `ft` is `"bool"` or `"int"`, else `TEXT`;
   append `"," + storeident(k)!$storeerr + " " + coltype`.
4. Append `")"` and return.

**Error handling:** Only `storeident` fails the function, for the table name
or any field name.

### `storeallsql(contenttype: $str): @$content!$storeerr`

**Purpose:** Load all rows of a content type from the SQLite backend.

**Parameters:** `contenttype: $str` — the table name to select from.

**Returns:** `@$content!$storeerr` — array of content rows, or `$storeerr` on a
bad table name or a DB error.

**Logic:**

1. Build `"SELECT id,slug,title,type,body FROM " + storeident(contenttype)!$storeerr`.
2. `db.many(sql;@())!$storeerr` — run the query (no parameters) on the
   database the caller has opened.
3. For each returned row: read `slug`, `type`, `title`, `body` with
   `row.str(r;key)`, each matched `{$ok:s s;$err:e <default>}` (defaults `""`,
   `"page"`, `""`, `""`). Build a fresh `meta` map recording
   `slug`/`type`/`title` when non-empty. Append
   `$content{slug;type:ctype;title:ctitle;meta;body}`.
4. Return the results array.

**Error handling:** `storeident` and `db.many` raise `$storeerr`; per-column
reads are total.

### `storewrite(contenttype: $str; content: $content): bool!$storeerr`

**Purpose:** Upsert one `$content` into a SQLite table — UPDATE when a row with
the same slug exists, otherwise INSERT.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `contenttype` | `$str` | Target table name. |
| `content` | `$content` | The content to persist. |

**Returns:** `bool!$storeerr` — `true` on success, `$storeerr` on a bad table
name or a DB error.

**Logic:**

1. `table = storeident(contenttype)!$storeerr`.
2. Build `"SELECT COUNT(*) AS n FROM " + table + " WHERE slug=?"`.
3. Run `db.one(check;@(content.slug))!$storeerr` -- a COUNT always returns
   one row, so any failure here is a real error and is propagated. Read
   column `n` with `row.str`; an unreadable `n` is a `$storeerr`. `found` is
   `n != "0"`. (Story 121.66: this was `SELECT id` matched
   `{$ok:r true;$err:e false}`, so every failure read as not-found and the
   write became an INSERT -- a duplicate row on a table without `id`.)
4. If `found`: `db.exec("UPDATE <table> SET title=?,type=?,body=? WHERE slug=?";
   @(title;type;body;slug))!$storeerr`, return `true`.
5. Else: `db.exec("INSERT INTO <table>(slug,title,type,body) VALUES(?,?,?,?)";
   @(slug;title;type;body))!$storeerr`, return `true`.

**Error handling:** `storeident`, the existence check and `db.exec` raise
`$storeerr`. "No row with this slug" is a count of 0, not an error.
Values are bound as parameters; only the table name is spliced.

### `storeallflat(contentdir: $str; contenttype: $str): @$content!$storeerr`

**Purpose:** Load all content of a type from the flat-file backend by reading
every `.md`/`.json` file under `<contentdir>/<contenttype>`.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `contentdir` | `$str` | Root content directory. |
| `contenttype` | `$str` | Sub-directory (content type) to list. |

**Returns:** `@$content!$storeerr` — parsed content, or `$storeerr` if the
directory is missing or cannot be listed.

**Logic:**

1. `dir = path.join(contentdir;contenttype)`.
2. If `!file.isdir(dir)`, return `$storeerr{msg:"no content dir: <dir>"}`
   (story 134.8: a failed stdlib call under `!` returned a null array that
   crashed the caller on `.len`, so the missing directory is checked first).
3. `files = file.listall(dir)!$storeerr`.
4. For each file path `fpath`:
   - Ending `".md"`: read `path.join(dir;fpath)` matched `{$ok:s s;$err:e ""}`;
     if non-empty, `parsed = storetryparse(src)`, and append it with its slug
     replaced by `path.stem(fpath)` when the front matter gave none.
   - Else ending `".json"`: read it the same way; if non-empty, append
     `storetryparsejson(src)` (no slug fallback).
   - Otherwise skip.
5. Return the results array.

**Error handling:** A missing directory and a failed listing raise
`$storeerr`; an unreadable or empty file is skipped.

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

**Returns:** `$content!$storeerr` — the first match, or
`$storeerr{msg:"no content with slug: <slug>"}`.

**Logic:** Loop over `col`; return the first `item` with `item.slug==slug`.
After the loop, return the not-found error.

**Error handling:** Not-found is an explicit `$storeerr` (story 127.127; see
Notes).

### `storefind(col: @$content; key: $str; val: $str): $content!$storeerr`

**Purpose:** Find the first content whose `meta[key]` equals `val`.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `col` | `@$content` | Content collection to search. |
| `key` | `$str` | Meta key to compare. |
| `val` | `$str` | Required value. |

**Returns:** `$content!$storeerr` — the first match, or
`$storeerr{msg:"no content with <key> = <val>"}`.

**Logic:** Loop over `col`; for each `item`, `mv = item.meta.get(key)` (the
raw value, not a result) and return `item` when `str.eq(mv;val)`. After the
loop, return the not-found error.

**Error handling:** Not-found is an explicit `$storeerr` (story 127.127).

## Control Flow

There is no `main`; this is a library module. The flat path is the primary
entry: `storeall(..."flat")` → `storeallflat` → `file.listall` + per-file
`storetryparse`/`storetryparsejson`, which wrap the fallible
`storeparsefront`/`storeparsejson`. The SQLite path is `storeall(..."sqlite")`
→ `storeallsql`, with `storewrite` for upserts and `storesqlcreate` for DDL.
The SQLite functions are library pieces only: they query whatever database the
caller has already opened with `db.open`, and nothing in ooke opens one, creates
the tables or copies flat files in. ooke's own build and serve paths call
`storeallflat` directly, and there is no configuration key that selects the SQLite
path (`[store].backend` was parsed and then ignored; removed by story 134.34).
`storeslug`/`storefind` are post-load lookups over an already-loaded
collection. `storedefault` is the shared total fallback for the `try*`
wrappers.

## Notes

- **Canonical result form.** All match arms use `$ok`/`$err`.
- **Map values returned by `map.get` are raw, not results.** `m.get(k)` yields
  the stored value directly; `storesqlcreate` and `storefind` use it as such.
  (An earlier build matched it with `$ok`/`$err` arms and crashed.)
- **Identifiers are checked, values are bound** (story 121.25). Every table
  and column name reaching SQL text passes `storeident`; every value goes
  through a `?` parameter.
- **Not-found is an explicit `$storeerr`.** `storeslug`/`storefind` used to
  force the error by propagating `file.listall("")`, on the assumption that it
  always fails. It does not always fail, and then the function fell off its end
  and returned a null `$content` (story 127.127; toke now rejects the shape as
  E4071).
- **Earlier workarounds are gone.** Previous revisions of this companion
  described `storesqlcreate` emitting only the base columns (no `map.keys`)
  and `storefind` always returning not-found (struct-field map reads
  mis-compiled). The current source iterates `fields.keys()` and reads
  `item.meta.get(key)` directly.
