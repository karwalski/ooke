---
source_file: "main.tk"
source_hash: "d2e45cc52c51de9ee0dde9d2ad377aae761ade2a682d85ea63cde14818cce1ed"
compiler_version: "0.3.9"
generated_at: "2026-06-16T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.main`

The ooke binary **entry point**: the only module that defines `f=main`. It owns
argv parsing and command dispatch, delegating all command logic to the
`ooke.cli` library module. Keeping the entry point in its own module (rather than
making `main.tk` also be `ooke.cli`) is what lets the cli test import `ooke.cli`
and define its own `f=main` without a link-time symbol collision.

**Imports:**
- `std.args` (`args`) — argv access (`count`, `get`).
- `std.str` (`str`) — `eq`/`concat`/`len` for command matching and messages.
- `std.log` (`log`) — usage/error output.
- `std.process` (`process`) — `spawn`/`wait`/`stdout`/`stderr` for the
  `compile` command (runs the app Makefile generator + `make`).
- `ooke.cli` (`cli`) — all command logic (`clinew`, `cligen`, `cligenspec`,
  `runserve`, `runbuild`, usage/version).
- `ooke.repair` (`repair`) — `repairfile` for the `repair` command.
- `ooke.run` (`run`) — `run`/`build` for the CLI-package commands.

## Functions

### `main(): i64`

**Purpose:** Parse argv and dispatch to the matching command, returning that
command's exit code (0 success, non-zero failure).

**Dispatch (parity with the reference CLI):**

| argv[1] | Behaviour |
|---------|-----------|
| (none) / `--help` | print usage, exit 0 |
| `--version` | print version, exit 0 |
| `new <name>` | `cli.clinew` (usage error → 1) |
| `serve` | `cli.runserve(".")` |
| `build` | `cli.runbuild(".")` |
| `build --cli [path]` | `run.build(path)` |
| `run [path] [args…]` | `run.run(path; args)` |
| `compile [path]` | gen app Makefile + `make -f Makefile.serve` |
| `gen <type> <name>` | `cli.cligen` |
| `gen spec <container> <type>` | `cli.cligenspec` |
| `repair <file>` | `repair.repairfile(path; 10)` |
| anything else | unknown-command message + usage, exit 1 |

## Constants

None.

## Control Flow

A single nested `if/el` ladder over the first argument, each leaf returning an
exit code via short-return `<`. The `run` command loops argv[3..] into a mutable
`@$str` to forward to `run.run`. The `compile` command is a linear sequence of
`process.spawn`/`process.wait` steps, each guarded for failure. No recursion.

## Notes

- **Thin entry only.** No command logic lives here; every branch forwards to a
  library function. This honours toke's "small, multiple files" goal and keeps
  `f=main` isolated to one module.
- **Canonical `$ok`/`$err`** in every argv `mt` match; `str.eq` for all command
  comparisons.
- Replaces the previous `main.tk`, which was module `ooke.cli` and combined entry
  + logic + `f=main` (the source of the cli-test link collision).
