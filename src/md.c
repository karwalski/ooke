/*
 * md.c — minimal Markdown-to-HTML renderer for ooke template engine
 *
 * Two-pass approach:
 *   Pass 1: split source into logical block-level elements
 *   Pass 2: process inline markup within each block
 */

#include "md.h"

#include <ctype.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* -------------------------------------------------------------------------
 * Generic string buffer
 * ---------------------------------------------------------------------- */

typedef struct {
    char  *buf;
    size_t len;
    size_t cap;
} StrBuf;

static void sb_init(StrBuf *sb) {
    sb->buf = NULL;
    sb->len = 0;
    sb->cap = 0;
}

static int sb_grow(StrBuf *sb, size_t need) {
    if (sb->len + need + 1 <= sb->cap) return 1;
    size_t new_cap = sb->cap ? sb->cap * 2 : 256;
    while (new_cap < sb->len + need + 1) new_cap *= 2;
    char *p = realloc(sb->buf, new_cap);
    if (!p) return 0;
    sb->buf = p;
    sb->cap = new_cap;
    return 1;
}

static void sb_appendn(StrBuf *sb, const char *s, size_t n) {
    if (!s || n == 0) return;
    if (!sb_grow(sb, n)) return;
    memcpy(sb->buf + sb->len, s, n);
    sb->len += n;
    sb->buf[sb->len] = '\0';
}

static void sb_append(StrBuf *sb, const char *s) {
    if (s) sb_appendn(sb, s, strlen(s));
}

static void sb_appendc(StrBuf *sb, char c) {
    sb_appendn(sb, &c, 1);
}

/* Caller owns the returned buffer. sb is reset to empty. */
static char *sb_finish(StrBuf *sb) {
    if (!sb->buf) {
        /* return empty string */
        char *e = malloc(1);
        if (e) *e = '\0';
        return e;
    }
    char *r = sb->buf;
    sb->buf = NULL;
    sb->len = 0;
    sb->cap = 0;
    return r;
}


/* -------------------------------------------------------------------------
 * HTML escaping helpers
 * ---------------------------------------------------------------------- */

/* Append s with HTML escaping of <, >, &, " */
static void sb_append_escaped(StrBuf *sb, const char *s, size_t n) {
    for (size_t i = 0; i < n; i++) {
        switch (s[i]) {
            case '<': sb_append(sb, "&lt;");   break;
            case '>': sb_append(sb, "&gt;");   break;
            case '&': sb_append(sb, "&amp;");  break;
            case '"': sb_append(sb, "&quot;"); break;
            default:  sb_appendc(sb, s[i]);    break;
        }
    }
}

/* Escape a NUL-terminated string */
static void sb_escape(StrBuf *sb, const char *s) {
    if (s) sb_append_escaped(sb, s, strlen(s));
}

/* -------------------------------------------------------------------------
 * Line splitting
 * ---------------------------------------------------------------------- */

typedef struct {
    char  **lines;
    size_t  count;
    size_t  cap;
} LineArray;

static void la_init(LineArray *la) {
    la->lines = NULL;
    la->count = 0;
    la->cap   = 0;
}

static void la_push(LineArray *la, char *line) {
    if (la->count >= la->cap) {
        size_t new_cap = la->cap ? la->cap * 2 : 64;
        char **p = realloc(la->lines, new_cap * sizeof(char *));
        if (!p) return;
        la->lines = p;
        la->cap   = new_cap;
    }
    la->lines[la->count++] = line;
}

static void la_free(LineArray *la) {
    for (size_t i = 0; i < la->count; i++) free(la->lines[i]);
    free(la->lines);
    la->lines = NULL;
    la->count = 0;
    la->cap   = 0;
}

