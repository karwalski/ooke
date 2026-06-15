---
source_file: "config.tk"
source_hash: "5b1360128a53ce8669c47fd1ebb2b34eba892522cd71276d9707f37240c638d6"
compiler_version: "0.3.9"
generated_at: "2026-06-15T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.config`

Loads and parses an ooke site's `ooke.toml` configuration file into a single
flat `$ookecfg` record. Every key has a hard-coded default, so `configload`
always returns a fully-populated config unless the file read or the TOML parse
itself fails — those two failures (and only those) surface as `$configerr`.

**Imports:**
- `std.toml` (alias `toml`) — TOML parse + typed key/section accessors.
- `std.file` (alias `file`) — read the config file from disk.

## Types

### `$ookecfg`

The complete ooke site configuration, flattened (TOML sections are hoisted into
prefixed field names; there is no nested config type).

| Field | Type | Description |
|-------|------|-------------|
| `sitename` | `$str` | `[site].name` — site name. Default `"my-site"`. |
| `siteurl` | `$str` | `[site].url` — canonical site URL. Default `""`. |
| `sitelanguage` | `$str` | `[site].language` — language code. Default `"en"`. |
| `buildoutput` | `$str` | `[build].output` — static build output dir. Default `"build/"`. |
| `buildminify` | `bool` | `[build].minify` — minify HTML/CSS on build. Default `true`. |
| `buildinlinecss` | `bool` | `[build].inlinecss` — inline CSS on build. Default `true`. |
| `serverport` | `i64` | `[server].port` — HTTP listen port. Default `3000`. |
| `serverworkers` | `i64` | `[server].workers` — worker count (`0` = auto-detect CPU). Default `0`. |
| `servercorsorigins` | `$str` | `[server].corsorigins` — CORS allow-origin. Default `""`. |
| `storebackend` | `$str` | `[store].backend` — `"flat"` or `"sqlite"`. Default `"flat"`. |
| `logaccess` | `$str` | `[log].access` — access-log file path. Default `"logs/access.log"`. |
| `logmaxlines` | `i64` | `[log].maxlines` — access-log rotation line cap. Default `10000`. |
| `logmaxagedays` | `i64` | `[log].maxagedays` — access-log retention days. Default `30`. |
| `apiprefix` | `$str` | `[paths].apiprefix` — API route namespace prefix. Default `""`. |

### `$configerr`

Error type for `configload`.

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
3. Look up the six sections `site`, `build`, `server`, `store`, `log`, `paths`
   with `toml.section`. Each lookup is matched `{$ok:v v; $err:e tab}` — a
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

## Control Flow

`configload` is the single entry point. It is linear: two fallible steps
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
- **Schema reconciliation deferred (113.2a).** This module is behaviourally
  faithful to the reference: it reads `inlinecss`/`corsorigins`/`access`, while
  the shipped `ooke.toml` uses snake_case `inline_css`/`cors_origins`/
  `access_format`, and `[log].access_format` (a format) differs from this
  module's `logaccess` (a path). Reconciling the authoritative config schema is
  story 113.2a — not silently changed here.
- **Dropped the unused `std.str` import** the reference module carried.
