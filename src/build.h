#ifndef OOKE_BUILD_H
#define OOKE_BUILD_H

#include "config.h"

/* Run the full build pipeline for a project rooted at project_dir.
 * Uses config.build_output as the output directory.
 * Returns 0 on success, non-zero on error. */
int ooke_build(const char *project_dir, const OokeConfig *cfg);

/* Copy a directory tree recursively: src/ -> dst/
 * Creates dst if it doesn't exist.
 * Returns number of files copied, or -1 on error. */
int copy_dir_recursive(const char *src, const char *dst);

/* Inline CSS: replace <link rel="stylesheet" href="..."> with <style>...</style>
 * The href must point to a file under static_dir.
 * Returns new heap-allocated string. Caller frees. */
char *html_inline_css(const char *html, const char *build_dir, const char *static_dir);

/* Minify HTML: strip <!-- comments --> and collapse runs of whitespace between tags
 * Returns new heap-allocated string. Caller frees. */
char *html_minify(const char *html);

#endif /* OOKE_BUILD_H */
