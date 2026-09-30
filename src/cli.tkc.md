---
source_file: "cli.tk"
source_hash: "75257b656cf33ac7abf7fc734c11c3a2b372b9622ca461483ed9ef4d2826569f"
compiler_version: "3.0.0"
generated_at: "2026-10-01T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.cli`

The ooke CLI **command-logic library**. It holds every command implementation
(usage and help text, scaffolding, code generation, config defaults, and the
`serve`/`build` drivers) as plain exported functions with **no `f=main`**, so
it is independently testable and linkable. The binary entry point is the
separate `ooke.main` module (`main.tk`), which imports this module and
dispatches argv to these functions.

The split exists because toke links a single `f=main` per program: when the old
`main.tk` was itself `ooke.cli` *and* defined `f=main`, the cli test (with its
own `f=main`) collided at link. toke does not let two source files contribute
to one module (a function in one `m=ooke.cli` file cannot reference one in
another — E3011), so the logic lives here and the entry is `ooke.main`.

**Imports:**
- `std.str` (`str`) — string building and comparison (`concat`, `join`, `eq`,
  `fromint`, `len`).
- `std.file` (`file`) — scaffold directory/file creation; `file.exists` for
  `ooke.toml`.
- `std.log` (`log`) — user-facing output (usage, help, progress, errors).
- `std.io` (`io`) — `io.println` for `--version` (stdout, story 134.43).
- `std.path` (`path`) — path joining.
- `ooke.config` (`config`) — `configload`, `configadmin`,
  `configlogunsupported`, and the `$ookecfg` type.
- `ooke.serve` (`serve`) — `servetlscheck`, `serveopenlogs`, `serverun`.
- `ooke.floor` (`floor`) — `floortoml()`, the `[requires]` block for a new
  project, generated from ooke's own `ooke.toml` (`src/_floor.tk`, 134.35);
  and `ookeversion()`, generated from `VERSION` (121.66).
- `ooke.build` (`build`) — `buildrun` and the `$buildreport` type.
- `ooke.handlers` (`handlers`) — `registerall`, the dynamic-handler registry.

## Types

None defined here. Uses `$ookecfg` (ooke.config) and `$buildreport`
(ooke.build).

## Functions

### Usage and help

#### `cliprintusage(): i64`

Log the usage banner (commands `new`, `serve`, `build`, `gen`, `gen spec`,
`repair`, `compile`, `run`, `build --cli`; options `--help`, `--version`) one
`log.info` line each. Returns 0.

#### `cliishelp(arg: $str): bool`

Is `arg` a request for help: `--help`, `-h` or `help`. Story 134.19:
`ooke serve --help` used to fall through and bind a port, so `main.tk` asks
this before it dispatches.

#### `cliprintcmdusage(cmd: $str): i64`

The help for one command — `serve`, `build`, `new`, `gen`, `repair`, `run`,
`compile` — logged with `log.info`, returning 0. Any other `cmd` falls back to
`cliprintusage()`. The `serve` and `build` text says the project path defaults
to the current directory and that templates (and `[build].output`) resolve
against the project, not the working directory.

#### `cliprintversion(): i64`

`io.println(str.concat("ooke ";floor.ookeversion()))` — on stdout, exactly
`ooke <VERSION>` (story 134.43, public-api.md §1.1; it was a JSON log record
on stderr). Returns 0. `floor.ookeversion()` is generated from `VERSION` by
the Makefile into `src/_floor.tk` (story 121.66; it was a literal here that
had to be bumped beside `VERSION`). `make check-ooke-version` fails if this
file hard-codes a version again.

### Scaffolding

#### `climkdir(p: $str): bool` and `cliwrite(p: $str; content: $str): bool`

`file.mkdir(p)` (which is `mkdir -p`) or `file.write(p;content)`, as `true`
on success. On failure each logs, at error, `could not create directory <p>`
or `could not write <p>` and returns `false`. Every scaffolding step below
goes through one of them and stops with 1 on `false` (story 121.66: every
result was discarded and "Created" was logged regardless).

