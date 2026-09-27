# ooke's public API surface: what is stable, what is internal

Story 134.10. Semver applies to §1 and to nothing else. If it is not listed in
§1, a patch release may change it without warning.

## 1. Stable — covered by semver from 3.0.0

### 1.1 The CLI

| Command | Contract |
|---|---|
| `ooke new <name>` | scaffolds `ooke.toml`, `pages/index.tk`, `templates/base.tkt`, `templates/index.tkt` |
| `ooke serve [path]` | serves the project at `path` (default: the working directory); templates resolve against the project (story 134.37) |
| `ooke build` | renders the project to the `[build] output` directory |
| `ooke compile [path]` | per-app serve binary with handlers compiled in |
| `ooke run [path]` | compile and run a CLI package |
| `ooke build --cli [path]` | CLI binary only |
| `ooke gen <type> <name>` | scaffold a component (e.g. `gen island counter`) |
| `ooke repair <file>` | diagnose a compiler error and suggest a fix |
| `--help`, `--version` | on every command; `--version` prints `ooke <VERSION>` |

Exit status is part of the contract: **0 on success, non-zero on failure.**
`ooke build` exits 1 with a diagnostic naming the cause, and reports API routes
under `pages/api/` as deliberately excluded from the static build rather than
failing on them (story 134.24).

`--help` being answered before dispatch is itself a 3.0.0 fix: `ooke serve
--help` used to start a server (story 134.19).

### 1.2 `ooke.toml`

The `[site]`, `[build]`, `[server]`, `[log]`, `[paths]` and `[requires]`
sections, and the keys ooke reads from them. (`[store]` is not among them: its
one key, `backend`, selected nothing and was removed in 3.0.0 — story 134.34.) Key names follow the
**no-underscore convention** (`inlinecss`, `accessformat`, `apiprefix`,
`mintokecommit`) — toke's Profile-1 character set excludes `_`, so this is a
language constraint, not a style choice.

Note `[requires]` is a floor, and **a floor may be raised in a minor release**
when ooke adopts a new toke feature. That is the one documented exception to
semver here, and 134.16 exercised it: the floor moved 2.5 months in a day.

### 1.3 Project layout and template syntax

`pages/` file-based routing (including `[slug].tk` dynamic segments), the
`templates/*.tkt` syntax (layout inheritance, blocks, partials, filters,
`{! island(...) !}`), `content/` Markdown-with-frontmatter, `models/`
validation models, `static/`. Described in `README.md` and
`docs/extension-api.md`.

**Template output is escaped by default** from 3.0.0 (ADR-0011). Raw
interpolation needs `{{raw ...}}`. Any 2.0.0 template that relied on raw
output changes meaning — silently producing escaped text rather than failing.

## 2. Internal — no compatibility promise

- **`src/ooke.*.tki` and `src/ooke/*`** — the module interfaces and emitted IR.
  These are how loke imports `ooke.router`, `ooke.config` and three others at
  about 30 sites (story 134.11). They are **not** a supported API: they exist to
  build the ooke binary, they change with ooke's internals, and nothing tests
  them as a consumer surface. If you import them, pin an exact ooke commit and
  expect to follow it. Making them supportable is not scheduled.
- **`src/_handlers.tk`** — generated from `pages/` by `scripts/gen_handlers.sh`
  on every build. Build output: not tracked, ignored, and removed by
  `make clean` (story 134.22).
- **The handler registry and toke's import cap** (story 138.7). The registry
  an app gets from `ooke compile` (`<project>/_handlers.tk`) is one module that
  imports every handler page plus `std.http`. toke caps a module at 32 imports
  unless told otherwise (`E9010`, "compiler limit exceeded: too many imports"),
  so an app with more than 31 handler pages used to stop compiling. The
  generated `Makefile.serve` now compiles that one module with
  `--max-imports=<its import count>` whenever the count is above 32, and
  leaves the compile line alone otherwise. You do not need a `tkc.toml`
  setting for it. `test/serve/many_pages.sh` builds and serves a 40-page app.
- **`test/support/ookeassert.tk`** — ooke's own test helper. Tracked so a clone
  can run the suite (story 134.21), not published for reuse.
- **Everything in `bench/`, `scripts/`, `testproj/`.**
- **The toke stdlib.** ooke links about 75 of toke's C stdlib translation units,
  but it does not re-export them. The nine native binding modules loke asked for
  live in **toke's** stdlib, not ooke's, and ooke exposes none of them — that
  was the structural finding of story 134.11, and it is why requests about them
  belong to toke (Epic 136), not here.

## 3. What a consumer should actually pin

    ooke   3.0.0-rc.2   (a git tag, or the release tarball + its SHA256)
    toke   668caa6      (a commit: toke 3.0.0 is below ooke's floor; story 138.7)

Both, together. Pinning ooke without pinning toke pins nothing: ooke is
source-compiled against whatever toke you have, and the floors — compile,
behaviour and installable — span 2.5 months (`docs/versioning.md` §1).
