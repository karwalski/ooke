/*
 * serve.c — ooke live HTTP/HTTPS server
 *
 * Implements ooke_serve():
 *   1. Open access log
 *   2. Scan pages/ → OokeRouteTable
 *   3. Build in-memory page cache (static routes rendered at startup)
 *   4. Register routes with the toke stdlib TkRouter
 *   5. Register /static/ file serving via router_static()
 *   6. Start HTTP or HTTPS server (blocking)
 */

#include "serve.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <errno.h>

/* toke stdlib */
#include "router.h"
#include "log.h"
#include "http.h"

/* ooke modules */
#include "config.h"
#include "ooke_router.h"
#include "store.h"
#include "template.h"

/* ---------------------------------------------------------------------------
 * Global server state (set once in ooke_serve before the server starts)
 * --------------------------------------------------------------------------*/

static const OokeConfig    *g_cfg         = NULL;
static const char          *g_project_dir = NULL;
static OokeRouteTable      *g_routes      = NULL;

/* ---------------------------------------------------------------------------
 * In-memory page cache for static (non-dynamic) routes
 * --------------------------------------------------------------------------*/

#define PAGE_CACHE_MAX 1024

typedef struct {
    char  pattern[OOKE_ROUTE_PATTERN_MAX];
    char *html;   /* heap-allocated; NULL means not yet rendered */
} PageCacheEntry;

static PageCacheEntry g_cache[PAGE_CACHE_MAX];
static int            g_cache_count = 0;

/* Look up a cached page by URL pattern. Returns NULL if not found. */
static const char *cache_get(const char *pattern)
{
    for (int i = 0; i < g_cache_count; i++) {
        if (strcmp(g_cache[i].pattern, pattern) == 0)
            return g_cache[i].html;
    }
    return NULL;
}

/* Store a rendered page into the cache. Takes ownership of html. */
static void cache_put(const char *pattern, char *html)
{
    if (g_cache_count >= PAGE_CACHE_MAX) {
        free(html);
        return;
    }
    strncpy(g_cache[g_cache_count].pattern, pattern, OOKE_ROUTE_PATTERN_MAX - 1);
    g_cache[g_cache_count].pattern[OOKE_ROUTE_PATTERN_MAX - 1] = '\0';
    g_cache[g_cache_count].html = html;
    g_cache_count++;
}

/* ---------------------------------------------------------------------------
 * Extract content type from a .tk file path.
 *
 * Dynamic pages follow the convention:  pages/<type>/[slug].tk
 * We derive the content type from the directory name one level above the
 * file when a dynamic segment is present, e.g.:
 *   pages/blog/[slug].tk  →  "blog"
 *   pages/docs/[slug].tk  →  "docs"
 *
 * If the convention cannot be determined, returns an empty string.
 * out must be at least 128 bytes.
 * --------------------------------------------------------------------------*/

static void extract_content_type(const char *file_path, char *out, size_t outsz)
{
    out[0] = '\0';

    /* Work on a copy so we can tokenise safely */
    char tmp[OOKE_ROUTE_PATH_MAX];
    strncpy(tmp, file_path, sizeof(tmp) - 1);
    tmp[sizeof(tmp) - 1] = '\0';

    /* Strip trailing filename (e.g. "[slug].tk") */
    char *slash = strrchr(tmp, '/');
    if (!slash) return;
    *slash = '\0';

    /* The directory name is now the last component */
    char *dir = strrchr(tmp, '/');
    const char *type = dir ? dir + 1 : tmp;

    /* Skip "pages" itself */
    if (strcmp(type, "pages") == 0) return;

    strncpy(out, type, outsz - 1);
    out[outsz - 1] = '\0';
}

/* ---------------------------------------------------------------------------
 * Build a TplContext from:
 *   - site config fields (prefixed "site.")
 *   - content file frontmatter fields
 * Caller must call tpl_ctx_free() on the returned context.
 * --------------------------------------------------------------------------*/

static TplContext *build_ctx(const OokeConfig *cfg, const ContentFile *cf)
{
    TplContext *ctx = tpl_ctx_new();
    if (!ctx) return NULL;

    /* Site fields */
    tpl_ctx_set(ctx, "site.name",     cfg->site_name);
    tpl_ctx_set(ctx, "site.url",      cfg->site_url);
    tpl_ctx_set(ctx, "site.language", cfg->site_language);

    /* Content frontmatter */
    if (cf) {
        for (size_t i = 0; i < cf->field_count; i++) {
            tpl_ctx_set(ctx, cf->fields[i].key, cf->fields[i].val);
        }
        if (cf->body)  tpl_ctx_set(ctx, "body",  cf->body);
        if (cf->slug)  tpl_ctx_set(ctx, "slug",  cf->slug);
        if (cf->type)  tpl_ctx_set(ctx, "type",  cf->type);
    }

    return ctx;
}

