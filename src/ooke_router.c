#include "ooke_router.h"

#include <dirent.h>
#include <sys/stat.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/* ---------------------------------------------------------------------------
 * Internal helpers — string utilities
 * --------------------------------------------------------------------------*/

/* Return 1 if s ends with suffix, 0 otherwise. */
static int str_ends_with(const char *s, const char *suffix) {
    size_t slen = strlen(s);
    size_t suflen = strlen(suffix);
    if (suflen > slen) return 0;
    return strcmp(s + slen - suflen, suffix) == 0;
}

/* Strip a trailing suffix from s in-place. Suffix must be present. */
static void str_strip_suffix(char *s, const char *suffix) {
    size_t slen = strlen(s);
    size_t suflen = strlen(suffix);
    if (suflen <= slen && strcmp(s + slen - suflen, suffix) == 0) {
        s[slen - suflen] = '\0';
    }
}

/* Copy at most n characters from src into dst, always NUL-terminate. */
static void str_copy(char *dst, size_t n, const char *src) {
    snprintf(dst, n, "%s", src);
}

/* ---------------------------------------------------------------------------
 * Internal helpers — route table growth
 * --------------------------------------------------------------------------*/

#define OOKE_ROUTE_INITIAL_CAP 16

static OokeRouteTable *table_alloc(void) {
    OokeRouteTable *t = malloc(sizeof(*t));
    if (!t) return NULL;
    t->routes = malloc(sizeof(OokeRoute) * OOKE_ROUTE_INITIAL_CAP);
    if (!t->routes) { free(t); return NULL; }
    t->count = 0;
    t->cap   = OOKE_ROUTE_INITIAL_CAP;
    return t;
}

static int table_push(OokeRouteTable *t, const OokeRoute *r) {
    if (t->count >= t->cap) {
        size_t newcap = t->cap * 2;
        OokeRoute *newroutes = realloc(t->routes, sizeof(OokeRoute) * newcap);
        if (!newroutes) return -1;
        t->routes = newroutes;
        t->cap    = newcap;
    }
    t->routes[t->count++] = *r;
    return 0;
}

/* ---------------------------------------------------------------------------
 * route_from_path — derive an OokeRoute from a file path
 *
 * pages_dir : root pages directory, e.g. "pages" (no trailing slash)
 * file_path : absolute or relative path to the .tk file
 *             e.g. "pages/blog/[slug].tk"
 *
 * Fills in *out; returns 0 on success, -1 if the file should be skipped.
 * --------------------------------------------------------------------------*/
static int route_from_path(const char *pages_dir,
                            const char *file_path,
                            OokeRoute  *out)
{
    memset(out, 0, sizeof(*out));

    /* Build the full pages_dir prefix we need to strip, with trailing '/'. */
    char prefix[OOKE_ROUTE_PATH_MAX];
    size_t prefix_len = (size_t)snprintf(prefix, sizeof(prefix), "%s/", pages_dir);

    /* file_path must start with the prefix. */
    if (strncmp(file_path, prefix, prefix_len) != 0) return -1;

    /* rel: relative path from pages/, e.g. "blog/[slug].tk" */
    const char *rel = file_path + prefix_len;

    /* Must end with .tk */
    if (!str_ends_with(rel, ".tk")) return -1;

    /* Store the original file path. */
    str_copy(out->file_path, sizeof(out->file_path), file_path);

    /* Check is_api: relative path starts with "api/" */
    out->is_api = (strncmp(rel, "api/", 4) == 0) ? 1 : 0;

    /* Work on a mutable copy of rel without the .tk suffix. */
    char work[OOKE_ROUTE_PATH_MAX];
    str_copy(work, sizeof(work), rel);
    str_strip_suffix(work, ".tk");
    /* work is now e.g. "blog/[slug]" or "index" or "about" */

    /* Split by '/' into segments. */
    char *segments[OOKE_ROUTE_PARAMS_MAX + 8];
    int   seg_count = 0;
    char *tok = strtok(work, "/");
    while (tok && seg_count < (int)(sizeof(segments)/sizeof(segments[0]))) {
        segments[seg_count++] = tok;
        tok = strtok(NULL, "/");
    }

    /* Build the URL pattern segment by segment. */
    char pattern[OOKE_ROUTE_PATTERN_MAX];
    pattern[0] = '\0';
    size_t plen = 0;

    for (int i = 0; i < seg_count; i++) {
        const char *seg = segments[i];

        /* Last segment "index" means directory index — skip it (produces no
         * additional path component, leaving the parent path as-is). */
        if (strcmp(seg, "index") == 0 && i == seg_count - 1) {
            /* directory index: don't append anything */
            continue;
        }

        /* Dynamic segment: [name] → :name */
        if (seg[0] == '[' && seg[strlen(seg) - 1] == ']') {
            /* Extract the param name (without brackets). */
            size_t namelen = strlen(seg) - 2; /* strip '[' and ']' */
            char   paramname[OOKE_ROUTE_PARAM_MAX];
            if (namelen >= sizeof(paramname)) namelen = sizeof(paramname) - 1;
            memcpy(paramname, seg + 1, namelen);
            paramname[namelen] = '\0';

            /* Record the parameter. */
            if (out->param_count < OOKE_ROUTE_PARAMS_MAX) {
                str_copy(out->params[out->param_count],
                         OOKE_ROUTE_PARAM_MAX, paramname);
                out->param_count++;
            }
            out->is_dynamic = 1;

            /* Append /:name to pattern. */
            plen += (size_t)snprintf(pattern + plen, sizeof(pattern) - plen,
                                     "/:%s", paramname);
        } else {
            /* Static segment. */
            plen += (size_t)snprintf(pattern + plen, sizeof(pattern) - plen,
                                     "/%s", seg);
        }
    }

    /* If pattern is empty after processing, we have the root "/". */
    if (plen == 0) {
        str_copy(out->pattern, sizeof(out->pattern), "/");
    } else {
        str_copy(out->pattern, sizeof(out->pattern), pattern);
    }

    return 0;
}