#### `clinew(name: $str): i64`

Scaffold a new project at `name`:

1. `climkdir` `name` and its `pages/`, `templates/`, `content/`, `static/`.
2. Write `ooke.toml`: `[site]` (name, empty url, `en`), `[build]`
   (`build/`, minify and inlinecss on), `[server]` (`host = "127.0.0.1"`,
   port 3000, workers 0), `[paths]` (empty apiprefix), `[log]`
   (`access = "-"`, `accessformat = "combined"`), then `floor.floortoml()` —
   the `[requires]` block, generated rather than restated (134.35).
3. Write `pages/index.tk` (`m=pages.index;`).
4. Write `templates/base.tkt`, the Coin Gold page shell, which yields `title`
   and `content`, and `templates/index.tkt`, which declares
   `{! layout("base") !}` and fills both blocks (story 134.24: the scaffold
   used to write only `base.tkt`, in a `{{…}}` syntax ooke does not have, so
   the route `/` had no `templates/index.tkt` and a new project could not be
   built).
5. Log `Created project: <name>` and return 0.

Each directory and file goes through `climkdir`/`cliwrite`; the first failure
returns 1 (logged, naming the path) with no "Created" line.

#### `cligen(gentype: $str; genname: $str): i64`

Scaffold one component, relative to the working directory:

| `gentype` | Writes |
|-----------|--------|
| `page` | `pages/<name>.tk` = `m=pages.<name>;` |
| `type` | `models/<name>.toml` (mkdir `models/`) with `name` and `title`/`slug` required `str` fields |
| `api` | `pages/api/<name>.tk` = `m=pages.api.<name>;` (mkdir `pages/api/`), then logs a hint on wiring a handler |
| `island` | `islands/<name>.tk` = `m=islands.<name>;` (mkdir `islands/`) |

Each logs `Created <kind>: <path>` and returns 0 once its `climkdir` and
`cliwrite` succeed; a failed one returns 1 (logged, naming the path) with no
"Created" line -- e.g. `ooke gen page x` with no `pages/`. An unknown type
logs `unknown gen type: <type>` and returns 1.

### Type-specialised containers (`ooke gen spec`)

#### `retcolon(t: $str): $str`

`"):" + t` — the parameter-list close and return type shared by the
generators.

#### `specstack(t: $str; name: $str): $str`

The toke source of module `name`: `i=stk:std.stack;`,
`t=$<name>=stk.$stack;`, and `new`, `push(s;val:t):t`, `pop`, `peek` (`:t`),
`len`, `empty` (`:i64`), each casting to `stk.$stack` and delegating to
`stk.stack.*`.

#### `specqueue(t: $str; name: $str): $str`

As `specstack` over `std.queue` (`que`): `new`, `push`, `pop`, `peek`, `len`.

#### `specset(t: $str; name: $str): $str`

As `specstack` over `std.set` (`st`): `new`, `add(s;val):t`,
`has(s;val):i64`, `remove(s;val):t`, `len`.

#### `cligenspec(container: $str; typename: $str): i64`

`name = container + typename`; write `<name>.tk` in the working directory from
`specstack` / `specqueue` / `specset` for `stack` / `queue` / `set` with
`cliwrite` (a failed write returns 1, no "Created"), log
`Created specialised: <file>`, return 0. Any other container logs
`unknown container: <c>, expected: stack, queue, set` and returns 1.

### Config

#### `cfgdefault(): $ookecfg`

A fully-populated `$ookecfg` with the same defaults `config.configload`
applies: `my-site`, `""`, `en`; `build/`, minify and inlinecss `true`; port
3000, host `127.0.0.1`, workers 0, corsorigins `""`; `[log]` access `-`, error
`""`, format `combined`; tls cert/key `""`; apiprefix `""`. Used only as the
unreachable `$err` arm after `clicfgloads` has succeeded.

