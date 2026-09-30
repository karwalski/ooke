---
source_file: "serve.tk"
source_hash: "f0474ab590697bbb23e7b6cdd54e1f0fb1d7578bb9bcfd9b985333aa21bb99b8"
compiler_version: "3.0.0"
generated_at: "2026-10-01T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.serve`

Compiles an ooke site into a live HTTP server. It scans the project's `pages/`
directory for routes, renders each page's template, and registers the result as
a static GET (or JSON GET + echo POST for API routes) handler. A page whose
template fails to render answers 500. It then validates and wires up CORS, a
custom 404 page, a `/static` file mount, and finally binds `[server] host` and
starts either an HTTP worker pool or an HTTPS/TLS worker pool. The `[log]` and
`[tls]` settings are checked and applied by helpers the CLI calls first.

**Imports:**
- `std.http` (alias `http`) — static/JSON route registration, the 500 handler,
  CORS, custom 404, static-dir mount, and the host-bound HTTP / TLS worker pools.
- `std.log` (alias `log`) — info/warn/error logging, and the access/error logs
  (`openaccess`, `openerror`, `accessformat`).
- `std.file` (alias `file`) — `file.exists` probes for the 404 template and the
  TLS cert/key.
- `std.str` (alias `str`) — string building, prefix/suffix tests, replace, eq,
  split, trim.
- `std.path` (alias `path`) — join project subdirectories.
- `std.json` (alias `json`) — `json.enc`, which quotes and escapes the route
  path in the API fallback body.
- `ooke.router` (alias `ookerouter`) — scan `pages/` into `$route` records.
- `ooke.template` (alias `tpl`) — render `.tkt` templates with a context map,
  and `tplescape` for the fallback page.
- `ooke.store` (alias `store`) — load content collections for dynamic routes.
- `ooke.build` (alias `build`) — `buildresolve`, which anchors a
  project-relative path (template, log, cert, key) to the project directory.

## Types

### `$serveerr`

Error type for the fallible serve functions.

| Field | Type | Description |
|-------|------|-------------|
| `msg` | `$str` | Human-readable failure description. |

## Functions

### `servegetjson(pattern: $str; json: $str): i64`

**Purpose:** Register a static GET route that returns a fixed JSON body.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `pattern` | `$str` | The URL path to register. |
| `json` | `$str` | The JSON body to serve verbatim. |

**Returns:** `i64` — always `0`.

**Logic:**

1. Call `http.getstaticmime(pattern; json; "application/json")`.
2. Log an info line `"static json GET: " + pattern`.
3. Return `0`.

**Error handling:** None.

### `servetplerrorbody(): $str`

**Purpose:** The body a client gets for a page whose template failed to render
(story 121.59).

**Returns:** `$str` — the constant `"500 Internal Server Error"`. It names no
template, path or error: those go to the server log only.

### `servetplerror(req: i64): i64`

**Purpose:** The request handler registered for a page whose template failed.

**Parameters:** `req: i64` — the request (unused).

**Returns:** `i64` — `http.reserr(servetplerrorbody())`, a 500 response.

### `serverenderfailed(route: $str; tpath: $str): i64`

**Purpose:** Handle a page whose template failed to render (story 121.59).

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `route` | `$str` | The URL path of the page. |
| `tpath` | `$str` | The resolved template path. |

**Returns:** `i64` — always `0`.

**Logic:**

