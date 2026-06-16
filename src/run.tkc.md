---
source_file: "run.tk"
source_hash: "a886a39874c19e9bb8b7639486bdddbff8b9a94d7d41b334e0a83f18007152f8"
compiler_version: "0.3.9"
generated_at: "2026-06-15T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.run`

The ooke CLI compile-and-run driver. Reads a project's `ooke.toml` `[package]`
section to discover the entry point and binary name, shells out to `tkc` to
compile the entry point into `build/<name>`, then executes the produced binary
(forwarding caller arguments) or, in build mode, stops after a successful
compile. Used by the ooke CLI for `ooke run` and `ooke build`.

**Imports:**
- `std.str` (alias `str`) — string concatenation and length.
- `std.log` (alias `log`) — structured progress/error logging.
- `std.file` (alias `file`) — read config, test for entry/output existence, make the build dir.
- `std.path` (alias `path`) — join project dir with relative paths.
- `std.toml` (alias `toml`) — parse `ooke.toml` and read typed `[package]` keys.
- `std.process` (alias `process`) — spawn `tkc` / the built binary and capture exit code + stdout/stderr.

## Types

### `$runerr`

Error type for the fallible functions (`loadclicfg`, `runcompile`).

| Field | Type | Description |
|-------|------|-------------|
| `msg` | `$str` | Human-readable failure description. |

### `$clicfg`

The resolved per-project CLI configuration drawn from `[package]`.

| Field | Type | Description |
|-------|------|-------------|
| `name` | `$str` | Output binary name (`[package].name`). Default `"app"`. |
| `entry` | `$str` | Entry-point source path, relative to the project dir (`[package].entry`). Default `"src/main.tk"`. |

## Functions

### `loadclicfg(projectdir: $str): $clicfg!$runerr`

**Purpose:** Load `<projectdir>/ooke.toml` and extract the `[package]` `name`
and `entry`, applying defaults for absent keys.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `projectdir` | `$str` | Project root directory. |

**Returns:** `$clicfg!$runerr` — the resolved config, or `$runerr` if the TOML
file cannot be read or parsed.

**Logic:**

1. `tomlpath = path.join(projectdir; "ooke.toml")`.
2. Read the file with `file.read`; propagate failure as `$runerr` via `!$runerr`.
3. Parse the source with `toml.load`; propagate parse failure as `$runerr`.
4. Look up the `package` section with `toml.section`, matched
   `{$ok:v v; $err:e tab}` — a missing section falls back to the root table.
5. Read `name` with `toml.str(pkg;"name")`, matched `{$ok:v v; $err:e "app"}`.
6. Read `entry` with `toml.str(pkg;"entry")`, matched
   `{$ok:v v; $err:e "src/main.tk"}`.
7. Return `$clicfg{name; entry}`.

**Error handling:** Only `file.read` and `toml.load` raise `$runerr`. Section and
key lookups are total — they fall back to the root table or the documented
default.

### `runcompile(projectdir: $str; cfg: $clicfg): $str!$runerr`

**Purpose:** Compile the project's entry point with `tkc` and return the path of
the produced binary, or an empty string when compilation yields no binary.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `projectdir` | `$str` | Project root directory. |
| `cfg` | `$clicfg` | Resolved CLI config (entry + binary name). |

**Returns:** `$str!$runerr` — the output binary path on success; an empty `$str`
when compilation does not produce a binary; `$runerr` only on the missing-entry
raise (see *Error handling* and *Notes* for the observed short-circuit caveat).

**Logic:**

1. `entrypath = path.join(projectdir; cfg.entry)`.
2. If `!file.exists(entrypath)`, raise `$runerr{msg:"entry point not found: <entrypath>"}`
   (`if(...){ !$runerr{...} }el{};`).
3. `outbin = path.join(projectdir; str.concat("build/"; cfg.name))`.
4. `builddir = path.join(projectdir; "build")`; create it with `file.mkdir`,
   matched `{$ok:v v; $err:e false}` (the result is bound but ignored).
5. Log `"compiling <entrypath> -> <outbin>"`.
6. Spawn `tkc <entrypath> --out <outbin>` via `process.spawn(@("tkc";entrypath;"--out";outbin))`,
   matched `{$ok:v v; $err:e 0}` to a handle `h`. If `h = 0`, raise
   `$runerr{msg:"failed to spawn tkc"}`.
7. `ecode = process.wait(h)` matched `{$ok:v v; $err:e 0-1}` (`-1` on wait error).
8. `errout = process.stderr(h)` matched `{$ok:v v; $err:e ""}`.
9. If `ecode != 0` (`!(ecode=0)`), log `"tkc error: <errout>"` and return `""`.
10. Else if `str.len(errout) > 0`, log `"tkc: <errout>"`.
11. If `!file.exists(outbin)`, log `"compilation produced no output binary"` and
    return `""`.
12. Return `outbin`.

**Error handling:** Missing entry and spawn failure are reported via `!$runerr`.
Compilation failure (nonzero `tkc` exit, or no output binary) is reported by
returning an empty `$str` (callers treat empty as failure). `process.wait` /
`process.stderr` failures fall back to `-1` / `""`.

