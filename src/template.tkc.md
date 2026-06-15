---
source_file: "template.tk"
source_hash: "56111dcadc157aad3ce284f75f208cb8c9768326411cc73756beed06316897b5"
compiler_version: "0.3.9"
generated_at: "2026-06-15T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.template`

The ooke `.tkt` template engine. It lexes template source into a token stream,
resolves `{= expr =}` expressions (with an optional `| filter` pipe), executes
`{! directive !}` directives (layout, block/end, var, yield, partial, island),
strips `{# comment #}` regions, and renders the result to an HTML string. It also
provides a simple per-path token cache so repeated renders of the same template
skip re-lexing.

**Imports:**
- `std.file` (alias `file`) — read template, layout, and partial files from disk.
- `std.str` (alias `str`) — string scanning/slicing (`indexof`, `slice`, `trim`,
  `len`, `replace`, `concat`, `upper`, `lower`).
- `std.path` (alias `path`) — join the templates dir with a layout/partial name.
- `std.md` (alias `md`) — Markdown rendering for the `md` filter.

## Types

### `$tokenkind`

A one-hot flag set classifying a lexed token. Exactly one field is `true` per
token.

| Field | Type | Description |
|-------|------|-------------|
| `raw` | `bool` | Literal passthrough text. |
| `expr` | `bool` | A `{= … =}` expression. |
| `directive` | `bool` | A `{! … !}` directive. |
| `comment` | `bool` | A `{# … #}` comment. |

### `$token`

A single lexed template token.

| Field | Type | Description |
|-------|------|-------------|
| `kind` | `$tokenkind` | The token classification. |
| `content` | `$str` | For `raw`, the literal text; otherwise the inner text between the delimiters (delimiters stripped). |

### `$tplerr`

Error type for fallible template operations.

| Field | Type | Description |
|-------|------|-------------|
| `msg` | `$str` | Human-readable failure description. |

### `$block`

A named content block collected from a child template for layout inheritance.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `$str` | Block name (the directive argument). |
| `content` | `$str` | Rendered block body. |

### `$tplcache`

A per-path cache of already-lexed token streams.

| Field | Type | Description |
|-------|------|-------------|
| `entries` | `@($str:@$token)` | Map from template path to its lexed token array. |

### `$renderresult`

The result of a cached render: the output plus the (possibly updated) cache.

| Field | Type | Description |
|-------|------|-------------|
| `output` | `$str` | The rendered HTML string. |
| `cache` | `$tplcache` | The cache after inserting this template's tokens. |

## Functions

### `tplescape(s: $str): $str`

**Purpose:** HTML-escape a string.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `s` | `$str` | Raw text to escape. |

**Returns:** `$str` — the escaped text.

**Logic:** Apply `str.replace` in order: `&`→`&amp;`, `<`→`&lt;`, `>`→`&gt;`,
`"`→`&quot;`, `'`→`&#39;` (ampersand first so later entities are not
double-escaped). Return the final string.

**Error handling:** None.

### `tplapplyfilter(val: $str; filtername: $str): $str`

**Purpose:** Apply a named expression filter to a value.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `val` | `$str` | The value to transform. |
| `filtername` | `$str` | Filter name (leading/trailing whitespace is trimmed). |

**Returns:** `$str` — the filtered value.

**Logic:** Trim `filtername`. Dispatch via a nested `if`/`el` chain: `md` →
`md.render(val)`; `escape` → `tplescape(val)`; `upper` → `str.upper(val)`;
`lower` → `str.lower(val)`; `trim` → `str.trim(val)`. Any other (or empty) name
returns `val` unchanged.

**Error handling:** None. Unknown filters are a no-op.

### `tplresolveexpr(expr: $str; ctx: @($str:$str)): $str`

**Purpose:** Resolve a `{= … =}` expression body against the context map,
applying an optional `| filter`.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `expr` | `$str` | The raw inner expression text. |
| `ctx` | `@($str:$str)` | Variable name → value map. |

**Returns:** `$str` — the resolved (and optionally filtered) value, or `""` if
the key is absent.

**Logic:**

1. Trim the expression.
2. Find the first `|` with `str.indexof`.
3. If a pipe is present (`indexof >= 0`): the key is the trimmed slice before the
   pipe (slice matched `{$ok:v v;$err:e trimmed}`); the filter name is the
   trimmed slice after the pipe (matched `{$ok:v v;$err:e ""}`). Bind the
   context lookup to `vgot=ctx.get(key)`, take its value with
   `mt vgot {$ok:v v;$err:e ""}`, then return `tplapplyfilter(val;filter)`.
