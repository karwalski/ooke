---
source_file: "cli.tk"
source_hash: "fb779961bda25fbbdea3bc20fb76ef6beca8e236cb4f7a4c9a3bb1613310b31c"
compiler_version: "0.3.9"
generated_at: "2026-06-16T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.cli`

The ooke CLI **command-logic library**. It holds every command implementation
(scaffolding, code generation, config defaults, serve/build dispatch) as plain
exported functions with **no `f=main`**, so it is independently testable and
linkable. The binary entry point lives in the separate `ooke.main` module
(`main.tk`), which imports this module and dispatches argv to these functions.

This split exists because toke links a single `f=main` per program: when the
old `main.tk` was itself module `ooke.cli` *and* defined `f=main`, the cli test
(which has its own `f=main`) collided at link. toke does not support multiple
source files contributing to one module (verified: a function in one `m=ooke.cli`
file cannot reference a function in another `m=ooke.cli` file — E3011), so the
logic was moved here as `ooke.cli` and the entry kept as `ooke.main`.

**Imports:**
- `std.str` (`str`) — string building (`concat`, `eq`, `fromint`, `len`).
- `std.file` (`file`) — scaffold directory/file creation.
- `std.log` (`log`) — user-facing output.
- `std.path` (`path`) — path joining.
- `ooke.config` (`config`) — `configload` + the `$ookecfg` type.
- `ooke.serve` (`serve`) — `serverun` for the dev server.
- `ooke.build` (`build`) — `buildrun` + the `$buildreport` type.
- `ooke.handlers` (`handlers`) — `registerall` dynamic-handler registry.

## Functions

- `cliprintusage(): void` — print the help/usage banner.
- `cliprintversion(): void` — print the version string.
- `clinew(name: $str): i64` — scaffold a new project tree (`pages/`,
  `templates/`, `content/`, `static/`, `ooke.toml`, a starter page and base
  template). Returns 0.
- `cligen(gentype: $str; genname: $str): i64` — scaffold a component. `gentype`
  is `page` | `type` | `api` | `island`; unknown types log and return 1.
- `retcolon(t: $str): $str` — codegen helper: returns `"):" + t`, the shared
  parameter-list-close + return-type fragment used by the spec generators.
- `specstack / specqueue / specset(t: $str; name: $str): $str` — generate the
  full toke source for a type-specialised stack / queue / set wrapper module.
- `cligenspec(container: $str; typename: $str): i64` — write a specialised
  container module file. `container` is `stack` | `queue` | `set`; unknown
  containers log and return 1.
- `cfgdefault(): $ookecfg` — return a fully-populated default `$ookecfg`, used
  as the fallback when `ooke.toml` cannot be loaded.
- `runserve(projectdir: $str): i64` — load config (or default), register dynamic
  handlers, and run the dev server. Returns the server exit code.
- `runbuild(projectdir: $str): i64` — load config (or default), run the static
  build, and report page/asset counts and validation errors/warnings.

## Constants

None.

## Control Flow

`cligen` and `cligenspec` are nested `if/el` dispatchers on a string tag, each
arm writing one file and returning 0, with a trailing unknown-tag arm returning
1. The `spec*` generators are linear `str.concat` accumulations of code
fragments. `runserve`/`runbuild` are linear: load-or-default config, then a
single fallible call matched `{$ok…;$err…}`. No loops except the scaffold
sequences; no recursion.

## Notes

- **Canonical result form.** All `mt` match arms use the spec-canonical
  `$ok`/`$err` variant names (toke-spec-prompt.md). The previous source used the
  non-canonical `Ok`/`Err`.
- **String comparison via `str.eq`.** Dispatch on command/type/container strings
  uses `str.eq(a;b)` (the published equality primitive) rather than `a=b`.
- **Dropped unused imports.** The old combined `main.tk` imported `std.args`,
  `std.http`, `std.process`, `ooke.repair`, `ooke.apihealth`, and `ooke.run`.
  Of these only argv/process/repair/run dispatch belongs to the entry point, so
  they now live in `ooke.main`; `std.http`/`ooke.apihealth` were unused and are
  dropped entirely.
- **`cfgdefault` is BLOCKED on a toke codegen bug (Track B).** This function is
  correct as written, but when its returned `$ookecfg` (a type defined in the
  third module `ooke.config`) is read by a *caller in yet another module*, every
  field is misread (all `$str` fields alias field 0; all `i64` fields read one
  shared garbage word). The 2-module path (`ooke.config` → caller) is fine; only
  the 3-module return path is corrupt. `test_cli.testcfgdefault` fails on this.
  No workaround applied per the NO-WORKAROUNDS rule. The same path affects
  `runserve`/`runbuild` reading `config.configload`'s result.
