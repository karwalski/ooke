---
source_file: "repair.tk"
source_hash: "00ace73ec80fcf5ec4c4fc840175675568001c8409fdbc2b26637581089ebc8f"
compiler_version: "0.3.9"
generated_at: "2026-06-15T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.repair`

A minimal compile-check driver: it shells out to `tkc --check` on a toke source
file, then counts the diagnostics emitted on stderr. It is the foundation for an
auto-repair loop (re-check after edits) but currently performs a single check
pass and reports how many diagnostics were found.

**Imports:**
- `std.str` (alias `str`) — string splitting, trimming, length, concatenation,
  and integer-to-string conversion.
- `std.log` (alias `log`) — informational logging of progress and each
  diagnostic line.
- `std.process` (alias `process`) — spawn the `tkc` subprocess and read its
  exit code and stderr.

## Types

### `$diagnostic`

A single compiler diagnostic. Declared for the module's public interface; the
current implementation counts diagnostic lines rather than populating this
record, but the type is exported for callers that parse structured diagnostics.

| Field | Type | Description |
|-------|------|-------------|
| `code` | `$str` | Diagnostic / error code (e.g. `"E2004"`). |
| `msg` | `$str` | Human-readable diagnostic message. |
| `line` | `i64` | 1-based source line of the diagnostic. |
| `col` | `i64` | 1-based source column of the diagnostic. |
| `file` | `$str` | Path of the file the diagnostic refers to. |
| `fix` | `$str` | Suggested fix text. |

## Functions

### `parsediags(raw: $str): i64`

**Purpose:** Count the non-empty diagnostic lines in a raw stderr blob, logging
each one.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `raw` | `$str` | Raw stderr text from a `tkc` invocation (newline-separated lines). |

**Returns:** `i64` — the number of non-empty (after trimming) lines in `raw`.

**Logic:**

1. Split `raw` on the newline character `"\n"` into a list `lines`.
2. Initialise a mutable counter `count` to `0`.
3. Loop with index `i` from `0` (inclusive) while `i < lines.len`, incrementing
   `i` by `1` each iteration:
   a. Trim the i-th line with `str.trim` into `line`.
   b. If `str.len(line) > 0` (the trimmed line is non-empty): log it with
      `log.info` prefixed by `"  diag: "` (empty `@()` args list), and increment
      `count` by `1`.
   c. Otherwise (empty line): do nothing.
4. Return `count`.

**Error handling:** None. All inputs are valid; empty input yields `0`.

### `repairfile(filepath: $str, maxiters: i64): i64`

**Purpose:** Run `tkc --check` on `filepath` once and report the diagnostic
count: `0` when the file checks clean, the diagnostic count when it does not, and
`1` when the checker cannot be spawned.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `filepath` | `$str` | Path of the toke source file to check. |
| `maxiters` | `i64` | Reserved repair-iteration cap; bound to a local but not yet used (single-pass implementation). |

**Returns:** `i64` — `0` if the file checks clean (empty stderr); the number of
diagnostic lines if it does not; `1` if `tkc` could not be spawned.

**Logic:**

1. Bind `mi` to `maxiters` (reserved; the value is currently unused beyond this
   binding).
2. Log `"repair: checking "` concatenated with `filepath`.
3. Spawn the subprocess `tkc --check <filepath>` via `process.spawn` with the
   argument list `@("tkc"; "--check"; filepath)`. Match the result
   `{$ok:v v; $err:e 0}`: on success bind `h` to the process handle; on failure
   bind `h` to `0`.
4. If `h = 0` (spawn failed): log `"repair: failed to spawn tkc"` and return `1`.
   Otherwise fall through (empty `el{}`).
5. Wait for the process with `process.wait(h)`, matched `{$ok:v v; $err:e 0-1}`,
   binding the exit code to `ecode` (defaulting to `-1` on error; the value is
   read for sequencing but not branched on).
6. Read the process stderr with `process.stderr(h)`, matched
   `{$ok:v v; $err:e ""}`, binding `errout` (defaulting to the empty string).
7. If `str.len(errout) = 0` (no stderr output): log `"repair: clean"` and return
   `0`.
8. Otherwise: call `parsediags(errout)` to count diagnostic lines into
   `errcount`, log `"repair: found "` + `str.fromint(errcount)` + `" diagnostic(s)"`,
   and return `errcount`.

**Error handling:** Spawn failure surfaces as a `0` handle and returns `1`. Wait
and stderr-read failures fall back to defaults (`-1` exit, empty stderr) so the
clean path is taken; no exception propagates.

## Control Flow

Two functions. `repairfile` is the entry point: it spawns and waits on a `tkc`
subprocess, then delegates stderr-line counting to `parsediags`. `parsediags` is
a pure line-counting loop with no subprocess interaction and is independently
testable. Data flows one way: `repairfile` produces the stderr string and passes
it to `parsediags`, whose count becomes `repairfile`'s return value on the
non-clean path.

## Notes

- **Canonical result form.** The three `process.*` results are matched with the
  spec-canonical `$ok`/`$err` variant names (toke-spec-prompt.md: "Variants are
  `$lowercase`"). The previous source used the non-canonical `Ok`/`Err` (Track B
  113.B.9); behaviour is identical.
- **`str.fromint`, not `str.from_int`.** The v0.3 lexer rejects underscores in
  identifiers (error `E1003`), so the stdlib accessor is spelled `str.fromint` in
  source even though its `.tki` interface entry is named `str.from_int`. Both
  mangle to `tk_str_from_int`.
- **`maxiters` is reserved.** It is bound to `mi` for forward-compatibility with
  a future re-check loop but does not yet drive any iteration; behaviour is
  single-pass. Kept for signature parity with the reference.
- **`ecode` is read but not branched on.** Diagnostic presence is decided solely
  by whether stderr is empty, matching the reference behaviour: a clean exit code
  with stderr output still reports diagnostics, and an empty stderr reports clean
  regardless of exit code.
