---
source_file: "config.tk"
source_hash: "763decfeb2f9959771cbebef2c9c92a6ff6d8dc8d12911ec6e77a7e3621d9d0f"
compiler_version: "3.0.0"
generated_at: "2026-10-01T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.config`

Loads and parses an ooke site's `ooke.toml` configuration file into a single
flat `$ookecfg` record. Every key has a hard-coded default, so `configload`
always returns a fully-populated config unless the file read or the TOML parse
itself fails — those two failures (and only those) surface as `$configerr`.
Two helpers re-read the file for keys that are *not* part of the config but
that `ooke serve` must report on: the unwired `[log]` rotation keys
(`configlogunsupported`) and `[server] admin` (`configadmin`).

**Imports:**
- `std.toml` (alias `toml`) — TOML parse + typed key/section accessors.
- `std.file` (alias `file`) — read the config file from disk.

## Types

### `$ookecfg`

The complete ooke site configuration, flattened (TOML sections are hoisted into
prefixed field names; there is no nested config type). It has 16 fields and
must stay at 16 or fewer: toke's code generator drops every struct field past
the 16th (`TKC_MAX_PARAMS`), so `tkc --check` passes and the build fails with
E4025 "no field" (measured in story 134.40).

| Field | Type | Description |
|-------|------|-------------|
| `sitename` | `$str` | `[site].name` — site name. Default `"my-site"`. |
| `siteurl` | `$str` | `[site].url` — canonical site URL. Default `""`. |
| `sitelanguage` | `$str` | `[site].language` — language code. Default `"en"`. |
| `buildoutput` | `$str` | `[build].output` — static build output dir. Default `"build/"`. |
| `buildminify` | `bool` | `[build].minify` — minify HTML/CSS on build. Default `true`. |
| `buildinlinecss` | `bool` | `[build].inlinecss` — inline CSS on build. Default `true`. |
| `serverport` | `i64` | `[server].port` — HTTP listen port. Default `3000`. |
| `serverhost` | `$str` | `[server].host` — the address `ooke serve` binds. Default `"127.0.0.1"` (loopback only; story 138.7). toke validates it at bind time: an IPv4 literal, `"localhost"`, or `""`/`"*"`/`"0.0.0.0"` for all interfaces. |
| `serverworkers` | `i64` | `[server].workers` — worker count (`0` = auto-detect CPU). Default `0`. |
| `servercorsorigins` | `$str` | `[server].corsorigins` — CORS allow-origin. Default `""`. |
| `logaccess` | `$str` | `[log].access` — access log: a path relative to the project, `"-"` for stderr, `""` for off. Default `"-"`. Applied by `serve.serveopenlogs` (story 134.40). |
| `logerror` | `$str` | `[log].error` — error log (the access line again for status >= 400); same values. Default `""`. |
| `logaccessformat` | `$str` | `[log].accessformat` — `"combined"` or `"json"`. Default `"combined"`. |
| `tlscert` | `$str` | `[tls].cert` — certificate path, relative to the project. Default `""` (plain HTTP). |
| `tlskey` | `$str` | `[tls].key` — private key path. Default `""`. Both or neither (`serve.servetlscheck`). |
| `apiprefix` | `$str` | `[paths].apiprefix` — API route namespace prefix. Default `""`. |

### `$configerr`

Error type for `configload`, `configlogunsupported` and `configadmin`.

| Field | Type | Description |
|-------|------|-------------|
| `msg` | `$str` | Human-readable failure description. |

## Functions

### `configload(path: $str): $ookecfg!$configerr`

**Purpose:** Read and parse `ooke.toml` at `path` into a fully-populated
`$ookecfg`, applying a default for every absent section or key.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `path` | `$str` | Filesystem path to the TOML config file. |

**Returns:** `$ookecfg!$configerr` — the populated config, or `$configerr` if the
file cannot be read or the TOML cannot be parsed.

**Logic:**

1. Read the file at `path` with `file.read`; propagate failure as `$configerr`
   via the `!$configerr` operator.
2. Parse the source with `toml.load`; propagate parse failure as `$configerr`.
3. Look up the six sections `site`, `build`, `server`, `log`, `paths`,
   `tls` with `toml.section`. Each lookup is matched `{$ok:v v; $err:e tab}` — a
   missing section falls back to the **root table** `tab` (not an empty table),
   so a key lookup against a missing section degrades to a top-level lookup
   rather than always hitting the default.
