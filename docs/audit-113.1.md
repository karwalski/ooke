# 113.1 — ooke audit & boundary map

**Date:** 2026-06-15
**Status:** complete
**Method:** parallel agent read of every ooke source module + `.tki` + companion + test,
the ooke spec (`ooke-specification.md`, `ooke-bindings-required.md`), the build
(`Makefile`, e2e + parity scripts), and a per-stdlib-module trace to its `.tki` /
`tk_*_w` wrapper / C backing.

This is the understanding that gates the Epic 113 pure-toke rebuild. ooke must
reach every capability **only** through the published toke stdlib API
(`import → .tki → tk_*_w → C in toke core`); this audit classifies whether each
dependency is reachable that way today, and what toke-core work (Track B) is
required where it is not.

---

## 1. Module map & rebuild order

12 toke modules in `src/`. Dependency tiers (rebuild bottom-up):

| Tier | Modules | Internal deps |
|------|---------|---------------|
| 0 (leaves) | `config`, `store`, `router`, `template`, `apihealth`, `validate`, `repair`, `run` | none |
| 1 | `handlers` | `apihealth` |
| 2 | `build` | `config, router, template, store, validate` |
| 2 | `serve` | `router, template, store` |
| 3 | `cli` (`main.tk`) | `config, serve, build, repair, apihealth, handlers, run` |

This is the 113.2 → 113.9 story order: config → store → router → template →
build → serve → cli → (apihealth/validate/repair/run/handlers extras).

### Per-module summary

| Module | Purpose | Fns | stdlib imports |
|--------|---------|-----|----------------|
| `config` | Parse `ooke.toml` → flat `$ookecfg`; every key has a default; only fails on file-read / TOML-parse error. | 1 | toml, str, file |
| `store` | Content store: parse md (frontmatter) + json → `$content`; dual backend flat-file vs SQLite; DDL gen; in-mem lookup. | 12 | file, str, path, json, db |
| `router` | Filesystem route scan (`pages/`), derive pattern/template/type, match URL (static-before-dynamic, least-dynamic wins), capture params. | 7 | file, str, path |
| `template` | `.tkt` engine: lex (`{= =}`/`{! !}`/comments), render against str→str ctx, filters (md/escape/upper/lower/trim), layout/block/yield, partials, islands, cache. | 13 | file, str, path, md |
| `build` | Static site build: render static+dynamic pages, validate vs models, copy assets, 404; inline-css + minify helpers; build report. | 7 | file, str, path, log |
| `serve` | Compile site → http static route table; custom 404; `/static` mount; CORS; start HTTP worker pool or HTTPS/TLS. | 4 | http, log, file, str, path |
| `cli` (`main`) | argv dispatch: `new`/`serve`/`build`/`gen`/`repair`/`migrate`; `gen spec` container codegen. | 13 | args, str, file, log, path, http, process |
| `apihealth` | `GET /api/health` → fixed JSON `{status:ok, service:ooke}`. | 2 | http |
| `validate` | Load TOML model (field types/required), validate content meta (required + int/bool checks), merge/log results. | 5 | file, str, path, toml, log |
| `repair` | Run `tkc`, parse JSON diagnostics, iterate fixes (`ooke repair`). | 2 | str, log, process |
| `run` | Build/run driver: read `ooke.toml [package]`, invoke `tkc <entry> --out build/<name>`, exec binary forwarding args. | 5 | str, log, file, path, toml, process, args |
| `handlers` | Central route table; binds `GET /api/health` → `apihealth.get`; returns registered paths. | 2 | http |

---

## 2. Stdlib dependency classification

ooke depends on **11 stdlib modules**. Classification for the pure-toke rebuild:

