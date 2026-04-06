/*
 * template.c — ooke template engine implementation
 *
 * Stages:
 *   1. Lex: scan source into flat token array (TTok)
 *   2. Parse: build AST of TNode from tokens
 *   3. Render: walk AST, produce HTML string
 *
 * Internal structs (TTok, TNode) are not exposed in the public header.
 */

#include "template.h"
#include "md.h"

#include <ctype.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* =========================================================================
 * String buffer (internal)
 * ====================================================================== */

typedef struct {
    char  *buf;
    size_t len;
    size_t cap;
} SB;

static void sb_init(SB *sb) { sb->buf = NULL; sb->len = 0; sb->cap = 0; }

static int sb_grow(SB *sb, size_t need) {
    if (sb->len + need + 1 <= sb->cap) return 1;
    size_t nc = sb->cap ? sb->cap * 2 : 512;
    while (nc < sb->len + need + 1) nc *= 2;
    char *p = realloc(sb->buf, nc);
    if (!p) return 0;
    sb->buf = p;
    sb->cap = nc;
    return 1;
}

static void sb_appendn(SB *sb, const char *s, size_t n) {
    if (!s || n == 0) return;
    if (!sb_grow(sb, n)) return;
    memcpy(sb->buf + sb->len, s, n);
    sb->len += n;
    sb->buf[sb->len] = '\0';
}

static void sb_append(SB *sb, const char *s) {
    if (s) sb_appendn(sb, s, strlen(s));
}

static void sb_appendc(SB *sb, char c) { sb_appendn(sb, &c, 1); }

static char *sb_finish(SB *sb) {
    if (!sb->buf) { char *e = malloc(1); if (e) *e = '\0'; return e; }
    char *r = sb->buf; sb->buf = NULL; sb->len = 0; sb->cap = 0;
    return r;
}

static void sb_free(SB *sb) {
    free(sb->buf); sb->buf = NULL; sb->len = 0; sb->cap = 0;
}

/* HTML escape into SB */
static void sb_escape(SB *sb, const char *s) {
    if (!s) return;
    for (; *s; s++) {
        switch (*s) {
            case '<': sb_append(sb, "&lt;");   break;
            case '>': sb_append(sb, "&gt;");   break;
            case '&': sb_append(sb, "&amp;");  break;
            case '"': sb_append(sb, "&quot;"); break;
            default:  sb_appendc(sb, *s);      break;
        }
    }
}

/* Public API: return heap-allocated escaped string */
char *tpl_html_escape(const char *s) {
    SB sb; sb_init(&sb);
    sb_escape(&sb, s);
    return sb_finish(&sb);
}

/* =========================================================================
 * Context
 * ====================================================================== */

TplContext *tpl_ctx_new(void) {
    TplContext *c = calloc(1, sizeof(*c));
    return c;
}

void tpl_ctx_set(TplContext *ctx, const char *key, const char *val) {
    if (!ctx || !key) return;
    /* update existing */
    for (size_t i = 0; i < ctx->len; i++) {
        if (strcmp(ctx->keys[i], key) == 0) {
            free(ctx->vals[i]);
            ctx->vals[i] = val ? strdup(val) : strdup("");
            return;
        }
    }
    /* grow */
    if (ctx->len >= ctx->cap) {
        size_t nc = ctx->cap ? ctx->cap * 2 : 16;
        char **nk = realloc(ctx->keys, nc * sizeof(char *));
        char **nv = realloc(ctx->vals, nc * sizeof(char *));
        if (!nk || !nv) return;
        ctx->keys = nk; ctx->vals = nv; ctx->cap = nc;
    }
    ctx->keys[ctx->len] = strdup(key);
    ctx->vals[ctx->len] = val ? strdup(val) : strdup("");
    ctx->len++;
}

const char *tpl_ctx_get(const TplContext *ctx, const char *key) {
    if (!ctx || !key) return NULL;
    for (size_t i = 0; i < ctx->len; i++)
        if (strcmp(ctx->keys[i], key) == 0) return ctx->vals[i];
    return NULL;
}

void tpl_ctx_free(TplContext *ctx) {
    if (!ctx) return;
    for (size_t i = 0; i < ctx->len; i++) { free(ctx->keys[i]); free(ctx->vals[i]); }
    free(ctx->keys); free(ctx->vals); free(ctx);
}

