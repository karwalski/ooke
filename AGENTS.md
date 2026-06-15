# AGENTS.md
## Claude Code Operating Specification — ooke (pure-toke rebuild)

**Version:** 2.0
**Repository:** toke-ooke-pure (rebuild of ooke)
**Project:** ooke — CMS and web framework built on toke
**Language:** toke only (compiled via tkc)
**Governing decision:** `toke/docs/decisions/ADR-0005.md`
**Tracker:** `toke/docs/progress.md` — Epic 113

Read this file in full before touching anything.

---

## 1. What This Project Is

ooke is a CMS and web application framework implemented **entirely in toke**:
file-system routing, a `.tkt` template engine, a flat-file (and SQLite) content
store, static build mode, a dynamic HTTP serve mode, and a CLI scaffold. The
binary is produced by compiling toke source with `tkc`.

This repo is the **pure-toke rebuild**. It is seeded from the previous `toke-ooke`
as the behavioural + plumbing **parity reference** (`main` branch). The rebuild
happens on `feature/pure-toke-rebuild`.

---

## 2. The Core Rule — pure toke, native capability lives in toke core (ADR-0005)

**ooke contains zero non-toke code (no C, shell, Python, or hand-written JS) and
never reaches a native symbol directly. It never declares an `extern`.**

ooke obtains every capability **only** through the published toke stdlib API:

```
ooke (.tk)  →  import std.<module>  →  .tki interface  →  tk_*_w wrapper  →  C backing (in toke, not here)
```

When a required capability does not exist, is ooke-shaped, or is buggy:

1. **Do not** write C here. **Do not** declare an `extern` here. **Do not**
   hand-roll a fragile pure-toke workaround for a missing primitive.
2. Open a paired **Track B (113.B)** story in `toke/docs/progress.md`.
3. Mark the dependent ooke story `blocked` on it.
4. Solve it in **toke core** as a *generalised, reusable* stdlib capability
   (module + `.tki` + `tk_*_w` wrapper, C-backed where a true primitive is
   needed) so every toke program benefits — then unblock the ooke story.

### NO WORKAROUNDS — fix toke core (hard rule)

When you hit a toke **compiler / build / codegen / runtime** bug while rebuilding
a module, you MUST NOT work around it (no avoiding the buggy construct, no
restructuring the test to dodge it, no degraded reimplementation). Instead:

1. **STOP** at the blocking point and **capture your partial work so it can be
   resumed**: return the module source as far as you got, a one-paragraph
   "resume note" (what is done, what remains, the exact next step), and which
   functions are verified vs unverified.
2. **File a precise bug report**: a minimal toke reproducer, the exact command,
   observed-vs-expected behaviour, and your best root-cause pointer (file:line
   in the toke compiler if you can find it).
3. Mark the story **blocked** on a new/existing Track B (113.B) item. Do **not**
   mark it done, and do **not** commit a workaround.

The core toke bug will be fixed (compiler/build/codegen/run), then your story
will be **resumed from your partial work** and finished cleanly. Workarounds are
forbidden: they create degraded code and hide root-of-trust bugs. Faithful,
clean, efficient code is the only acceptable output.

C-backed stdlib *in toke core* is fine and expected. The invariant is only about
*where* native code lives (toke, never ooke) and *how* ooke consumes it (the
published API, never directly).

---

## 3. Working Rules for Every Story (per ADR-0005 + companion-file-spec)

1. **Consult the spec + syntax while authoring.** Read `toke/docs/spec/*`
   (semantics, grammar, the prompt) and the current syntax. No guessed
   constructs.
2. **Small, multiple files.** Single canonical patterns, token-efficient, no
   mega-files. This honours toke's design goals.
3. **Companion file for every source file.** `foo.tk` → `foo.tkc.md`, per the
   Companion File Format Specification 1.0 (`toke/docs/companion-file-spec.md`):
   YAML frontmatter with a correct `source_hash`, then Module / Types /
   Functions / Constants / Control Flow / Notes sections.
4. **Test each function as it is written.** Tests live in `test/`, written in
   toke, compiled with `tkc`. `make test` must be green before a story is `done`.
5. **Plumbing parity is mandatory.** loke will run on this ooke, so the full
   surface must match the reference: HTTP + workers, file routing, dynamic
   GET/POST/PUT/DELETE/PATCH handlers, CORS, api-prefix, templates, flat-file +
   SQLite store, TLS, Markdown CMS, TOML config, YAML frontmatter, islands,
   static serving, access/error logs.

---

## 4. Repository Structure

```
toke-ooke-pure/
├── src/            ooke framework source (.tk + .tki + .tkc.md companions)
├── pages/          example/scaffold pages
├── templates/      example/scaffold templates (.tkt)
├── content/        example content (.md + .json)
├── models/         TOML content-type definitions
├── islands/        client-side interactive components
├── static/         served at /static/*
├── test/           toke test suite (template/ store/ router/ build/ config/ cli/)
├── testproj/       example project used in tests
├── ooke.toml       example project configuration
├── Makefile        build rules
└── AGENTS.md       this file
```

---

## 5. Progress Tracking & Git

- Stories live in `toke/docs/progress.md` under **Epic 113** (Track A = ooke
  rebuild, Track B = toke-core gaps). Only the main thread edits `progress.md`.
- Never commit to `main`. Work on `feature/pure-toke-rebuild` (or finer
  `feature/ooke-113.<n>-<component>` branches). Conventional commits with scope,
  e.g. `feat(ooke/template): pure-toke layout inheritance`.

---

## 6. First Action Each Session

1. Read `toke/docs/progress.md` Epic 113 — Track A status and any open Track B blockers.
2. Confirm `toke/docs/decisions/ADR-0005.md` is being honoured.
3. Never write C, `extern`, or any non-toke code in this repo — even temporarily.