| Module | Class | C backing | Notes |
|--------|-------|-----------|-------|
| `std.db` | ✅ reusable-as-is | `db.c` + `db_glue.c` (sqlite3; mysql/postgres alts) | `db.many/one/exec`, `row.str` all published 1:1. DB-agnostic surface. |
| `std.file` | ✅ reusable-as-is | `file.c` + `file_glue.c` | all 7 ooke APIs (read/write/mkdir/isdir/listall/copy/exists) published + wrapped. |
| `std.path` | ✅ reusable-as-is | `path.c` | 6 pure path-string fns; ooke uses join/ext/dir. No fs calls. |
| `std.log` | ✅ reusable-as-is | `log.c` + `log_glue.c` | ooke uses `log.info` only. |
| `std.md` | ✅ reusable (minor) | `md.c` + `md_glue.c` (vendored cmark) | `md.render` fine. `md.renderfile` is a **dead export** (no wrapper) → 113.B.7. |
| `std.args` | ✅ reusable (minor) | `args.c` + `args_glue.c` | ooke uses count/get. `args.all()` lacks a wrapper (unreachable) → 113.B.8. |
| `std.http` | ⚠️ **partial** | `http.c`/`http2.c` + `tk_web_glue.c` (~30 wrappers) | C is feature-complete; **the published `http.tki` under-exposes it**. Biggest gap cluster → 113.B.1/113.B.2. |
| `std.str` | ⚠️ needs-generalising | `str.c` + `str_glue.c` | C has every op (often both name variants). `.tki` naming drift: ooke calls `str.fromint/toint/eq`; tki publishes `from_int/to_int`, no `str.eq` → 113.B.3. |
| `std.toml` | ⚠️ needs-generalising | `toml.c` + `toml_glue.c` (vendored tomlc99) | Read path works; `loadfile` unreachable (no wrapper), errors swallowed, no f64/array/keys/free → 113.B.4. |
| `std.json` | ⚠️ needs-generalising | `json.c` + `json_glue.c` | `dec`/`str` work; `keys/entries/has` wrappers exist but unpublished; no nested-path/generic get; no object construction → 113.B.5. |
| `std.process` | ⚠️ needs-generalising | `process.c` + `process_glue.c` | **`spawn` wrapper hardcodes `sh -c` instead of execvp argv per `.tki`** (injection hazard); stdout/stderr drain-once; no `run` convenience → 113.B.6. |

**Key insight:** there are essentially **no "missing" capabilities** — the C
backing in toke core already implements everything ooke needs. The work is
almost entirely at the **published-interface layer** (`.tki` files under-export
or mis-name what the C wrappers already provide) plus a few wrapper-contract
bugs. This is the cleanest possible shape for "no C in ooke": we mostly publish
and align existing core capability rather than write new C.

---

## 3. Full plumbing / parity surface (loke runs on this)

The rebuild must reach behavioural parity across this surface (from the spec +
the e2e/parity harness). Verified by `test/verify_parity.sh` (status + `<title>`
+ body-length ±10% vs the C reference binary) and `test/e2e/*` (Playwright +
shell curl checks).

**Server:** HTTP server + request/response + middleware; multi-worker
(`workers=0` → CPU auto-detect, `TK_HTTP_WORKERS` override); TLS/HTTPS
termination (cert/key, no reverse proxy); graceful shutdown.
**Routing:** filesystem scan of `pages/` → static dispatch table; `[slug]`/`[id]`
dynamic segments via `req.params(name)`; static-before-dynamic priority.
**Handlers:** dynamic GET/POST/PUT/DELETE/PATCH bound to toke fn pointers;
`req.path/params/body/header`; `res.json(status;body)/status/ok/err` chaining;
CORS for API; api-prefix convention (`pages/api/*` → JSON, `/api/` gating).
**Templates:** `.tkt` lex `{= =}`/`{! !}`/comments; layout inheritance +
named blocks + partials; filters md/escape/upper/lower/trim/date.
**Content:** flat-file (md+YAML frontmatter, json) and embedded SQLite behind one
interface; schema-gen from content types; flat→sqlite migration; `std.db`
connection-string dispatch; `migrations/*.sql` runner.
**Content engine:** Markdown→HTML; YAML frontmatter; TOML config + `models/*.toml`;
content validation (field type + required → build-time errors).
**Build:** static site gen to `build/`; CSS inline/critical; HTML/CSS minify;
image optimise; single-binary `--binary` with embedded assets.
**Islands:** directive parse + hydration registration + `ooke-islands.js` loader.
**Logging:** access log combined/NDJSON (runtime switch); separate `error.log`
for 4xx/5xx with rotation + gzip; custom error pages `templates/errors/`.
**Security:** CSP header generation (strict default).
**Extensions:** scan `extensions/`, filename-sorted load, hooks
`init/onrequest/onresponse/onshutdown`, route + middleware registration.
**CLI:** `new`/`serve`/`build`/`gen (type/page/island/api/spec)`/`repair`/`migrate`;
`ooke repair` + `tkc --lint/--fix` over structured JSON diagnostics.
**Admin:** `/admin` mount (serve mode) with auth + auto CRUD.

**`ooke.toml` config keys:** `[site] name/url/language`; `[build]
output/minify/inline_css/image_optimize`; `[server] port/workers/admin`;
`[store] backend`; `[log] access_format`; `[paths] api_prefix`; `[requires]
min_toke`; (spec also drafts `[theme] primary/bg/font`).