/* ---------------------------------------------------------------------------
 * Render a static page (.tk file with no dynamic params).
 *
 * We look for a companion template at:
 *   templates/<stem>.tkt
 * where stem is derived from the .tk file path, e.g.:
 *   pages/about.tk  →  templates/about.tkt
 *   pages/index.tk  →  templates/index.tkt
 *
 * Returns heap-allocated HTML string (caller frees), or NULL on error.
 * --------------------------------------------------------------------------*/

static char *render_static_page(const OokeRoute *route, const OokeConfig *cfg)
{
    /* Derive template name from file path:
     * "pages/blog/index.tk" → stem = "blog/index" → "templates/blog/index.tkt" */
    const char *fp = route->file_path;
    const char *pages_prefix = "pages/";
    if (strncmp(fp, pages_prefix, strlen(pages_prefix)) == 0)
        fp += strlen(pages_prefix);

    /* Strip .tk suffix */
    char stem[OOKE_ROUTE_PATH_MAX];
    strncpy(stem, fp, sizeof(stem) - 1);
    stem[sizeof(stem) - 1] = '\0';
    size_t slen = strlen(stem);
    if (slen > 3 && strcmp(stem + slen - 3, ".tk") == 0)
        stem[slen - 3] = '\0';

    char tpl_path[OOKE_ROUTE_PATH_MAX * 2];
    snprintf(tpl_path, sizeof(tpl_path), "templates/%s.tkt", stem);

    /* Check template exists; if not, return a minimal fallback */
    struct stat st;
    if (stat(tpl_path, &st) != 0) {
        /* No template — return a bare placeholder so the route still works */
        char *html = malloc(256);
        if (!html) return NULL;
        snprintf(html, 256,
                 "<!DOCTYPE html><html><body>"
                 "<p>Page: %s</p>"
                 "</body></html>",
                 route->pattern);
        return html;
    }

    TplContext *ctx = build_ctx(cfg, NULL);
    if (!ctx) return NULL;

    char *html = tpl_renderfile(tpl_path, ctx, "templates");
    tpl_ctx_free(ctx);
    return html;
}

/* ---------------------------------------------------------------------------
 * Render a dynamic page for a matched request.
 *
 * Extracts the slug from matched params, loads the content item, renders
 * the template.
 *
 * Returns heap-allocated HTML string (caller frees), or NULL on error.
 * --------------------------------------------------------------------------*/

static char *render_dynamic_page(const OokeRoute *route,
                                 const OokeRouteMatch *match,
                                 const OokeConfig *cfg)
{
    /* Find the slug param value */
    const char *slug = NULL;
    for (int i = 0; i < match->param_count; i++) {
        if (strcmp(match->params[i][0], "slug") == 0) {
            slug = match->params[i][1];
            break;
        }
    }

    /* Derive content type from the .tk file path */
    char content_type[128];
    extract_content_type(route->file_path, content_type, sizeof(content_type));

    /* Load content item from content/<type>/ */
    char content_dir[OOKE_ROUTE_PATH_MAX];
    snprintf(content_dir, sizeof(content_dir), "content");

    ContentFile *cf = NULL;
    ContentCollection col = { NULL, 0, 0 };
    int loaded = 0;

    if (slug && content_type[0]) {
        col = store_all(content_dir, content_type);
        const ContentFile *found = store_slug(&col, slug);
        if (found) {
            cf = (ContentFile *)found; /* safe: we own col */
            loaded = 1;
        }
    }

    /* Derive template path */
    const char *fp = route->file_path;
    const char *pages_prefix = "pages/";
    if (strncmp(fp, pages_prefix, strlen(pages_prefix)) == 0)
        fp += strlen(pages_prefix);

    char stem[OOKE_ROUTE_PATH_MAX];
    strncpy(stem, fp, sizeof(stem) - 1);
    stem[sizeof(stem) - 1] = '\0';
    size_t slen = strlen(stem);
    if (slen > 3 && strcmp(stem + slen - 3, ".tk") == 0)
        stem[slen - 3] = '\0';

    char tpl_path[OOKE_ROUTE_PATH_MAX * 2];
    snprintf(tpl_path, sizeof(tpl_path), "templates/%s.tkt", stem);

    /* Build context and render */
    TplContext *ctx = build_ctx(cfg, cf);
    char *html = NULL;

    if (ctx) {
        /* Also expose matched param values */
        for (int i = 0; i < match->param_count; i++) {
            tpl_ctx_set(ctx, match->params[i][0], match->params[i][1]);
        }

        struct stat st;
        if (stat(tpl_path, &st) == 0) {
            html = tpl_renderfile(tpl_path, ctx, "templates");
        } else {
            /* Fallback: simple HTML showing the slug */
            html = malloc(512);
            if (html) {
                snprintf(html, 512,
                         "<!DOCTYPE html><html><body>"
                         "<p>Content: %s / %s</p>"
                         "</body></html>",
                         content_type[0] ? content_type : "unknown",
                         slug ? slug : "(no slug)");
            }
        }
        tpl_ctx_free(ctx);
    }

    if (loaded)
        store_free_collection(&col);

    return html;
}

