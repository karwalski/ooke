# ooke versions, the toke floor, and the compatibility promise

Story 134.7. Everything here is evidenced by a build, not by assertion: each claim
below names the toke commit that was checked out, built, and run against ooke's
current sources on 2026-09-19.

## 1. The toke version ooke actually needs

`ooke.toml [requires]` is the single source of truth, and it carries three keys,
not one:

```toml
[requires]
mintoke       = "2.8.0"
mintokedate   = "2026-07-06"
mintokecommit = "b66bd8e"
```

**A semver floor alone is meaningless for toke today.** `toke/VERSION` has read
`2.8.0` since commit `f1e30b3` (2026-06-21). Everything since — the whole v0.4
syntax break (Epic 116), the ADR-0010 capability model and ADR-0011
escape-by-default (Epic 124), the lint rules and the pattern catalogue — shipped
under that same string. So "2.8.0" names both a compiler that cannot build ooke
and one that can. Until toke bumps its version, the enforceable floor is the
commit.

### The evidenced floor, step by step

| Step | Feature ooke depends on | Introduced by | Evidence |
|---|---|---|---|
| 1 | `std.queue` / `std.set` / `std.stack` | toke **2.6.0**, `f7fe774` (2026-04-30) | `src/` imports all three |
| 2 | `str.fromint` | `75dffd8` (2026-06-01, pre-2.8.0) | used in `cli.tk`, `build.tk` |
| 3 | `=` / `==` split (Epic 116.3/A3) | `335113d` (2026-07-01), **after the 2.8.0 release** | 55 `==` in `src/`; released 2.8.0 emits W2021 "`'=='` detected; toke uses `'='` for equality" on every one |
| 4 | expression-oriented `if` (Epic 116.1/A1) | `3bc1dbb` (2026-07-01) | released 2.8.0 rejects `src/store.tk:148` with **E2002 "unexpected token in expression, got 'if'"** — a hard error, not a warning |
| 5 | `capabilities.c` as a link dependency (ADR-0010, 124.4a/f) | `8c073a6` / `8dd3149` (2026-07-06) | the `Makefile` link line names `$(TOKE_STDLIB)/capabilities.c`; it does not exist in any earlier toke |
| 6 | **`src/tkc.toml [capabilities]` manifest parsed and baked (ADR-0010, 124.4b)** | **`b66bd8e` (2026-07-06)** | **this is the floor.** Any earlier tkc aborts before parsing a single line of toke: `tkc: tkc.toml:9: expected key = value` |

**Result: the earliest toke that builds current ooke is `b66bd8e`, 2026-07-06.**
Verified by building tkc at that commit and running a full `make` of ooke against
it: clean build, working binary, `ooke new` scaffolds a project. The same test at
`8c073a6` (six commits earlier, same day) fails on `tkc.toml`, and at the released
`2.8.0` (`f1e30b3`) fails at the language level. The ceiling is toke HEAD, which is
what 134.6 and 134.8 were measured and built against.

### Known imprecision

The floor is proven for *building*. ooke's **runtime** behaviour has only ever been
exercised against toke HEAD: several 127.x stdlib and codegen fixes landed on
2026-09-19 (interpolation allocation, array dispatch, map semantics, json
printing), and no one has run ooke's tests against a floor-era compiler — ooke's
test suite has never been executed at all (story 134.5). Treat `b66bd8e` as the
**compile** floor and toke HEAD as the only **tested** compiler until 134.5 is
green and can be re-run at the floor.

## 2. How the floor is enforced

It used to be decorative: `Makefile: check-toke-version` existed but was not a
prerequisite of anything, it compared major versions only, and it duplicated the
floor as `MIN_TOKE_VERSION := 2.0.0` next to `mintoke = "2.0.0"` in `ooke.toml`,
so the two could drift — and both were wrong by eight minor releases.

Now:

