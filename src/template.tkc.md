---
source_file: "template.tk"
source_hash: "2271a6f7c102de0ea6f7e990d79e1dc8bbfffe1c2e98b20110d04afb42dcce26"
compiler_version: "3.0.0"
generated_at: "2026-10-01T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.template`

The ooke `.tkt` template engine. It lexes template source into a token stream,
resolves `{= expr =}` expressions (with an optional `| filter` pipe), executes
`{! directive !}` directives (layout, block/end, var, yield, partial, island),
strips `{# comment #}` regions, and renders the result to an HTML string.

Values are escaped for the place in the HTML where they land (story 121.58), not
with one HTML-body escaper everywhere: every byte of output is fed through an
HTML context tracker (`hcfeed`, a port of toke's `src/stdlib/template.c`
tracker, 121.37) and `ctxescape` picks the escaper from the state it leaves.
Partial and layout names are confined to the templates directory (121.57),
symlinks resolved (121.59 (3)). A
missing or unreadable template, layout or partial is a `$tplerr`, logged where
it is raised (121.59, 134.24). A per-path token cache lets repeated renders of
the same template skip re-lexing.

**Imports:**
- `std.file` (alias `file`) — probe and read template, layout and partial files.
- `std.log` (alias `log`) — error-level logging of every `$tplerr` where it is
  raised (a caller cannot read `e.msg` off the payload: RT005, toke 127.78).
- `std.str` (alias `str`) — scanning, slicing, builders, case and replace.
- `std.path` (alias `path`) — join the templates dir with a layout/partial name.
- `std.md` (alias `md`) — Markdown rendering for the `md` filter.

## Types

### `$tokenkind`

A one-hot flag set classifying a lexed token. Exactly one field is `true`.

| Field | Type | Description |
|-------|------|-------------|
| `raw` | `bool` | Literal passthrough text. |
| `expr` | `bool` | A `{= … =}` expression. |
| `directive` | `bool` | A `{! … !}` directive. |
| `comment` | `bool` | A `{# … #}` comment. |

### `$token`

| Field | Type | Description |
|-------|------|-------------|
| `kind` | `$tokenkind` | The token classification. |
| `content` | `$str` | For `raw`, the literal text; otherwise the text between the delimiters. |

### `$tplerr`

| Field | Type | Description |
|-------|------|-------------|
| `msg` | `$str` | Human-readable failure description (also logged at error level). |

### `$block`

A named block collected from a child template for layout inheritance. It holds
the block's **tokens**, not rendered text (121.58), so the block is rendered —
and its values escaped — where the layout yields it.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `$str` | Block name (the directive argument). |
| `toks` | `@$token` | The block's tokens. |

### `$hc`

HTML context tracker state; every field is an `i64` code except the two names.

| Field | Description |
|-------|-------------|
| `st` | Tokenizer state: 0 text, 1 tagopen, 2 endtagopen, 3 tagname, 4 intag, 5 attrname, 6 afterattrname, 7 beforevalue, 8 value, 9 markup (`<!`/`<?`), 10 comment, 11 rawtext. |
| `closing` | 1 inside an end tag. |
| `tagel` | Kind of the element being opened: 0 none, 1 script, 2 style, 3 rcdata (title, textarea). |
| `rawel` | Kind of the rawtext element currently open (same codes). |
| `rname` | Lower-case name of that rawtext element (to find its end tag). |
| `name` | Lower-case tag or attribute name being read (max 31 bytes). |
| `nover` | 1 when `name` overflowed 31 bytes. |
| `ak` | Attribute kind: 0 normal, 1 url, 2 js (`on*`), 3 css (`style`). |
| `quote` | The value's quote byte (34 or 39), or 0 when unquoted. |
| `vlen` | Bytes of the attribute value so far (leading spaces not counted). |
| `urlpart` | 1 once a URL value has passed `?` or `#`. |
| `js` | JS sub-state: 0 code, 1 `"…"`, 2 `'…'`, 3 `` `…` ``, 4 `//`, 5 `/* */`. |
| `css` | CSS sub-state: 0 code, 1 `"…"`, 2 `'…'`, 3 `/* */`. |
| `esc` | 1 after a backslash in a JS/CSS string. |
| `slash` | 1 after a `/` (possible comment start). |
| `star` | 1 after a `*` in a block comment. |
| `dashes` | Consecutive `-` in an HTML comment. |
| `mcount` | Bytes read of a `<!` markup opener (to recognise `<!--`). |
| `endlen` | Bytes matched of `</rname` in rawtext. |

### `$rout`

One render's output, the tracker state after it, and whether it held an island.