/* =========================================================================
 * Lexer
 * ====================================================================== */

typedef enum {
    TTOK_RAW,
    TTOK_EXPR,
    TTOK_DIRECTIVE,
    TTOK_COMMENT
} TTokKind;

typedef struct {
    TTokKind kind;
    char    *content; /* heap-allocated, NUL-terminated */
} TTok;

typedef struct {
    TTok  *toks;
    size_t count;
    size_t cap;
} TokArray;

static void ta_init(TokArray *ta) { ta->toks = NULL; ta->count = 0; ta->cap = 0; }

static void ta_push(TokArray *ta, TTokKind kind, const char *s, size_t n) {
    if (ta->count >= ta->cap) {
        size_t nc = ta->cap ? ta->cap * 2 : 64;
        TTok *p = realloc(ta->toks, nc * sizeof(TTok));
        if (!p) return;
        ta->toks = p; ta->cap = nc;
    }
    char *content = malloc(n + 1);
    if (!content) return;
    memcpy(content, s, n);
    content[n] = '\0';
    ta->toks[ta->count].kind    = kind;
    ta->toks[ta->count].content = content;
    ta->count++;
}

static void ta_free(TokArray *ta) {
    for (size_t i = 0; i < ta->count; i++) free(ta->toks[i].content);
    free(ta->toks); ta->toks = NULL; ta->count = 0; ta->cap = 0;
}

/*
 * Lex source into tokens.
 * Recognise {= =}, {! !}, {# #} delimiters.
 * Everything else is TTOK_RAW.
 */
static TokArray tpl_lex(const char *src) {
    TokArray ta; ta_init(&ta);
    const char *p = src;
    const char *raw_start = p;

    while (*p) {
        if (p[0] == '{' && (p[1] == '=' || p[1] == '!' || p[1] == '#')) {
            /* flush raw */
            if (p > raw_start)
                ta_push(&ta, TTOK_RAW, raw_start, (size_t)(p - raw_start));

            char open2  = p[1];
            TTokKind kind;
            const char *close;
            if (open2 == '=') { kind = TTOK_EXPR;      close = "=}"; }
            else if (open2 == '!') { kind = TTOK_DIRECTIVE; close = "!}"; }
            else              { kind = TTOK_COMMENT;   close = "#}"; }

            p += 2; /* skip {X */
            const char *inner_start = p;
            /* find closing delimiter */
            while (*p) {
                if (p[0] == close[0] && p[1] == close[1]) break;
                p++;
            }
            if (!*p) {
                fprintf(stderr, "ooke/template: unclosed %c} delimiter\n", open2);
                /* consume rest as content anyway */
                if (kind != TTOK_COMMENT)
                    ta_push(&ta, kind, inner_start, (size_t)(p - inner_start));
            } else {
                if (kind != TTOK_COMMENT)
                    ta_push(&ta, kind, inner_start, (size_t)(p - inner_start));
                p += 2; /* skip X} */
            }
            raw_start = p;
        } else {
            p++;
        }
    }

    /* flush trailing raw */
    if (p > raw_start)
        ta_push(&ta, TTOK_RAW, raw_start, (size_t)(p - raw_start));

    return ta;
}

/* =========================================================================
 * AST
 * ====================================================================== */

typedef enum {
    TNODE_RAW,
    TNODE_EXPR,
    TNODE_LAYOUT,
    TNODE_BLOCK,
    TNODE_YIELD,
    TNODE_PARTIAL,
    TNODE_ISLAND,
} TNodeKind;

/*
 * Filter in an expression pipeline:
 *   name         — e.g. "escape", "upper", "md"
 *   arg          — optional string argument (e.g. "d M Y" for date filter)
 */
typedef struct {
    char *name;
    char *arg;  /* NULL if no argument */
} TFilter;

typedef struct TNode TNode;

struct TNode {
    TNodeKind  kind;

    /* TNODE_RAW */
    char      *raw;

    /* TNODE_EXPR */
    char      *expr_path;   /* e.g. "post.title" */
    TFilter   *filters;
    size_t     filter_count;

    /* TNODE_LAYOUT, TNODE_BLOCK, TNODE_YIELD, TNODE_PARTIAL, TNODE_ISLAND */
    char      *name;        /* layout/block/yield/partial/island name */
    char      *hydrate;     /* TNODE_ISLAND hydrate strategy */