1. Log at error level `"serve: <route> — template <tpath> could not be
   rendered; answering 500. The template's own error is logged above."`
   (template.tk logs the template's own error where it is raised).
2. Register `servetplerror` for the route with `http.get(route; &servetplerror)`.

**Error handling:** None. Before 121.59 a failed render became `""` and the page
was served as the empty-template fallback (200) or skipped (404).

### `servepostjson(pattern: $str; json: $str): i64`

**Purpose:** Register a static POST route that returns a fixed JSON body.

**Parameters:** as `servegetjson`.

**Returns:** `i64` — always `0`.

**Logic:** Call `http.postjson(pattern; json)`, log `"static json POST: " +
pattern`, return `0`.

**Error handling:** None.

### `serveregisterstatic(projectdir: $str; pagesdir: $str; contentdir: $str; templatesdir: $str; sitename: $str; siteurl: $str; sitelanguage: $str; apiprefix: $str; handledpaths: @$str): i64!$serveerr`

**Purpose:** Scan the pages directory and register every page as an HTTP
route, in three passes: plain static pages, dynamic content pages, and API
routes. Paths in `handledpaths` are skipped so a live handler takes precedence
over a static fallback.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `projectdir` | `$str` | Project root. Each route's project-relative `templatepath` is anchored to it with `build.buildresolve` before rendering, so serving works from any working directory (story 134.37). |
| `pagesdir` | `$str` | Directory scanned for page routes. |
| `contentdir` | `$str` | Directory of content collections (for dynamic routes). |
| `templatesdir` | `$str` | Directory layouts and partials are named in. |
| `sitename` | `$str` | `site.name` context value. |
| `siteurl` | `$str` | `site.url` context value. |
| `sitelanguage` | `$str` | `site.language` context value. |
| `apiprefix` | `$str` | When non-empty, namespaces `/api/...` paths as `/api/<prefix>/...`. |
| `handledpaths` | `@$str` | Paths already served by a dynamic handler; skip these. |

**Returns:** `i64!$serveerr` — on success, the number of routes registered
from a real template render (static pages plus dynamic content pages; API
fallbacks, empty-template fallbacks and 500 routes are not counted); `$serveerr`
if the route scan failed (story 134.43 made the count meaningful).

**Logic:**

1. Scan routes with `ookerouter.routerscan(pagesdir)`. If the scan failed, log
   `"route scan failed, refusing to start: " + pagesdir` at error level and
   return `$serveerr{msg:"route scan failed: " + pagesdir}` (story 134.18: a
   failed scan used to become an empty route set, so the server answered 404
   for everything and looked healthy). Otherwise take the routes.
2. Mutable `rendered = 0`.
3. **Pass 1 — static, non-API pages.** For each route `r` with
   `!r.isdynamic && !r.isapi`:
   a. `webpath` starts as `r.pattern`. If it starts with `"/api/"` and
      `apiprefix` is non-empty, rewrite it to
      `"/api/" + apiprefix + "/" + (pattern without "/api/")`.
   b. If any entry of `handledpaths` equals `webpath` (`str.eq`), log
      `"skip (dynamic handler registered): " + webpath` and do nothing else.
   c. Otherwise build `ctx = @("site.name":sitename; "site.url":siteurl;
      "site.language":sitelanguage)`, resolve
      `tpath = build.buildresolve(projectdir; r.templatepath)`, and render with
      `tpl.tplrenderfile(tpath; ctx; templatesdir)`:
      - Render failed (`$err`): `serverenderfailed(webpath; tpath)` — 500.
      - Non-empty `html`: log `"reg static: " + webpath`, register
        `http.getstatic(webpath; html)`, `rendered += 1`.
      - Empty, and `webpath` starts with `"/api/"`: register the JSON body
        `{"status":"ok","endpoint":` + `json.enc(webpath)` + `}` with
        `http.getstaticmime(...; "application/json")` and `http.postecho(webpath)`.
        The path is JSON-encoded (story 121.63): it comes from a file name
        under `pages/`, and a name holding `"` or `\` made the body invalid
        JSON.
      - Empty otherwise: register the fallback page
        `<html><body><p>` + `tpl.tplescape(webpath)` + `</p></body></html>`
        with `http.getstatic`. The path is HTML-escaped (story 121.61): it
        comes from a file name under `pages/`, and a page named
        `/<script>x</script>` was served as markup.
4. **Pass 2 — dynamic, non-API pages.** For each route with
   `isdynamic && !isapi`: load `store.storeallflat(contentdir; contenttype)`
   (a failure gives an empty collection). For each item, build `ctx2` adding
   `slug`, `body`, `title` to the site fields, resolve and render the route's
   template the same way:
   - Render failed: `serverenderfailed(pattern with ":slug" replaced by slug;
     tpath2)` — 500.
   - Non-empty `html2`: `fullurl` = pattern with `":slug"` replaced by the slug;
     log `"reg dyn: " + fullurl`, `http.getstatic(fullurl; html2)`,
     `rendered += 1`.
   - Empty: log `"skip dyn (no html): " + slug`.
5. **Pass 3 — API routes.** For each route with `isapi`: `apipath` is its
   pattern, rewritten with `apiprefix` as in 3a when that is non-empty. If
   `handledpaths` holds it, log a skip line; otherwise log
   `"api route (no handler, static fallback): " + apipath` and register the
   default JSON body and echo POST as in 3c.
6. Return `rendered`.

**Error handling:** Only the route scan fails the function. A failed
collection load is an empty collection; a failed template render answers 500
for that route.

The scan failure is logged from `pagesdir` rather than read off the error
payload, because reading a field off a struct-style error payload traps RT005 —
toke story 127.78, open. Carry the payload's message once that is fixed.

### `servelogtarget(projectdir: $str; p: $str): $str`

**Purpose:** Map a `[log]` path to the file std.log opens (story 134.40).

**Returns:** `"/dev/stderr"` when `p` is `"-"`; otherwise
`build.buildresolve(projectdir; p)`.

### `serveopenlogs(projectdir: $str; access: $str; errorlog: $str; format: $str): i64!$serveerr`

**Purpose:** Apply the `[log]` settings: open the access and error logs std.http
writes to (story 134.40).

**Parameters:** `access` and `errorlog` are `"-"` (stderr), `""` (off) or a
project-relative file; `format` is `"combined"` or `"json"`.

**Returns:** `i64!$serveerr` — `0`, or `$serveerr` naming the problem.

**Logic:**

1. If `format` is neither `"combined"` nor `"json"`, log and return
   `$serveerr` (`[log] accessformat must be "combined" or "json", got "<format>"`).
2. `log.accessformat(format)`.
3. If `access` is non-empty, `log.openaccess(servelogtarget(...); 0; 0; 0)`; a
   non-zero result logs and returns `$serveerr` (`[log] access log could not be
   opened: <path>`).
4. The same for `errorlog` with `log.openerror`.

**Error handling:** A configured log that cannot be opened is an error, not a
silent no-log. Rotation is not wired: std.log's rotation loses lines
(`config.configlogunsupported`). Design: docs/logging-and-tls.md.

### `servetlscheck(projectdir: $str; cert: $str; key: $str): i64!$serveerr`

**Purpose:** Check `[tls]` before anything binds (story 134.40).

**Returns:** `i64!$serveerr` — `0` when both are empty or both name existing
files (resolved with `build.buildresolve`); otherwise log and return
`$serveerr`: `[tls] needs both cert and key, or neither`, `[tls] cert not found:
<path>`, or `[tls] key not found: <path>`.

### `servecorscheck(origins: $str): i64!$serveerr`

**Purpose:** Validate `[server] corsorigins` before it reaches `http.setcors`
(story 121.25, audit OOK-05).

**Returns:** `i64!$serveerr`.

**Logic:**

1. Empty: return `0`.
2. Exactly `"*"` after trimming: log a warning (any web page may read every
   response) and return `0`.
3. Otherwise split on `,`; for each trimmed entry strip an `https://` or
   `http://` scheme. The entry is bad if nothing is left after the scheme (this
   includes no scheme at all) or the rest contains `/`, a space or `*`. A bad
   entry logs and returns `$serveerr` naming it:
   `[server] corsorigins: "<entry>" is not an origin -- each entry is
   scheme://host[:port] (http or https, no path), or the whole value is "*"`.
4. Return `0`.

**Error handling:** toke matches an Origin against the list exactly, so a
malformed entry would fail silently; refusing to start is the only visible
failure.

### `serverlisten(projectdir: $str; host: $str; port: i64; uport: u64; uworkers: u64; tlscert: $str; tlskey: $str): i64`

**Purpose:** Bind `[server] host` and run the worker pool (story 138.7, O-3).

**Returns:** `i64` — the listener's result; non-zero means it failed (a host
toke refuses, a port that does not bind, a certificate that does not load).