4. Otherwise bind `vgot2=ctx.get(trimmed)` and return
   `mt vgot2 {$ok:v v;$err:e ""}`.

**Error handling:** Total — a missing key resolves to `""`.

### `tpllex(src: $str): @$token!$tplerr`

**Purpose:** Lex template source into a `@$token` stream.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `src` | `$str` | Template source. |

**Returns:** `@$token!$tplerr` — the token array. (The error arm is declared for
signature compatibility; this implementation never raises.)

**Logic:**

1. Initialise mutable `tokens=@()` and mutable `remaining=src`. Precompute the
   four `$tokenkind` flag records (`rawkind`, `exprkind`, `dirkind`, `cmtkind`).
2. Loop with mutable `running=true` (counter `ii` from `0`, unused for control):
   a. Let `rem=remaining`, `rlen=str.len(rem)`. If `rlen=0`, set `running=false`.
   b. Otherwise find the earliest of `{=`, `{!`, `{#` via `str.indexof`
      (`posexpr`, `posdir`, `poscmt`). Track the smallest non-negative position
      in mutable `bestpos` (init `-1`) and the matching `besttype` (`"expr"`,
      `"dir"`, or `"cmt"`).
   c. If no delimiter found (`bestpos<0`): append a `raw` token with the whole
      `rem`, clear `remaining`, stop.
   d. Otherwise: if `bestpos>0`, append a `raw` token for the text before the
      delimiter. Compute `afteropen` = slice from `bestpos+2`. Pick the matching
      close delimiter (`=}`, `!}`, or `#}`). Find it via `str.indexof`.
      - If the close is missing (`closepos<0`): append a `raw` token for the
        remaining text, clear `remaining`, stop (unterminated tag is treated as
        literal).
      - Otherwise slice the `inner` content `[0,closepos)` and `afterclose`
        `[closepos+2,end)`. Append a token of the corresponding kind (`expr`,
        `dir`, or `cmt`) carrying `inner`, then set `remaining=afterclose`.
3. Return `tokens`.

All `str.slice` results are matched `{$ok:v v;$err:e ""}`.

**Error handling:** Total in practice; malformed/unterminated tags degrade to raw
text rather than erroring.

### `tpldirectivename(content: $str): $str`

**Purpose:** Extract the directive name (the part before `(`).

**Parameters:** `content: $str` — the directive inner text.

**Returns:** `$str` — the trimmed name, or the whole trimmed content if there is
no `(`.

**Logic:** Trim. Find `(` with `str.indexof`. If present, return the slice
`[0,paren)` (matched `{$ok:v v;$err:e trimmed}`); else return the trimmed text.

**Error handling:** None.

### `tpldirectivearg(content: $str): $str`

**Purpose:** Extract a directive's single parenthesised argument, unquoting a
double-quoted string.

**Parameters:** `content: $str` — the directive inner text.

**Returns:** `$str` — the argument, or `""` if absent/malformed.

**Logic:** Trim. Find `(`; if absent return `""`. Slice after `(` to get
`afteropen`; find `)`; if absent return `""`. Slice the raw arg `[0,close)`,
trim it to `t`, let `tlen=str.len(t)`. If `tlen>1`, take the first and last
characters; if both are `"`, return the inner `[1,tlen-1)` (matched
`{$ok:v v;$err:e t}`), else return `t`. If `tlen<=1`, return `t`. All slices
matched `{$ok:v v;$err:e ""}` (or the noted fallback).

**Error handling:** None; malformed args yield `""`.

### `tplfindblock(blocks: @$block; name: $str): $str`

**Purpose:** Find a collected block's content by name.

**Parameters:** `blocks: @$block`; `name: $str`.

**Returns:** `$str` — the matching block's `content`, or `""` if not found.

**Logic:** Loop `i` from `0` to `blocks.len`; if `blocks.get(i).name = name`
return its `content`. After the loop, return `""`.

**Error handling:** None.

### `tplislandparse(content: $str): @($str:$str)`

**Purpose:** Parse an `island("name" hydrate="…")` directive into a
`{name, hydrate}` map.

**Parameters:** `content: $str` — the directive inner text.

**Returns:** `@($str:$str)` — keys `"name"` and `"hydrate"`. Defaults are
`name=""` and `hydrate="load"`.