    /* children (TNODE_BLOCK uses this) */
    TNode    **children;
    size_t     child_count;
    size_t     child_cap;
};

static TNode *node_new(TNodeKind kind) {
    TNode *n = calloc(1, sizeof(*n));
    if (n) n->kind = kind;
    return n;
}

static void node_add_child(TNode *parent, TNode *child) {
    if (!parent || !child) return;
    if (parent->child_count >= parent->child_cap) {
        size_t nc = parent->child_cap ? parent->child_cap * 2 : 8;
        TNode **p = realloc(parent->children, nc * sizeof(TNode *));
        if (!p) return;
        parent->children = p;
        parent->child_cap = nc;
    }
    parent->children[parent->child_count++] = child;
}

static void node_free(TNode *n);

static void node_free_children(TNode *n) {
    for (size_t i = 0; i < n->child_count; i++) node_free(n->children[i]);
    free(n->children);
    n->children = NULL; n->child_count = 0; n->child_cap = 0;
}

static void node_free(TNode *n) {
    if (!n) return;
    free(n->raw);
    free(n->expr_path);
    free(n->name);
    free(n->hydrate);
    for (size_t i = 0; i < n->filter_count; i++) {
        free(n->filters[i].name);
        free(n->filters[i].arg);
    }
    free(n->filters);
    node_free_children(n);
    free(n);
}

/* =========================================================================
 * String utilities for parsing
 * ====================================================================== */

/* Trim leading and trailing whitespace; returns heap-allocated copy */
static char *str_trim(const char *s) {
    while (isspace((unsigned char)*s)) s++;
    size_t len = strlen(s);
    while (len > 0 && isspace((unsigned char)s[len-1])) len--;
    char *r = malloc(len + 1);
    if (!r) return NULL;
    memcpy(r, s, len);
    r[len] = '\0';
    return r;
}

/* Extract string argument from directive, e.g. layout("name") → name */
static char *extract_string_arg(const char *s) {
    const char *p = strchr(s, '"');
    if (!p) {
        /* try single quote */
        p = strchr(s, '\'');
        if (!p) return NULL;
        char q = *p++;
        const char *end = strchr(p, q);
        if (!end) return NULL;
        char *r = malloc((size_t)(end - p) + 1);
        if (!r) return NULL;
        memcpy(r, p, (size_t)(end - p));
        r[end - p] = '\0';
        return r;
    }
    p++;
    const char *end = strchr(p, '"');
    if (!end) return NULL;
    char *r = malloc((size_t)(end - p) + 1);
    if (!r) return NULL;
    memcpy(r, p, (size_t)(end - p));
    r[end - p] = '\0';
    return r;
}

/*
 * Parse island directive: island("name"; hydrate="strategy")
 * Fills *name_out and *hydrate_out (heap). Returns 0 on success.
 */
static int parse_island_args(const char *s, char **name_out, char **hydrate_out) {
    *name_out    = NULL;
    *hydrate_out = NULL;

    /* extract first quoted string = name */
    const char *p = strchr(s, '"');
    if (!p) return -1;
    p++;
    const char *end = strchr(p, '"');
    if (!end) return -1;
    size_t nlen = (size_t)(end - p);
    *name_out = malloc(nlen + 1);
    if (!*name_out) return -1;
    memcpy(*name_out, p, nlen);
    (*name_out)[nlen] = '\0';

    /* look for hydrate="..." */
    const char *hy = strstr(end + 1, "hydrate=");
    if (hy) {
        hy += 8; /* skip hydrate= */
        if (*hy == '"') hy++;
        const char *hend = strchr(hy, '"');
        if (hend) {
            size_t hlen = (size_t)(hend - hy);
            *hydrate_out = malloc(hlen + 1);
            if (*hydrate_out) {
                memcpy(*hydrate_out, hy, hlen);
                (*hydrate_out)[hlen] = '\0';
            }
        }
    }
    if (!*hydrate_out) *hydrate_out = strdup("load");

    return 0;
}

/* =========================================================================
 * Expression parser
 * Parse "path | filter1 | filter2("arg")" into a TNODE_EXPR node.
 * ====================================================================== */