**Logic:**

1. `addr = host + ":" + port`. If `host` is `"127.0.0.1"` or `"localhost"`, log
   that the server listens on loopback only and how to accept other machines.
2. With `tlscert` non-empty: resolve cert and key with `build.buildresolve`, log
   `"mode: HTTPS (TLS) on " + addr`, and return
   `http.servetlsworkerson(host; uport; cert; key; uworkers)` (`[server]
   workers` is honoured under TLS, story 134.47; `0` = auto).
3. Otherwise log `"mode: HTTP on " + addr` and return
   `http.serveworkerson(host; uport; uworkers)`.

**Error handling:** Host validation is toke's; a refused host fails the start
and toke prints a diagnostic with `stage="host"`.

### `serverun(projectdir: $str; host: $str; port: i64; workers: i64; buildoutput: $str; tlscert: $str; tlskey: $str; sitename: $str; siteurl: $str; sitelanguage: $str; apiprefix: $str; corsorigins: $str; handledpaths: @$str): i64!$serveerr`

**Purpose:** Register everything and start the live HTTP(S) server. Blocks in
the listener.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `projectdir` | `$str` | Project root (contains `pages/`, `content/`, `templates/`). |
| `host` | `$str` | Address to bind (`[server] host`). |
| `port` | `i64` | TCP port. |
| `workers` | `i64` | Worker count (`0` = auto). |
| `buildoutput` | `$str` | Static build output dir (accepted for signature parity; unused). |
| `tlscert` | `$str` | TLS certificate path; empty selects plain HTTP. |
| `tlskey` | `$str` | TLS key path. |
| `sitename` | `$str` | `site.name` context value. |
| `siteurl` | `$str` | `site.url` context value. |
| `sitelanguage` | `$str` | `site.language` context value. |
| `apiprefix` | `$str` | API path namespace prefix. |
| `corsorigins` | `$str` | CORS allow-origin list; empty disables CORS. |
| `handledpaths` | `@$str` | Paths already served by dynamic handlers. |

