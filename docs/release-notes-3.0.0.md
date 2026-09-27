# ooke 3.0.0-rc.2 — release notes

**Status: release candidate. Not published, not tagged.** rc.2 prepared by
story 138.7 on 2026-09-28; rc.1 by story 134.10 on 2026-09-19. The rc.2
section comes first; everything after it is the rc.1 notes, kept because
rc.2 changes them only where the rc.2 section says so.

## rc.2 — what changed, and why it is still a candidate

**Why rc.2 exists.** rc.1 does not build on current toke. Its `src/store.tk`
ends `storeslug` and `storefind` in an error propagation with no `<`; toke
made that a hard error (E4071, "function body ends in an error propagation
with no '<'") after rc.1 was cut, at `store.tk:174:3` and `:183:3`. ooke main
had already fixed it (127.127). rc.2 is cut from main. (loke handoff
2026-09-27, O-1.)

**What was measured** (2026-09-28, each toke built in a fresh worktree, ooke's
full `make test`):

| toke | result |
|---|---|
| main `18b9f73` (2026-09-28; `668caa6` + tracker docs) | rc.2 as shipped: `make test` exits 0 — check, test-check and suite 12/12, and every script suite, including `[server] host` |
| main `512f904`, and `cee7cc0` | rc.2 before `[server] host`: `make test` exits 0 |
| `v3.0.0` = `0b0bc4e` (2026-09-23) | **fails** (measured on ooke main `b5b198f`): suite 11/12 — `test_template`, "a render through the populated cache serves the stored tokens, not the changed file" |

**134.15 is resolved and a new blocker replaced it.** toke has cut a version
(`3.0.0`), so `mintoke` means something again, and `ooke.toml [requires]` now
says `mintoke = "3.0.0"`. But toke 3.0.0 is not enough, twice over:

- it lowers `.set` on a map-typed struct field as an array `.set`, so ooke's
  template cache has never stored anything (toke 127.226, fixed in `cee7cc0`).
  The page still renders — the cache falls back to reading the file — but
  every request re-reads and re-parses its template, and the suite says so;
- it has no host-binding serve functions, which `[server] host` (below) calls
  (toke 138.1, merged as `668caa6`).

So the floor is still a commit, `668caa6`, and `make check-versions` refuses
toke 3.0.0 by name:

    ERROR: toke 0b0bc4e (2026-09-23) does not contain 668caa6 — ooke's floor.

**What turns this into 3.0.0:** a toke release that contains `668caa6`
(toke story 138.17). Then `mintoke` alone is the floor, the commit/date pair
can be dropped, and `docs/RELEASING.md` says what else changes.

**New in rc.2 — breaking: `ooke serve` binds `[server] host`, and the default
is 127.0.0.1.** rc.1 listened on every interface and had no setting for it.
A deployment that must be reachable from other machines now needs
`host = "0.0.0.0"` in `[server]`; without it the server answers only on its
own machine, and its start log says so and names the setting. The reasoning
for loopback as ooke's default, when toke's port-only functions keep every
interface, is in `docs/logging-and-tls.md`, "Bind address". (loke handoff O-3.)

**New in rc.2:** an app with more than 31 handler pages compiles. The handler
registry `ooke compile` generates imports every page plus `std.http`, and toke
caps a module at 32 imports by default (E9010). The generated `Makefile.serve`
now passes `--max-imports=<count>` for that module when it is needed
(`docs/public-api.md`; `make test-many-pages` builds and serves 40 pages).
(loke handoff O-2.)

Everything else that changed since rc.1 is in `CHANGELOG.md`.

---

# rc.1 notes (2026-09-19)

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