static TNode *parse_expr(const char *content) {
    TNode *n = node_new(TNODE_EXPR);
    if (!n) return NULL;

    char *copy = str_trim(content);
    if (!copy) { node_free(n); return NULL; }

    /* split on | */
    /* first segment is path, rest are filters */
    size_t filter_alloc = 4;
    n->filters = malloc(filter_alloc * sizeof(TFilter));
    if (!n->filters) { free(copy); node_free(n); return NULL; }
    n->filter_count = 0;

    char *p     = copy;
    int   first = 1;

    while (*p) {
        /* find next | (but not inside quotes) */
        char *pipe = NULL;
        int   in_q = 0;
        char  q    = 0;
        for (char *c = p; *c; c++) {
            if (!in_q && (*c == '"' || *c == '\'')) { in_q = 1; q = *c; }
            else if (in_q && *c == q)               { in_q = 0; }
            else if (!in_q && *c == '|')            { pipe = c; break; }
        }

        size_t seg_len;
        if (pipe) {
            seg_len = (size_t)(pipe - p);
        } else {
            seg_len = strlen(p);
        }

        /* trim segment */
        while (seg_len > 0 && isspace((unsigned char)p[0])) { p++; seg_len--; }
        while (seg_len > 0 && isspace((unsigned char)p[seg_len-1])) seg_len--;

        if (first) {
            n->expr_path = malloc(seg_len + 1);
            if (n->expr_path) {
                memcpy(n->expr_path, p, seg_len);
                n->expr_path[seg_len] = '\0';
            }
            first = 0;
        } else {
            /* parse filter name and optional arg */
            if (n->filter_count >= filter_alloc) {
                filter_alloc *= 2;
                TFilter *fp = realloc(n->filters, filter_alloc * sizeof(TFilter));
                if (!fp) { free(copy); node_free(n); return NULL; }
                n->filters = fp;
            }
            /* e.g. "date(\"d M Y\")" or "upper" */
            char seg[256];
            if (seg_len >= sizeof(seg)) seg_len = sizeof(seg) - 1;
            memcpy(seg, p, seg_len); seg[seg_len] = '\0';

            char *paren = strchr(seg, '(');
            TFilter *f = &n->filters[n->filter_count];
            if (paren) {
                size_t nlen = (size_t)(paren - seg);
                while (nlen > 0 && isspace((unsigned char)seg[nlen-1])) nlen--;
                f->name = malloc(nlen + 1);
                if (f->name) { memcpy(f->name, seg, nlen); f->name[nlen] = '\0'; }
                /* extract arg string */
                f->arg = extract_string_arg(paren);
            } else {
                f->name = malloc(seg_len + 1);
                if (f->name) { memcpy(f->name, seg, seg_len); f->name[seg_len] = '\0'; }
                f->arg = NULL;
            }
            n->filter_count++;
        }

        if (!pipe) break;
        p = pipe + 1;
    }

    free(copy);
    return n;
}

/* =========================================================================
 * Parser
 * ====================================================================== */

/*
 * Parse flat token array into a tree.
 * *pos is the current index into ta->toks; it is advanced by this function.
 * parent_block: non-NULL when parsing inside a {! block !} … {! end !}.
 *
 * Returns a root TNode (kind TNODE_RAW reused as container, name == NULL)
 * or NULL on error.
 */
typedef struct {
    TNode  *root;      /* always a container node */
} ParseCtx;

/* Forward decl */
static int parse_tokens(const TokArray *ta, size_t *pos, TNode *container);

static TNode *tpl_parse(const TokArray *ta) {
    TNode *root = node_new(TNODE_RAW); /* use RAW as container */
    if (!root) return NULL;
    root->raw = strdup(""); /* no raw content */
    size_t pos = 0;
    if (parse_tokens(ta, &pos, root) < 0) {
        node_free(root);
        return NULL;
    }
    return root;
}

/*
 * Parse tokens into container's children.
 * Returns 0 on normal end-of-tokens, 1 if we hit an "end" directive
 * (used by block parsing to know when to stop).
 */