| Field | Type | Description |
|-------|------|-------------|
| `text` | `$str` | The rendered text. |
| `hc` | `$hc` | Tracker state after `text`. |
| `islands` | `bool` | An `island` directive was rendered (the islands script is appended once, at the top). |

### `$tplcache`

| Field | Type | Description |
|-------|------|-------------|
| `entries` | `@($str:@$token)` | Template path → lexed tokens. |

### `$renderresult`

| Field | Type | Description |
|-------|------|-------------|
| `output` | `$str` | The rendered HTML string. |
| `cache` | `$tplcache` | The cache after inserting this template's tokens. |

## Functions

### `tplescape(s: $str): $str`

**Purpose:** HTML-escape text (for HTML text and quoted attribute values).

**Logic:** `str.replace` in order: `&`→`&amp;`, `<`→`&lt;`, `>`→`&gt;`,
`"`→`&quot;`, `'`→`&#39;` (ampersand first so later entities are not
double-escaped). Also used by serve.tk for the empty-template fallback page
(121.61).

### HTML context tracker

#### `hcnew(): $hc`

The start state: every field `0` or `""` (text context).

#### `hcspace(c: i64): bool` / `hcalpha(c: i64): bool` / `hcalnum(c: i64): bool`

Byte classes: HTML whitespace (32, 9, 10, 13, 12); ASCII letter; letter or digit.

#### `hcpack(m: i64; e: i64; sl: i64; sr: i64): i64`

Packs a JS/CSS sub-state as `m | e<<3 | sl<<4 | sr<<5` (mode, esc, slash, star)
so the sub-machines are pure `i64 → i64` functions and `hcfeed` allocates
nothing per byte.

#### `hcjs(p: i64; c: i64): i64`

One byte of the JS sub-machine over a packed state. In code: `/` then `/` opens
a line comment (4), `/` then `*` a block comment (5); `"`, `'`, `` ` `` open a
string (1, 2, 3). In a string: a backslash sets `esc`, which the next byte
clears; the matching quote closes it, and so does a newline except in a
template literal. A line comment ends at newline; a block comment at `*/`.

#### `hccss(p: i64; c: i64): i64`

The CSS equivalent: `/*` opens a comment (3); `"` and `'` open strings (1, 2),
closed by the matching quote or a newline, with backslash escapes; a comment
ends at `*/`.

#### `hcelemkind(n: $str; over: i64): i64`

Element kind for a tag name: `script` 1, `style` 2, `title`/`textarea` 3, else
0 (always 0 when the name overflowed).

#### `hcattrkind(n: $str; over: i64): i64`

Attribute kind: a name starting `on` is 2 (JS) even when overflowed; otherwise
(0 when overflowed) `style` is 3; the URL attributes (`href`, `src`, `action`,
`formaction`, `cite`, `data`, `poster`, `background`, `codebase`, `longdesc`,
`usemap`, `manifest`, `icon`, `profile`, `classid`, `archive`, `srcset`,
`ping`, `lowsrc`, `dynsrc`, `xlink:href`, `xmlns`) and any name containing
`url` or `uri` are 1; else 0.

#### `hcfeed(h: $hc; s: $str): $hc`

**Purpose:** Feed `s` through the tracker; return the state after its last byte.

**Logic:** Copy every field into a mutable local, then for each byte `c`:

- **0 text:** `<` → 1.
- **1 tagopen:** letter → start a tag name (`closing=0`) in 3; `/` → 2; `!` or
  `?` → 9 (`mcount` 0 for `!`, 2 for `?`); `<` stays 1; else → 0.
- **2 endtagopen:** letter → tag name with `closing=1`; `>` → 0; else → 9 as a
  bogus comment.
- **3 tagname:** space or `/` → 4, recording `tagel` (0 for an end tag); `>` →
  tag end (same `tagel`); else append to the name.
- **4 intag:** space or `/` stay; `>` → tag end; else start an attribute name.
- **5 attrname:** space → 6 and `ak`; `=` → 7 and `ak`; `/` → 4; `>` → tag end;
  else append.
- **6 afterattrname:** `=` → 7; `/` → 4; `>` → tag end; other non-space → a new
  attribute name.
- **7 beforevalue:** `"`/`'` → value start with that quote; `>` → tag end; other
  non-space → value start unquoted, and the byte is a value byte.
- **8 value:** the quote (or a space, unquoted) → 4; `>` unquoted → tag end;
  else a value byte.
- **9 markup:** within the first two bytes after `<!`, `--` → 10; otherwise `>`
  → 0.
