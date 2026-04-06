#ifndef OOKE_TEMPLATE_H
#define OOKE_TEMPLATE_H

#include <stddef.h>

/*
 * template.h — ooke template engine public API
 *
 * Template syntax (.tkt files):
 *   {= expr =}           output expression (HTML-escaped by default)
 *   {! directive !}      control directive
 *   {# comment #}        ignored
 *   everything else      raw HTML passthrough
 *
 * Directives:
 *   layout("name")               declare parent layout
 *   block("name") ... end        define a named content block
 *   yield("name")                output a named block (used in layouts)
 *   partial("name")              include templates/partials/<name>.tkt
 *   island("name"; hydrate="x")  island component placeholder
 *
 * Expressions:
 *   variable                look up key in context
 *   obj.field               dotted path lookup
 *   expr | filter           apply filter
 *   Filters: md, date("format"), escape, upper, lower, trim
 */

/* -------------------------------------------------------------------------
 * Key-value rendering context
 * ---------------------------------------------------------------------- */

typedef struct {
    char  **keys;
    char  **vals;
    size_t  len;
    size_t  cap;
} TplContext;

TplContext *tpl_ctx_new(void);
void        tpl_ctx_set(TplContext *ctx, const char *key, const char *val);
const char *tpl_ctx_get(const TplContext *ctx, const char *key);
void        tpl_ctx_free(TplContext *ctx);

/* -------------------------------------------------------------------------
 * Compiled template (opaque)
 * ---------------------------------------------------------------------- */

typedef struct TplTemplate TplTemplate;

/* Compile a template from a source string. Returns NULL on error. */
TplTemplate *tpl_compile(const char *source);

/* Compile a template from a file path. Returns NULL on error. */
TplTemplate *tpl_compile_file(const char *path);

/*
 * Render a compiled template with the given context.
 * templates_dir: base directory for resolving layouts and partials
 *   (e.g. "templates" — engine will look for templates_dir/layouts/<name>.tkt
 *    and templates_dir/partials/<name>.tkt)
 * Returns heap-allocated HTML string. Caller must free(). Returns NULL on error.
 */
char *tpl_render(TplTemplate *t, TplContext *ctx, const char *templates_dir);

void tpl_free(TplTemplate *t);

/* Convenience: compile_file + render + free in one call. */
char *tpl_renderfile(const char *path, TplContext *ctx, const char *templates_dir);

/* -------------------------------------------------------------------------
 * HTML utilities
 * ---------------------------------------------------------------------- */

/* Returns a heap-allocated HTML-escaped copy of s. Caller must free(). */
char *tpl_html_escape(const char *s);

#endif /* OOKE_TEMPLATE_H */
