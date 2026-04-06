#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>
#include <dirent.h>
#include <sys/stat.h>
#include "store.h"

/* ---------------------------------------------------------------------------
 * Internal helpers
 * --------------------------------------------------------------------------- */

/* Trim leading and trailing ASCII whitespace in-place.
 * Returns a pointer to the first non-whitespace character inside s.
 * The string is modified: trailing whitespace is overwritten with NUL. */
static char *trim_ws(char *s) {
    char *end;
    while (isspace((unsigned char)*s)) s++;
    if (*s == '\0') return s;
    end = s + strlen(s) - 1;
    while (end > s && isspace((unsigned char)*end)) end--;
    *(end + 1) = '\0';
    return s;
}

/* Return the filename stem of path (the basename without extension).
 * The returned string is heap-allocated; caller must free it. */
static char *path_stem(const char *path) {
    const char *slash;
    const char *dot;
    const char *base;
    size_t      len;
    char       *result;

    /* Find last slash */
    slash = strrchr(path, '/');
    base  = slash ? slash + 1 : path;

    /* Find last dot after the base */
    dot = strrchr(base, '.');
    len = dot ? (size_t)(dot - base) : strlen(base);

    result = (char *)malloc(len + 1);
    if (!result) return NULL;
    memcpy(result, base, len);
    result[len] = '\0';
    return result;
}

/* Read an entire file into a heap-allocated buffer (NUL-terminated).
 * Sets *out_len to the number of bytes read (not counting NUL).
 * Returns NULL on failure. */
static char *read_file(const char *path, size_t *out_len) {
    FILE   *f;
    struct  stat st;
    size_t  file_size;
    char   *buf;
    size_t  n_read;

    if (stat(path, &st) != 0) return NULL;
    file_size = (size_t)st.st_size;

    /* Guard against absurdly large files */
    if (file_size > 1024 * 1024) return NULL;

    buf = (char *)malloc(file_size + 1);
    if (!buf) return NULL;

    f = fopen(path, "rb");
    if (!f) { free(buf); return NULL; }

    n_read = fread(buf, 1, file_size, f);
    fclose(f);

    buf[n_read] = '\0';
    if (out_len) *out_len = n_read;
    return buf;
}

/* Parse frontmatter out of raw file content.
 * Populates f->fields, f->field_count, f->body.
 * All strings are heap-allocated.
 * Returns 1 on success, 0 on allocation failure. */
static int parse_frontmatter(const char *content, ContentFile *f) {
    const char *p     = content;
    const char *body_start;
    size_t      fields_cap = 8;
    size_t      field_count = 0;
    FrontmatterField *fields;

    /* Initialise output */
    f->fields      = NULL;
    f->field_count = 0;
    f->body        = NULL;

    /* Check for opening delimiter */
    if (strncmp(p, "---\n", 4) != 0) {
        /* No frontmatter — entire content is body */
        f->body = strdup(p);
        return f->body ? 1 : 0;
    }
    p += 4; /* skip opening --- */

    fields = (FrontmatterField *)malloc(fields_cap * sizeof(FrontmatterField));
    if (!fields) return 0;

    /* Parse lines until closing --- or end of string */
    while (*p != '\0') {
        const char *line_end;
        size_t      line_len;
        char       *line;
        char       *colon;
        char       *key_s;
        char       *val_s;

        line_end = strchr(p, '\n');
        line_len = line_end ? (size_t)(line_end - p) : strlen(p);

        /* Detect closing delimiter */
        if (line_len == 3 && strncmp(p, "---", 3) == 0) {
            p = line_end ? line_end + 1 : p + 3;
            break;
        }

        /* Copy line into a mutable buffer for parsing */
        line = (char *)malloc(line_len + 1);
        if (!line) goto fail_fields;
        memcpy(line, p, line_len);
        line[line_len] = '\0';

        /* Advance past this line */
        p = line_end ? line_end + 1 : p + line_len;

        /* Split on first colon */
        colon = strchr(line, ':');
        if (!colon) {
            /* Malformed line — skip */
            free(line);
            continue;
        }

        *colon = '\0';
        key_s  = trim_ws(line);
        val_s  = trim_ws(colon + 1);

        /* Skip blank keys */
        if (*key_s == '\0') { free(line); continue; }

        /* Grow fields array if needed */
        if (field_count == fields_cap) {
            size_t new_cap = fields_cap * 2;
            FrontmatterField *tmp = (FrontmatterField *)realloc(
                fields, new_cap * sizeof(FrontmatterField));
            if (!tmp) { free(line); goto fail_fields; }
            fields     = tmp;
            fields_cap = new_cap;
        }

        fields[field_count].key = strdup(key_s);
        fields[field_count].val = strdup(val_s);
        free(line);

        if (!fields[field_count].key || !fields[field_count].val) {
            free(fields[field_count].key);
            free(fields[field_count].val);
            goto fail_fields;
        }
        field_count++;
    }

    /* Everything remaining (from p onward) is the body */
    body_start  = p;
    f->body     = strdup(body_start);
    if (!f->body) goto fail_fields;

    f->fields      = fields;
    f->field_count = field_count;
    return 1;

fail_fields:
    for (size_t i = 0; i < field_count; i++) {
        free(fields[i].key);
        free(fields[i].val);
    }
    free(fields);
    return 0;
}

/* ---------------------------------------------------------------------------
 * Public API
 * --------------------------------------------------------------------------- */

