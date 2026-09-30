---
source_file: "main.tk"
source_hash: "53bd563a9945866f359067d25eb5d135b2a6cd07b446352f54f87d5699ad9660"
compiler_version: "3.0.0"
generated_at: "2026-10-01T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.main`

The ooke binary **entry point**: the only module that defines `f=main`. It owns
argv parsing and command dispatch, delegating command logic to the `ooke.cli`,
`ooke.run` and `ooke.repair` library modules; only `compile` runs its steps
here. Keeping the entry point in its own module (rather than making `main.tk`
also be `ooke.cli`) is what lets the cli test import `ooke.cli` and define its
own `f=main` without a link-time symbol collision.

**Imports:**
- `std.args` (alias `args`) — argv access (`count`, `get`).
- `std.str` (alias `str`) — `eq`/`concat`/`len`/`contains`/`split` for command
  matching, messages and `$PATH` parsing.
- `std.log` (alias `log`) — usage and error output.
- `std.process` (alias `process`) — `spawn`/`wait`/`stdout`/`stderr` for the
  `compile` command (runs the app Makefile generator, then `make`).
- `std.env` (alias `env`) — `env.getor` for `$OOKE_ROOT` and `$PATH`.
- `std.file` (alias `file`) — `file.exists` probes when locating the generator
  script.
- `std.path` (alias `path`) — `path.dir` / `path.join`.
- `ooke.cli` (alias `cli`) — command logic (`clinew`, `cligen`, `cligenspec`,
  `runserve`, `runbuild`), usage/version (`cliprintusage`, `cliprintversion`,
  `cliprintcmdusage`) and `cliishelp`.
- `ooke.repair` (alias `repair`) — `repairfile` for the `repair` command.
- `ooke.run` (alias `run`) — `run`/`build` for the CLI-package commands.

## Types

None.

## Functions

### `bindir(argv0: $str): $str`

**Purpose:** The directory the running ooke binary lives in (story 134.45).

**Parameters:** `argv0: $str` — the program name as invoked (argv[0]).

**Returns:** `$str` — the directory, or `""` if none is found.

**Logic:**

1. If `argv0` contains a `/`, return `path.dir(argv0)`.
2. Otherwise split `$PATH` (`env.getor("PATH"; "")`) on `:`; for each
   non-empty entry `d`, return `d` if `path.join(d; argv0)` exists.
3. Return `""`.

**Error handling:** None. A symlinked binary is not followed; the source says
to set `OOKE_ROOT` for that layout.

### `genscript(): $str`

**Purpose:** Locate `scripts/gen_app_makefile.sh` from the ooke installation
rather than the current directory (story 134.45: `ooke compile` used to work
only when run from the ooke checkout).

**Returns:** `$str` — the script path, or `""` if none is found.

**Logic:**

1. If `$OOKE_ROOT` is set and non-empty, return
   `path.join(OOKE_ROOT; "scripts/gen_app_makefile.sh")` (not probed).
2. Otherwise take argv[0] (`""` on error), find its directory with `bindir`,
   and return `path.join(dir; rel)` if that file exists.
3. Return `""`.

**Error handling:** None.

### `main(): i64`

**Purpose:** Parse argv and dispatch to the matching command, returning that
command's exit code (0 success, non-zero failure).

**Dispatch:**

| argv[1] | Behaviour |
|---------|-----------|
| (none) / `--help` | `cli.cliprintusage()`, exit 0 |
| `--version` | `cli.cliprintversion()`, exit 0 |
| `<cmd> <help-arg>` | if `cli.cliishelp(argv[2])`, return `cli.cliprintcmdusage(cmd)` — checked **before** dispatch, so no command acts on a help request (story 134.19; `ooke serve --help` used to bind a port) |
| `new <name>` | `cli.clinew(name)`; with no name, log `usage: ooke new <name>`, exit 1 |
| `serve [path]` | `cli.runserve(path)`, default `"."` (story 134.37) |
| `build --cli [path]` | `run.build(path)`, default `"."` |
| `build [path]` | `cli.runbuild(path)`, default `"."` (story 134.25: the argument used to be read and ignored) |
| `run [path] [args…]` | `run.run(path; argv[3..])`, path default `"."` |
| `compile [path]` | see below; path default `"."` |
| `gen spec <container> <type>` | `cli.cligenspec(container; type)`; fewer than 5 args → usage (containers: stack, queue, set), exit 1 |
| `gen <type> <name>` | `cli.cligen(type; name)`; fewer than 4 args → usage, exit 1 |
| `repair <file>` | `repair.repairfile(file; 10)`; no file → usage, exit 1 |
| anything else | log `unknown command: <cmd>`, usage, exit 1 |

**`compile`:**

1. Log `generating app build for <path>`; `gen = genscript()`. If empty, log
   an error naming the script and `OOKE_ROOT`, exit 1.
2. `process.spawn(@("sh"; gen; path))`; a spawn failure (handle `0`) logs
   `failed to run gen_app_makefile.sh`, exit 1.
3. `process.wait` (a plain `i32`, story 134.44 — it used to be matched with
   `$ok`/`$err` arms, which always took `$err`). Non-zero: log the script's
   stderr (if any) and `Makefile generation failed: <gen>` at error, exit 1.
4. `process.spawn(@("make"; "-f"; "Makefile.serve"; "-C"; path))`; spawn
   failure logs `failed to run make`, exit 1.
5. Wait; log make's stdout and stderr at info; non-zero exit logs
   `compilation failed` at error, exit 1.
6. Log `compile complete`, exit 0.

## Constants

None.

## Control Flow

A single nested `if/el` ladder over the first argument, each leaf returning an
exit code via short-return `<`. The `run` command loops argv[3..] into a
mutable `@$str` to forward to `run.run`. The `compile` command is a linear
sequence of `process.spawn`/`process.wait` steps, each guarded for failure.
No recursion.

## Notes

- **Thin entry.** Apart from `compile` and the script lookup, every branch
  forwards to a library function, keeping `f=main` isolated to one module.
- **Canonical `$ok`/`$err`** in every argv `mt` match; `str.eq` for command
  comparisons.