/* Split markdown into lines (copies each line, strips trailing \r) */
static LineArray split_lines(const char *src) {
    LineArray la;
    la_init(&la);
    const char *p = src;
    while (*p) {
        const char *start = p;
        while (*p && *p != '\n') p++;
        size_t len = (size_t)(p - start);
        /* strip trailing \r */
        while (len > 0 && start[len-1] == '\r') len--;
        char *line = malloc(len + 1);
        if (!line) { if (*p == '\n') p++; continue; }
        memcpy(line, start, len);
        line[len] = '\0';
        la_push(&la, line);
        if (*p == '\n') p++;
    }
    return la;
}

/* -------------------------------------------------------------------------
 * Inline processing
 * Handles: **bold**, *italic*, `code`, [link](url), ![img](url)
 * Escapes < > & outside of these constructs.
 * ---------------------------------------------------------------------- */

static void process_inline(StrBuf *out, const char *s, size_t len) {
    size_t i = 0;
    while (i < len) {
        /* Image: ![alt](url) */
        if (s[i] == '!' && i + 1 < len && s[i+1] == '[') {
            size_t j = i + 2;
            while (j < len && s[j] != ']') j++;
            if (j < len && j+1 < len && s[j+1] == '(') {
                size_t alt_start = i + 2;
                size_t alt_len   = j - alt_start;
                size_t k = j + 2;
                while (k < len && s[k] != ')') k++;
                if (k < len) {
                    size_t url_start = j + 2;
                    size_t url_len   = k - url_start;
                    sb_append(out, "<img src=\"");
                    sb_append_escaped(out, s + url_start, url_len);
                    sb_append(out, "\" alt=\"");
                    sb_append_escaped(out, s + alt_start, alt_len);
                    sb_append(out, "\">");
                    i = k + 1;
                    continue;
                }
            }
        }

        /* Link: [text](url) */
        if (s[i] == '[') {
            size_t j = i + 1;
            while (j < len && s[j] != ']') j++;
            if (j < len && j+1 < len && s[j+1] == '(') {
                size_t txt_start = i + 1;
                size_t txt_len   = j - txt_start;
                size_t k = j + 2;
                while (k < len && s[k] != ')') k++;
                if (k < len) {
                    size_t url_start = j + 2;
                    size_t url_len   = k - url_start;
                    sb_append(out, "<a href=\"");
                    sb_append_escaped(out, s + url_start, url_len);
                    sb_append(out, "\">");
                    /* recurse for text */
                    char *txt = malloc(txt_len + 1);
                    if (txt) {
                        memcpy(txt, s + txt_start, txt_len);
                        txt[txt_len] = '\0';
                        process_inline(out, txt, txt_len);
                        free(txt);
                    }
                    sb_append(out, "</a>");
                    i = k + 1;
                    continue;
                }
            }
        }

        /* Inline code: `...` */
        if (s[i] == '`') {
            size_t j = i + 1;
            while (j < len && s[j] != '`') j++;
            if (j < len) {
                sb_append(out, "<code>");
                sb_append_escaped(out, s + i + 1, j - i - 1);
                sb_append(out, "</code>");
                i = j + 1;
                continue;
            }
        }

        /* Bold: **...** */
        if (s[i] == '*' && i + 1 < len && s[i+1] == '*') {
            size_t j = i + 2;
            while (j + 1 < len && !(s[j] == '*' && s[j+1] == '*')) j++;
            if (j + 1 < len) {
                sb_append(out, "<strong>");
                process_inline(out, s + i + 2, j - i - 2);
                sb_append(out, "</strong>");
                i = j + 2;
                continue;
            }
        }

        /* Italic: *...* (single star) */
        if (s[i] == '*') {
            size_t j = i + 1;
            while (j < len && s[j] != '*') j++;
            if (j < len) {
                sb_append(out, "<em>");
                process_inline(out, s + i + 1, j - i - 1);
                sb_append(out, "</em>");
                i = j + 1;
                continue;
            }
        }

        /* HTML special chars */
        switch (s[i]) {
            case '<': sb_append(out, "&lt;");  break;
            case '>': sb_append(out, "&gt;");  break;
            case '&': sb_append(out, "&amp;"); break;
            default:  sb_appendc(out, s[i]);   break;
        }
        i++;
    }
}

