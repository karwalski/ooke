#include "build.h"
#include "config.h"
#include "ooke_router.h"
#include "store.h"
#include "template.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <dirent.h>
#include <errno.h>

/* -------------------------------------------------------------------------
 * Internal helpers: makedirs, write_html_file
 * ---------------------------------------------------------------------- */

static int makedirs(const char *path) {
    char tmp[1024];
    size_t len = strlen(path);
    if (len == 0 || len >= sizeof(tmp)) return -1;

    memcpy(tmp, path, len + 1);

    /* Strip trailing slash */
    if (tmp[len - 1] == '/') {
        tmp[len - 1] = '\0';
        len--;
    }

    for (size_t i = 1; i <= len; i++) {
        if (tmp[i] == '/' || tmp[i] == '\0') {
            char save = tmp[i];
            tmp[i] = '\0';
            if (mkdir(tmp, S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH) != 0) {
                if (errno != EEXIST) {
                    fprintf(stderr, "ooke build: mkdir '%s' failed: %s\n", tmp, strerror(errno));
                    return -1;
                }
            }
            tmp[i] = save;
        }
    }
    return 0;
}

static int write_html_file(const char *path, const char *html) {
    /* Create parent directories */
    char dir[1024];
    const char *last_slash = strrchr(path, '/');
    if (last_slash) {
        size_t dir_len = (size_t)(last_slash - path);
        if (dir_len >= sizeof(dir)) {
            fprintf(stderr, "ooke build: path too long: %s\n", path);
            return -1;
        }
        memcpy(dir, path, dir_len);
        dir[dir_len] = '\0';
        if (makedirs(dir) != 0) return -1;
    }

    FILE *f = fopen(path, "w");
    if (!f) {
        fprintf(stderr, "ooke build: cannot write '%s': %s\n", path, strerror(errno));
        return -1;
    }
    fputs(html, f);
    fclose(f);
    return 0;
}

/* -------------------------------------------------------------------------
 * Page handler source parsers
 * ---------------------------------------------------------------------- */

/* Extract the first quoted argument from a tpl.renderfile("..."; ...) call.
 * Returns heap-allocated string or NULL. Caller frees. */
static char *extract_template_path(const char *source) {
    const char *needle = "tpl.renderfile(\"";
    const char *p = strstr(source, needle);
    if (!p) return NULL;
    p += strlen(needle);

    const char *end = strchr(p, '"');
    if (!end) return NULL;

    size_t len = (size_t)(end - p);
    char *result = (char *)malloc(len + 1);
    if (!result) return NULL;
    memcpy(result, p, len);
    result[len] = '\0';
    return result;
}

/* Extract the content type from store.all("...") or store.slug("...") calls.
 * Returns heap-allocated string or NULL. Caller frees. */
static char *extract_content_type(const char *source) {
    const char *needles[] = { "store.all(\"", "store.slug(\"", NULL };
    for (int i = 0; needles[i]; i++) {
        const char *p = strstr(source, needles[i]);
        if (p) {
            p += strlen(needles[i]);
            const char *end = strchr(p, '"');
            if (!end) continue;
            size_t len = (size_t)(end - p);
            char *result = (char *)malloc(len + 1);
            if (!result) return NULL;
            memcpy(result, p, len);
            result[len] = '\0';
            return result;
        }
    }
    return NULL;
}

/* Parse all @("key":"value") pairs from source and add them to ctx.
 * Returns a new TplContext (heap allocated). Caller must tpl_ctx_free(). */
static TplContext *extract_static_context(const char *source) {
    TplContext *ctx = tpl_ctx_new();
    if (!ctx) return NULL;

    const char *p = source;
    while ((p = strstr(p, "@(\"")) != NULL) {
        p += 3; /* skip @(" */

        /* Read key */
        const char *key_end = strchr(p, '"');
        if (!key_end) break;
        size_t key_len = (size_t)(key_end - p);

        /* Expect ":"  after key */
        const char *after_key = key_end + 1;
        if (*after_key != ':') {
            p = key_end + 1;
            continue;
        }
        after_key++; /* skip : */
        if (*after_key != '"') {
            p = after_key;
            continue;
        }
        after_key++; /* skip opening " of value */

        const char *val_end = strchr(after_key, '"');
        if (!val_end) break;
        size_t val_len = (size_t)(val_end - after_key);

        char *key = (char *)malloc(key_len + 1);
        char *val = (char *)malloc(val_len + 1);
        if (key && val) {
            memcpy(key, p, key_len);
            key[key_len] = '\0';
            memcpy(val, after_key, val_len);
            val[val_len] = '\0';
            tpl_ctx_set(ctx, key, val);
        }
        free(key);
        free(val);

        p = val_end + 1;
    }

    return ctx;
}