static int parse_tokens(const TokArray *ta, size_t *pos, TNode *container) {
    while (*pos < ta->count) {
        const TTok *tok = &ta->toks[*pos];
        (*pos)++;

        switch (tok->kind) {
            case TTOK_RAW: {
                TNode *n = node_new(TNODE_RAW);
                if (!n) return -1;
                n->raw = strdup(tok->content);
                node_add_child(container, n);
                break;
            }

            case TTOK_COMMENT:
                /* ignore */
                break;

            case TTOK_EXPR: {
                TNode *n = parse_expr(tok->content);
                if (!n) return -1;
                node_add_child(container, n);
                break;
            }

            case TTOK_DIRECTIVE: {
                char *trimmed = str_trim(tok->content);
                if (!trimmed) return -1;

                /* "end" — closes a block */
                if (strcmp(trimmed, "end") == 0) {
                    free(trimmed);
                    return 1; /* signal end of block */
                }

                /* layout("name") */
                if (strncmp(trimmed, "layout(", 7) == 0 ||
                    strncmp(trimmed, "layout (", 8) == 0) {
                    TNode *n = node_new(TNODE_LAYOUT);
                    if (!n) { free(trimmed); return -1; }
                    n->name = extract_string_arg(trimmed);
                    node_add_child(container, n);
                    free(trimmed);
                    break;
                }

                /* block("name") */
                if (strncmp(trimmed, "block(", 6) == 0 ||
                    strncmp(trimmed, "block (", 7) == 0) {
                    TNode *n = node_new(TNODE_BLOCK);
                    if (!n) { free(trimmed); return -1; }
                    n->name = extract_string_arg(trimmed);
                    /* recursively parse children until "end" */
                    int r = parse_tokens(ta, pos, n);
                    if (r < 0) { node_free(n); free(trimmed); return -1; }
                    /* r == 1 means we hit "end", which is correct */
                    node_add_child(container, n);
                    free(trimmed);
                    break;
                }

                /* yield("name") */
                if (strncmp(trimmed, "yield(", 6) == 0 ||
                    strncmp(trimmed, "yield (", 7) == 0) {
                    TNode *n = node_new(TNODE_YIELD);
                    if (!n) { free(trimmed); return -1; }
                    n->name = extract_string_arg(trimmed);
                    node_add_child(container, n);
                    free(trimmed);
                    break;
                }

                /* partial("name") */
                if (strncmp(trimmed, "partial(", 8) == 0 ||
                    strncmp(trimmed, "partial (", 9) == 0) {
                    TNode *n = node_new(TNODE_PARTIAL);
                    if (!n) { free(trimmed); return -1; }
                    n->name = extract_string_arg(trimmed);
                    node_add_child(container, n);
                    free(trimmed);
                    break;
                }

                /* island("name"; hydrate="strategy") */
                if (strncmp(trimmed, "island(", 7) == 0 ||
                    strncmp(trimmed, "island (", 8) == 0) {
                    TNode *n = node_new(TNODE_ISLAND);
                    if (!n) { free(trimmed); return -1; }
                    parse_island_args(trimmed, &n->name, &n->hydrate);
                    node_add_child(container, n);
                    free(trimmed);
                    break;
                }

                fprintf(stderr, "ooke/template: unknown directive: %s\n", trimmed);
                free(trimmed);
                break;
            }
        }
    }
    return 0;
}

/* =========================================================================
 * Renderer
 * ====================================================================== */

/*
 * Block registry: maps block name → rendered HTML string.
 * Used by layout inheritance.
 */
typedef struct {
    char  **names;
    char  **html;
    size_t  count;
    size_t  cap;
} BlockMap;

static void bm_init(BlockMap *bm) { bm->names = NULL; bm->html = NULL; bm->count = 0; bm->cap = 0; }

static void bm_set(BlockMap *bm, const char *name, const char *html) {
    if (!name) return;
    for (size_t i = 0; i < bm->count; i++) {
        if (strcmp(bm->names[i], name) == 0) {
            free(bm->html[i]);
            bm->html[i] = html ? strdup(html) : strdup("");
            return;
        }
    }
    if (bm->count >= bm->cap) {
        size_t nc = bm->cap ? bm->cap * 2 : 8;
        char **nn = realloc(bm->names, nc * sizeof(char *));
        char **nh = realloc(bm->html,  nc * sizeof(char *));
        if (!nn || !nh) return;
        bm->names = nn; bm->html = nh; bm->cap = nc;
    }
    bm->names[bm->count] = strdup(name);
    bm->html [bm->count] = html ? strdup(html) : strdup("");
    bm->count++;
}

