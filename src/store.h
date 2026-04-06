#ifndef OOKE_STORE_H
#define OOKE_STORE_H

#include <stddef.h>

/* A single frontmatter key-value pair */
typedef struct {
    char *key;
    char *val;
} FrontmatterField;

/* A loaded content file */
typedef struct {
    FrontmatterField *fields;     /* frontmatter key-value pairs */
    size_t            field_count;
    char             *body;       /* everything after the closing --- */
    char             *path;       /* absolute file path */
    char             *slug;       /* value of "slug" frontmatter field (or filename stem) */
    char             *type;       /* content type (directory name, e.g. "posts") */
} ContentFile;

/* A collection of loaded content files */
typedef struct {
    ContentFile *items;
    size_t       count;
    size_t       cap;
} ContentCollection;

/* Load all content files of a given type from content_dir/type/
 * Returns allocated ContentCollection. Caller must free with store_free_collection(). */
ContentCollection store_all(const char *content_dir, const char *type);

/* Find first item where frontmatter field `key` equals `val`.
 * Returns pointer into collection (do not free individually), or NULL if not found. */
const ContentFile *store_find(const ContentCollection *col, const char *key, const char *val);

/* Shorthand: find by slug field */
const ContentFile *store_slug(const ContentCollection *col, const char *slug);

/* Get a frontmatter field value by key. Returns NULL if not found. */
const char *content_get(const ContentFile *f, const char *key);

/* Free a collection and all its contents */
void store_free_collection(ContentCollection *col);

/* Sort collection by created field (descending — newest first) */
void store_sort_by_created(ContentCollection *col);

/* Parse a single content file from disk.
 * Returns 1 on success, 0 on failure. */
int store_load_file(const char *path, const char *type, ContentFile *out);

#endif /* OOKE_STORE_H */