/* ---------------------------------------------------------------------------
 * qsort comparator — static routes before dynamic, then alphabetical
 * --------------------------------------------------------------------------*/
static int route_cmp(const void *a, const void *b) {
    const OokeRoute *ra = (const OokeRoute *)a;
    const OokeRoute *rb = (const OokeRoute *)b;

    /* Static beats dynamic. */
    if (ra->is_dynamic != rb->is_dynamic)
        return ra->is_dynamic - rb->is_dynamic; /* 0 < 1 so static first */

    /* Within same type: alphabetical by pattern. */
    return strcmp(ra->pattern, rb->pattern);
}

/* ---------------------------------------------------------------------------
 * Recursive directory scanner
 *
 * pages_dir : root of the pages tree, e.g. "pages"
 * rel_path  : current path relative to pages_dir, e.g. "blog" (empty string
 *             for the root call)
 * table     : route table to populate
 * --------------------------------------------------------------------------*/
static void scan_dir_recursive(const char *pages_dir,
                                const char *rel_path,
                                OokeRouteTable *table)
{
    /* Build the absolute path to the directory we are scanning. */
    char dir_path[OOKE_ROUTE_PATH_MAX];
    if (rel_path[0] == '\0') {
        snprintf(dir_path, sizeof(dir_path), "%s", pages_dir);
    } else {
        snprintf(dir_path, sizeof(dir_path), "%s/%s", pages_dir, rel_path);
    }

    DIR *d = opendir(dir_path);
    if (!d) {
        fprintf(stderr, "ooke router: cannot open directory '%s'\n", dir_path);
        return;
    }

    struct dirent *entry;
    while ((entry = readdir(d)) != NULL) {
        /* Skip . and .. */
        if (strcmp(entry->d_name, ".") == 0 ||
            strcmp(entry->d_name, "..") == 0)
        {
            continue;
        }

        /* Build the path to this entry. */
        char entry_path[OOKE_ROUTE_PATH_MAX];
        if (rel_path[0] == '\0') {
            snprintf(entry_path, sizeof(entry_path),
                     "%s/%s", pages_dir, entry->d_name);
        } else {
            snprintf(entry_path, sizeof(entry_path),
                     "%s/%s/%s", pages_dir, rel_path, entry->d_name);
        }

        struct stat st;
        if (stat(entry_path, &st) != 0) continue;

        if (S_ISREG(st.st_mode)) {
            /* Regular file — only care about .tk files. */
            if (!str_ends_with(entry->d_name, ".tk")) continue;

            OokeRoute r;
            if (route_from_path(pages_dir, entry_path, &r) == 0) {
                if (table_push(table, &r) != 0) {
                    fprintf(stderr, "ooke router: out of memory\n");
                }
            }
        } else if (S_ISDIR(st.st_mode)) {
            /* Subdirectory — recurse. */
            char new_rel[OOKE_ROUTE_PATH_MAX];
            if (rel_path[0] == '\0') {
                snprintf(new_rel, sizeof(new_rel), "%s", entry->d_name);
            } else {
                snprintf(new_rel, sizeof(new_rel),
                         "%s/%s", rel_path, entry->d_name);
            }
            scan_dir_recursive(pages_dir, new_rel, table);
        }
        /* Ignore symlinks, devices, etc. */
    }

    closedir(d);
}

/* ---------------------------------------------------------------------------
 * ooke_router_scan
 * --------------------------------------------------------------------------*/
OokeRouteTable *ooke_router_scan(const char *pages_dir) {
    OokeRouteTable *table = table_alloc();
    if (!table) {
        fprintf(stderr, "ooke router: out of memory\n");
        return NULL;
    }

    scan_dir_recursive(pages_dir, "", table);

    /* Sort: static routes first, then dynamic; alphabetical within each group. */
    if (table->count > 1) {
        qsort(table->routes, table->count, sizeof(OokeRoute), route_cmp);
    }

    return table;
}

