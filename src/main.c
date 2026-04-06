#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <errno.h>
#include "config.h"
#include "build.h"
#include "serve.h"

#define OOKE_VERSION "0.1.0"
#define CONFIG_FILE  "ooke.toml"

/* ---------------------------------------------------------------------------
 * Helpers
 * --------------------------------------------------------------------------*/

static int make_dir(const char *path) {
    if (mkdir(path, 0755) != 0 && errno != EEXIST) {
        fprintf(stderr, "ooke: cannot create directory '%s': %s\n", path, strerror(errno));
        return -1;
    }
    return 0;
}

/* Write text to a file; returns 0 on success, -1 on error. */
static int write_file(const char *path, const char *content) {
    FILE *f = fopen(path, "w");
    if (!f) {
        fprintf(stderr, "ooke: cannot write '%s': %s\n", path, strerror(errno));
        return -1;
    }
    fputs(content, f);
    fclose(f);
    return 0;
}

/* Build a path string of the form <base>/<rest> into buf. */
static void join_path(char *buf, size_t bufsz, const char *base, const char *rest) {
    snprintf(buf, bufsz, "%s/%s", base, rest);
}

/* ---------------------------------------------------------------------------
 * Usage / version
 * --------------------------------------------------------------------------*/

static void print_version(void) {
    printf("ooke %s\n", OOKE_VERSION);
}

static void print_usage(void) {
    printf("ooke %s — a CMS/web framework built on the toke language\n\n", OOKE_VERSION);
    printf("Usage:\n");
    printf("  ooke new <name>                     scaffold a new project\n");
    printf("  ooke build                          build static site\n");
    printf("  ooke serve                          run HTTP server\n");
    printf("  ooke serve --tls <cert> <key>       run HTTPS server\n");
    printf("  ooke gen type <name>                generate model stub\n");
    printf("  ooke gen page <path>                generate page handler stub\n");
    printf("  ooke gen api <name>                 generate API endpoint stub\n");
    printf("  ooke gen island <name>              generate island component stub\n");
    printf("  ooke --version                      print version\n");
    printf("  ooke --help                         print this help\n");
}

/* ---------------------------------------------------------------------------
 * cmd_new
 * --------------------------------------------------------------------------*/

static int cmd_new(const char *name) {
    char path[512];

    /* Top-level project directory */
    if (make_dir(name) != 0) return 1;

#define SUBDIR(p) \
    do { \
        join_path(path, sizeof(path), name, (p)); \
        if (make_dir(path) != 0) return 1; \
    } while (0)

    SUBDIR("content");
    SUBDIR("content/posts");
    SUBDIR("content/pages");
    SUBDIR("models");
    SUBDIR("pages");
    SUBDIR("pages/blog");
    SUBDIR("pages/api");
    SUBDIR("templates");
    SUBDIR("templates/partials");
    SUBDIR("islands");
    SUBDIR("static");
    SUBDIR("static/css");
    SUBDIR("static/images");
    SUBDIR("build");
    SUBDIR("logs");

#undef SUBDIR

    /* ooke.toml */
    {
        char toml[1024];
        snprintf(toml, sizeof(toml),
            "[site]\n"
            "name = \"%s\"\n"
            "url = \"http://localhost:3000\"\n"
            "language = \"en\"\n"
            "\n"
            "[build]\n"
            "output = \"build/\"\n"
            "minify = true\n"
            "inline_css = true\n"
            "image_optimize = false\n"
            "\n"
            "[server]\n"
            "port = 3000\n"
            "admin = false\n"
            "workers = 0\n"
            "\n"
            "[store]\n"
            "backend = \"flat\"\n"
            "\n"
            "[log]\n"
            "access = \"logs/access.log\"\n"
            "max_lines = 10000\n"
            "max_age_days = 30\n",
            name);
        join_path(path, sizeof(path), name, "ooke.toml");
        if (write_file(path, toml) != 0) return 1;
    }

    /* pages/index.tk */
    {
        const char *index_tk =
            "m=page.index;\n"
            "i=http:std.http;\n"
            "\n"
            "f=get(req:http.$req):http.$res{\n"
            "  <http.ok(\"<h1>Hello from ooke</h1>\");\n"
            "};\n";
        join_path(path, sizeof(path), name, "pages/index.tk");
        if (write_file(path, index_tk) != 0) return 1;
    }

    /* templates/base.tkt */
    {
        const char *base_tkt =
            "<!DOCTYPE html>\n"
            "<html lang=\"en\">\n"
            "<head>\n"
            "  <meta charset=\"UTF-8\">\n"
            "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
            "  <title>{= site.name =}</title>\n"
            "  <link rel=\"stylesheet\" href=\"/static/css/style.css\">\n"
            "</head>\n"
            "<body>\n"
            "  <nav>\n"
            "    <a href=\"/\">{= site.name =}</a>\n"
            "  </nav>\n"
            "  <main>\n"
            "    {! yield(\"content\") !}\n"
            "  </main>\n"
            "  <footer>\n"
            "    <p>Built with ooke on toke.</p>\n"
            "  </footer>\n"
            "</body>\n"
            "</html>\n";
        join_path(path, sizeof(path), name, "templates/base.tkt");
        if (write_file(path, base_tkt) != 0) return 1;
    }

    printf("ooke: created project '%s'\n", name);
    printf("  cd %s && ooke serve\n", name);
    return 0;
}

/* ---------------------------------------------------------------------------
 * cmd_build
 * --------------------------------------------------------------------------*/