- **10 comment:** `>` after two or more dashes → 0.
- **11 rawtext:** track `</rname` case-insensitively; followed by space or `/`
  → 4 (as an end tag), by `>` → 0. This ends the element even inside a JS
  string, as HTML does. Otherwise run the byte through `hcjs` (script) or
  `hccss` (style).

Then: a new attribute name resets `name`; name bytes are appended lower-cased
up to 31 bytes, past which `nover=1`; a tag end enters 11 for an opening
script/style/title/textarea (recording `rawel` and `rname`, clearing the
sub-states) or 0 otherwise; a value start enters 8 with `vlen`, `urlpart` and
the sub-states cleared; a value byte (leading spaces skipped) increments
`vlen`, sets `urlpart` on `?` or `#` in a URL value, and runs `hcjs`/`hccss` in
a JS/CSS value. Return the rebuilt `$hc`.

**Limits (as in toke):** character references in an attribute are not decoded,
and JS regular-expression literals are not recognised. Either can only mislead
the tracker about being in a string; every JS/CSS escaper's output holds no
quote, slash, star, newline or angle bracket, so a mis-tracked value comes out
as wrong text, not code.

### Escapers

#### `hchexdigit(d: i64): $str` / `hchex2(c: i64): $str`

One upper-case hex digit; a byte as two.

#### `esckeep(mode: i64; c: i64): bool`

Which bytes pass unchanged. Letters and digits always. Mode 1 (unquoted
attribute): also bytes > 127. Mode 2 (JS string body): also > 127, space, `_`,
`,`, `.`. Mode 3 (CSS string body): also > 127 and space. Modes 4 (URL) and 5
(URL component): also `-`, `.`, `_`, `~`; mode 4 also the reserved set
`: / ? # [ ] @ ! $ & ' ( ) * + , ; = %`.

#### `escrepl(mode: i64; c: i64): $str`

The replacement for a byte: mode 1 `&#N;`; mode 2 `\u00HH`; mode 3 `\H ` (one
digit below 16) or `\HH `; modes 4 and 5 `%HH`.

#### `escbytes(s: $str; mode: i64): $str`

Escapes `s` byte by byte in one `str.builder`, copying runs of kept bytes as
slices. In mode 2 the UTF-8 line separators U+2028/U+2029 (E2 80 A8/A9) become
` `/` ` (they end a line in pre-2019 JS strings).

#### `escjs(js: i64; s: $str): $str`

In JS code (`js==0`) a value becomes a quoted literal `"` + `escbytes(s;2)` +
`"`; inside a string or comment it is `escbytes(s;2)`.

#### `esccss(css: i64; s: $str): $str`

In CSS code a value passes only if every byte is a letter, digit, > 127, space
or one of `# % . , _ -`; otherwise it becomes `ZtokeZ`. Inside a CSS string or
comment it is `escbytes(s;3)`.

#### `escurl(vlen: i64; urlpart: i64; s: $str): $str`

When the value starts the URL (`vlen==0 && urlpart==0`) the scheme is decided
here: skip leading spaces, scan to the first `: / ? #`; if that is `:` and the
lower-cased scheme is not `http`, `https` or `mailto`, return `#ZtokeZ`. Then
`escbytes(s;5)` after `?`/`#`, else `escbytes(s;4)`.

#### `escname(s: $str): $str`

A value in a tag or attribute name: allowed only if 1–31 bytes of
`[A-Za-z0-9_-]` naming a plain attribute (`hcattrkind` 0); otherwise `ZtokeZ`.

#### `ctxescape(h: $hc; v: $str): $str`

Escape one value for the context `h`:

- text, markup, comment (st 0, 9, 10): `tplescape`.
- rawtext (11): script → `escjs(h.js)`, style → `esccss(h.css)`, title/textarea
  → `tplescape`.
- inside a tag before a value (st < 7): `escname`.
- a value (7 starts one, fresh; 8 continues one): apply the attribute kind's
  escaper (`escurl`, `escjs`, `esccss`, or none), then `tplescape` when quoted
  or `escbytes(…;1)` when unquoted.

### Values

#### `tplfilterctx(val: $str; filtername: $str; h: $hc): $str`

Trim the filter name. `md` → `md.render(val)` and `raw` → `val`, both written
unchanged (md is HTML ooke produced; raw is the explicit opt-out). Every other
name — `upper`, `lower`, `trim`, `escape`, or unknown (unchanged value) — is
applied and the result escaped with `ctxescape(h; …)`.

#### `tplexprctx(expr: $str; ctx: @($str:$str); h: $hc): $str`

Trim the expression. With a `|`: the key is the trimmed text before it, the
filter the trimmed text after it; the value is `ctx.get(key)` (`""` when
absent) passed to `tplfilterctx`. Without: `ctxescape(h; ctx.get(expr) or "")`.