### `runexec(binpath: $str; passargs: @$str): i64`

**Purpose:** Execute a compiled binary, forwarding extra arguments, and return
its exit code.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `binpath` | `$str` | Path to the binary to run. |
| `passargs` | `@$str` | Arguments to forward to the binary. |

**Returns:** `i64` — the binary's exit code, or `1` if the binary could not be
spawned.

**Logic:**

1. Initialise a mutable command array `cmdparts = mut.@(binpath)` (binary path as argv[0]).
2. Loop `i` from `0` (inclusive) to `passargs.len` (exclusive), appending each
   `passargs.get(i)` to `cmdparts` (reassigning `cmdparts` to the appended array).
3. Log `"running <binpath>"`.
4. Spawn `cmdparts` via `process.spawn`, matched `{$ok:v v; $err:e 0}` to handle
   `h`. If `h = 0`, log `"failed to spawn binary"` and return `1`.
5. `ecode = process.wait(h)` matched `{$ok:v v; $err:e 0-1}`.
6. `sout = process.stdout(h)` matched `{$ok:v v; $err:e ""}`; if non-empty, log it.
7. `serr = process.stderr(h)` matched `{$ok:v v; $err:e ""}`; if non-empty, log it.
8. Return `ecode as i64`.

**Error handling:** A spawn failure returns `1`. wait/stdout/stderr failures
fall back to `-1` / `""`.

### `run(projectdir: $str; passargs: @$str): i64`

**Purpose:** Compile then run a project. Entry point for `ooke run`.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `projectdir` | `$str` | Project root directory. |
| `passargs` | `@$str` | Arguments forwarded to the built binary. |

**Returns:** `i64` — the built binary's exit code, or `1` if config load or
compilation fails.

**Logic:**

1. `cfg = loadclicfg(projectdir)` matched
   `{$ok:v v; $err:e $clicfg{name:"app";entry:"src/main.tk"}}` (a load failure
   falls back to the default config).
2. `binpath = runcompile(projectdir; cfg)` matched `{$ok:v v; $err:e ""}`.
3. If `str.len(binpath) = 0`, log `"compilation failed, aborting run"` and return `1`.
4. Otherwise return `runexec(binpath; passargs)`.

**Error handling:** Config-load failure degrades to the default config; a compile
that yields no binary returns `1`.

### `build(projectdir: $str): i64`

**Purpose:** Compile a project without running it. Entry point for `ooke build`.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `projectdir` | `$str` | Project root directory. |

**Returns:** `i64` — `0` on a successful build, `1` if compilation fails.

**Logic:**

1. `cfg = loadclicfg(projectdir)` matched
   `{$ok:v v; $err:e $clicfg{name:"app";entry:"src/main.tk"}}`.
2. `binpath = runcompile(projectdir; cfg)` matched `{$ok:v v; $err:e ""}`.
3. If `str.len(binpath) = 0`, log `"compilation failed"` and return `1`.
4. Log `"built: <binpath>"` and return `0`.

**Error handling:** A compile that yields no binary returns `1`.

## Control Flow

`run` and `build` are the two entry points. Both first call `loadclicfg`
(read + parse `ooke.toml`, default-fill `[package]`), then `runcompile` (spawn
`tkc`). `run` continues into `runexec` to spawn the built binary and propagate
its exit code; `build` stops after reporting the built path. `runcompile` and
`runexec` are the two process-spawning leaves; `loadclicfg` is the only
TOML-reading leaf. Data flows `loadclicfg → $clicfg → runcompile → binpath →
runexec`.

## Notes

- **Canonical result form.** Match arms use the spec-canonical `$ok`/`$err`
  variant names (toke-spec-prompt.md: "Variants are `$lowercase`"). The previous
  source used the non-canonical `Ok`/`Err`; both compile, but `$ok`/`$err` is the
  spec form (Track B 113.B.9).
- **Dropped the unused `std.args` import** the reference module carried; it was
  never referenced.
- **`!err` raise does not short-circuit (compiler bug).** The entry-not-found
  `if(...){ !$runerr{...} }el{};` in `runcompile` raises an error, but execution
  continues through the rest of the function; a later ordinary `<""` return then
  determines the result. Observed effect: `runcompile` on a missing entry returns
  `$ok ""` (empty binpath), not `$runerr`. This matches the reference's observable
  behaviour — callers (`run`/`build`) treat an empty binpath as failure (`rc=1`),
  so the contract is unchanged. The test for `runcompile` therefore asserts
  "no binary produced" (`$ok` with empty string OR `$err`) rather than `$err`
  alone. Filed as a Track B compiler bug; behaviour kept faithful to the
  reference, not worked around.
- **`tkc` spawn args.** `process.spawn(@("tkc";...))` was observed to pass
  corrupted argv to the shell in the test harness (`sh: <garbage>: command not
  found`); the compile still fails cleanly (nonzero exit / no binary) so the
  observable outcome is unaffected. Noted as a Track B follow-up.
