---
source_file: "serve.tk"
source_hash: "59e8b242ef51129a56eb496ef5359e3f44e299d750ff2c1fb7173a07259ba03d"
compiler_version: "0.3.9"
generated_at: "2026-06-16T00:00:00Z"
format_version: "1.0"
---

## Module

**Name:** `ooke.serve`

Compiles an ooke site into a live HTTP server. It scans the project's `pages/`
directory for routes, renders each page's template, and registers the result as
a static GET (or JSON GET + echo POST for API routes) handler. It then wires up
CORS, a custom 404 page, a `/static` file mount, and finally starts either an
HTTP worker pool or an HTTPS/TLS listener. Most behaviour is observable only
against a running server (covered by `test/e2e/*.sh`); the pure registration,
api-prefix path-rewrite, and dedup logic is unit-tested in `test/serve/`.

**Imports:**
- `std.http` (alias `http`) — static/JSON route registration, CORS, custom 404,
  static-dir mount, and the worker-pool / TLS listeners.
- `std.log` (alias `log`) — structured info logging of each registration step.
- `std.file` (alias `file`) — `file.exists` probe for the optional 404 template.
- `std.str` (alias `str`) — string building, prefix/suffix tests, replace, eq.
- `std.path` (alias `path`) — join project subdirectories.
- `ooke.router` (alias `ookerouter`) — scan `pages/` into `$route` records.
- `ooke.template` (alias `tpl`) — render `.tkt` templates with a context map.
- `ooke.store` (alias `store`) — load content collections for dynamic routes.

## Types

### `$serveerr`

Error type for `serverun`.

| Field | Type | Description |
|-------|------|-------------|
| `msg` | `$str` | Human-readable failure description. |

## Functions

### `servegetjson(pattern: $str; json: $str): void`

**Purpose:** Register a static GET route that returns a fixed JSON body.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `pattern` | `$str` | The URL path to register. |
| `json` | `$str` | The JSON body to serve verbatim. |

**Returns:** `void`.

**Logic:**

1. Call `http.getstaticmime(pattern; json; "application/json")` to register the
   route with an explicit `application/json` Content-Type.
2. Log an info line `"static json GET: " + pattern`.

**Error handling:** None.

### `servepostjson(pattern: $str; json: $str): void`

**Purpose:** Register a static POST route that returns a fixed JSON body.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `pattern` | `$str` | The URL path to register. |
| `json` | `$str` | The JSON body to serve verbatim. |

**Returns:** `void`.

**Logic:**

1. Call `http.postjson(pattern; json)` to register the POST route.
2. Log an info line `"static json POST: " + pattern`.

**Error handling:** None.

### `serveregisterstatic(pagesdir: $str; contentdir: $str; templatesdir: $str; sitename: $str; siteurl: $str; sitelanguage: $str; apiprefix: $str; handledpaths: @$str): void`

**Purpose:** Scan the pages directory and register every page as a static HTTP
route, in three passes: plain static pages, dynamic content pages, and API
routes. Dynamic handler paths in `handledpaths` are skipped so a live handler
takes precedence over a static fallback.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `pagesdir` | `$str` | Directory scanned for page routes. |
| `contentdir` | `$str` | Directory of content collections (for dynamic routes). |
| `templatesdir` | `$str` | Directory used as the template render base. |
| `sitename` | `$str` | `site.name` context value. |
| `siteurl` | `$str` | `site.url` context value. |
| `sitelanguage` | `$str` | `site.language` context value. |
| `apiprefix` | `$str` | When non-empty, namespaces `/api/...` paths as `/api/<prefix>/...`. |
| `handledpaths` | `@$str` | Paths already served by a dynamic handler; skip these. |

**Returns:** `void`.

**Logic:**

1. Scan routes: `routes = mt ookerouter.routerscan(pagesdir) {$ok:r r; $err:e @($route)}`.
   On scan failure fall back to a one-element default-route array.