**Logic:** Trim. Find `(`; if absent return the default map. Slice after `(` to
`afteropen`, find `)`, slice `inner` `[0,close)`. Find the first `"` (`q1`); if
absent return defaults. Slice after `q1` to `afterq1`, find the next `"` (`q2`);
if absent return defaults. `iname` is the slice `[0,q2)` of `afterq1`; `rest` is
the slice after `q2`. Search `rest` for `hydrate="`; if absent return
`{name:iname, hydrate:"load"}`. Otherwise slice after the `hydrate="` match
(offset `+9`), find the closing `"`; if absent return `{name:iname,
hydrate:"load"}`, else `hval` is the slice up to that quote and return
`{name:iname, hydrate:hval}`. All slices matched `{$ok:v v;$err:e <fallback>}`.

**Error handling:** None; malformed input degrades to defaults.

### `tplrender(tokens: @$token; ctx: @($str:$str); templatesdir: $str; blocks: @$block): $str!$tplerr`

**Purpose:** Render a token stream to an HTML string, handling expressions,
directives, layout inheritance, partials, and islands.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `tokens` | `@$token` | The lexed tokens to render. |
| `ctx` | `@($str:$str)` | Variable context. |
| `templatesdir` | `$str` | Directory used to resolve layout/partial paths. |
| `blocks` | `@$block` | Blocks supplied by a child template (used by `yield` when rendering a layout). |

**Returns:** `$str!$tplerr` — rendered output, or `$tplerr` if a referenced
layout/partial file or its lex/render fails.

**Logic:**

1. Mutable state: `buf=""` (main output), `hasislands=false`, `inblock=false`,
   `currentblockname=""`, `currentblockbuf=""`, `collectedblocks=@()`,
   `layoutname=""`.
2. Loop `i` over `tokens`:
   - `raw` token: append `tok.content` to `currentblockbuf` if `inblock` else to
     `buf`.
   - `expr` token: `val=tplresolveexpr(tok.content;ctx)`; append to the block
     buffer or `buf` per `inblock`.
   - `comment` token: ignored (no branch body).
   - `directive` token: compute `dname=tpldirectivename` and
     `darg=tpldirectivearg`, then dispatch:
     - `layout`: set `layoutname=darg`.
     - `block`: set `inblock=true`, `currentblockname=darg`,
       `currentblockbuf=""`.
     - `end`: if `inblock`, append a `$block{name:currentblockname;
       content:currentblockbuf}` to `collectedblocks` and reset block state.
     - `var`: bind `vargot=ctx.get(darg)`, take `varval` via
       `mt vargot {$ok:v v;$err:e ""}`, append per `inblock`.
     - `yield`: `blockcontent=tplfindblock(blocks;darg)`; if non-empty append to
       `buf`.
     - `partial`: `partialpath=path.join(templatesdir; darg+".tkt")`; bind
       `psrcr=file.read(partialpath)`, take `partialsrc` via
       `mt psrcr {$ok:s s;$err:e ""}`; if non-empty, lex it (`!$tplerr`),
       recursively `tplrender(...;@())` (`!$tplerr`), append per `inblock`.
     - `island`: `iparse=tplislandparse(tok.content)`; bind
       `inameg=iparse.get("name")` / `ihydrateg=iparse.get("hydrate")` and read
       them via `mt … {$ok:v v;$err:e <"" / "load">}`; build
       `<div data-island="NAME" data-hydrate="HYDRATE"></div>` with nested
       `str.concat`, append per `inblock`, and set `hasislands=true`.
     - Any other directive name: no-op.
3. After the loop, `islandscript` =
   `<script src="/static/ooke-islands.js" defer></script>`.
4. If `layoutname` is non-empty: read the layout file
   (`path.join(templatesdir; layoutname+".tkt")`, `!$tplerr`), lex it
   (`!$tplerr`), and render it passing `collectedblocks` as the blocks
   (`!$tplerr`). Return that output, appending `islandscript` if `hasislands`.
5. Otherwise return `buf`, appending `islandscript` if `hasislands`.

**Error handling:** Layout reading/lexing/rendering propagate `$tplerr` via `!`.
Partial reads are total (missing partial → empty). Context lookups are total.

### `tplrenderfile(templatepath: $str; ctx: @($str:$str); templatesdir: $str): $str!$tplerr`

**Purpose:** Read a template file, lex it, and render it.

**Parameters:** `templatepath` (file to read); `ctx`; `templatesdir`.

**Returns:** `$str!$tplerr`.

**Logic:** `src=file.read(templatepath)!$tplerr`; `tokens=tpllex(src)!$tplerr`;
return `tplrender(tokens;ctx;templatesdir;@())!$tplerr`.

