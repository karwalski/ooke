# Changelog

Dates are the dates the work was done, not publication dates. Nothing below has
been published; see `docs/RELEASING.md`.

## 3.0.0-rc.1 — unreleased (prepared 2026-09-19, story 134.10)

Release **candidate**, not a release — because toke has never cut a version for
the v0.4 break (story 134.15, owner decision), so this release can only pin its
one hard dependency as a git commit. Read `docs/release-notes-3.0.0.md` before
adopting.

### Breaking, relative to 2.0.0

The version loke was written against is **2.0.0** (2026-06-21). Everything here
breaks a 2.0.0-era consumer.

- **toke v0.4 syntax is now required of your code too.** ooke's sources moved to
  `==` for equality and expression-oriented `if`; so must the `pages/*.tk` and
  modules in your project. 2.0.0-era sources do not compile.
- **Templates escape by default** (toke ADR-0011). A template that relied on raw
  interpolation now emits escaped text. Use `{{raw ...}}`. This changes output
  rather than failing, so it will not announce itself.
- **A capability grant set is baked into the binary with `enforce = true`**
  (toke ADR-0010).
- **The toke floor is a commit, not a version.** `ooke.toml [requires]` gained
  `mintokedate` and `mintokecommit`; `mintoke` alone is not enforceable while
  toke's VERSION is frozen at 2.8.0 (story 134.15).
- **`ooke new` writes a `[requires]` block** into every scaffolded project.
  Previously it wrote no floor at all.
- **No-underscore naming** for configuration keys and stdlib call names, imposed
  by toke's Profile-1 character set.
- **`[store].backend` is gone, and `$ookecfg` lost its `storebackend` field.**
  The key was documented as `"flat"` or `"sqlite"` "with automatic migration",
  parsed, and then read by nothing: build and serve always used the flat-file
  store. No SQLite content backend exists to select — nothing opens a database,
  creates its tables or migrates content into it. An `ooke.toml` that still has
  a `[store]` table loads unchanged; the table is ignored. Code importing
  `ooke.config` that read `storebackend` no longer compiles. (134.34)

### Fixed

- **The test suite had never run.** All 12 tests were reported `SKIP (link)` and
  the runner exited 0. Now 12/12 — and the runner takes its build configuration
  from `make print-build-vars` rather than a hand-copied list, which is how it
  drifted out of linkability unnoticed. (134.5)
- **157 assertions were inert.** `test.eq` results were computed and discarded,
  so tests could not fail. Now 187 live assertions, each proved able to fail by
  mutating one expectation per file and confirming all 11 files go red. (134.17)
- **`ooke serve` segfaulted** on a missing `pages/` directory, and did not honour
  SIGTERM. Exit 139, `EXC_BAD_ACCESS`. (134.14)
- **`serve` swallowed a `routerscan` error** into an empty route set and served
  nothing rather than refusing to start. (134.18)
- **`ooke serve --help` started a server** instead of printing help. Help is now
  answered before dispatch for every command in all three spellings. (134.19)
- **Two configuration flags were parsed and never used.** Wired, not removed.
  (134.20)
- **Reproducible site builds** — the 132.20 blocker, root-caused to toke 127.58.
  (134.8)
- **A clone could not run the tests**: `test/support/` was untracked, so every
  fresh clone died on a `make` error that named the file but not the cause.
  Tracked now, with a preflight that fails by name. (134.21)
- **`tkc --check` coverage 28/30 → 30/30**; lint warnings 96 → 2, errors 0;
  all 63 string-concatenation chains converted to the canonical form.
  (134.2, 134.3)
- **`ooke build` aborted on any project containing an API route**, and `ooke
  new` scaffolded one — so the first thing an adopter did produced a project
  that could not be built. `routerscan` set an is-API flag the build never
  read, and the CLI wrapper discarded the error and logged the single word
  "build failed". Both halves fixed, and API routes are now reported as
  deliberately excluded from the static build. (134.24)
- **`ooke new` scaffolded one template where the route it also scaffolds needs
  two**, and that template used `{{title}}`/`{{content}}` — not ooke template
  syntax — so both would have reached the browser verbatim. It now writes
  `base.tkt` and `index.tkt`. (134.24)
- **The version gate was decorative** — it compared major versions only,
  restated the floor in a second place, and was a prerequisite of nothing. It
  now reads `ooke.toml` as the single source of truth and gates `make` and
  `make test`. `ooke --version` and `VERSION` had also disagreed for three
  months; that is now a build failure. (134.7)

### Changed

- Templates render into a string builder rather than a concat chain; 15.4%
  memory reduction, measured. A template cache was implemented, measured and
  **rejected**. (134.4)
- `TOKE_ROOT` and `TKC` are overridable (`?=`) instead of absolute paths into
  one developer's home directory. Nobody else could build ooke before this.
  (134.16)

### Known defects

See `docs/release-notes-3.0.0.md`. The short list: **134.15** (toke has no
usable released version — you must pin a commit), 134.22 and 134.23 (both
minor), and the caveats on ooke's internal module surface (134.11).

## 2.0.0 — 2026-06-21

The pure-toke rebuild (Epic 113): ooke re-implemented as 100% toke, with the
native glue pushed down into a reusable toke core (ADR-0005).