/* Inline-process a NUL-terminated string, return heap string */
static char *inline_html(const char *s) {
    StrBuf sb;
    sb_init(&sb);
    process_inline(&sb, s, strlen(s));
    return sb_finish(&sb);
}

/* -------------------------------------------------------------------------
 * Block-level rendering state machine
 * ---------------------------------------------------------------------- */

typedef enum {
    BLK_NONE,
    BLK_PARA,
    BLK_UL,
    BLK_OL,
    BLK_BLOCKQUOTE,
    BLK_CODE,
} BlockState;

/* Returns 1 if line is blank (empty or only whitespace) */
static int is_blank(const char *line) {
    while (*line) { if (!isspace((unsigned char)*line)) return 0; line++; }
    return 1;
}

/* Returns number of leading # for a heading line, else 0 */
static int heading_level(const char *line) {
    int n = 0;
    while (line[n] == '#') n++;
    if (n > 0 && n <= 6 && line[n] == ' ') return n;
    return 0;
}

/* Returns 1 if line starts with "- " */
static int is_ul_item(const char *line) {
    return line[0] == '-' && line[1] == ' ';
}

/* Returns 1 if line matches ordered list pattern "N. " */
static int is_ol_item(const char *line) {
    const char *p = line;
    while (isdigit((unsigned char)*p)) p++;
    return p > line && p[0] == '.' && p[1] == ' ';
}

/* Returns 1 if line starts with "> " or ">" */
static int is_blockquote(const char *line) {
    return line[0] == '>' && (line[1] == ' ' || line[1] == '\0');
}

/* Returns 1 if line is exactly "---" (with optional surrounding spaces) */
static int is_hr(const char *line) {
    const char *p = line;
    while (*p == ' ') p++;
    if (p[0]=='-' && p[1]=='-' && p[2]=='-') {
        p += 3;
        while (*p == '-') p++;
        while (*p == ' ') p++;
        return *p == '\0';
    }
    return 0;
}

/* Returns 1 if line starts with ``` (fenced code block) */
static int is_fence(const char *line, char **lang_out) {
    if (line[0]=='`' && line[1]=='`' && line[2]=='`') {
        const char *lang = line + 3;
        while (*lang == ' ') lang++;
        if (lang_out) {
            if (*lang) {
                /* copy language tag */
                const char *end = lang;
                while (*end && !isspace((unsigned char)*end)) end++;
                size_t n = (size_t)(end - lang);
                *lang_out = malloc(n + 1);
                if (*lang_out) { memcpy(*lang_out, lang, n); (*lang_out)[n] = '\0'; }
            } else {
                *lang_out = NULL;
            }
        }
        return 1;
    }
    return 0;
}

/* Returns 1 if line starts with < (HTML passthrough) */
static int is_html_passthrough(const char *line) {
    return line[0] == '<';
}