/* -------------------------------------------------------------------------
 * Output path computation
 * ---------------------------------------------------------------------- */

/* Compute the output file path for a route + optional slug.
 * Result is written into out_buf (size out_sz).
 * pattern "/" -> build_output/index.html
 * pattern "/about" -> build_output/about/index.html
 * pattern "/blog/:slug" + slug="hello" -> build_output/blog/hello/index.html
 */
static void build_output_path(const OokeConfig *cfg, const OokeRoute *route,
                               const char *slug, char *out_buf, size_t out_sz) {
    /* Strip trailing slash from build_output */
    char base[256];
    size_t blen = strlen(cfg->build_output);
    if (blen == 0) {
        strncpy(base, "build", sizeof(base) - 1);
        base[sizeof(base) - 1] = '\0';
    } else {
        strncpy(base, cfg->build_output, sizeof(base) - 1);
        base[sizeof(base) - 1] = '\0';
        if (base[blen - 1] == '/') base[blen - 1] = '\0';
    }

    const char *pattern = route->pattern;

    if (strcmp(pattern, "/") == 0) {
        snprintf(out_buf, out_sz, "%s/index.html", base);
        return;
    }

    /* Build path by substituting :param with slug */
    char expanded[512];
    if (slug && route->is_dynamic) {
        char *out_p = expanded;
        const char *in_p = pattern;
        size_t remaining = sizeof(expanded) - 1;

        while (*in_p && remaining > 0) {
            if (*in_p == ':') {
                /* Find end of param name */
                const char *param_end = in_p + 1;
                while (*param_end && *param_end != '/' && *param_end != '\0')
                    param_end++;
                /* Replace with slug */
                size_t slug_len = strlen(slug);
                if (slug_len > remaining) slug_len = remaining;
                memcpy(out_p, slug, slug_len);
                out_p += slug_len;
                remaining -= slug_len;
                in_p = param_end;
            } else {
                *out_p++ = *in_p++;
                remaining--;
            }
        }
        *out_p = '\0';
    } else {
        strncpy(expanded, pattern, sizeof(expanded) - 1);
        expanded[sizeof(expanded) - 1] = '\0';
    }

    /* expanded is like "/blog/hello" — append /index.html */
    snprintf(out_buf, out_sz, "%s%s/index.html", base, expanded);
}

/* -------------------------------------------------------------------------
 * Read a file into a heap-allocated string. Caller frees.
 * ---------------------------------------------------------------------- */
static char *read_file_str(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    rewind(f);
    if (size < 0) { fclose(f); return NULL; }

    char *buf = (char *)malloc((size_t)size + 1);
    if (!buf) { fclose(f); return NULL; }

    size_t n = fread(buf, 1, (size_t)size, f);
    fclose(f);
    buf[n] = '\0';
    return buf;
}

/* -------------------------------------------------------------------------
 * Build a single static page
 * ---------------------------------------------------------------------- */

static char *build_static_page(const char *project_dir, const OokeRoute *route,
                                const OokeConfig *cfg) {
    (void)project_dir;

    /* Read handler source */
    char *source = read_file_str(route->file_path);
    if (!source) {
        fprintf(stderr, "ooke build: cannot read handler '%s'\n", route->file_path);
        return NULL;
    }

    /* Extract template path */
    char *tpl_path = extract_template_path(source);
    if (!tpl_path) {
        fprintf(stderr, "ooke build: no tpl.renderfile() call in '%s', skipping\n", route->file_path);
        free(source);
        return NULL;
    }

    /* Build context */
    TplContext *ctx = extract_static_context(source);
    free(source);
    if (!ctx) ctx = tpl_ctx_new();

    /* Add site context */
    tpl_ctx_set(ctx, "site.name", cfg->site_name);
    tpl_ctx_set(ctx, "site.url",  cfg->site_url);

    /* Render */
    char *html = tpl_renderfile(tpl_path, ctx, "templates");
    free(tpl_path);
    tpl_ctx_free(ctx);

    if (!html) {
        fprintf(stderr, "ooke build: template render failed for route '%s'\n", route->pattern);
        return NULL;
    }

    /* Post-process */
    if (cfg->build_inline_css) {
        char *inlined = html_inline_css(html, cfg->build_output, "static");
        if (inlined) { free(html); html = inlined; }
    }
    if (cfg->build_minify) {
        char *minified = html_minify(html);
        if (minified) { free(html); html = minified; }
    }

    return html;
}