**Returns:** `i64!$serveerr` — `$serveerr` when the route scan fails, the CORS
value is malformed, or the listener stops with an error; otherwise it blocks.

**Logic:**

1. Join `projectdir` with `"pages"`, `"content"`, `"templates"`.
2. `serveregisterstatic(...)!$serveerr` — nothing is bound before this point.
3. `servecorscheck(corsorigins)!$serveerr`; if `corsorigins` is non-empty,
   `http.setcors(corsorigins)` and log `"CORS enabled: " + corsorigins`.
4. Log `"routes registered, registering 404 handler"`. If
   `templatesdir/errors/404.tkt` exists, render it with the site context plus
   `"request.path":"(unknown)"`:
   - Render failed: log at **error** level `"serve: 404 template <path> could
     not be rendered; answering the default 404. The template's own error is
     logged above."` (story 121.61; it was an info line). The client gets the
     default 404, which names nothing.
   - Non-empty output: `http.setnotfound(nfhtml)` and log
     `"custom 404 registered from templates/errors/404.tkt"`.
   - Empty output: log a warning that the template rendered nothing and the
     default 404 is used.
   If the file does not exist, log that the default 404 is used.
5. Log `"starting servedir"`, `http.servedir("/static"; projectdir)`, log
   `"servedir done, starting listen"`. The mount is `projectdir`, not
   `projectdir/static`: toke's servedir keeps the URL prefix (root + path), so
   `/static/x` is `projectdir/static/x` and `/static/ooke.toml` is a 404
   (story 121.25, audit OOK-01; pinned by test/serve/static_mount.sh).
6. Cast `port` and `workers` to `u64`; `rc = serverlisten(...)`.
7. If `rc` is non-zero, log `"server stopped with an error on port <port>
   (host <host>)"` and return `$serveerr` (story 134.40: this result used to be
   discarded, so a failed bind exited 0 with no message). Otherwise return `0`.

**Error handling:** As under Returns. `[tls]` and `[log]` are applied by the
caller (cli.tk) through `servetlscheck` and `serveopenlogs` before `serverun`.

## Control Flow

`cli.tk` calls `servetlscheck`, `serveopenlogs`, then `serverun`. `serverun`
registers every page route up front (`serveregisterstatic`: scan → render →
register, with `serverenderfailed` for a failed render), checks and applies
CORS, installs the custom 404, mounts `/static`, and hands control to
`serverlisten`, which blocks in `http.serveworkerson` or
`http.servetlsworkerson`. `servegetjson` / `servepostjson` are standalone
helpers not called by `serverun`.

## Notes

- **Canonical result form.** All `mt` match arms use `$ok`/`$err`.
- **What a client sees on a template failure.** A page: 500 with the generic
  `servetplerrorbody()`. The 404 template: the default 404. Neither carries a
  template name, path or error; the log carries all three.
- **`http.setnotfound` scope (toke).** The custom 404 body is used by toke's
  static-route dispatcher only; a path that matches no route is answered by the
  router's own `Not Found`. Reported with story 121.61; not an ooke change.
- **Tests.** `test/serve/test_serve.tk` unit-tests `serveregisterstatic` (the
  three passes, the api-prefix rewrite, the `handledpaths` skip, the rendered
  count, and that a missing pages directory fails), `servecorscheck`, and `servegetjson`/`servepostjson`. Live behaviour
  is covered by shell tests in `test/serve/`: `template_errors.sh` (500 on a
  failed template, the error-level 404 log and the escaped fallback page),
  `serve_logs_tls.sh`, `serve_tls_workers.sh`, `serve_host.sh`,
  `static_mount.sh`, `serve_from_parent.sh`, and `test/e2e/test_serve.sh`.
- **Http API consumed via the published stdlib only.** No native symbol is
  touched and no `extern` is declared, per ADR-0005.