/* ---------------------------------------------------------------------------
 * pattern_match — match url_path against a single route pattern
 *
 * Fills in out_params[i][0] = param name, out_params[i][1] = captured value.
 * Returns 1 on match, 0 on no match.
 * out_param_count is set to the number of params captured.
 * --------------------------------------------------------------------------*/
static int pattern_match(const char *pattern,
                          const char *url_path,
                          char        out_params[OOKE_ROUTE_PARAMS_MAX][2][OOKE_MATCH_VALUE_MAX],
                          int        *out_param_count,
                          const OokeRoute *route)
{
    *out_param_count = 0;

    /* Split both pattern and path by '/'.
     * We make mutable copies on the stack. */
    char pat_buf[OOKE_ROUTE_PATTERN_MAX];
    char url_buf[OOKE_ROUTE_PATTERN_MAX];

    snprintf(pat_buf, sizeof(pat_buf), "%s", pattern);
    snprintf(url_buf, sizeof(url_buf), "%s", url_path);

    /* Tokenise — collect pointers into local arrays. */
    char *pat_segs[OOKE_ROUTE_PARAMS_MAX + 8];
    char *url_segs[OOKE_ROUTE_PARAMS_MAX + 8];
    int   pat_count = 0;
    int   url_count = 0;

    /* Special case: root pattern "/" */
    int pat_is_root = (strcmp(pat_buf, "/") == 0);
    int url_is_root = (strcmp(url_buf, "/") == 0 || url_buf[0] == '\0');

    if (!pat_is_root) {
        char *tok = strtok(pat_buf, "/");
        while (tok && pat_count < (int)(sizeof(pat_segs)/sizeof(pat_segs[0]))) {
            pat_segs[pat_count++] = tok;
            tok = strtok(NULL, "/");
        }
    }

    if (!url_is_root) {
        char *tok = strtok(url_buf, "/");
        while (tok && url_count < (int)(sizeof(url_segs)/sizeof(url_segs[0]))) {
            url_segs[url_count++] = tok;
            tok = strtok(NULL, "/");
        }
    }

    /* Both root → match immediately. */
    if (pat_is_root && url_is_root) {
        return 1;
    }

    /* One root, other not → no match. */
    if (pat_is_root || url_is_root) {
        return 0;
    }

    /* Segment counts must be equal. */
    if (pat_count != url_count) return 0;

    /* Walk both arrays simultaneously. */
    int param_idx = 0;
    for (int i = 0; i < pat_count; i++) {
        const char *ps = pat_segs[i];
        const char *us = url_segs[i];

        if (ps[0] == ':') {
            /* Dynamic segment — capture. */
            const char *name = ps + 1; /* skip ':' */
            if (param_idx < OOKE_ROUTE_PARAMS_MAX) {
                /* param name: use the route's recorded param name if available
                 * (for robustness we also accept the pattern-derived name). */
                const char *recorded_name =
                    (route && param_idx < route->param_count)
                        ? route->params[param_idx]
                        : name;
                snprintf(out_params[param_idx][0],
                         OOKE_MATCH_VALUE_MAX, "%s", recorded_name);
                snprintf(out_params[param_idx][1],
                         OOKE_MATCH_VALUE_MAX, "%s", us);
                param_idx++;
            }
        } else {
            /* Static segment — must match exactly. */
            if (strcmp(ps, us) != 0) return 0;
        }
    }

    *out_param_count = param_idx;
    return 1;
}

/* ---------------------------------------------------------------------------
 * ooke_router_match
 * --------------------------------------------------------------------------*/
OokeRouteMatch ooke_router_match(const OokeRouteTable *table,
                                  const char *url_path)
{
    OokeRouteMatch m;
    memset(&m, 0, sizeof(m));
    m.route = NULL;

    if (!table || !url_path) return m;

    for (size_t i = 0; i < table->count; i++) {
        const OokeRoute *r = &table->routes[i];
        int param_count = 0;
        char params[OOKE_ROUTE_PARAMS_MAX][2][OOKE_MATCH_VALUE_MAX];
        memset(params, 0, sizeof(params));

        if (pattern_match(r->pattern, url_path, params, &param_count, r)) {
            m.route = r;
            m.param_count = param_count;
            memcpy(m.params, params, sizeof(params));
            return m;
        }
    }

    /* No match — route remains NULL. */
    return m;
}

/* ---------------------------------------------------------------------------
 * ooke_router_free
 * --------------------------------------------------------------------------*/
void ooke_router_free(OokeRouteTable *table) {
    if (!table) return;
    free(table->routes);
    free(table);
}

/* ---------------------------------------------------------------------------
 * ooke_router_print
 * --------------------------------------------------------------------------*/
void ooke_router_print(const OokeRouteTable *table) {
    if (!table) return;

    for (size_t i = 0; i < table->count; i++) {
        const OokeRoute *r = &table->routes[i];
        const char *dyn_marker = r->is_dynamic ? "*" : " ";
        const char *methods    = r->is_api     ? "GET/POST" : "GET     ";
        printf("  %s %s %-32s  ->  %s\n",
               dyn_marker, methods, r->pattern, r->file_path);
    }
}