char *md_to_html(const char *markdown) {
    if (!markdown) return strdup("");

    LineArray la = split_lines(markdown);
    StrBuf out;
    sb_init(&out);

    BlockState state   = BLK_NONE;
    int        in_code = 0;   /* inside fenced code block */
    char      *code_lang = NULL;

    /* Helper: close any open block */
#define CLOSE_BLOCK() do {                          \
    switch (state) {                                \
        case BLK_PARA:       sb_append(&out, "</p>\n");   break; \
        case BLK_UL:         sb_append(&out, "</ul>\n");  break; \
        case BLK_OL:         sb_append(&out, "</ol>\n");  break; \
        case BLK_BLOCKQUOTE: sb_append(&out, "</blockquote>\n"); break; \
        default: break;                             \
    }                                               \
    state = BLK_NONE;                               \
} while(0)

    for (size_t i = 0; i < la.count; i++) {
        const char *line = la.lines[i];

        /* --- fenced code block handling --- */
        if (in_code) {
            if (is_fence(line, NULL)) {
                /* close code block */
                sb_append(&out, "</code></pre>\n");
                in_code = 0;
                free(code_lang);
                code_lang = NULL;
            } else {
                /* raw content: escape only */
                sb_escape(&out, line);
                sb_appendc(&out, '\n');
            }
            continue;
        }

        /* --- detect fenced code block opening --- */
        if (is_fence(line, &code_lang)) {
            CLOSE_BLOCK();
            sb_append(&out, "<pre><code");
            if (code_lang && *code_lang) {
                sb_append(&out, " class=\"language-");
                sb_escape(&out, code_lang);
                sb_append(&out, "\"");
            }
            sb_append(&out, ">");
            in_code = 1;
            continue;
        }

        /* --- blank line: close current block --- */
        if (is_blank(line)) {
            CLOSE_BLOCK();
            continue;
        }

        /* --- HTML passthrough --- */
        if (is_html_passthrough(line)) {
            CLOSE_BLOCK();
            sb_append(&out, line);
            sb_appendc(&out, '\n');
            continue;
        }

        /* --- horizontal rule --- */
        if (is_hr(line)) {
            CLOSE_BLOCK();
            sb_append(&out, "<hr>\n");
            continue;
        }

        /* --- headings --- */
        int hlvl = heading_level(line);
        if (hlvl > 0) {
            CLOSE_BLOCK();
            char tag[8];
            snprintf(tag, sizeof(tag), "<h%d>", hlvl);
            sb_append(&out, tag);
            char *inl = inline_html(line + hlvl + 1);
            sb_append(&out, inl);
            free(inl);
            snprintf(tag, sizeof(tag), "</h%d>\n", hlvl);
            sb_append(&out, tag);
            continue;
        }

        /* --- blockquote --- */
        if (is_blockquote(line)) {
            const char *content = line[1] == ' ' ? line + 2 : line + 1;
            if (state != BLK_BLOCKQUOTE) {
                CLOSE_BLOCK();
                sb_append(&out, "<blockquote><p>");
                state = BLK_BLOCKQUOTE;
            } else {
                sb_append(&out, " ");
            }
            char *inl = inline_html(content);
            sb_append(&out, inl);
            free(inl);
            continue;
        }

        /* --- unordered list --- */
        if (is_ul_item(line)) {
            if (state != BLK_UL) {
                CLOSE_BLOCK();
                sb_append(&out, "<ul>\n");
                state = BLK_UL;
            }
            sb_append(&out, "<li>");
            char *inl = inline_html(line + 2);
            sb_append(&out, inl);
            free(inl);
            sb_append(&out, "</li>\n");
            continue;
        }

        /* --- ordered list --- */
        if (is_ol_item(line)) {
            if (state != BLK_OL) {
                CLOSE_BLOCK();
                sb_append(&out, "<ol>\n");
                state = BLK_OL;
            }
            /* skip past the "N. " prefix */
            const char *p = line;
            while (isdigit((unsigned char)*p)) p++;
            p += 2; /* skip ". " */
            sb_append(&out, "<li>");
            char *inl = inline_html(p);
            sb_append(&out, inl);
            free(inl);
            sb_append(&out, "</li>\n");
            continue;
        }

        /* --- paragraph --- */
        if (state == BLK_PARA) {
            /* continuation: add a space */
            sb_appendc(&out, ' ');
        } else {
            CLOSE_BLOCK();
            sb_append(&out, "<p>");
            state = BLK_PARA;
        }
        char *inl = inline_html(line);
        sb_append(&out, inl);
        free(inl);
    }

    /* close any open block at EOF */
    if (in_code) {
        sb_append(&out, "</code></pre>\n");
        free(code_lang);
    } else {
        if (state == BLK_BLOCKQUOTE) {
            sb_append(&out, "</p></blockquote>\n");
            state = BLK_NONE;
        }
        CLOSE_BLOCK();
    }

#undef CLOSE_BLOCK

    la_free(&la);
    return sb_finish(&out);
}
