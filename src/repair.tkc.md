---
source_file: "repair.tk"
source_hash: "04c62e17b5827f23dd5ab4b1e2e1cdf2c39a646810a0aeef86bbd511e4743645"
compiler_version: "3.0.0"
generated_at: "2026-10-01T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.repair`

A minimal compile-check driver behind `ooke repair <file>`: it shells out to
`tkc --check` on a toke source file, then counts the diagnostic lines emitted
on stderr. It is the foundation for an auto-repair loop but performs a single
check pass and reports how many diagnostics were found.

**Imports:**
- `std.str` (alias `str`) — split, trim, len, concat, join.
- `std.log` (alias `log`) — informational logging of progress and each
  diagnostic line.
- `std.process` (alias `process`) — spawn the `tkc` subprocess, wait on it and
  read its stderr.

## Types

### `$diagnostic`

A single compiler diagnostic. Declared for the module's public interface; the
implementation counts diagnostic lines rather than populating this record.

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

**Returns:** `i64` — the number of lines in `raw` that are non-empty after
trimming.

**Logic:**

1. Split `raw` on `"\n"` into `lines`; `count` starts at `0`.
2. For each line: trim it with `str.trim`; if non-empty, log
   `"  diag: " + line` at info and increment `count`.
3. Return `count`.

**Error handling:** None. Empty input yields `0`.

### `repairfile(filepath: $str; maxiters: i64): i64`

**Purpose:** Run `tkc --check` on `filepath` once and report the diagnostic
count.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `filepath` | `$str` | Path of the toke source file to check. |
| `maxiters` | `i64` | Reserved repair-iteration cap; not used (single pass). `main` passes `10`. |

**Returns:** `i64` — `0` if `tkc` exited 0 (warnings on stderr do not
count); otherwise the number of non-empty stderr lines, or `1` if there were
none; `1` if `tkc` could not be spawned.

**Logic:**

1. Log `"repair: checking " + filepath`.
2. `process.spawn(@("tkc"; "--check"; filepath))`, matched
   `{$ok:v v; $err:e 0}` into `h`.
3. If `h == 0`: log `"repair: failed to spawn tkc"`, return `1`.
4. `ecode = process.wait(h)` — a plain `i32` exit status, not a result
   (134.45).
5. Read stderr with `process.stderr(h)`, `{$ok:v v; $err:e ""}`.
6. `ecode == 0`: the file is clean. Log `"repair: clean"`, or
   `"repair: clean (<n> warning(s))"` when stderr held lines; return `0`.
7. Otherwise `errcount = parsediags(errout)`. If it is `0` (tkc failed and
   printed nothing), log at error `"repair: tkc exited <ecode> on <file> with
   no diagnostics"` and return `1`. Else log
   `"repair: found <errcount> diagnostic(s)"` and return `errcount`.

**Error handling:** Spawn failure returns `1`. tkc's exit status decides clean
or not (story 121.66: it used to be ignored, so a silent tkc failure read as
clean and a warning as a diagnostic). A stderr-read failure is treated as
empty stderr.

## Control Flow

`repairfile` spawns and waits on a `tkc` subprocess, then hands its stderr to
`parsediags`, whose count becomes the return value on the non-clean path.
`parsediags` is a pure line-counting loop and independently testable.

## Notes

- **Canonical result form.** The `process.spawn` and `process.stderr` results
  are matched with `$ok`/`$err`; `process.wait` is not a result and is not
  matched (134.45).
- **`maxiters` is reserved** for a future re-check loop; behaviour is
  single-pass.
- **The compiler is found as `tkc` on `$PATH`.** `main` does not return the
  count as the exit status (it was truncated modulo 256, so 256 diagnostics
  exited 0 -- 121.66); any count above 0 exits 1.