2. **Pass 1 — static, non-API pages.** Loop `i` from `0` to `routes.len`
   (exclusive). For each route `r` where `!r.isdynamic && !r.isapi`:
   a. Start `webpath` mutable at `r.pattern`. If `r.pattern` starts with
      `"/api/"` **and** `apiprefix` is non-empty, rewrite it to
      `"/api/" + apiprefix + "/" + (pattern with "/api/" prefix trimmed)`.
   b. Set a mutable flag `alreadyhandled = false`; loop over `handledpaths` and
      set it `true` if any equals `webpath` (via `str.eq`).
   c. If `alreadyhandled`, log a skip line and do nothing else.
   d. Otherwise build a context map `@("site.name":sitename; "site.url":siteurl;
      "site.language":sitelanguage)` and render the route's `templatepath` with
      `tpl.tplrenderfile(tpath; ctx; templatesdir)`, matched `{$ok:h h; $err:e ""}`.
      - If the rendered `html` is non-empty: log `"reg static: " + webpath` and
        register it via `http.getstatic(webpath; html)`.
      - If empty and `webpath` starts with `"/api/"`: build a default JSON body
        `{"status":"ok","endpoint":"<webpath>"}`, log, register it via
        `http.getstaticmime(webpath; defaultjson; "application/json")`, and add
        an echo POST handler via `http.postecho(webpath)`.
      - If empty and not an API path: build fallback HTML
        `<html><body><p><webpath></p></body></html>`, log, and register via
        `http.getstatic(webpath; fallbackhtml)`.
3. **Pass 2 — dynamic, non-API pages.** Loop `j` over routes. For each route
   where `isdynamic && !isapi`:
   a. Take its `contenttype` and load the collection via
      `store.storeall(contentdir; ctype; "flat")`, matched `{$ok:c c; $err:e @()}`.
   b. Loop `k` over the collection. For each item read `slug`, `body`, `title`,
      build a context map adding `slug`/`body`/`title` to the site fields, and
      render the route's `templatepath`.
      - If the rendered `html2` is non-empty: compute `fullurl` by replacing
        `":slug"` in the route pattern with the item's `slug`, log
        `"reg dyn: " + fullurl`, and register via `http.getstatic(fullurl; html2)`.
      - Otherwise log a `"skip dyn (no html): " + slug` line.
4. **Pass 3 — API routes.** Loop `a` over routes. For each route `ra` where
   `ra.isapi`:
   a. Start `apipath` mutable at `ra.pattern`. If `apiprefix` is non-empty,
      rewrite to `"/api/" + apiprefix + "/" + (pattern with "/api/" trimmed)`.
   b. Set `apihandled = false`; loop over `handledpaths` and set it `true` if any
      equals `apipath`.
   c. If `apihandled`, log a skip line. Otherwise log a fallback line, build the
      default JSON body `{"status":"ok","endpoint":"<apipath>"}`, register it via
      `http.getstaticmime(apipath; defaultjson; "application/json")`, and add an
      echo POST via `http.postecho(apipath)`.

**Error handling:** Both fallible calls (`routerscan`, `storeall`) are matched
with total `mt … {$ok…; $err…}` arms that fall back to an empty/default
collection; the function never raises.

### `serverun(projectdir: $str; port: i64; workers: i64; buildoutput: $str; tlscert: $str; tlskey: $str; sitename: $str; siteurl: $str; sitelanguage: $str; apiprefix: $str; corsorigins: $str; handledpaths: @$str): i64!$serveerr`

**Purpose:** Wire up and start the live HTTP(S) server for a project: register
all static routes, enable CORS, install a custom 404, mount `/static`, and start
either the HTTP worker pool or the TLS listener. This call blocks in the
listener and does not return under normal operation.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `projectdir` | `$str` | Project root (contains `pages/`, `content/`, `templates/`). |
| `port` | `i64` | TCP port to listen on. |
| `workers` | `i64` | Worker count for the HTTP pool. |
| `buildoutput` | `$str` | Static build output dir (accepted for signature parity). |
| `tlscert` | `$str` | TLS certificate path; empty selects plain HTTP. |
| `tlskey` | `$str` | TLS key path (used only when `tlscert` is non-empty). |
| `sitename` | `$str` | `site.name` context value. |
| `siteurl` | `$str` | `site.url` context value. |
| `sitelanguage` | `$str` | `site.language` context value. |
| `apiprefix` | `$str` | API path namespace prefix. |
| `corsorigins` | `$str` | CORS allow-origin; empty disables CORS. |
| `handledpaths` | `@$str` | Paths already served by dynamic handlers. |