#### `clicfgloads(cfgpath: $str): bool`

Story 134.42. `true` if there is no file at `cfgpath` (a missing `ooke.toml`
means "use the defaults"), else whether `config.configload` succeeds. A
present file that fails to load used to be served or built with the defaults,
silently.

#### `clireportcfgerr(cfgpath: $str): i64`

Log at error that `<cfgpath>` could not be read or is not valid TOML, that
ooke refuses to fall back to defaults, and how to proceed. Returns 1. It names
the file and the cause class rather than the parser's message, which toke
cannot surface (E4034 on toke main, RT005 at the floor; `!$configerr`
propagation drops it).

#### `clireportserveerr(): i64`

Log `serve did not start — see the error above` at error; return 1. The reason
itself is logged by serve.tk where it fails: reading `e.msg` off the payload
traps RT005 (toke 127.78, open).

### Commands

#### `runserve(projectdir: $str): i64`

1. `cfgpath = projectdir/ooke.toml`; if `!clicfgloads(cfgpath)`, return
   `clireportcfgerr(cfgpath)`.
2. Load the config (the `$err` arm is `cfgdefault()`).
3. `serve.servetlscheck(projectdir; tlscert; tlskey)`; on failure return
   `clireportserveerr()` (134.40).
4. `config.configadmin(cfgpath)` (121.25, OOK-03): `"true"` logs an error —
   ooke has no admin interface, nor authentication, sessions, CSRF protection
   or rate limiting — and returns 1; `"false"` warns that the key is ignored.
5. `config.configlogunsupported(cfgpath)`: a non-empty result warns that those
   `[log]` keys are ignored (ooke does not rotate logs).
6. `serve.serveopenlogs(projectdir; logaccess; logerror; logaccessformat)`; on
   failure return `clireportserveerr()`.
7. `handlers.registerall()`, logging `auto-registered <n> handler routes`.
8. `serve.serverun(projectdir; host; port; workers; output; tlscert; tlskey;
   sitename; siteurl; sitelanguage; apiprefix; corsorigins; handledpaths)`:
   `$ok` → 0, `$err` → `clireportserveerr()` (serverun fails rather than start
   with no routes, 134.18).

#### `runbuild(projectdir: $str): i64`

1. As `runserve` steps 1–2.
2. `build.buildrun(projectdir; cfg)`; an `$err` becomes a report with
   `pagesbuilt = -1`.
3. `pagesbuilt < 0`: log at error that the build failed for `projectdir` and
   no site was written, pointing at the error build.tk logged where it was
   raised (134.24 — the payload's `e.msg` cannot be read, RT005); return 1.
4. Log `pages built` and `assets copied`; log validation errors and warnings
   when non-zero.
5. `pagesskipped > 0`: log `pages skipped: <n> — build failed` at error and
   return 1.
6. `assetsfailed > 0`: log `assets not copied: <n> — build failed` at error
   and return 1 (121.67). Otherwise return 0.

## Control Flow

`main.tk` calls `cliishelp`/`cliprintcmdusage` before dispatch, then one of
`clinew`, `cligen`, `cligenspec`, `runserve`, `runbuild`. `cligen` and
`cligenspec` are nested `if/el` dispatchers on a string tag with an
unknown-tag arm returning 1; the `spec*` generators are linear string
concatenations. `runserve` and `runbuild` are linear sequences of checks that
each return 1 on refusal. No loops, no recursion.

## Notes

- **Canonical result form.** All `mt` arms use `$ok`/`$err`.
- **String comparison via `str.eq`** for command/type/container dispatch
  (`admin=="true"` in `runserve` uses `==`).
- **Errors are logged where they happen.** The payloads of `$configerr`,
  `$serveerr` and `$builderr` cannot be read from here (RT005, toke 127.78), so
  the callee logs the reason and this module logs the consequence.
- **`cliprintcmdusage("gen")` lists every gen type `cligen` accepts**: `page,
  type, api, island` (story 121.66; it listed `page, type`).