> Note the config-key naming drift: live `ooke.toml` uses `inline_css`,
> `image_optimize`, `access_format`; the spec draft and `config.tk` field names
> differ (`buildinlinecss`, `logaccess`). Reconcile during 113.2.

---

## 4. Notable findings requiring a decision or story

1. **`config` default mismatch (latent test bug).** `config.tk` defaults
   `serverworkers=0` but `test_config.tk` asserts `==4`. A faithful rebuild
   fails the test. Per the "bugs become stories" rule this is a decision, not a
   silent fix → **113.2a** (resolve before/with config rebuild).
2. **`store` undeclared `row` import.** `storeallsql` calls `row.str(...)` with
   no `i=row:std.row;` import. Either an implicit alias or a latent compile bug →
   resolve in **113.3** (may need `std.row` import or db row-accessor form).
3. **`Ok`/`Err` vs `$ok`/`$err` casing.** Sources use bare `Ok`/`Err` result
   arms; several test files use `$ok`/`$err`. Need to confirm which constructor
   casing the current compiler accepts (relates to the str `=` / variant-naming
   family) → compiler/spec clarification, **113.B.9**.
4. **`.tki` error-union erasure.** Interfaces export functions with the `!error`
   arm stripped (e.g. `configload` shown as `ookecfg`, not `$ookecfg!$configerr`).
   Decide whether `.tki` should faithfully encode error unions → **113.B.10**.
5. **Version drift.** Some `.tki` declare `1.0.0` while `.tkc` companions say
   `1.1.0`. Reconcile during each module rebuild (companions regenerated anyway).
6. **Unused imports** (`run` imports `std.args` unused; `config` imports
   `std.str` unused). Drop on rebuild; confirm compiler tolerance.

---

## 5. Track B seed list (toke-core stories)

These feed Epic 113 Track B. Most are *publish/align existing core capability*,
not new C — consistent with ADR-0005 (capability lives in toke core, consumed
via the published API).

| Track B | toke-core deliverable | Blocks | Priority |
|---------|----------------------|--------|----------|
| 113.B.1 | `http.tki`: export the handler/server wrappers that exist in `tk_web_glue.c` but are unpublished — `getstatic`, `postjson` (route variant), `postecho`, `setnotfound`, `servedir`; reconcile the full intended public surface. | serve, apihealth, handlers | P0 |
| 113.B.2 | `http.tki`: resolve naming mismatch — ooke calls `http.servetls`/`http.serveworkers`; tki publishes `serve_tls`/`serve_workers`. Add aliases or align. | serve | P0 |
| 113.B.3 | `str.tki`: publish `str.fromint`/`str.toint` aliases (tki has `from_int`/`to_int`); resolve `str.eq` (publish or confirm `=` operator); single naming convention + stable aliases. | all (pervasive) | P0 |
| 113.B.4 | `std.toml`: add `tk_toml_loadfile_w` (declared, unreachable); thread real `tomlerr.msg` through wrappers (currently swallowed); add `toml.f64`, array access, `toml.keys`/`len`, table free. | config, validate | P1 |
| 113.B.5 | `std.json`: export `json.keys`/`entries`/`has`/`haskey` (wrappers exist); add nested-path key access + generic `json.get`; object construction/mutation for output. | store | P1 |
| 113.B.6 | `std.process`: fix `tk_process_spawn_w` to honour the `[str]` argv contract (currently `sh -c`, injection hazard); add `process.run(cmd)->{code,out,err}` (ooke's exact pattern); document drain-once stdout/stderr; expose richer spawn opts + existing extras (exec/exitcode/poll/env). | run, repair, cli | P1 |
| 113.B.7 | `std.md`: `md.renderfile` is a dead export (no wrapper) — add `tk_md_render_file_w` or remove the export. | (none — template uses read+render) | P3 |
| 113.B.8 | `std.args`: add `tk_args_all_w` wrapper for `args.all()` (declared, unreachable); stop dropping `ArgsErr.msg` at the ABI boundary. | (none — ooke uses count/get) | P3 |
| 113.B.9 | Compiler/spec: confirm canonical result-constructor casing (`Ok`/`Err` vs `$ok`/`$err`) and document; align ooke source + tests. | template, store, cli, build | P1 |
| 113.B.10 | Spec/tooling: decide whether `.tki` exports must faithfully encode `!error` unions (currently erased); update interface-gen + checker accordingly. | all (interface fidelity) | P2 |

**P0 (113.B.1/.2/.3) gate the serve + CLI rebuild** and should land first.
`std.db/file/path/log` need no Track B work.