static const char *bm_get(const BlockMap *bm, const char *name) {
    if (!name) return NULL;
    for (size_t i = 0; i < bm->count; i++)
        if (strcmp(bm->names[i], name) == 0) return bm->html[i];
    return NULL;
}

static void bm_free(BlockMap *bm) {
    for (size_t i = 0; i < bm->count; i++) { free(bm->names[i]); free(bm->html[i]); }
    free(bm->names); free(bm->html);
    bm->names = NULL; bm->html = NULL; bm->count = 0; bm->cap = 0;
}

/* -------------------------------------------------------------------------
 * Apply a single filter to a value string.
 * Returns heap-allocated result. Caller must free().
 * do_escape is set to 0 if the filter produces raw HTML (e.g. md).
 * ---------------------------------------------------------------------- */
static char *apply_filter(const TFilter *f, const char *val, int *do_escape) {
    if (!f->name) return strdup(val ? val : "");

    if (strcmp(f->name, "md") == 0) {
        *do_escape = 0;
        return md_to_html(val ? val : "");
    }

    if (strcmp(f->name, "escape") == 0) {
        *do_escape = 0; /* already escaped */
        return tpl_html_escape(val ? val : "");
    }

    if (strcmp(f->name, "raw") == 0) {
        *do_escape = 0;
        return strdup(val ? val : "");
    }

    if (strcmp(f->name, "upper") == 0) {
        char *r = strdup(val ? val : "");
        if (r) { for (char *p = r; *p; p++) *p = (char)toupper((unsigned char)*p); }
        return r;
    }

    if (strcmp(f->name, "lower") == 0) {
        char *r = strdup(val ? val : "");
        if (r) { for (char *p = r; *p; p++) *p = (char)tolower((unsigned char)*p); }
        return r;
    }

    if (strcmp(f->name, "trim") == 0) {
        const char *s = val ? val : "";
        while (isspace((unsigned char)*s)) s++;
        size_t len = strlen(s);
        while (len > 0 && isspace((unsigned char)s[len-1])) len--;
        char *r = malloc(len + 1);
        if (r) { memcpy(r, s, len); r[len] = '\0'; }
        return r;
    }

    if (strcmp(f->name, "date") == 0) {
        /* val is a u64 unix timestamp in milliseconds */
        long long ms = val ? atoll(val) : 0;
        time_t ts = (time_t)(ms / 1000);
        struct tm tm_info;
#ifdef _WIN32
        localtime_s(&tm_info, &ts);
#else
        localtime_r(&ts, &tm_info);
#endif
        const char *fmt = f->arg ? f->arg : "%Y-%m-%d";

        /* translate simple toke date format codes */
        /* Support: d=day, M=month name abbrev (3-char), Y=4-digit year,
                    m=month num, H=hour, i=minute, s=second */
        /* Build a strftime format string */
        char strfmt[256];
        size_t si = 0;
        for (const char *c = fmt; *c && si + 4 < sizeof(strfmt); c++) {
            if (*c == 'd' && (c == fmt || !isalpha((unsigned char)*(c-1)))) {
                strfmt[si++] = '%'; strfmt[si++] = 'd';
            } else if (*c == 'M') {
                strfmt[si++] = '%'; strfmt[si++] = 'b';
            } else if (*c == 'Y') {
                strfmt[si++] = '%'; strfmt[si++] = 'Y';
            } else if (*c == 'm') {
                strfmt[si++] = '%'; strfmt[si++] = 'm';
            } else if (*c == 'H') {
                strfmt[si++] = '%'; strfmt[si++] = 'H';
            } else if (*c == 'i') {
                strfmt[si++] = '%'; strfmt[si++] = 'M';
            } else if (*c == 's') {
                strfmt[si++] = '%'; strfmt[si++] = 'S';
            } else {
                strfmt[si++] = *c;
            }
        }
        strfmt[si] = '\0';

        char datebuf[256];
        strftime(datebuf, sizeof(datebuf), strfmt, &tm_info);
        return strdup(datebuf);
    }

    /* unknown filter: pass through */
    fprintf(stderr, "ooke/template: unknown filter: %s\n", f->name);
    return strdup(val ? val : "");
}

/* -------------------------------------------------------------------------
 * Resolve a dotted path in context.
 * Phase 1: flat lookup of "a.b.c" as a single key.
 * ---------------------------------------------------------------------- */
