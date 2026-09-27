# Request logs and TLS for `ooke serve`

Story 134.40. This covers what `[log]` and `[tls]` in `ooke.toml` do, why the
design is this small, and what the toke stdlib cannot do yet.

## What was wrong

- `[log]` had three keys, `accessformat`, `maxlines` and `maxagedays`.
  `config.configload` read them and nothing else did. `ooke serve` opened no
  log, so it logged no request anywhere. There was no key for a log path:
  story 134.23 removed a misnamed one.
- `serve.serverun` takes a certificate and a key, but `cli.runserve` always
  passed `""` for both, and `ooke.toml` had no key for either. So `ooke serve`
  only ever served plain HTTP.
- `serverun` threw away the return value of `http.servetls` and
  `http.serveworkers`. So a certificate that failed to load, or a port that
  failed to bind, ended the process with exit status 0 and no message.

## The capability that exists (toke `std.log`, `std.http`)

These were read from `toke/src/stdlib/log.c`, `log_glue.c`, `http.c` and
`stdlib/log.tki`:

| Call | What it does |
|---|---|
| `log.openaccess(path; maxlines; maxfiles; maxagedays)` | Opens (appends to) the process-wide access log. Returns 0, or -1 if the file cannot be opened. |
| `log.openerror(path; maxlines; maxfiles; maxagedays)` | The same for the error log. std.http writes the access line to it again when the status is >= 400. It is **not** a separate diagnostic stream. |
| `log.accessformat(fmt)` | `"combined"` (Apache Combined Log Format) or `"json"` (one JSON object per line). **Any other value is ignored without a message.** |
| `http.servetls(port; cert; key)` | Serves HTTPS through OpenSSL. Returns -1 if the cert or key does not load. The worker count comes from `TK_HTTP_WORKERS` or the CPU count. **It takes no worker argument.** |

std.http writes one line per request to whichever logs are open. If none is
open, it writes nothing.

## Design

```toml
[log]
access = "-"               # a file path, "-" for stderr, "" for off. Default "-".
error = ""                 # the same. Default "" (off).
accessformat = "combined"  # "combined" or "json". Default "combined".

[tls]
cert = "certs/cert.pem"    # both or neither. When set, serve speaks HTTPS.
key = "certs/key.pem"
```

- **Paths** are resolved against the project directory, not the working
  directory. The resolver is `build.buildresolve`, as for pages and templates
  (134.25, 134.37). So `ooke serve site` from the parent directory writes
  `site/logs/access.log`.
- **`"-"`** opens `/dev/stderr`. That puts request lines on the stream that
  already carries serve's JSON startup messages.
- **Why access defaults to stderr and error to off.** The brief asked for
  both to default to stderr. But std.log's error log only repeats access lines
  with status >= 400, so on the same stream it would print every 4xx and 5xx
  twice. An error log is useful only as a separate file, so it is opt-in.
- **Refusals.** Each of these makes serve log the reason and exit 1 before
  anything binds:
  - an `accessformat` that is not `combined` or `json`
  - a configured log that cannot be opened
  - a `[tls]` table with only one of `cert` and `key`
  - a `cert` or `key` file that does not exist

  A cert that exists but does not load stops the server with an error and a
  non-zero exit. Before this change it exited 0.
- **The one limit this design hits:** `$ookecfg` is now at 15 fields. toke's
  code generator drops every struct field past the 16th (see below).

## Rotation: `maxlines` and `maxagedays` are removed, not wired

std.log does rotate. `openaccess` takes `maxlines` and `maxagedays`, renames
the live file to `stem.YYYYMMDD-HHMMSS.ext`, gzips it, and deletes archives
older than `maxagedays`. But measured through ooke, it loses the log:

| Run (`maxlines = 5`, 40 requests) | Lines kept |
|---|---|
| 1 worker, 0.3 s between requests | 40 of 40 |
| 1 worker, back to back | **15 of 40** |
| 4 workers (pre-fork), 0.3 s apart | **4 of 40** |
| 4 workers, `maxlines = 0` (no rotation) | 40 of 40 |

There are two causes, both in `toke/src/stdlib/log.c`:

1. **The rotated name has one-second resolution.** When a second rotation
   falls in the same second, it renames onto the same name and gzips over the
   first archive.
2. **Each pre-fork worker keeps its own line count and its own `FILE*`.**
   When one worker rotates, it renames the file, gzips it and unlinks it. The
   other workers keep appending to the unlinked inode until they reach their
   own count. `ooke serve` runs pre-fork workers by default (`workers = 0`
   means one per CPU), and with TLS it always does.