**Error handling:** File read, lex, and render failures propagate via `!`.

### `tplcachenew(): $tplcache`

**Purpose:** Construct an empty template cache.

**Parameters:** None.

**Returns:** `$tplcache` — `entries` is an empty map of the cache's element type,
written as the literal `@($str:@($token))` (an empty `$str`→`@$token` map).

**Logic:** Return `$tplcache{entries:@($str:@($token))}`.

**Error handling:** None.

### `tplcacheget(cache: $tplcache; path: $str): @$token!$tplerr`

**Purpose:** Return the cached token stream for `path`, lexing the file on a
miss.

**Parameters:** `cache: $tplcache`; `path: $str`.

**Returns:** `@$token!$tplerr`.

**Logic:** `r=cache.entries.get(path)`; `hit=mt r {$ok:toks true;$err:e false}`.
If `hit`, return the cached tokens via `mt r {$ok:toks toks;$err:e @()}`.
Otherwise read the file (`!$tplerr`) and lex it (`!$tplerr`).

**Error handling:** On a miss, file read/lex failures propagate via `!`.

### `tplrenderfilecached(templatepath: $str; ctx: @($str:$str); templatesdir: $str; cache: $tplcache): $renderresult!$tplerr`

**Purpose:** Render a template using a token cache, returning both the output and
the updated cache.

**Parameters:** `templatepath`; `ctx`; `templatesdir`; `cache`.

**Returns:** `$renderresult!$tplerr`.

**Logic:** `r=cache.entries.get(templatepath)`;
`hit=mt r {$ok:toks true;$err:e false}`. Mutable `tokens=@()`. If `hit`, set
`tokens` from the cache via `mt r {$ok:toks toks;$err:e @()}`; else read the file
(`!$tplerr`) and lex (`!$tplerr`). Compute
`newentries=cache.entries.set(templatepath;tokens)`,
`newcache=$tplcache{entries:newentries}`,
`out=tplrender(tokens;ctx;templatesdir;@())!$tplerr`, and return
`$renderresult{output:out;cache:newcache}`.

**Error handling:** File read, lex, and render failures propagate via `!`.

## Control Flow

There is no module entry point; this is a library. The typical pipeline is
`tplrenderfile` (or `tplrenderfilecached`): read → `tpllex` → `tplrender`.
`tplrender` is the engine. It is recursive: a `partial` directive re-enters
`tplrender` for the included template, and a `layout` directive re-enters
`tplrender` for the parent layout, threading the child's `collectedblocks` so the
layout's `yield` directives (resolved through `tplfindblock`) can splice in the
child's blocks. Expression resolution flows token → `tplresolveexpr` →
(optional) `tplapplyfilter`. The cache functions wrap lexing with a
path-keyed `$tplcache` map.

## Notes

- **Canonical result form.** All match arms use the spec-canonical `$ok`/`$err`
  variant names (toke-spec-prompt.md: "Variants are `$lowercase`"). The previous
  source used the non-canonical `Ok`/`Err` (Track B 113.B.9).
- **Empty cache literal (compiler-bug workaround).** `tplcachenew` initialises
  `entries` with the empty typed-map literal `@($str:@($token))`. The previous
  source used a sentinel entry `@("__init__":@())` whose value was an *untyped*
  empty array literal (`@()`) placed into a map whose declared value type is the
  array `@$token`. That mismatch produces a corrupt map that segfaults on the
  next `.get` — a real toke codegen bug (Track B). The empty typed-map literal
  is the canonical, behaviourally-equivalent fix (the cache simply starts empty
  rather than carrying a dummy entry; callers only `.get`/`.set` real paths, so
  observable behaviour is unchanged).
- **Behaviour preserved for loke parity.** Signatures, types, directive set
  (`layout`/`block`/`end`/`var`/`yield`/`partial`/`island`), filter set
  (`md`/`escape`/`upper`/`lower`/`trim`), delimiters (`{= =}`/`{! !}`/`{# #}`),
  the island `<div>`/`<script>` emission, and the layout/partial recursion are
  all unchanged from the reference.
- **Inline `mt` over a method call.** `mt ctx.get(k) {…}` and
  `mt iparse.get(k) {…}` are bound to an intermediate `let` first (e.g.
  `let vgot=ctx.get(k); mt vgot {…}`). Writing the method call inline before the
  match `{` makes the parser read `ctx.get(k) {…}` as map indexing
  (`E4031: cannot index into 'map'`). Inline `mt` over a *free function* call
  (e.g. `mt str.slice(…) {…}`) is fine and is kept.
