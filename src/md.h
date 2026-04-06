#ifndef OOKE_MD_H
#define OOKE_MD_H

/*
 * md.h — minimal Markdown-to-HTML renderer for ooke template engine
 *
 * Supports: headings, bold, italic, inline code, fenced code blocks,
 * links, images, unordered/ordered lists, blockquotes, horizontal rules,
 * paragraphs, HTML passthrough, and proper HTML escaping.
 */

/*
 * Convert a Markdown string to an HTML string.
 * Returns a heap-allocated NUL-terminated string. Caller must free().
 * Returns NULL on allocation failure.
 */
char *md_to_html(const char *markdown);

#endif /* OOKE_MD_H */