/* ---------------------------------------------------------------------------
 * Route handler — dispatches every GET request through the ooke route table.
 *
 * Signature must match TkRouteHandler: TkRouteResp (*)(TkRouteCtx ctx)
 * --------------------------------------------------------------------------*/

static TkRouteResp ooke_dispatch(TkRouteCtx ctx)
{
    const char *path = ctx.path ? ctx.path : "/";

    /* Match against the ooke route table */
    OokeRouteMatch match = ooke_router_match(g_routes, path);

    if (!match.route) {
        return router_resp_status(404,
            "<!DOCTYPE html><html><body><h1>404 Not Found</h1></body></html>");
    }

    const OokeRoute *route = match.route;

    /* API routes: not supported in Phase 1 */
    if (route->is_api) {
        return router_resp_status(501,
            "<!DOCTYPE html><html><body><h1>501 Not Implemented</h1>"
            "<p>API routes are not supported in serve mode (Phase 1).</p>"
            "</body></html>");
    }

    char *html = NULL;

    if (!route->is_dynamic) {
        /* Static route: serve from cache */
        const char *cached = cache_get(route->pattern);
        if (cached) {
            /* router_resp_ok expects a non-freeable pointer; we must copy */
            return router_resp_ok(cached, "text/html; charset=utf-8");
        }
        /* Not in cache (shouldn't happen after startup warmup, but handle it) */
        html = render_static_page(route, g_cfg);
    } else {
        /* Dynamic route: render on demand */
        html = render_dynamic_page(route, &match, g_cfg);
    }

    if (!html) {
        return router_resp_status(500,
            "<!DOCTYPE html><html><body><h1>500 Internal Server Error</h1>"
            "</body></html>");
    }

    /* Build response; router_resp_ok copies nothing — we must keep html alive.
     * For dynamic pages we return the pointer directly; the stdlib copies the
     * body before handler returns (per the toke router contract).
     * We free after composing the response struct. */
    TkRouteResp resp = router_resp_ok(html, "text/html; charset=utf-8");
    free(html);
    return resp;
}

/* ---------------------------------------------------------------------------
 * Warm up the page cache: render all non-dynamic routes at startup.
 * --------------------------------------------------------------------------*/

static void warmup_cache(const OokeRouteTable *routes, const OokeConfig *cfg)
{
    for (size_t i = 0; i < routes->count; i++) {
        const OokeRoute *r = &routes->routes[i];
        if (r->is_dynamic || r->is_api)
            continue;

        char *html = render_static_page(r, cfg);
        if (html) {
            cache_put(r->pattern, html);
            /* html ownership transferred to cache */
        }
    }
}

/* ---------------------------------------------------------------------------
 * Resolve the static/ directory relative to project_dir.
 * --------------------------------------------------------------------------*/

static void build_static_dir(const char *project_dir, char *out, size_t outsz)
{
    if (project_dir && strcmp(project_dir, ".") != 0) {
        snprintf(out, outsz, "%s/static", project_dir);
    } else {
        strncpy(out, "static", outsz - 1);
        out[outsz - 1] = '\0';
    }
}

/* ---------------------------------------------------------------------------
 * ooke_serve — public entry point
 * --------------------------------------------------------------------------*/

