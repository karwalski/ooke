#ifndef OOKE_ROUTER_H
#define OOKE_ROUTER_H

#include <stddef.h>

/* ---------------------------------------------------------------------------
 * ooke file-system router
 *
 * Routes are derived from the directory structure under pages/:
 *
 *   pages/index.tk          ->  GET /
 *   pages/about.tk          ->  GET /about
 *   pages/blog/index.tk     ->  GET /blog
 *   pages/blog/[slug].tk    ->  GET /blog/:slug   (dynamic segment)
 *   pages/api/posts.tk      ->  GET /api/posts, POST /api/posts
 * --------------------------------------------------------------------------*/

#define OOKE_ROUTE_PATTERN_MAX  512
#define OOKE_ROUTE_PATH_MAX     512
#define OOKE_ROUTE_PARAMS_MAX   16
#define OOKE_ROUTE_PARAM_MAX    64
#define OOKE_MATCH_VALUE_MAX    256

/* A single route entry. */
typedef struct {
    char pattern[OOKE_ROUTE_PATTERN_MAX];   /* URL pattern, e.g. "/blog/:slug"           */
    char file_path[OOKE_ROUTE_PATH_MAX];    /* Path to .tk handler, e.g. "pages/blog/[slug].tk" */
    char params[OOKE_ROUTE_PARAMS_MAX][OOKE_ROUTE_PARAM_MAX]; /* Named param names, e.g. {"slug"} */
    int  param_count;
    int  is_dynamic;    /* 1 if any dynamic segments, 0 if fully static */
    int  is_api;        /* 1 if under pages/api/ (supports POST, PUT, DELETE) */
} OokeRoute;

/* The full route table. */
typedef struct {
    OokeRoute *routes;
    size_t     count;
    size_t     cap;
} OokeRouteTable;

/* Result of matching a URL against the route table. */
typedef struct {
    const OokeRoute *route;     /* NULL if no match */
    char params[OOKE_ROUTE_PARAMS_MAX][2][OOKE_MATCH_VALUE_MAX];
                                /* params[i][0]=name, params[i][1]=value */
    int  param_count;
} OokeRouteMatch;

/* ---------------------------------------------------------------------------
 * Public API
 * --------------------------------------------------------------------------*/

/* Scan pages/ directory and build route table.
 * Returns a heap-allocated table; caller must free with ooke_router_free().
 * Returns an empty (non-NULL) table on error. */
OokeRouteTable *ooke_router_scan(const char *pages_dir);

/* Match an incoming URL path against the route table.
 * Static routes are checked before dynamic routes.
 * Returns a match with route=NULL if no match is found. */
OokeRouteMatch ooke_router_match(const OokeRouteTable *table, const char *url_path);

/* Free the route table and all associated memory. */
void ooke_router_free(OokeRouteTable *table);

/* Print all routes to stdout (for debugging / ooke build output).
 * Dynamic routes are marked with '*'. */
void ooke_router_print(const OokeRouteTable *table);

#endif /* OOKE_ROUTER_H */
