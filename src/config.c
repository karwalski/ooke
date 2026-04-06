#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "config.h"

void ooke_config_defaults(OokeConfig *out) {
    memset(out, 0, sizeof(*out));

    /* [site] */
    strncpy(out->site_name,     "My Ooke Site",       sizeof(out->site_name)     - 1);
    strncpy(out->site_url,      "http://localhost:3000", sizeof(out->site_url)   - 1);
    strncpy(out->site_language, "en",                  sizeof(out->site_language) - 1);

    /* [build] */
    strncpy(out->build_output,  "build/",              sizeof(out->build_output)  - 1);
    out->build_minify         = 1;
    out->build_inline_css     = 1;
    out->build_image_optimize = 0;

    /* [server] */
    out->server_port    = 3000;
    out->server_admin   = 0;
    out->server_workers = 0;

    /* [store] */
    strncpy(out->store_backend, "flat",                sizeof(out->store_backend) - 1);

    /* [log] */
    strncpy(out->log_access,    "logs/access.log",     sizeof(out->log_access)    - 1);
    out->log_max_lines    = 10000;
    out->log_max_age_days = 30;
}

/* Trim leading and trailing whitespace in-place; returns pointer to first
   non-whitespace character. The string is modified so trailing whitespace
   is replaced with NUL. */
static char *trim(char *s) {
    char *end;
    while (isspace((unsigned char)*s)) s++;
    if (*s == '\0') return s;
    end = s + strlen(s) - 1;
    while (end > s && isspace((unsigned char)*end)) end--;
    *(end + 1) = '\0';
    return s;
}

/* Strip surrounding double-quotes from s, returning pointer inside s. */
static char *strip_quotes(char *s) {
    size_t len = strlen(s);
    if (len >= 2 && s[0] == '"' && s[len - 1] == '"') {
        s[len - 1] = '\0';
        return s + 1;
    }
    return s;
}

int ooke_config_load(const char *path, OokeConfig *out) {
    FILE *f;
    char  line[1024];
    char  section[64] = "";

    ooke_config_defaults(out);

    f = fopen(path, "r");
    if (!f) return -1;

    while (fgets(line, sizeof(line), f)) {
        char *p = trim(line);

        /* Skip blank lines and comments. */
        if (*p == '\0' || *p == '#') continue;

        /* Section header: [section] */
        if (*p == '[') {
            char *end = strchr(p + 1, ']');
            if (end) {
                size_t len = (size_t)(end - (p + 1));
                if (len >= sizeof(section)) len = sizeof(section) - 1;
                memcpy(section, p + 1, len);
                section[len] = '\0';
            }
            continue;
        }

        /* Key = value line */
        char *eq = strchr(p, '=');
        if (!eq) continue;

        *eq = '\0';
        char *key = trim(p);
        char *val = trim(eq + 1);
        val = strip_quotes(val);

        /* Interpret boolean strings as integers. */
        int bool_val = 0;
        int is_bool  = 0;
        if (strcmp(val, "true") == 0)  { bool_val = 1; is_bool = 1; }
        if (strcmp(val, "false") == 0) { bool_val = 0; is_bool = 1; }

        /* Dispatch on section + key. */
        if (strcmp(section, "site") == 0) {
            if (strcmp(key, "name") == 0)
                strncpy(out->site_name, val, sizeof(out->site_name) - 1);
            else if (strcmp(key, "url") == 0)
                strncpy(out->site_url, val, sizeof(out->site_url) - 1);
            else if (strcmp(key, "language") == 0)
                strncpy(out->site_language, val, sizeof(out->site_language) - 1);

        } else if (strcmp(section, "build") == 0) {
            if (strcmp(key, "output") == 0)
                strncpy(out->build_output, val, sizeof(out->build_output) - 1);
            else if (strcmp(key, "minify") == 0)
                out->build_minify = is_bool ? bool_val : atoi(val);
            else if (strcmp(key, "inline_css") == 0)
                out->build_inline_css = is_bool ? bool_val : atoi(val);
            else if (strcmp(key, "image_optimize") == 0)
                out->build_image_optimize = is_bool ? bool_val : atoi(val);

        } else if (strcmp(section, "server") == 0) {
            if (strcmp(key, "port") == 0)
                out->server_port = atoi(val);
            else if (strcmp(key, "admin") == 0)
                out->server_admin = is_bool ? bool_val : atoi(val);
            else if (strcmp(key, "workers") == 0)
                out->server_workers = atoi(val);

        } else if (strcmp(section, "store") == 0) {
            if (strcmp(key, "backend") == 0)
                strncpy(out->store_backend, val, sizeof(out->store_backend) - 1);

        } else if (strcmp(section, "log") == 0) {
            if (strcmp(key, "access") == 0)
                strncpy(out->log_access, val, sizeof(out->log_access) - 1);
            else if (strcmp(key, "max_lines") == 0)
                out->log_max_lines = atoi(val);
            else if (strcmp(key, "max_age_days") == 0)
                out->log_max_age_days = atoi(val);
        }
    }

    fclose(f);
    return 0;
}