/* -------------------------------------------------------------------------
 * Build dynamic pages (one per content item)
 * ---------------------------------------------------------------------- */

static int build_dynamic_pages(const char *project_dir, const OokeRoute *route,
                                const OokeConfig *cfg,
                                int *page_count, long *total_bytes) {
    (void)project_dir;

    /* Read handler source */
    char *source = read_file_str(route->file_path);
    if (!source) {
        fprintf(stderr, "ooke build: cannot read handler '%s'\n", route->file_path);
        return 0;
    }

    char *content_type = extract_content_type(source);
    if (!content_type) {
        fprintf(stderr, "ooke build: no store.all/store.slug() call in '%s', skipping dynamic route '%s'\n",
                route->file_path, route->pattern);
        free(source);
        return 0;
    }

    char *tpl_path = extract_template_path(source);
    if (!tpl_path) {
        fprintf(stderr, "ooke build: no tpl.renderfile() call in '%s', skipping\n", route->file_path);
        free(source);
        free(content_type);
        return 0;
    }

    /* Load content collection */
    ContentCollection col = store_all("content", content_type);
    if (col.count == 0) {
        fprintf(stderr, "ooke build: no content items of type '%s', skipping dynamic route '%s'\n",
                content_type, route->pattern);
        store_free_collection(&col);
        free(content_type);
        free(tpl_path);
        free(source);
        return 0;
    }

    /* Static context from handler source */
    TplContext *base_ctx_tpl = extract_static_context(source);
    free(source);

    int rendered = 0;

    for (size_t i = 0; i < col.count; i++) {
        ContentFile *item = &col.items[i];

        TplContext *ctx = tpl_ctx_new();
        if (!ctx) continue;

        /* Copy static context values */
        if (base_ctx_tpl) {
            for (size_t k = 0; k < base_ctx_tpl->len; k++) {
                tpl_ctx_set(ctx, base_ctx_tpl->keys[k], base_ctx_tpl->vals[k]);
            }
        }

        /* Site context */
        tpl_ctx_set(ctx, "site.name", cfg->site_name);
        tpl_ctx_set(ctx, "site.url",  cfg->site_url);

        /* Frontmatter fields with "post." prefix */
        for (size_t k = 0; k < item->field_count; k++) {
            char key[128];
            snprintf(key, sizeof(key), "post.%s", item->fields[k].key);
            tpl_ctx_set(ctx, key, item->fields[k].val);
        }

        /* Body */
        if (item->body) tpl_ctx_set(ctx, "post.body", item->body);
        if (item->slug) tpl_ctx_set(ctx, "post.slug", item->slug);
        if (item->type) tpl_ctx_set(ctx, "post.type", item->type);

        /* Render */
        char *html = tpl_renderfile(tpl_path, ctx, "templates");
        tpl_ctx_free(ctx);

        if (!html) {
            fprintf(stderr, "ooke build: template render failed for slug '%s'\n",
                    item->slug ? item->slug : "(null)");
            continue;
        }

        /* Post-process */
        if (cfg->build_inline_css) {
            char *inlined = html_inline_css(html, cfg->build_output, "static");
            if (inlined) { free(html); html = inlined; }
        }
        if (cfg->build_minify) {
            char *minified = html_minify(html);
            if (minified) { free(html); html = minified; }
        }

        /* Compute output path */
        char out_path[1024];
        build_output_path(cfg, route, item->slug, out_path, sizeof(out_path));

        if (write_html_file(out_path, html) == 0) {
            *page_count += 1;
            *total_bytes += (long)strlen(html);
            rendered++;
        }

        free(html);
    }

    if (base_ctx_tpl) tpl_ctx_free(base_ctx_tpl);
    store_free_collection(&col);
    free(content_type);
    free(tpl_path);

    return rendered;
}

/* -------------------------------------------------------------------------
 * copy_dir_recursive
 * ---------------------------------------------------------------------- */