4. Read each individual key with the typed accessor (`toml.str`/`toml.bool`/
   `toml.i64`) against its section, matched `{$ok:v v; $err:e <default>}` so a
   missing or wrong-typed key yields the documented default (listed in the
   `$ookecfg` table above).
5. Construct and return the `$ookecfg` record literal from the bound values.

**Error handling:** Only `file.read` and `toml.load` raise `$configerr` (via
`!`). All section/key lookups are total — they never raise; they fall back to a
default value (keys) or the root table (sections).

### `configlogunsupported(path: $str): $str!$configerr`

**Purpose:** Name the `[log]` rotation keys that are set but not applied
(story 134.40). std.log's rotation was measured to lose lines (4 of 40 kept
across 4 pre-fork workers; a same-second second rotation overwrites the
first), so `maxlines` and `maxagedays` are not wired; serve names them and
ignores them, as an old `[store]` table is ignored (134.34).

**Logic:** Read (`!$configerr`) and parse (`!$configerr`) the file; take the
`log` section (falling back to the root table). A key counts as present when
`toml.i64` on it succeeds. Return `"maxlines, maxagedays"`, `"maxlines"`,
`"maxagedays"` or `""`.

**Error handling:** Only the read and the parse fail. A key holding a
non-integer value is not reported.

### `configadmin(path: $str): $str!$configerr`

**Purpose:** Read `[server] admin` so that serve can refuse `admin = true`
and name `admin = false` as ignored (story 121.25, audit OOK-03). ooke has no
admin interface, nor the authentication, sessions, CSRF protection or rate
limiting to put one behind.

**Logic:** Read and parse the file (`!$configerr`). If there is no `[server]`
section, return `""`. If `admin` is a bool, return `"true"` or `"false"`. If it
is a string or an integer, return `"true"` — a string `"false"` is not false:
refusing is the safe reading. Otherwise (absent) return `""`.

**Error handling:** Only the read and the parse fail.

## Control Flow

`configload` is the main entry point; `configlogunsupported` and `configadmin`
each re-read and re-parse the file independently. It is linear: two fallible steps
(read, parse) that short-circuit to `$configerr`, followed by a sequence of
total section/key reads each guarded by a `mt … {$ok…;$err…}` match, ending in
one record-literal return. No loops, no recursion, no mutable state.

## Notes

- **Defaults are load-bearing for loke parity.** `configload` must never fail on
  a missing section or key — only on file-read or TOML-parse failure. The exact
  default values above are depended on by callers.
- **Canonical result form.** Match arms use the spec-canonical `$ok`/`$err`
  variant names (toke-spec-prompt.md: "Variants are `$lowercase`"). The previous
  source used the non-canonical `Ok`/`Err`; both compile, but `$ok`/`$err` is
  the spec form (Track B 113.B.9).
- **Schema reconciled (113.2a).** Config keys use the **no-underscore**
  convention project-wide (matches toke's Profile-1 identifier rules — `_` is
  outside the charset, E1003 — so the TOML key string equals the toke field
  token 1:1, eliminating the silent-ignore drift class). Keys: `inlinecss`,
  `corsorigins`, `apiprefix`, `[log].accessformat`. The `[log]` key is now
  `accessformat` (default `"combined"`), matching the real stdlib capability
  `tk_log_accessformat_w`; the old dead `access` *path* read was removed.
  (Story 134.40 wired `[log]` into serve and added `access`/`error` path keys
  and `[tls]`; `maxlines`/`maxagedays` were removed — std.log's rotation loses
  lines. See docs/logging-and-tls.md and `configlogunsupported`.) The no-op `imageoptimize` key was dropped (no image-optimize
  feature exists).
- **`[store]` is gone (134.34).** `[store].backend` was read into a field that
  nothing used — build and serve hardcoded `"flat"`, and there is no SQLite
  content backend. The key is no longer read; an old `[store]` table loads
  unchanged and is ignored.
- **Bind address (138.7).** `host` defaults to loopback, unlike toke's
  port-only serve functions, because `ooke serve` is first a development and
  local-first server; a deployment sets `host = "0.0.0.0"`
  (docs/logging-and-tls.md, "Bind address").
- **Dropped the unused `std.str` import** the reference module carried.