static int cmd_build(void) {
    OokeConfig cfg;
    if (ooke_config_load(CONFIG_FILE, &cfg) != 0) {
        fprintf(stderr, "ooke build: cannot open '%s'\n", CONFIG_FILE);
        return 1;
    }
    printf("Building site '%s' → %s\n", cfg.site_name, cfg.build_output);
    return ooke_build(".", &cfg);
}

/* ---------------------------------------------------------------------------
 * cmd_serve
 * --------------------------------------------------------------------------*/

static int cmd_serve(const char *cert, const char *key) {
    OokeConfig cfg;
    if (ooke_config_load(CONFIG_FILE, &cfg) != 0) {
        fprintf(stderr, "ooke serve: cannot open '%s'\n", CONFIG_FILE);
        return 1;
    }
    return ooke_serve(".", &cfg, cert, key);
}

/* ---------------------------------------------------------------------------
 * cmd_gen_type
 * --------------------------------------------------------------------------*/

static int cmd_gen_type(const char *name) {
    char path[512];
    char buf[1024];

    snprintf(path, sizeof(path), "models/%s.tk", name);
    snprintf(buf, sizeof(buf),
        "m=models.%s;\n"
        "\n"
        "t=$%s{\n"
        "  $title:$str;\n"
        "  $slug:$str;\n"
        "  $body:$str;\n"
        "  $published:bool;\n"
        "  $created:u64;\n"
        "  $tags:@($str)\n"
        "};\n",
        name, name);

    if (write_file(path, buf) != 0) return 1;
    printf("ooke gen type: created %s\n", path);
    return 0;
}

/* ---------------------------------------------------------------------------
 * cmd_gen_page
 * --------------------------------------------------------------------------*/

static int cmd_gen_page(const char *pagepath) {
    char filepath[512];
    char buf[1024];

    snprintf(filepath, sizeof(filepath), "pages/%s.tk", pagepath);
    snprintf(buf, sizeof(buf),
        "m=page.%s;\n"
        "i=http:std.http;\n"
        "i=tpl:ooke.template;\n"
        "i=store:ooke.store;\n"
        "\n"
        "f=get(req:http.$req):http.$res{\n"
        "  <tpl.renderfile(\"templates/%s.tkt\"; @(\"title\":\"Page Title\"));\n"
        "};\n",
        pagepath, pagepath);

    if (write_file(filepath, buf) != 0) return 1;
    printf("ooke gen page: created %s\n", filepath);
    return 0;
}

/* ---------------------------------------------------------------------------
 * cmd_gen_api
 * --------------------------------------------------------------------------*/

static int cmd_gen_api(const char *name) {
    char path[512];
    char buf[1024];

    snprintf(path, sizeof(path), "pages/api/%s.tk", name);
    snprintf(buf, sizeof(buf),
        "m=api.%s;\n"
        "i=http:std.http;\n"
        "i=json:std.json;\n"
        "\n"
        "f=get(req:http.$req):http.$res{\n"
        "  <http.json(200; \"{\\\"ok\\\":true}\");\n"
        "};\n"
        "\n"
        "f=post(req:http.$req):http.$res{\n"
        "  <http.json(201; \"{\\\"ok\\\":true}\");\n"
        "};\n",
        name);

    if (write_file(path, buf) != 0) return 1;
    printf("ooke gen api: created %s\n", path);
    return 0;
}

/* ---------------------------------------------------------------------------
 * cmd_gen_island
 * --------------------------------------------------------------------------*/

static int cmd_gen_island(const char *name) {
    char path[512];
    char buf[1024];

    snprintf(path, sizeof(path), "islands/%s.tk", name);
    snprintf(buf, sizeof(buf),
        "m=island.%s;\n"
        "i=http:std.http;\n"
        "\n"
        "# Island component: renders interactive fragment for %s\n"
        "f=render(props:@($str)):$str{\n"
        "  <\"<div class=\\\"island-%s\\\"></div>\";\n"
        "};\n",
        name, name, name);

    if (write_file(path, buf) != 0) return 1;
    printf("ooke gen island: created %s\n", path);
    return 0;
}

/* ---------------------------------------------------------------------------
 * main
 * --------------------------------------------------------------------------*/

int main(int argc, char **argv) {
    if (argc < 2) {
        print_usage();
        return 1;
    }

    if (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "-v") == 0) {
        print_version();
        return 0;
    }

    if (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
        print_usage();
        return 0;
    }

    if (strcmp(argv[1], "new") == 0) {
        if (argc < 3) {
            fprintf(stderr, "ooke new: expected <name>\n");
            return 1;
        }
        return cmd_new(argv[2]);
    }

    if (strcmp(argv[1], "build") == 0) {
        return cmd_build();
    }

    if (strcmp(argv[1], "serve") == 0) {
        const char *cert = NULL;
        const char *key  = NULL;
        if (argc >= 5 && strcmp(argv[2], "--tls") == 0) {
            cert = argv[3];
            key  = argv[4];
        }
        return cmd_serve(cert, key);
    }

    if (strcmp(argv[1], "gen") == 0) {
        if (argc < 4) {
            fprintf(stderr, "ooke gen: expected <type|page|api|island> <name>\n");
            return 1;
        }
        const char *kind = argv[2];
        const char *name = argv[3];

        if (strcmp(kind, "type") == 0)   return cmd_gen_type(name);
        if (strcmp(kind, "page") == 0)   return cmd_gen_page(name);
        if (strcmp(kind, "api") == 0)    return cmd_gen_api(name);
        if (strcmp(kind, "island") == 0) return cmd_gen_island(name);

        fprintf(stderr, "ooke gen: unknown kind '%s'\n", kind);
        return 1;
    }

    fprintf(stderr, "ooke: unknown command '%s' (try --help)\n", argv[1]);
    return 1;
}
