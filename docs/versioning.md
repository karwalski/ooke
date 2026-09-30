# ooke versions, the toke floor, and the compatibility promise

Story 134.7. Everything here is evidenced by a build, not by assertion: each claim
below names the toke commit that was checked out, built, and run against ooke's
current sources on 2026-09-19.

## 1. The toke version ooke actually needs

`ooke.toml [requires]` is the single source of truth, and it carries three keys,
not one:

```toml
[requires]
mintoke       = "3.1.0"
mintokedate   = "2026-10-01"
mintokecommit = "db47d591"
```

(Raised for rc.2 by story 138.7, set to toke's 3.1.0 release by story
138.17, and raised past that release to an unreleased toke commit by story
121.59 (3) — see "Two more floors", "The release floor" and "The realpath
floor" below. The history
that follows is the rc.1 record and is kept as evidence.)

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

### Known imprecision — RESOLVED, and the floor moved (story 134.16)

The table above proves a **compile** floor. Story 134.16 tested the other half and
the answer was no.

ooke's suite became honest on 2026-09-19 (134.5 made it run at all, 134.17 turned
157 inert `test.eq` calls into 187 live assertions, each proved capable of failing
by mutation). It was then re-run against a tkc built at `b66bd8e`:

| toke | ooke suite |
|---|---|
| `b66bd8e` 2026-07-06 — the 134.7 compile floor | **10 of 12** |
| `c2aa278` 2026-09-19 | **12 of 12** |

Failures at `b66bd8e`:

- `test_config` — `build.minify: got true, want false`, `build.inlinecss: got
  true, want false`. A TOML `false` is read back as `true`.
- `test_router` — `RT005: nil dereference`, a hard runtime abort.

**The compiler is the cause, not the stdlib.** Crossing the two trees isolates it:

| tkc | stdlib C | result |
|---|---|---|
| `b66bd8e` | HEAD | fails, identically |
| HEAD | `b66bd8e` | passes |

Bisected across 293 commits (9 steps, each a `make clean` rebuild of tkc — an
incremental rebuild across commits produces a compiler that is neither endpoint,
see §6). **First commit at which the suite passes: `c2aa278` (2026-09-19),
"fix(llvm): consume @tk_current_error for toml.bool and toml.i64, so false and 0
are values".** Confirmed minimal against the whole tree, not just the compiler:
at `c2aa278` ooke is 12/12; at its parent `beff3db` it is 11/12. (`test_router`
passes at `beff3db`, so the RT005 abort was fixed earlier in the range; the
binding constraint is the TOML one.)

### A third floor, found by packaging from a clone (story 134.10)

`c2aa278` is where ooke's behaviour becomes correct. It is **not** a commit a
consumer can use, and the reason is the same defect class as ooke's own 134.21.

A fresh `git clone` of toke at `c2aa278` has **no `stdlib/vendor` directory at
all**. toke's story 127.85 — which tracks the vendored cmark and tomlc99 so a
clone can build `std.toml` and `std.md` — is commit `6cc9061`, *later* than
`c2aa278`. Before it, those sources were ignored: present in every working
tree, absent from every clone, and the build dies in clang with an opaque
`E9003` that names neither the dependency nor the cure.

So there are three floors, and the declared one is the highest:

| Floor | Commit | Date | Means |
|---|---|---|---|
| compile | `b66bd8e` | 2026-07-06 | ooke's sources compile (134.7) |
| behaviour | `c2aa278` | 2026-09-19 | ooke's suite passes (134.16) |
| **installable** | **`6cc9061`** | **2026-09-19** | **a clone of toke builds at all (127.85)** |

Verified from clean clones of both repositories outside the development tree,
with no overrides: toke at `6cc9061` builds from a plain clone; ooke builds
against it by the documented default (toke checked out beside ooke); `make
test` is 12/12; `ooke new` + `ooke build` exits 0 and writes `build/index.html`.

The lesson is the one 134.21 and 127.85 already taught and this floor had not
yet learned: **a floor that has only ever been tested in a tree which already
had the files is untested.** Both earlier floors were established by checking
out a commit into a directory that still had an untracked `stdlib/vendor` from
a previous build.

**What the old floor was claiming.** `minify` and `inlinecss` live in
`ooke.toml`, so on any toke between `b66bd8e` and `c2aa278` a site that
configures `minify = false` is silently minified anyway — the configuration is
obeyed as its opposite, with no diagnostic. `ooke.toml [requires]` declared
support for that range. It no longer does:

```toml
mintoke       = "2.8.0"
mintokedate   = "2026-09-19"
mintokecommit = "6cc9061"
```

**Both floors are real and they are 2.5 months apart.** Keep the distinction:
`b66bd8e` is the earliest toke that *builds* ooke, `c2aa278` the earliest that
*runs* it correctly. `[requires]` carries the higher one, because a build that
produces a binary which misreads its own configuration is not support.

### Two more floors: toke 3.0.0 is not enough (story 138.7)

toke cut `3.0.0` (tag `v3.0.0` = `0b0bc4e`, 2026-09-23), resolving 134.15. It
does not run ooke. Measured on 2026-09-28 with each toke built in a fresh
worktree (tracked files only, as a clone gets) and ooke main's full `make
test`:

| toke | result |
|---|---|
| `0b0bc4e` = v3.0.0 | suite **11/12** — `test_template`: the template cache never stores (ooke main `b5b198f`) |
| `cee7cc0` (2026-09-27) | every `make test` target passes (ooke `b5b198f`, and rc.2 before `[server] host`) |
| `512f904` (main, 2026-09-27) | every `make test` target passes (ooke `b5b198f`, and rc.2 before `[server] host`) |
| `18b9f73` (main, 2026-09-28; `668caa6` + tracker docs) | every `make test` target passes on rc.2 as shipped, `[server] host` included |

The binding defect is toke's 127.226: `.set` on a map-typed struct field
lowered as an array `.set`, a silent no-op, so `tplrenderfilecached` never stored and
every render re-read its template. Fixed by Batch DA, merged as `cee7cc0`.

Then rc.2 gained `[server] host` (loke handoff O-3), which binds through
toke's `http.serveworkerson` and `http.servetlson` — toke story 138.1, merged
as `668caa6`. No earlier toke has them, so rc.2 as shipped does not compile
before `668caa6`, and `cee7cc0` stops being the floor. So:

| Floor | Commit | Date | Means |
|---|---|---|---|
| compile | `b66bd8e` | 2026-07-06 | ooke's sources compile (134.7) |
| behaviour | `c2aa278` | 2026-09-19 | rc.1's suite passes (134.16) |
| installable | `6cc9061` | 2026-09-19 | a clone of toke builds at all (127.85) |
| cache | `cee7cc0` | 2026-09-27 | the template cache stores (127.226) |
| **host** | **`668caa6`** | **2026-09-28** | **`[server] host` compiles (138.1); the suite passes** |

`mintoke = "3.0.0"` was meaningful — it refused every 2.8.0-labelled toke —
but it was not sufficient, because `v3.0.0` itself is below the floor.

### The release floor (story 138.17, 2026-09-30)

toke **3.1.0** is the first toke release that contains `668caa6` (and so
`cee7cc0`). Measured: ooke rc.2's full `make test` against toke
`release/3.1.0` (`toke 3.1.0`) exits 0 — every target, suite 12/12, the
40-page registry built with `--max-imports=41`. So `mintoke = "3.1.0"` is now
sufficient on its own. `mintokecommit`/`mintokedate` name `216965f`
(2026-09-30), the commit that set toke's `VERSION` to 3.1.0 and an ancestor of
the release; they stay only because CI clones toke at `mintokecommit`, and can
be dropped (and the Makefile gate simplified) once `v3.1.0` is published.

Not measured: whether any commit between `v3.0.0` and `cee7cc0` also passes.
127.226's fix commits reach toke's main only through the `cee7cc0` merge,
and toke's 127.226 row records ooke's `test_template` failing on main from
`25e55f5` until that merge, so no earlier main commit is a floor ooke should
declare.

### The realpath floor (story 121.59 (3), 2026-10-01)

ooke now resolves partial and layout paths with toke's `file.realpath` (toke
story 121.60) so a symlinked directory inside `templates/` cannot lead a read
outside it, and links `os_glue.c`, where toke 121.70 moved `os.write`'s
wrapper (`tk_os_write_w`; without it ooke fails to link against toke main).
Both arrived in toke merge `db47d591` (2026-10-01), which is **not in any
released toke**: 3.1.0 has neither. So `mintoke = "3.1.0"` is necessary but
no longer sufficient, and the commit/date pair is the enforceable floor again.
Measured: ooke's `make test` passes against toke main containing `db47d591`.
When toke releases a version containing `db47d591`, set `mintoke` to it.

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
- `check-ooke-version` fails if `src/cli.tk` hard-codes a version rather than
  printing `floor.ookeversion()`, which the Makefile generates from `VERSION`
  (story 121.66), or if `VERSION` is not a plain version string. It began as a
  check that `VERSION` and a literal in `src/cli.tk` agreed, because they
  disagreed for three months; the literal is gone, so they cannot.
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

`VERSION` is **3.0.0-rc.2** (rc.1 was prepared 2026-09-19, rc.2 on 2026-09-28). The last release was **2.0.0** (2026-06-21, the
pure-toke rebuild). Since then ooke has taken changes that break consumers:

- migration to v0.4 syntax (`==`, expression-`if`) — **a project's own `pages/`
  sources must be v0.4 too**, so 2.0.0-era user code does not compile;
- escape-by-default in the template engine (ADR-0011) — templates that relied on
  raw interpolation now escape unless they use `{{raw ...}}`;
- a baked capability grant set with `enforce = true` (ADR-0010);
- the 134.8 build changes (static generation of the docs tree, explicit failure
  instead of RT005).

That is a major bump: the next release is **3.0.0**, prepared by story 134.10. The
`-dev` suffix is deliberate — 3.0.0 is **not released yet**.

Gate status as of 2026-09-19:

| Gate | State |
|---|---|
| 134.2 checkability | done — `tkc --check -I src` 30/30 |
| 134.3 lint | done — warnings 96 → 2, errors 0 |
| 134.5 suite runs | done — 12/12 on 187 live assertions |
| 134.17 assertions are real | done — every one proved able to fail, by mutation |
| 134.7 / 134.16 floor | done — floor measured for build *and* behaviour |
| 134.13 RSS leak | superseded → 127.65; diagnosed as **not ooke's** |
| 134.24 `ooke build` aborts on API routes | fixed 2026-09-19, verified end to end |
| 134.15 toke has never cut a v0.4 version | resolved — toke tagged `v3.0.0` (2026-09-23) |
| 138.7 toke 3.0.0 fails ooke's suite (127.226) and lacks the host-binding serve functions (138.1) | resolved — toke 3.1.0 contains both; the floor is `mintoke = "3.1.0"` (138.17) |

**134.15 is why the artefact prepared by 134.10 is a release *candidate* and not
a release**: ooke cannot express its one hard dependency as a version, only as a
commit. See `docs/release-notes-3.0.0.md`.

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
  (it previously wrote no floor at all). That block is generated at build time
  from this repository's `ooke.toml [requires]` (`src/_floor.tk`, story 134.35);
  it used to be a second, hand-kept copy in `src/cli.tk`, which was left at the
  `b66bd8e` compile floor after the declared floor moved to `6cc9061`.

## 5. For downstream projects (loke, moke, toke-website)

**Use toke 3.1.0 or later, and wait for ooke 3.0.0.** (Updated for rc.2,
stories 138.7 and 138.17; the rest of this section is the rc.1 record.)

The floor is `6cc9061`, not `b66bd8e`: 134.16 raised it to `c2aa278` once ooke's
suite could be run against an older compiler, and 134.10 raised it again to
`6cc9061`, the earliest toke a consumer can actually clone and build. See §1.

- **toke**: no tagged release contains what ooke needs. The newest release,
  2.8.0 (2026-06-21), cannot compile ooke. What is unreleased: the v0.4 syntax
  break, ADR-0010 capabilities, ADR-0011 escaping, `std.fmt`, the lint rules, and
  every 127.x fix — three months of work under an unbumped version string. A
  downstream project must build toke from `main`, or wait for toke to cut the
  version bump the v0.4 break requires (proposed 3.0.0; see the report for story
  134.7).
- **ooke**: released 2.0.0 is not the ooke this repo builds and is not what loke
  should target. Wait for **3.0.0**. Story 134.10 has prepared the artefact and
  the instructions, and the P0 that blocked it (134.24) was fixed and verified
  while it was being prepared. What 3.0.0 now waits on is **134.15** — an owner
  decision in *toke*, not a defect in ooke. See `docs/release-notes-3.0.0.md`
  and `docs/install.md`.

## 6. A method note, because it changed a result

The bisect in §1 first reported its own known-good endpoint as broken. The cause
was toke's incremental build: after `git checkout` of a different commit,
`make -j8` produced a `toke` binary that behaved like neither commit, and the
suite failed against it. `make clean && make` at the same commit passed. Every
measurement above therefore rebuilds tkc from clean, and any future
"which toke commit does X" question must do the same — an incremental rebuild
across commits is not evidence about either commit. Filed for toke as a
build-correctness defect (see the 134.16 report).