static const char *resolve_path(const TplContext *ctx, const char *path) {
    if (!path) return "";
    const char *v = tpl_ctx_get(ctx, path);
    return v ? v : "";
}

/* -------------------------------------------------------------------------
 * Build path to layout or partial file.
 * ---------------------------------------------------------------------- */
static char *make_layout_path(const char *templates_dir, const char *name) {
    /* templates_dir/<name>.tkt  (layouts live directly in templates/) */
    size_t len = strlen(templates_dir) + strlen(name) + 16;
    char *path = malloc(len);
    if (!path) return NULL;
    snprintf(path, len, "%s/%s.tkt", templates_dir, name);
    return path;
}

static char *make_partial_path(const char *templates_dir, const char *name) {
    size_t len = strlen(templates_dir) + strlen(name) + 32;
    char *path = malloc(len);
    if (!path) return NULL;
    snprintf(path, len, "%s/partials/%s.tkt", templates_dir, name);
    return path;
}

/* -------------------------------------------------------------------------
 * Load file into heap string
 * ---------------------------------------------------------------------- */
static char *load_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "ooke/template: cannot open file: %s\n", path);
        return NULL;
    }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz < 0) { fclose(f); return NULL; }
    char *buf = malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return NULL; }
    size_t read = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    buf[read] = '\0';
    return buf;
}

/* -------------------------------------------------------------------------
 * Render a list of nodes into output SB.
 * bm: block map for layout inheritance (may be NULL when not in layout mode).
 * Returns 0 on success, -1 on error.
 * layout_name_out: if non-NULL and we encounter a TNODE_LAYOUT, set it.
 * ---------------------------------------------------------------------- */

/*
 * Shared render state passed through recursive calls.
 */
typedef struct {
    const TplContext *ctx;
    const char       *templates_dir;
    BlockMap         *bm;       /* layout block map, may be NULL */
    char            **layout;   /* pointer to layout name storage, may be NULL */
} RenderState;

static int render_nodes_rs(TNode **nodes, size_t count, RenderState *rs, SB *out);

static int render_node(TNode *n, RenderState *rs, SB *out) {
    if (!n) return 0;

    switch (n->kind) {

        case TNODE_RAW:
            /* If it's a container (no raw text), render children */
            if (n->raw && n->raw[0]) {
                sb_append(out, n->raw);
            }
            /* also render children (root node acts as container) */
            return render_nodes_rs(n->children, n->child_count, rs, out);

        case TNODE_EXPR: {
            const char *val = resolve_path(rs->ctx, n->expr_path);
            /* apply filters in chain */
            char *current = strdup(val ? val : "");
            int   do_escape = 1;
            for (size_t i = 0; i < n->filter_count; i++) {
                int this_escape = 1;
                char *next = apply_filter(&n->filters[i], current, &this_escape);
                free(current);
                current = next ? next : strdup("");
                if (!this_escape) do_escape = 0;
            }
            if (do_escape) {
                sb_escape(out, current);
            } else {
                sb_append(out, current);
            }
            free(current);
            return 0;
        }

        case TNODE_LAYOUT:
            /* store layout name for post-render processing */
            if (rs->layout && n->name) {
                free(*rs->layout);
                *rs->layout = strdup(n->name);
            }
            return 0;

        case TNODE_BLOCK: {
            if (!rs->bm) {
                /* No layout context: just render block children directly */
                return render_nodes_rs(n->children, n->child_count, rs, out);
            }
            /* Render block content and store in block map */
            SB block_buf; sb_init(&block_buf);
            int r = render_nodes_rs(n->children, n->child_count, rs, &block_buf);
            if (r == 0) {
                char *html = sb_finish(&block_buf);
                bm_set(rs->bm, n->name, html);
                free(html);
            } else {
                sb_free(&block_buf);
            }
            return r;
        }

        case TNODE_YIELD: {
            if (!rs->bm) return 0;
            const char *html = bm_get(rs->bm, n->name);
            sb_append(out, html ? html : "");
            return 0;
        }

        case TNODE_PARTIAL: {
            if (!n->name || !rs->templates_dir) return 0;
            char *path = make_partial_path(rs->templates_dir, n->name);
            if (!path) return -1;
            char *src = load_file(path);
            free(path);
            if (!src) return -1;

            TokArray ta = tpl_lex(src);
            free(src);
            TNode *ptree = tpl_parse(&ta);
            ta_free(&ta);
            if (!ptree) return -1;

            /* render partial with same context */
            int r = render_nodes_rs(ptree->children, ptree->child_count, rs, out);
            node_free(ptree);
            return r;
        }

        case TNODE_ISLAND:
            sb_append(out, "<div data-island=\"");
            sb_escape(out, n->name ? n->name : "");
            sb_append(out, "\" data-hydrate=\"");
            sb_escape(out, n->hydrate ? n->hydrate : "load");
            sb_append(out, "\"></div>");
            return 0;
    }
    return 0;
}

