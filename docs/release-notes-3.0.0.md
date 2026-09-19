# ooke 3.0.0-rc.1 — release notes

**Status: release candidate. Not published, not tagged.** Prepared by story
134.10 on 2026-09-19.

## Why this is a candidate and not 3.0.0

Every quality gate 3.0.0 was waiting on is now green — the suite runs and is
honest (134.5, 134.17), the sources check and lint clean (134.2, 134.3), the
toke floor is measured for build *and* behaviour (134.7, 134.16), and the RSS
leak turned out not to be ooke's (134.13 → toke 127.65).

One defect is not, and it is the first thing a new adopter hits.

## Known defects a consumer will meet

### 134.24 — `ooke build` aborts on any project with an API route, and `ooke new` scaffolds one. **P0, OPEN**

`routerscan` sets a flag marking a route as an API handler and the build never
reads it, so the handler is rendered as a template and the build aborts.

Reproduced on this candidate, from a fresh scaffold:

    $ ooke new demosite && cd demosite && ooke build
    {"level":"error","msg":"build failed"}
    $ echo $?
    1

The exit status is correct; the message is the whole diagnostic. The CLI
wrapper discards the error it already has and logs one word, so you are told
nothing about which route, which file, or why.

Bisected across four builds: works at `81b4fb3` and `b663797`, fails from
`e7a6f60`. But 134.2 **exposed** it rather than causing it — changing a `:void`
return to `:i64` made an error that had previously been swallowed start
propagating. The defect is older than the commit that reveals it, and
134.8's result of 195 pages at exit 0 no longer reproduces.

**What works meanwhile:** `ooke serve` (dynamic serving, including API routes),
`ooke new`, `ooke repair`, `ooke gen`, the template engine, the store, and the
whole module surface the tests cover. It is static generation of a project
containing an API route that fails. A project with no API route builds.

### 134.15 — toke has never cut a version for the v0.4 break. **P1, OPEN, owner decision**

You cannot pin toke by semver. `toke/VERSION` has read `2.8.0` since
2026-06-21, unchanged across the entire v0.4 language break, so the same string
names both a compiler that cannot build ooke and one that can. ooke's floor is
therefore a commit — `c2aa278`, 2026-09-19 — and `ooke.toml [requires]` carries
`mintokecommit` and `mintokedate` alongside `mintoke`. When toke cuts the
version, `mintoke` becomes sufficient and the other two keys can be dropped;
the Makefile gate reads all three from `ooke.toml` and nothing restates them,
so that is a one-file change.

Practical consequence: **you must build toke from source at a pinned commit.**
No released toke works. See `docs/install.md`.

### 134.16 — the floor you were previously told was wrong. **Fixed in this candidate**

Not a defect you will hit, but a correction you should know about if you read
an earlier version of `docs/versioning.md`. The declared floor `b66bd8e`
(2026-07-06) was proven for *compiling* ooke only. Running ooke's suite against
it gives 10 of 12: a TOML `false` is read back as `true`, so `minify = false`
and `inlinecss = false` in your own `ooke.toml` are silently obeyed as `true`,
and `test_router` dies on `RT005: nil dereference`. The real floor is
`c2aa278`, 2.5 months later. If you pinned `b66bd8e`, re-pin.

### 134.22 — `src/_handlers.tk` is generated, tracked, and deleted by `make clean`. **P2, planned**

Cosmetic for a consumer: the build regenerates it. It means a working tree and
a fresh clone can disagree about that file depending on which command ran last.

### 134.23 — `src/config.tkc.md` documents a `logaccess` field that does not exist. **P3, planned**

The real field has a different name. Documentation only; ooke's own tests read
the correct one. Worth knowing because the wrong name is what misled an earlier
test expectation.

### Not fixed, not ooke's

- **The ~1.3 KB RSS-per-request leak (134.13)** was diagnosed as **not ooke's
  and not the arena's**; it is tracked as toke 127.65. It is still real if you
  serve traffic on a toke that predates the fix.
- **The native bindings surface (134.11)**: 18 of 56 documented functions have
  no symbol and 9 more disagree with their implementation on arity. All nine
  modules live in **toke's** stdlib, not ooke's, and ooke exposes none of them.
  Tracked as Epic 136. Do not plan against the bindings documentation.

## What was measured, and how

- **Tests:** 12/12, 187 live assertions. Honesty established by mutation —
  one expectation changed per file, all 11 files confirmed to go red (134.17).
  Before 134.5 the suite had never executed at all.
- **Type check:** `tkc --check -I src` 30/30 files. **Lint:** 2 warnings, 0
  errors, down from 96.
- **Memory:** 15.4% reduction from the string-builder change, measured with
  Epic 131's harnesses (134.4).
- **Floor:** measured by building tkc at historical commits and running the
  suite, not by reading release notes (134.7, 134.16). `docs/versioning.md`
  carries the evidence and the method, including why an incremental rebuild
  across commits is not evidence about either commit.

Numbers for this candidate were produced with toke `b0e3916` (2026-09-19),
compiler sha256 `063338f1…e8c9c7ef`, recorded in the release manifest.
