#ifndef OOKE_CONFIG_H
#define OOKE_CONFIG_H

typedef struct {
    /* [site] */
    char site_name[256];
    char site_url[512];
    char site_language[16];
    /* [build] */
    char build_output[256];    /* default: "build/" */
    int  build_minify;         /* default: 1 */
    int  build_inline_css;     /* default: 1 */
    int  build_image_optimize; /* default: 0 */
    /* [server] */
    int  server_port;          /* default: 3000 */
    int  server_admin;         /* default: 0 */
    int  server_workers;       /* default: 0 (auto = cpu count) */
    /* [store] */
    char store_backend[16];    /* "flat" or "sqlite" */
    /* [log] */
    char log_access[256];      /* default: "logs/access.log" */
    int  log_max_lines;        /* default: 10000 */
    int  log_max_age_days;     /* default: 30 */
} OokeConfig;

int  ooke_config_load(const char *path, OokeConfig *out);
void ooke_config_defaults(OokeConfig *out);

#endif /* OOKE_CONFIG_H */