**Returns:** `i64!$serveerr` — does not return normally (the listener blocks);
the type permits `$serveerr` for plumbing parity.

**Logic:**

1. Join `projectdir` with `"pages"`, `"content"`, `"templates"` to get the three
   subdirectories.
2. Call `serveregisterstatic` with those directories, the site context, the
   `apiprefix`, and `handledpaths` to register every static route.
3. If `corsorigins` is non-empty, call `http.setcors(corsorigins)` and log
   `"CORS enabled: " + corsorigins`. Otherwise do nothing.
4. Log a "registering 404 handler" line. Build the 404 template path
   `templatesdir + "/errors/404.tkt"`. If `file.exists` of that path is true,
   render it with a context that also carries `"request.path":"(unknown)"`,
   matched `{$ok:h h; $err:e ""}`:
   - If the rendered HTML is non-empty, install it via `http.setnotfound(nfhtml)`
     and log success.
   - Otherwise log that the render failed and fall back to the default 404.
   If the template file does not exist, log that the default 404 is used.
5. Log "starting servedir" and mount the static directory with
   `http.servedir("/static"; projectdir)`, then log "servedir done".
6. Cast `port` and `workers` to `u64` as `uport`/`uworkers`.
7. If `tlscert` is not equal to `""` (i.e. TLS certs were provided): log the
   HTTPS mode line and call `http.servetls(uport; tlscert; tlskey)`. Otherwise
   log the HTTP mode line and call `http.serveworkers(uport; uworkers)`.

**Error handling:** The function's return type carries `$serveerr` for parity,
but the body raises no errors directly; all fallible sub-calls are handled
inside `serveregisterstatic`. The listener call blocks.

## Control Flow

`serverun` is the entry point. It performs all route registration up front
(delegating the three-pass scan/render/register to `serveregisterstatic`), then
configures CORS, the custom 404, and the `/static` mount, and finally transfers
control to a blocking listener — `http.servetls` when TLS certs are present,
otherwise `http.serveworkers`. `servegetjson` / `servepostjson` are standalone
helpers for registering fixed-body JSON endpoints and are not called by
`serverun`. Data flows from the router scan into per-route template renders whose
output becomes the registered static body.

## Notes

- **Canonical result form.** All `mt` match arms use the spec-canonical
  `$ok`/`$err` variant names (toke-spec-prompt.md: "Variants are `$lowercase`").
  The previous source used the non-canonical `Ok`/`Err`; this is the only
  behavioural-equivalent change versus the reference (Track B 113.B.9).
- **Live behaviour is e2e-tested.** A real listener cannot run inside a unit
  test, so `serverun` (CORS enable, 404 install, `/static` mount, TLS vs worker
  listener) is covered by `test/e2e/test_serve.sh`. The unit test in
  `test/serve/test_serve.tk` exercises the pure, non-blocking surface:
  `serveregisterstatic` over a synthesized fixture (static, dynamic, and API
  passes), the api-prefix path rewrite (non-empty `apiprefix`), the
  `handledpaths` dedup skip, and the `servegetjson`/`servepostjson` helpers.
- **`void` return type.** `servegetjson`, `servepostjson`, and
  `serveregisterstatic` declare `:void` (the spec's unit type, semantics.md
  §predefined types), matching the `ooke.serve.tki` interface and the sibling
  rebuilt modules. The compiler emits a `W1020` lint nudge for the `void`
  keyword; this is a warning, not an error, and the construct is spec-valid.
- **Http API consumed via the published stdlib only.** Registration uses
  `http.getstatic`, `http.getstaticmime`, `http.postjson`, `http.postecho`,
  `http.setcors`, `http.setnotfound`, `http.servedir`, `http.servetls`, and
  `http.serveworkers` from `std.http`. No native symbol is touched and no
  `extern` is declared, per ADR-0005.