static int render_nodes_rs(TNode **nodes, size_t count, RenderState *rs, SB *out) {
    for (size_t i = 0; i < count; i++) {
        int r = render_node(nodes[i], rs, out);
        if (r < 0) return r;
    }
    return 0;
}

/* =========================================================================
 * TplTemplate
 * ====================================================================== */

struct TplTemplate {
    TNode *root;
};

TplTemplate *tpl_compile(const char *source) {
    if (!source) return NULL;
    TokArray ta = tpl_lex(source);
    TNode *root = tpl_parse(&ta);
    ta_free(&ta);
    if (!root) return NULL;
    TplTemplate *t = malloc(sizeof(*t));
    if (!t) { node_free(root); return NULL; }
    t->root = root;
    return t;
}

TplTemplate *tpl_compile_file(const char *path) {
    char *src = load_file(path);
    if (!src) return NULL;
    TplTemplate *t = tpl_compile(src);
    free(src);
    return t;
}

char *tpl_render(TplTemplate *t, TplContext *ctx, const char *templates_dir) {
    if (!t || !t->root) return NULL;

    char     *layout_name = NULL;
    BlockMap  bm;
    bm_init(&bm);

    RenderState rs;
    rs.ctx           = ctx;
    rs.templates_dir = templates_dir ? templates_dir : ".";
    rs.bm            = &bm;
    rs.layout        = &layout_name;

    SB body; sb_init(&body);

    /*
     * First pass: render the child template.
     * TNODE_LAYOUT sets layout_name.
     * TNODE_BLOCK renders its children and stores result in bm.
     * Other nodes are appended to body (for templates with no layout).
     */
    int r = render_nodes_rs(t->root->children, t->root->child_count, &rs, &body);
    if (r < 0) {
        sb_free(&body);
        bm_free(&bm);
        free(layout_name);
        return NULL;
    }

    char *result;

    if (layout_name && templates_dir) {
        /* Discard the body (it was only rendered to fill block map).
         * Now render the layout, which uses yield() to pull in blocks. */
        sb_free(&body);

        char *lpath = make_layout_path(templates_dir, layout_name);
        free(layout_name);
        layout_name = NULL;

        if (!lpath) { bm_free(&bm); return NULL; }

        char *lsrc = load_file(lpath);
        free(lpath);
        if (!lsrc) { bm_free(&bm); return NULL; }

        TokArray lta = tpl_lex(lsrc);
        free(lsrc);
        TNode *ltree = tpl_parse(&lta);
        ta_free(&lta);
        if (!ltree) { bm_free(&bm); return NULL; }

        SB layout_out; sb_init(&layout_out);
        RenderState lrs;
        lrs.ctx           = ctx;
        lrs.templates_dir = templates_dir;
        lrs.bm            = &bm;
        lrs.layout        = NULL; /* layouts don't chain by default */

        r = render_nodes_rs(ltree->children, ltree->child_count, &lrs, &layout_out);
        node_free(ltree);

        if (r < 0) {
            sb_free(&layout_out);
            bm_free(&bm);
            return NULL;
        }
        result = sb_finish(&layout_out);
    } else {
        free(layout_name);
        result = sb_finish(&body);
    }

    bm_free(&bm);
    return result;
}

void tpl_free(TplTemplate *t) {
    if (!t) return;
    node_free(t->root);
    free(t);
}

char *tpl_renderfile(const char *path, TplContext *ctx, const char *templates_dir) {
    TplTemplate *t = tpl_compile_file(path);
    if (!t) return NULL;
    char *result = tpl_render(t, ctx, templates_dir);
    tpl_free(t);
    return result;
}