- `make` (i.e. `all`) and `make test` run `check-versions` **first**, via a
  sub-make so ordering holds under `-j`.
- `check-toke-version` reads the floor out of `ooke.toml` — no restated constant —
  and fails on any of: toke `VERSION` below `mintoke`; `capabilities.c` absent;
  the toke checkout not containing `mintokecommit`; or (for a shallow clone with
  no such object) a HEAD commit dated before `mintokedate`.
- `check-ooke-version` fails if `VERSION` and the version `src/cli.tk` prints
  disagree. That check exists because they disagreed for three months.
- CI runs `check-versions` before building, on push, on PR, **and on a daily
  schedule** so drift in toke HEAD is caught the day it happens. The release
  workflow runs it before packaging any tarball.

Proof that the gate bites, not just passes:

```
$ make check-toke-version TOKE_ROOT=<toke @ f1e30b3 (released 2.8.0)>
ERROR: .../capabilities.c is missing — that toke predates ADR-0010 (2026-07-06).
$ make check-toke-version TOKE_ROOT=<toke @ 8c073a6>
ERROR: toke 8c073a6 (2026-07-06) does not contain b66bd8e — ooke's floor.
```

## 3. ooke's own version

`VERSION` is **3.0.0-dev**. The last release was **2.0.0** (2026-06-21, the
pure-toke rebuild). Since then ooke has taken changes that break consumers:

- migration to v0.4 syntax (`==`, expression-`if`) — **a project's own `pages/`
  sources must be v0.4 too**, so 2.0.0-era user code does not compile;
- escape-by-default in the template engine (ADR-0011) — templates that relied on
  raw interpolation now escape unless they use `{{raw ...}}`;
- a baked capability grant set with `enforce = true` (ADR-0010);
- the 134.8 build changes (static generation of the docs tree, explicit failure
  instead of RT005).

That is a major bump: the next release is **3.0.0**, tagged by story 134.10. The
`-dev` suffix is deliberate — 3.0.0 is **not released yet**, and these are the
gates it waits on: 134.5 (the test suite has never run), 134.13 (~1.3 KB of RSS
leaked per request served — a web server that leaks per request cannot ship), and
134.2/134.3 (checkability and lint).

## 4. The compatibility promise

For 3.0.0 onwards:

- **Semver on the ooke surface**: the CLI (`ooke new|build|serve|run|gen`), the
  `ooke.toml` schema, the page/handler module layout, and the `.tkt` template
  syntax. A breaking change to any of those is a major bump.
- **Not covered**: anything under `src/ooke.*.tki` (internal module interfaces),
  `src/_handlers.tk` (generated), and the `[requires]` floor itself, which may be
  raised in a minor release when ooke adopts a new toke feature.
- **The toke floor is part of the contract**: a consumer pinning ooke 3.x must
  also honour `[requires]`. `ooke new` now writes a `[requires]` block into every
  scaffolded project, so a new project inherits the floor instead of having none
  (it previously wrote no floor at all).

## 5. For downstream projects (loke, moke, toke-website)

**Wait for toke `b66bd8e` (2026-07-06) or later — in practice, toke HEAD — and for
ooke 3.0.0.**

- **toke**: no tagged release contains what ooke needs. The newest release,
  2.8.0 (2026-06-21), cannot compile ooke. What is unreleased: the v0.4 syntax
  break, ADR-0010 capabilities, ADR-0011 escaping, `std.fmt`, the lint rules, and
  every 127.x fix — three months of work under an unbumped version string. A
  downstream project must build toke from `main`, or wait for toke to cut the
  version bump the v0.4 break requires (proposed 3.0.0; see the report for story
  134.7).
- **ooke**: released 2.0.0 is not the ooke this repo builds and is not what loke
  should target. Wait for **3.0.0** (story 134.10), which is blocked on 134.5,
  134.13, 134.2 and 134.3. 134.13 is the one that matters most for anything that
  serves traffic.
