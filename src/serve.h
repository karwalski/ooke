#ifndef OOKE_SERVE_H
#define OOKE_SERVE_H

#include "config.h"

/*
 * ooke_serve — run the live HTTP/HTTPS server for a project.
 *
 * project_dir: root directory of the ooke project (contains ooke.toml,
 *              pages/, templates/, content/, static/).
 * cfg:         already-loaded project configuration.
 * cert_path:   path to TLS certificate PEM file, or NULL for plain HTTP.
 * key_path:    path to TLS private key PEM file, or NULL for plain HTTP.
 *
 * Blocks until the server exits.
 * Returns 0 on clean shutdown, non-zero on error.
 */
int ooke_serve(const char *project_dir, const OokeConfig *cfg,
               const char *cert_path, const char *key_path);

#endif /* OOKE_SERVE_H */