int ooke_serve(const char *project_dir, const OokeConfig *cfg,
               const char *cert_path, const char *key_path)
{
    /* Store globals for use by the route handler */
    g_cfg         = cfg;
    g_project_dir = project_dir ? project_dir : ".";

    /* Change working directory to project root so relative paths work */
    if (project_dir && strcmp(project_dir, ".") != 0) {
        if (chdir(project_dir) != 0) {
            fprintf(stderr, "ooke serve: cannot chdir to '%s': %s\n",
                    project_dir, strerror(errno));
            return 1;
        }
    }

    /* Print startup banner */
    const char *scheme = (cert_path && key_path) ? "https" : "http";
    printf("ooke serving at %s://0.0.0.0:%d\n", scheme, cfg->server_port);
    printf("  workers: %d\n",
           cfg->server_workers > 0 ? cfg->server_workers : 1);
    fflush(stdout);

    /* Open access log */
    TkAccessLog *access_log = NULL;
    if (cfg->log_access[0]) {
        access_log = tk_access_log_open(cfg->log_access,
                                        cfg->log_max_lines,
                                        0,
                                        cfg->log_max_age_days);
        if (access_log)
            tk_access_log_set_global(access_log);
        else
            fprintf(stderr, "ooke serve: warning: could not open access log '%s'\n",
                    cfg->log_access);
    }

    /* Scan pages/ directory */
    g_routes = ooke_router_scan("pages");
    if (!g_routes) {
        fprintf(stderr, "ooke serve: failed to scan pages/ directory\n");
        tk_access_log_close(access_log);
        return 1;
    }

    printf("  routes: %zu\n", g_routes->count);

    /* Warm up static page cache */
    warmup_cache(g_routes, cfg);
    printf("  cached: %d static page(s)\n", g_cache_count);
    fflush(stdout);

    /* Build toke router */
    TkRouter *router = router_new();
    if (!router) {
        fprintf(stderr, "ooke serve: failed to create router\n");
        ooke_router_free(g_routes);
        tk_access_log_close(access_log);
        return 1;
    }

    /* Serve static assets from static/ */
    char static_dir[1024];
    build_static_dir(".", static_dir, sizeof(static_dir));
    router_static(router, "/static/", static_dir);

    /* Catch-all GET handler — ooke_dispatch handles all page routing */
    router_get(router, "/:path*", ooke_dispatch);
    /* Also handle bare "/" */
    router_get(router, "/", ooke_dispatch);

    /* Add access logging middleware (uses the global access log file) */
    if (access_log)
        router_use_log(router, ROUTER_LOG_COMMON, cfg->log_access);

    /* Start server */
    int nworkers = cfg->server_workers > 0 ? cfg->server_workers : 1;
    int result   = 0;

    if (cert_path && key_path) {
        /* TLS */
        TkTlsCtx *tls = http_tls_ctx_new(cert_path, key_path);
        if (!tls) {
            fprintf(stderr, "ooke serve: failed to load TLS cert/key\n");
            router_free(router);
            ooke_router_free(g_routes);
            tk_access_log_close(access_log);
            return 1;
        }

        /* Capture current route table into a TkHttpRouter for worker pool */
        /* Note: http_serve_tls_workers uses the global http route table,
         * not the TkRouter. We use router_serve for non-TLS and
         * http_serve_tls_workers for TLS (registering via http_GET first). */
        (void)nworkers; /* TLS path: use single-process TLS for Phase 1 */
        TkHttpErr err = http_serve_tls(NULL, NULL,
                                       (uint64_t)cfg->server_port, tls);
        if (err != TK_HTTP_OK) {
            fprintf(stderr, "ooke serve: TLS server error %d\n", (int)err);
            result = 1;
        }
        http_tls_ctx_free(tls);
    } else {
        /* Plain HTTP — use TkRouter (handles workers internally via router_serve) */
        TkRouterErr err = router_serve(router, NULL,
                                       (uint64_t)cfg->server_port);
        if (err.failed) {
            fprintf(stderr, "ooke serve: server error: %s\n",
                    err.msg ? err.msg : "(unknown)");
            result = 1;
        }
    }

    /* Cleanup (reached only after server exits) */
    router_free(router);
    ooke_router_free(g_routes);

    for (int i = 0; i < g_cache_count; i++)
        free(g_cache[i].html);
    g_cache_count = 0;

    tk_access_log_close(access_log);

    return result;
}
