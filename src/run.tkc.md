---
source_file: "run.tk"
source_hash: "c925d8f098a5c79fbd3da72981c7dde27eac8fa1535d44b8f4ca5bf9e97fe8ee"
compiler_version: "3.0.0"
generated_at: "2026-10-01T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.run`

The ooke CLI compile-and-run driver. Reads a project's `ooke.toml` `[package]`
section to discover the entry point and binary name, spawns `tkc` to compile
the entry point into `build/<name>`, then executes the produced binary
(forwarding caller arguments) or, in build mode, stops after a successful
compile. Used by the ooke CLI for `ooke run` and `ooke build --cli`.

**Imports:**
- `std.str` (alias `str`) — string concatenation and length.
- `std.log` (alias `log`) — structured progress/error logging.
- `std.file` (alias `file`) — read config, test for entry/output existence, make the build dir.
- `std.path` (alias `path`) — join project dir with relative paths.
- `std.toml` (alias `toml`) — parse `ooke.toml` and read typed `[package]` keys.
- `std.process` (alias `process`) — spawn `tkc` / the built binary and capture exit code + stdout/stderr.

## Types

### `$runerr`

Error type for the fallible functions (`loadclicfg`, `runcompile`). In the
current source only `loadclicfg` produces one (a failed read or parse);
`runcompile` reports every failure by returning `""`.

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
the produced binary, or an empty string when there is no binary.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `projectdir` | `$str` | Project root directory. |
| `cfg` | `$clicfg` | Resolved CLI config (entry + binary name). |

**Returns:** `$str!$runerr` — the output binary path on success; an empty `$str`
on any failure. No path in the current source returns `$runerr`.

**Logic:**

1. `entrypath = path.join(projectdir; cfg.entry)`.
2. If `!file.exists(entrypath)`, log `"entry point not found: <entrypath>"`
   and return `""`.
3. `outbin = path.join(projectdir; str.concat("build/"; cfg.name))`.
4. `builddir = path.join(projectdir; "build")`; create it with `file.mkdir`,
   matched `{$ok:v v; $err:e false}` (result discarded).
5. Log `"compiling <entrypath> -> <outbin>"`.
6. Spawn `tkc <entrypath> --out <outbin>` via
   `process.spawn(@("tkc";entrypath;"--out";outbin))`, matched
   `{$ok:v v; $err:e 0}` to a handle `h`. If `h==0`, log
   `"failed to spawn tkc"` and return `""`.
7. `ecode = process.wait(h)` — a plain `i32` exit status, not a result
   (story 134.45).
8. `errout = process.stderr(h)` matched `{$ok:v v; $err:e ""}`.
9. If `!(ecode==0)`, log `"tkc error: <errout>"` and return `""`.
10. If `str.len(errout) > 0`, log `"tkc: <errout>"`.
11. If `!file.exists(outbin)`, log `"compilation produced no output binary"` and
    return `""`.
12. Return `outbin`.

**Error handling:** Every failure (missing entry, spawn failure, non-zero `tkc`
exit, no output binary) is logged at info level and returned as `""`; callers
treat empty as failure. A `process.stderr` failure reads as `""`.

**Story 134.45:** `process.wait` was matched with `$ok`/`$err` arms; it
compiled and always took the `$err` arm (toke 127.202), so every compile,
successful or not, reported "tkc error" and `ooke run` / `build --cli` never
ran anything. The status is now compared directly.

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
5. `ecode = process.wait(h)` — a plain `i32` status (story 134.45; it used
   to read `-1` for every child, so `ooke run` exited 255 even when the
   program exited 0).
6. `sout = process.stdout(h)` matched `{$ok:v v; $err:e ""}`; if non-empty, log it.
7. `serr = process.stderr(h)` matched `{$ok:v v; $err:e ""}`; if non-empty, log it.
8. Return `ecode as i64`.

**Error handling:** A spawn failure logs `"failed to spawn binary"` and
returns `1`. stdout/stderr failures read as `""`. The child's output is
captured and logged at info level after it exits, not streamed.

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

- **Canonical result form.** Match arms use `$ok`/`$err`.
- **Exit status is compared, not matched** (story 134.45): see `runcompile`
  and `runexec`.
- **`tkc` from `PATH`.** `runcompile` spawns `"tkc"` by name; the compiler
  must be on `PATH`. Its output is `build/<name>` under the project.
- **Failures are logged at info level.** A missing entry point, a failed
  spawn and a `tkc` error are all `log.info` lines; the non-zero exit status
  of `run`/`build` is what marks the failure.