#### `tplapplyfilter(val: $str; filtername: $str): $str` / `tplresolveexpr(expr: $str; ctx: @($str:$str)): $str`

The HTML-text forms, kept for callers outside a render: `tplfilterctx` /
`tplexprctx` with `hcnew()`.

### Lexing and directive parsing

#### `tpllex(src: $str): @$token!$tplerr`

Scan `src` by index from `pos`: find the earliest of `{=`, `{!`, `{#` at or
after it (`str.indexfrom`; each opener's next position is cached and searched
again only once `pos` has passed it). None → the rest is one `raw` token.
Otherwise emit a `raw` token for any text before it, find the matching close
(`=}`, `!}`, `#}`) after the opener; if there is none the rest from `pos` is
`raw` (an unterminated tag is literal text -- and the text before the opener,
already emitted, appears twice: 127.298); else emit an `expr`, `directive` or
`comment` token with the inner text and continue after the close. Each token's
text is the one slice it needs (127.257: the old loop re-sliced the whole
unscanned tail twice per tag, 7.4 MB per lex of a 70 KB page). The error arm
is declared for signature compatibility; it never raises.

#### `tpldirectivename(content: $str): $str`

The trimmed text before `(`, or the whole trimmed text.

#### `tpldirectivearg(content: $str): $str`

The trimmed text between the first `(` and the next `)`, with one pair of
surrounding double quotes removed; `""` when either paren is missing.

#### `tplfindblock(blocks: @$block; name: $str): @$token`

The `toks` of the first block with that name, or `@()`.

#### `tplislandparse(content: $str): @($str:$str)`

Parse `island("name" hydrate="…")` into `@("name":…; "hydrate":…)`; the
defaults are `""` and `"load"` for any part that is missing or malformed.

### Names and rendering

#### `tplnameok(name: $str): bool`

121.57: a partial or layout name is a name inside the templates directory, not
a path. False for the empty name, a backslash, a leading `/`, or any empty,
`.` or `..` segment (so `../x`, `/etc/x`, `a/../../x`, `a//b`, `./a` are
refused); `/` is allowed as the separator for nested names
(`partials/header`).

#### `tplnamepath(templatesdir: $str; kind: $str; name: $str): $str!$tplerr`