const char *content_get(const ContentFile *f, const char *key) {
    size_t i;
    if (!f || !key) return NULL;
    for (i = 0; i < f->field_count; i++) {
        if (f->fields[i].key && strcmp(f->fields[i].key, key) == 0)
            return f->fields[i].val;
    }
    return NULL;
}

int store_load_file(const char *path, const char *type, ContentFile *out) {
    char   *content;
    size_t  content_len;
    const char *slug_field;

    if (!path || !out) return 0;

    memset(out, 0, sizeof(*out));

    content = read_file(path, &content_len);
    if (!content) return 0;

    if (!parse_frontmatter(content, out)) {
        free(content);
        return 0;
    }
    free(content);

    out->path = strdup(path);
    if (!out->path) goto fail;

    out->type = type ? strdup(type) : NULL;
    if (type && !out->type) goto fail;

    /* Resolve slug: prefer frontmatter, fall back to filename stem */
    slug_field = content_get(out, "slug");
    if (slug_field) {
        out->slug = strdup(slug_field);
    } else {
        out->slug = path_stem(path);
    }
    if (!out->slug) goto fail;

    return 1;

fail:
    store_free_collection(NULL); /* just a safety no-op */
    /* Free whatever was partially allocated */
    for (size_t i = 0; i < out->field_count; i++) {
        free(out->fields[i].key);
        free(out->fields[i].val);
    }
    free(out->fields);
    free(out->body);
    free(out->path);
    free(out->type);
    free(out->slug);
    memset(out, 0, sizeof(*out));
    return 0;
}

const ContentFile *store_find(const ContentCollection *col,
                              const char *key, const char *val) {
    size_t i;
    if (!col || !key || !val) return NULL;
    for (i = 0; i < col->count; i++) {
        const char *fval = content_get(&col->items[i], key);
        if (fval && strcmp(fval, val) == 0)
            return &col->items[i];
    }
    return NULL;
}

const ContentFile *store_slug(const ContentCollection *col, const char *slug) {
    size_t i;
    if (!col || !slug) return NULL;
    for (i = 0; i < col->count; i++) {
        if (col->items[i].slug && strcmp(col->items[i].slug, slug) == 0)
            return &col->items[i];
    }
    return NULL;
}

void store_free_collection(ContentCollection *col) {
    size_t i, j;
    if (!col) return;
    for (i = 0; i < col->count; i++) {
        ContentFile *f = &col->items[i];
        for (j = 0; j < f->field_count; j++) {
            free(f->fields[j].key);
            free(f->fields[j].val);
        }
        free(f->fields);
        free(f->body);
        free(f->path);
        free(f->slug);
        free(f->type);
    }
    free(col->items);
    col->items = NULL;
    col->count = 0;
    col->cap   = 0;
}

/* qsort comparator: descending by created timestamp */
static int cmp_created_desc(const void *a, const void *b) {
    const ContentFile *fa = (const ContentFile *)a;
    const ContentFile *fb = (const ContentFile *)b;
    const char        *sa = content_get(fa, "created");
    const char        *sb = content_get(fb, "created");
    uint64_t           ta = sa ? (uint64_t)strtoull(sa, NULL, 10) : 0;
    uint64_t           tb = sb ? (uint64_t)strtoull(sb, NULL, 10) : 0;

    if (ta > tb) return -1;
    if (ta < tb) return  1;
    return 0;
}

void store_sort_by_created(ContentCollection *col) {
    if (!col || col->count < 2) return;
    qsort(col->items, col->count, sizeof(ContentFile), cmp_created_desc);
}

ContentCollection store_all(const char *content_dir, const char *type) {
    ContentCollection col;
    DIR              *dir;
    struct dirent    *ent;
    char              dir_path[4096];
    char              file_path[4096];
    size_t            dir_len;

    col.items = NULL;
    col.count = 0;
    col.cap   = 0;

    if (!content_dir || !type) return col;

    /* Build path: content_dir/type */
    dir_len = (size_t)snprintf(dir_path, sizeof(dir_path), "%s/%s",
                               content_dir, type);
    if (dir_len >= sizeof(dir_path)) return col;

    dir = opendir(dir_path);
    if (!dir) return col; /* directory doesn't exist — return empty */

    while ((ent = readdir(dir)) != NULL) {
        const char *name = ent->d_name;
        size_t      name_len;
        ContentFile f;
        ContentFile *new_items;

        /* Skip hidden files and . / .. */
        if (name[0] == '.') continue;

        /* Only process .md files */
        name_len = strlen(name);
        if (name_len < 3) continue;
        if (strcmp(name + name_len - 3, ".md") != 0) continue;

        /* Build absolute file path */
        if ((size_t)snprintf(file_path, sizeof(file_path), "%s/%s",
                             dir_path, name) >= sizeof(file_path))
            continue;

        if (!store_load_file(file_path, type, &f)) continue;

        /* Grow items array if needed */
        if (col.count == col.cap) {
            size_t new_cap = col.cap == 0 ? 8 : col.cap * 2;
            new_items = (ContentFile *)realloc(col.items,
                                               new_cap * sizeof(ContentFile));
            if (!new_items) {
                /* Out of memory — free what we just loaded and stop */
                store_free_collection(NULL);
                for (size_t i = 0; i < f.field_count; i++) {
                    free(f.fields[i].key);
                    free(f.fields[i].val);
                }
                free(f.fields);
                free(f.body);
                free(f.path);
                free(f.slug);
                free(f.type);
                break;
            }
            col.items = new_items;
            col.cap   = new_cap;
        }

        col.items[col.count++] = f;
    }

    closedir(dir);

    store_sort_by_created(&col);
    return col;
}
