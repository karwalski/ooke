# AGENTS.md
## Claude Code Operating Specification — ooke

**Version:** 1.0
**Repository:** https://github.com/karwalski/ooke
**Project:** ooke — CMS and web framework built on toke
**Language:** toke (compiled via tkc)

This file is the authoritative operating specification for any AI coding agent working in this repository. Read it in full before touching any file.

---

## 1. What This Project Is

ooke is a CMS and web application framework implemented entirely in toke. It provides:

- **File-system routing** — `pages/blog/[slug].tk` → `/blog/:slug`
- **Template engine** — `.tkt` files with layout inheritance, blocks, partials, Markdown filter
- **Flat-file content store** — `.md` files with YAML frontmatter
- **Build mode** — renders static HTML to `build/`
- **Serve mode** — dynamic HTTP server using `std.router`
- **CLI scaffold** — `ooke new`, `ooke gen type/page/api/island`

The ooke binary is produced by compiling toke source with `tkc`. There is no C in this repository except the toke stdlib backing layer, which lives in the toke repo and is not part of ooke.

---

## 2. Language Rule — toke Only

**ooke is written exclusively in toke. No C, no shell, no Python, no JavaScript.**

This is not a preference — it is the specification. The ooke specification document states the framework is "built entirely on the toke programming language." Violating this rule creates a gap between what the project claims and what it delivers.

If a required capability does not exist in the toke stdlib:

1. Create a story in `toke/docs/progress.md` to add that stdlib capability.
2. Mark the ooke story as `blocked` with the specific stdlib gap documented.
3. Consult the user about whether to:
   - Take the stdlib story as the next priority.
   - Integrate an open source C library via FFI into the toke stdlib (C binding lives in toke, not ooke).
   - Approach the requirement differently using existing capabilities.
4. Do not write a C alternative, even temporarily.

---

## 3. Repository Structure

```
toke-ooke/
├── src/                    ooke framework source (.tk files) — TARGET STATE
│   ├── config.tk           TOML config parser (ooke.config)
│   ├── template.tk         Template engine (ooke.template)
│   ├── store.tk            Flat-file content store (ooke.store)
│   ├── router.tk           File-system router (ooke.router)
│   ├── build.tk            Build mode (ooke.build)
│   ├── serve.tk            Serve mode (ooke.serve)
│   └── main.tk             CLI entry point
│   (Current state: C files exist as Phase 1 placeholder — to be replaced)
├── pages/                  Example/scaffold pages
├── templates/              Example/scaffold templates
├── content/                Example content
├── static/                 Example static assets
├── test/                   ooke test suite
│   ├── template/           Template engine tests
│   ├── store/              Content store tests
│   ├── router/             Router tests
│   └── build/              Build mode tests
├── ooke.toml               Example project configuration
├── Makefile                Build rules
├── README.md
└── AGENTS.md               This file
```

---

## 4. Current State (Phase 1 — C Placeholder)

The Phase 1 implementation in `src/*.c` is a working C prototype that serves as a functional reference for the toke rewrite. It is **not** the target state. It exists only to:

1. Prove the ooke concept before the toke stdlib has all required capabilities.
2. Serve as a running reference while the stdlib gaps are filled.

The C implementation will be deleted when the toke rewrite is complete and all tests pass. Do not add new features to the C implementation — add them only to the toke rewrite (or add the corresponding stdlib story first).

---

## 5. toke Stdlib Dependencies

ooke's toke implementation depends on these toke stdlib modules:

**Already exists:**
- `std.http` — HTTP server, request/response
- `std.router` — HTTP routing with path params and middleware
- `std.file` — file read/write/list/exists
- `std.str` — string operations
- `std.yaml` — YAML parsing (used for frontmatter)
- `std.json` — JSON encoding/decoding
- `std.log` — structured logging
- `std.env` — environment variables
- `std.time` — time measurement for build reports

**Required — stories in progress.md (Epic 55):**
- `std.path` — path manipulation (join, ext, stem, dir, base)
- `std.args` — command-line argument access
- `std.md` — Markdown to HTML rendering
- `file.isdir(path): bool` — directory check
- `file.mkdir(path): void!FileErr` — create directory
- `file.copy(src; dst): void!FileErr` — copy file
- `file.listall(dir): [str]!FileErr` — recursive directory listing
- `str.startswith(s; prefix): bool`
- `str.endswith(s; suffix): bool`
- `str.replace(s; old; new): str`
- `str.indexof(s; sub): i64` (returns -1 if not found)
- `str.buf()` / `$strbuf` — string builder for efficient HTML construction

Do not implement ooke components that depend on missing stdlib without first creating the stdlib story and confirming the approach with the user.

---

## 6. Progress Tracking

Stories for ooke are tracked in `~/tk/toke/docs/progress.md`:
- **Epic 55** — toke stdlib extensions required for ooke-in-toke
- **Epic 56** — ooke rewrite in toke (replaces C implementation)

Update story statuses in progress.md after each session.

---

## 7. Testing

Every ooke module must have tests in `test/`. Tests are written in toke and compiled with `tkc`. Run with `make test`.

Test categories:
- `test/template/` — template lexer, parser, renderer, layout, partials
- `test/store/` — frontmatter parsing, collection listing, slug lookup
- `test/router/` — route scanning, pattern matching, dynamic segments
- `test/build/` — build mode output, CSS inlining, minification
- `test/config/` — TOML subset parser

A story is not done until all tests in its category pass and `make test` is green.

---

## 8. Git Rules

Never commit directly to `main`. Branch naming:
```
feature/ooke-<component>-<description>
fix/ooke-<component>-<description>
```

Follow conventional commit format:
```
feat(ooke/template): implement layout inheritance
fix(ooke/store): handle frontmatter with CRLF line endings
```

---

## 9. First Action Each Session

1. Read `~/tk/toke/docs/progress.md` for ooke Epic 55/56 status.
2. Check which stdlib stories (Epic 55) are done — only then can dependent ooke stories (Epic 56) proceed.
3. Never implement an ooke component in C as a "temporary" measure.