If `tplnameok(name)` is false, log and return `$tplerr` ("template: refused
<kind> name "<name>": …"). Otherwise `joined = path.join(templatesdir; name +
".tkt")`. If `joined` does not exist, return it unresolved (the caller reports
the missing file). Else resolve it and `templatesdir` with `file.realpath`
(121.59 (3), toke 121.60; needs the fs.read grant) and return the resolved path
only if it starts with the resolved root plus `/` (not a bare prefix, so a
sibling `templatesx/` is outside); otherwise, or if either resolve fails, log
and return `$tplerr` ("template: refused <kind> name "<name>": it resolves
outside the templates directory …"). The lexical rule cannot see a symlinked
directory inside templates/ that points outside; this can. Symlinks whose
target stays inside templates/ work, a symlinked partial file included,
because the resolved path is what is read.

#### `tplrenderctx(tokens: @$token; ctx: @($str:$str); templatesdir: $str; blocks: @$block; hc0: $hc; depth: i64): $rout!$tplerr`

**Purpose:** The engine. Render tokens as a continuation of output whose HTML
context is `hc0`; return the text, the context after it, and whether an island
was rendered.

**Logic:**

1. If `depth > 32`, log and return `$tplerr` (partials, layouts and yields nest
   too deep — a template that includes itself was unbounded recursion).
2. State: a `str.builder`, `hc = hc0`, `hasislands`, block collection
   (`inblock`, `blockname`, `blocktoks`, `collectedblocks`), `layoutname`.
3. For each token: inside a block, any token but `end` is kept in `blocktoks`.
   Otherwise:
   - `raw`: append; `hc = hcfeed(hc; text)`.
   - `expr`: `val = tplexprctx(content; ctx; hc)`; append and feed.
   - `comment`: nothing.
   - `directive`, by name:
     - `layout`: `layoutname = arg`.
     - `block`: start collecting under `arg`; `end`: store
       `$block{name; toks}` in `collectedblocks`.
     - `var`: `ctxescape(hc; ctx.get(arg) or "")`; append and feed.
     - `yield`: the named block's tokens from `blocks`, if any, rendered with
       `tplrenderctx(…; @(); hc; depth+1)!`; append, take its `hc`, carry its
       `islands`.
     - `partial`: `tplnamepath(templatesdir; "partial"; arg)!`. A missing file
       ("template: no partial template: <path>") or a failed read ("template:
       partial template could not be read: <path>") is logged and returned as `$tplerr`
       (121.59). An empty partial renders nothing; otherwise lex it and render
       with the current `hc` at `depth+1`, as for yield.
     - `island`: `tplislandparse`; append and feed
       `<div data-island="NAME" data-hydrate="HYDRATE"></div>`; `hasislands`.
     - anything else: nothing.
4. With a `layoutname`: `tplnamepath(…; "layout"; …)!`; a missing file
   ("template: no layout template: <path>") or failed read is logged and
   returned as `$tplerr`. Lex it and render it from `hc0` (the layout's output
   replaces this template's, from the same start) with `collectedblocks` at
   `depth+1`; return its text and `hc`, islands from either.
5. Otherwise return the built text, `hc`, `hasislands`.

**Error handling:** Every failure is logged at error level where it is raised
and propagated with `!$tplerr`.

#### `tplrender(tokens: @$token; ctx: @($str:$str); templatesdir: $str; blocks: @$block): $str!$tplerr`

`tplrenderctx(…; hcnew(); 0)!`; if it rendered an island, append
`<script src="/static/ooke-islands.js" defer></script>` once.

#### `tplreadsource(templatepath: $str): $str!$tplerr`

The source of a template file. A missing file ("template: no template file:
<path>", 134.24) or a failed read ("template: template file could not be read:
<path>", 121.59) is logged at error level and returned as `$tplerr`. The one
reader for `tplrenderfile`, `tplcacheget` and `tplrenderfilecached` (121.63).
A directory is not a failed read: std.file reads it as an empty string.

#### `tplrenderfile(templatepath: $str; ctx: @($str:$str); templatesdir: $str): $str!$tplerr`

`tplreadsource(templatepath)!`, lex, and `tplrender(…; @())!`.

### Cache

#### `tplcachenew(): $tplcache`

`$tplcache{entries:@($str:@($token))}` — an empty typed map.

#### `tplcacheget(cache: $tplcache; path: $str): @$token!$tplerr`

The cached tokens for `path`, or `tplreadsource(path)!` and lex (`!`) it on a
miss, so a missing or unreadable file is logged as in `tplrenderfile`. The
cache is not updated.

#### `tplrenderfilecached(templatepath: $str; ctx: @($str:$str); templatesdir: $str; cache: $tplcache): $renderresult!$tplerr`

Tokens from the cache, or `tplreadsource(templatepath)!` and lex on a miss;
store them under `templatepath`; render with `tplrender(…; @())!`; return the
output and the new cache. A missing or unreadable file is logged exactly as in
`tplrenderfile` (121.63; before, `file.read`'s error propagated with no log
line).

## Control Flow

A library; no entry point. `tplrenderfile` (or `tplrenderfilecached`): `tplreadsource` →
`tpllex` → `tplrender` → `tplrenderctx`. `tplrenderctx` is recursive: `yield`
and `partial` re-enter it with the current tracker state, so their values are
escaped for where they land; `layout` re-enters it from the template's start
state, threading the collected blocks so the layout's `yield` renders them.
Every byte written goes through `hcfeed`, and every value through `ctxescape`
(directly, or via `tplexprctx` → `tplfilterctx`).

## Notes

- **Canonical result form.** All match arms use `$ok`/`$err`.
- **Empty cache literal.** `tplcachenew` uses the empty typed-map literal
  `@($str:@($token))`. A sentinel entry with an untyped `@()` value produced a
  corrupt map that segfaulted on the next `.get` (a toke codegen bug, Track B).
- **Errors are logged where raised.** A caller cannot read `e.msg` off a
  `$tplerr` (RT005, toke 127.78, open), so each is logged at error level by the
  function that raises it; serve.tk and build.tk log the route or page.
- **Directive and filter set** (`layout`/`block`/`end`/`var`/`yield`/
  `partial`/`island`; `md`/`raw`/`escape`/`upper`/`lower`/`trim`) and the
  delimiters (`{= =}`/`{! !}`/`{# #}`) are unchanged from the reference; the
  escaping (121.58), name confinement (121.57), missing-partial error (121.59)
  and depth bound are deliberate departures.
- **Inline `mt` over a method call.** `mt ctx.get(k) {…}` is written through a
  `let` first; inline, the parser reads `ctx.get(k) {…}` as map indexing
  (`E4031`). Inline `mt` over a free function call is fine.
- **Tests.** `test/template/test_template.tk` (lexing, rendering, escaping per
  context, names, partials); `test/serve/template_errors.sh` (failures under
  serve and build).