ooke cannot fix either from toke, and the toke-first rule says to report a
missing stdlib capability rather than work around it. So ooke no longer reads
the keys. If an `ooke.toml` still sets either one, serve logs a warning naming
them (`config.configlogunsupported`) and ignores them. An old `[store]` table
is ignored the same way (134.34). `ooke new` no longer writes them. To rotate,
use an external tool that truncates in place, such as `logrotate` with
`copytruncate`. That works because the logs are opened in append mode. A tool
that renames the file needs serve to reopen it, and serve has no way to.

When std.log's rotation is safe across processes and within one second,
wiring it back means passing two integers to `log.openaccess` in
`serve.serveopenlogs`.

## Bind address

Story 138.7 (loke handoff O-3). `[server] host` is the address `ooke serve`
listens on, and so is the per-app binary `ooke compile` builds, which runs the
same `cli.runserve`:

```toml
[server]
host = "127.0.0.1"   # the default: this machine only
port = 3000
```

ooke passes it to toke's `http.serveworkerson` (or `http.servetlson` with
`[tls]`), toke story 138.1. toke decides what a host may be: an IPv4 literal,
`"localhost"` (127.0.0.1), or `""`, `"*"` or `"0.0.0.0"` for every
interface. A name to resolve or an IPv6 address is refused, not widened to
every interface: the server does not start, toke prints
`DIAGNOSTIC: kind=server_start_failed ... stage="host"`, ooke logs
`server stopped with an error on port N (host H)`, and the process exits 1.

**The default is 127.0.0.1, loopback only.** Before 138.7 ooke listened on
every interface and had no setting for it. toke kept every interface as the
default of its port-only functions, so that toke servers already deployed do
not drop off the network with no compile error. ooke chose the other default,
for three reasons:

- `ooke serve` is first a development and local-first server. loke runs it
  on the user's own machine, where "every interface" includes whatever
  network that machine has joined.
- The two mistakes are not equally visible. A loopback server that should
  have been public fails the first request from another machine, and its
  start log says what to change:
  `listening on loopback only (127.0.0.1:3000); set [server] host = "0.0.0.0" in ooke.toml to accept connections from other machines`.
  A public server that should have been private tells nobody.
- 3.0.0 is already a breaking release (see `CHANGELOG.md`), and it says so.

A deployment sets `host = "0.0.0.0"`. `ooke new` writes `host = "127.0.0.1"`
into the scaffold, so the setting is visible in every new project.

`test/serve/serve_host.sh` (`make test-serve-host`) checks the listening socket
with `lsof`, so it tests what the kernel reports, not what ooke logs: no key
gives `127.0.0.1:PORT`, `host = "0.0.0.0"` gives `*:PORT`, and
`host = "example.com"` is refused with a non-zero exit that names the host.

## TLS

`[tls] cert` and `key` go to `serverun`, which calls `http.servetlson`. The test
makes a self-signed pair locally with `openssl req -x509`, so it needs no
network. It checks that HTTPS serves the project and that plain HTTP on the
same port gets no answer.

Known limit: `http.servetls` takes no worker count. So `[server].workers` is
ignored under TLS, and the worker count comes from `TK_HTTP_WORKERS` or the
CPU count. The C function `http_serve_tls_workers` exists, but std.http does
not expose it to toke.

## Found on the way, and reported rather than worked around

- **toke: a struct with more than 16 fields.** `tkc --check` accepts it, but
  `--emit-llvm` fails with `E4025 struct 'X' has no field 'f16'`, tagged
  `stage: type_check`. The cause is `StructInfo.field_names[TKC_MAX_PARAMS]`
  in `src/llvm.c`, where `TKC_MAX_PARAMS` is 16. `--check` and the build
  disagree, and the message names a field that exists.
- **toke std.log:** the two rotation defects above. Also, `accessformat`
  ignores an unknown value without a message.
- **toke std.http:** `servetls` has no worker-count parameter.

## Tests

- `test/serve/serve_logs_tls.sh` runs as `make test-serve-logs`, which is part
  of `make test`. It serves a copy of `testproj/`, sends real requests and
  reads the files that were written. It checks:
  - the access file (combined format)
  - the error file (the 404 only)
  - JSON format
  - the stderr default
  - `access = ""` (off)
  - that the rotation keys are named and ignored
  - each refusal
  - HTTPS
- `test/config/test_config.tk` checks that the new keys are read, their
  defaults, and `configlogunsupported`.
- `test/cli/test_cli.tk` checks that `cfgdefault` matches the new defaults.
