# ooke 3.0.0-rc.1 — release notes

**Status: release candidate. Not published, not tagged.** Prepared by story
134.10 on 2026-09-19.

## Why this is a candidate and not 3.0.0

Every quality gate 3.0.0 was waiting on is green. The suite runs and is honest
(134.5, 134.17), the sources check and lint clean (134.2, 134.3), the toke
floor is measured for build *and* behaviour (134.7, 134.16), the RSS leak
turned out not to be ooke's (134.13 → toke 127.65), and **134.24 — the P0 that
made this a candidate in the first place — was fixed while this release was
being prepared** (see below).

What keeps the `-rc.1` is **134.15, and it is not ooke's to fix**: toke has
never cut a version for the v0.4 break, so this release cannot express its own
dependency as a version. It pins a commit instead. An adopter can use that, but
a general release whose single hard requirement is "a git SHA on somebody's
main branch" is a candidate. The owner decision in 134.15 is what turns this
into 3.0.0; `docs/RELEASING.md` says what changes when it does.

Secondarily: 134.24's fix is hours old and its story row is still open pending
close-out. It is verified here (below) but not yet signed off.

## Known defects a consumer will meet

### 134.24 — `ooke build` aborted on any project with an API route. **FIXED, verify before you trust this note**

This was the P0 that made 3.0.0 a candidate, and it is fixed:
`routerscan` set a flag marking a route as an API handler and the build never
read it, so the handler was rendered as a template and the build aborted with
the single word `build failed`. Both halves are repaired — the flag is read,
and the wrapper reports the error it already had.

Reproduced as broken, then as fixed, on a scaffold from this candidate:

    # before (ooke-toke built at 57f1915^^)
    $ ooke new demosite && cd demosite && ooke build
    {"level":"error","msg":"build failed"}      # exit 1, and that is the whole diagnostic

    # after
    $ ooke new demosite && cd demosite && ooke build
    {"level":"info","msg":"pages built: 1"}
    {"level":"info","msg":"assets copied: 0"}   # exit 0, build/index.html written

And with an API route present, which is the case the defect was named for:

    $ cp .../api/hello.tk pages/api/hello.tk && ooke build
    {"level":"info","msg":"build: 1 api route(s) under pages/api/ are request
     handlers, not pages — they are served by `ooke serve` and are not rendered
     into the static build"}                    # exit 0

A second defect was fixed in the same area and is worth knowing about because
it changes what `ooke new` writes: the scaffold produced **one** template,
`templates/base.tkt`, while the route it also scaffolds (`pages/index.tk`, i.e.
`/`) derives `templates/index.tkt`. That template was not a layout either — it
used `{{title}}` and `{{content}}`, which are not ooke template syntax, so both
would have been served to the browser verbatim. `ooke new` now writes
`base.tkt` (the shell) and `index.tkt` (the page), in ooke's own convention.

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