int copy_dir_recursive(const char *src, const char *dst) {
    DIR *d = opendir(src);
    if (!d) {
        /* Source doesn't exist — not necessarily an error (e.g. no static/ dir) */
        return 0;
    }

    if (makedirs(dst) != 0) {
        closedir(d);
        return -1;
    }

    int total = 0;
    struct dirent *entry;

    while ((entry = readdir(d)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
            continue;

        char src_path[1024], dst_path[1024];
        snprintf(src_path, sizeof(src_path), "%s/%s", src, entry->d_name);
        snprintf(dst_path, sizeof(dst_path), "%s/%s", dst, entry->d_name);

        struct stat st;
        if (stat(src_path, &st) != 0) continue;

        if (S_ISDIR(st.st_mode)) {
            int n = copy_dir_recursive(src_path, dst_path);
            if (n < 0) { closedir(d); return -1; }
            total += n;
        } else if (S_ISREG(st.st_mode)) {
            /* Copy file */
            FILE *fin = fopen(src_path, "rb");
            if (!fin) continue;

            FILE *fout = fopen(dst_path, "wb");
            if (!fout) { fclose(fin); continue; }

            char buf[65536];
            size_t n;
            while ((n = fread(buf, 1, sizeof(buf), fin)) > 0) {
                fwrite(buf, 1, n, fout);
            }
            fclose(fin);
            fclose(fout);
            total++;
        }
    }

    closedir(d);
    return total;
}

/* -------------------------------------------------------------------------
 * html_inline_css
 * ---------------------------------------------------------------------- */

char *html_inline_css(const char *html, const char *build_dir, const char *static_dir) {
    (void)build_dir;

    /* We'll do repeated passes replacing <link rel="stylesheet" href="..."> */
    char *result = strdup(html);
    if (!result) return NULL;

    const char *search_prefix = "<link rel=\"stylesheet\" href=\"";
    const char *search_prefix2 = "<link rel='stylesheet' href='";

    /* We'll do multiple replacements in a loop */
    int changed = 1;
    while (changed) {
        changed = 0;

        /* Try both quote styles */
        for (int qi = 0; qi < 2; qi++) {
            const char *prefix = (qi == 0) ? search_prefix : search_prefix2;
            char close_quote = (qi == 0) ? '"' : '\'';
            char close_tag_char = (qi == 0) ? '"' : '\'';

            char *p = strstr(result, prefix);
            if (!p) continue;

            char *href_start = p + strlen(prefix);
            char *href_end = strchr(href_start, close_quote);
            if (!href_end) continue;

            /* Find end of <link ... > tag */
            char *tag_end = strchr(href_end, '>');
            if (!tag_end) continue;
            tag_end++; /* include '>' */

            size_t href_len = (size_t)(href_end - href_start);
            char href[512];
            if (href_len >= sizeof(href)) continue;
            memcpy(href, href_start, href_len);
            href[href_len] = '\0';

            (void)close_tag_char;

            /* href should start with /static/ or static/ */
            const char *rel_path = href;
            if (strncmp(rel_path, "/static/", 8) == 0) rel_path += 1; /* skip leading / */
            else if (strncmp(rel_path, "static/", 7) != 0) continue;   /* not a local static file */

            /* Build the actual file path: static_dir + "/" + path-after-"static/" */
            const char *after_static = rel_path + strlen("static/");
            char css_path[1024];
            snprintf(css_path, sizeof(css_path), "%s/%s", static_dir, after_static);

            char *css_content = read_file_str(css_path);
            if (!css_content) continue; /* file not found, leave link as-is */

            /* Build replacement: <style>CSS</style> */
            size_t style_len = strlen("<style>") + strlen(css_content) + strlen("</style>");
            char *style_tag = (char *)malloc(style_len + 1);
            if (!style_tag) { free(css_content); continue; }
            snprintf(style_tag, style_len + 1, "<style>%s</style>", css_content);
            free(css_content);

            /* Build new result string */
            size_t before_len = (size_t)(p - result);
            size_t after_offset = (size_t)(tag_end - result);
            size_t old_len = strlen(result);
            size_t after_len = old_len - after_offset;
            size_t new_len = before_len + style_len + after_len;

            char *new_result = (char *)malloc(new_len + 1);
            if (!new_result) { free(style_tag); continue; }

            memcpy(new_result, result, before_len);
            memcpy(new_result + before_len, style_tag, style_len);
            memcpy(new_result + before_len + style_len, result + after_offset, after_len);
            new_result[new_len] = '\0';

            free(style_tag);
            free(result);
            result = new_result;
            changed = 1;
            break; /* restart outer loop */
        }
    }

    return result;
}

/* -------------------------------------------------------------------------
 * html_minify
 * ---------------------------------------------------------------------- */

char *html_minify(const char *html) {
    size_t len = strlen(html);
    /* Output buffer — worst case same length */
    char *out = (char *)malloc(len + 1);
    if (!out) return NULL;

    const char *p = html;
    char *q = out;

    int in_pre = 0;  /* inside <pre> or <code> */
    int in_style_or_script = 0;

    while (*p) {
        /* Track <pre>/<code> blocks to avoid collapsing whitespace inside them */
        if (!in_pre) {
            if (strncasecmp(p, "<pre", 4) == 0 || strncasecmp(p, "<code", 5) == 0) {
                in_pre = 1;
            } else if (strncasecmp(p, "<style", 6) == 0 || strncasecmp(p, "<script", 7) == 0) {
                in_style_or_script = 1;
            }
        } else {
            if (strncasecmp(p, "</pre>", 6) == 0 || strncasecmp(p, "</code>", 7) == 0) {
                in_pre = 0;
            }
        }

        if (in_style_or_script) {
            if (strncasecmp(p, "</style>", 8) == 0 || strncasecmp(p, "</script>", 9) == 0) {
                in_style_or_script = 0;
            }
            *q++ = *p++;
            continue;
        }

        /* Strip HTML comments (but preserve IE conditionals <!--[if...]) */
        if (!in_pre && strncmp(p, "<!--", 4) == 0 && *(p + 4) != '[') {
            const char *end = strstr(p + 4, "-->");
            if (end) {
                p = end + 3;
                continue;
            }
        }

        /* Collapse whitespace between tags */
        if (!in_pre && (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n')) {
            /* Look back: if previous output char was '>' and next non-ws is '<',
             * skip all whitespace. Otherwise collapse to single space. */
            const char *ws_start = p;
            while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;

            int prev_is_tag_close = (q > out && *(q - 1) == '>');
            int next_is_tag_open  = (*p == '<');

            if (prev_is_tag_close && next_is_tag_open) {
                /* Drop whitespace entirely */
                (void)ws_start;
                continue;
            } else if (ws_start != p) {
                /* Collapse to single space */
                *q++ = ' ';
            }
            continue;
        }

        *q++ = *p++;
    }

    *q = '\0';
    return out;
}

/* -------------------------------------------------------------------------
 * ooke_build — main entry point
 * ---------------------------------------------------------------------- */

int ooke_build(const char *project_dir, const OokeConfig *cfg) {
    (void)project_dir;

    struct timeval tv_start, tv_end;
    gettimeofday(&tv_start, NULL);

    /* Scan pages/ */
    OokeRouteTable *table = ooke_router_scan("pages");
    if (!table) {
        fprintf(stderr, "ooke build: failed to scan pages/\n");
        return 1;
    }
    ooke_router_print(table);

    /* Ensure build output directory exists */
    char build_out[256];
    strncpy(build_out, cfg->build_output, sizeof(build_out) - 1);
    build_out[sizeof(build_out) - 1] = '\0';
    /* Strip trailing slash for makedirs */
    size_t bo_len = strlen(build_out);
    if (bo_len > 0 && build_out[bo_len - 1] == '/') build_out[bo_len - 1] = '\0';
    if (strlen(build_out) == 0) strncpy(build_out, "build", sizeof(build_out) - 1);

    if (makedirs(build_out) != 0) {
        ooke_router_free(table);
        return 1;
    }

    int page_count = 0;
    long total_bytes = 0;

    for (size_t i = 0; i < table->count; i++) {
        OokeRoute *route = &table->routes[i];

        if (route->is_api) continue;

        if (!route->is_dynamic) {
            char *html = build_static_page(project_dir, route, cfg);
            if (html) {
                char out_path[1024];
                build_output_path(cfg, route, NULL, out_path, sizeof(out_path));
                if (write_html_file(out_path, html) == 0) {
                    page_count++;
                    total_bytes += (long)strlen(html);
                }
                free(html);
            }
        } else {
            build_dynamic_pages(project_dir, route, cfg, &page_count, &total_bytes);
        }
    }

    ooke_router_free(table);

    /* Copy static/ -> build/static/ */
    char static_dst[512];
    snprintf(static_dst, sizeof(static_dst), "%s/static", build_out);
    int copied = copy_dir_recursive("static", static_dst);
    if (copied > 0) {
        printf("Copied %d static file(s) to %s/\n", copied, static_dst);
    }

    gettimeofday(&tv_end, NULL);
    long elapsed_ms = (tv_end.tv_sec - tv_start.tv_sec) * 1000L +
                      (tv_end.tv_usec - tv_start.tv_usec) / 1000L;

    printf("Built %d pages (%.1f KB) in %ldms\n",
           page_count, (double)total_bytes / 1024.0, elapsed_ms);

    return 0;
}
