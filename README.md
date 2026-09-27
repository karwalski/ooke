# ooke

ooke is a web framework for building websites and web applications using the [toke](https://github.com/karwalski/toke) programming language. It compiles your entire site -- pages, templates, and server -- into a single binary file that runs anywhere without installing extra software.

**toke on ooke** -- build light, ship fast.

## About toke

> toke: a compiled language designed for LLM code generation, with a small grammar, one
> canonical form and compiler verification.

toke is a compiled programming language designed for LLM code generation. It has 14
keywords, a 59-character set, a backtrack-free grammar with bounded lookahead, and one
canonical form per construct, chosen by measurement in a 46-pattern catalogue and
reproduced by `tkc --min`. That makes generated code cheap to constrain during decoding,
cheap for a compiler to verify afterwards, and compact to emit. Token efficiency is one
measured property of toke, always reported with its tokenizer and its baseline, not the
whole claim.

*The one-liner and the paragraph above are reproduced word for word from the canonical
description,
[`docs/about/canonical.md`](https://github.com/karwalski/toke/blob/main/docs/about/canonical.md).
Every number published about toke comes from
[`docs/metrics-baseline.md`](https://github.com/karwalski/toke/blob/main/docs/metrics-baseline.md)
and nowhere else.*

## Features

- **File-based routing** -- drop a `.tk` file in `pages/` and it becomes a route. `pages/blog/[slug].tk` handles `/blog/:slug` automatically.
- **Dynamic route handlers** -- define `http.get`, `http.post`, `http.put`, `http.delete`, and `http.patch` handlers with toke function pointers for full control over request/response.
- **Template engine** -- `.tkt` templates with layout inheritance, blocks, partials, and filters. No separate template language to learn.
- **Markdown CMS** -- write content in Markdown with YAML frontmatter. ooke renders it at build time or on request.
- **JSON content** -- `.json` files alongside `.md` for structured content collections.
- **Content validation** -- define TOML models in `models/` with field types and required flags. ooke validates content against them automatically.
- **Island architecture** -- interactive client-side components with `{! island("name"; hydrate="visible") !}` directives and the `ooke-islands.js` hydration loader. Scaffold new islands with `ooke gen island <name>`.
- **Static site generation** -- `ooke build` renders your entire site to static HTML in `build/`. Deploy anywhere.
- **HTTP and HTTPS serving** -- `ooke serve` serves plain HTTP, or HTTPS when `[tls]` names a certificate and key (see [TLS](#tls)).
- **Worker scaling** -- set `workers = 0` for automatic CPU-count detection, or override at runtime with `TK_HTTP_WORKERS`.
- **Custom error pages** -- drop templates into `templates/errors/` (e.g. `404.tkt`) for branded error handling.
- **Logging** -- `ooke serve` writes its startup messages as JSON lines on standard error, and one access-log line per request -- to standard error by default, or to a file (see [Log](#log)).
- **Repair command** -- `ooke repair <file>` diagnoses compiler errors and suggests fixes.
- **Lint command** -- `tkc --lint` checks toke source for issues; add `--fix` for auto-repair.
- **Single binary deployment** -- one file, no runtime, no dependencies. Copy it to a server and run it.

## Quick Start

```bash
# Create a new project
ooke new mysite
cd mysite

# Start the development server
ooke serve

# Build static output
ooke build

# Diagnose a broken file
ooke repair pages/broken.tk

# Scaffold an island component
ooke gen island counter
```

## Project Structure

```
mysite/
  ooke.toml          # site configuration
  pages/             # file-based routing (.tk files)
    index.tk         # /
    about.tk         # /about
    blog/
      [slug].tk      # /blog/:slug (dynamic route)
    api/
      status.tk      # /api/status (JSON endpoint)
  templates/         # template files (.tkt)
    base.tkt         # root layout
    partials/        # reusable fragments
    errors/          # error pages (404.tkt, 500.tkt)
  content/           # markdown and JSON content
    posts/           # content collection (.md and .json)
    pages/           # static pages
  models/            # TOML content-type definitions
    posts.toml       # field types and required flags for posts
    pages.toml       # field types and required flags for pages
  islands/           # client-side interactive components
  static/            # served at /static/*
    css/
    images/
    ooke-islands.js  # island hydration loader
  extensions/        # custom extension modules
  src/               # framework source (internal)
```

## Content Validation

Define a content model in `models/` as a TOML file. Each field declares its type and whether it is required:

```toml
# models/posts.toml
[fields.title]
type = "string"
required = true

[fields.date]
type = "date"
required = true

[fields.draft]
type = "bool"
required = false

[fields.tags]
type = "list"
required = false
```

When ooke loads content from `content/posts/`, every entry is validated against `models/posts.toml`. Missing required fields or type mismatches produce clear build-time errors.

JSON content files (`.json`) sit alongside Markdown and follow the same validation rules.

## Template Syntax

ooke templates use `{= =}` for expressions and `{! !}` for directives. Block comments use `(* ... *)`.

### Expressions

```html
<h1>{=title=}</h1>
<p>{=author|upper=}</p>
<div>{=body|md=}</div>
```

### Directives

```html
{!layout("base")!}

{!block("content")!}
  <article>{=body|md=}</article>
{!end!}

{!partial("nav")!}

{!island("counter"; hydrate="visible")!}
```

### Islands

Islands are interactive client-side components that hydrate on demand. The `hydrate` parameter controls when the component activates:

- `"visible"` -- hydrate when the element scrolls into view
- `"idle"` -- hydrate during browser idle time
- `"load"` -- hydrate immediately on page load

Scaffold a new island:

```bash
ooke gen island counter
```

This creates the component skeleton in `islands/` and wires it into the `ooke-islands.js` hydration loader served from `static/`.

### Filters

| Filter   | Effect                              |
|----------|-------------------------------------|
| `md`     | Render Markdown to HTML             |
| `escape` | HTML-escape special characters      |
| `upper`  | Uppercase                           |
| `lower`  | Lowercase                           |
| `trim`   | Strip leading/trailing whitespace   |

## Dynamic Route Handlers

For routes that need custom logic beyond templates, register handler functions directly:

```toke
http.get("/api/health"; fn(req; res) {
    res.json({"status": "ok"})
})

http.post("/api/items"; fn(req; res) {
    let body = req.body()
    (* validate and store *)
    res.status(201).json(body)
})
```

Supported verbs: `http.get`, `http.post`, `http.put`, `http.delete`, `http.patch`.

## Configuration

Site settings live in `ooke.toml`:

```toml
[site]
name = "my-site"
url = "https://example.com"
language = "en"

[build]
output = "build/"
minify = true
inlinecss = true

[server]
port = 3000
workers = 0        # 0 = auto-detect CPU count

[log]
access = "-"                # "-" = stderr, "" = off, or a file path
accessformat = "combined"   # or "json"
```

### Server

| Key       | Default | Description |
|-----------|---------|-------------|
| `port`    | `3000`  | HTTP listen port. |
| `workers` | `0`     | Worker thread count. `0` auto-detects CPU count. Override at runtime with `TK_HTTP_WORKERS` env var. |
| `corsorigins` | `""` | CORS allow-origin sent by `ooke serve`. Empty disables CORS. |

### Content store

Content is read from the filesystem: Markdown and JSON files under `content/`.
There is no other content backend and no `[store]` section — an older
`ooke.toml` that still has `[store] backend = ...` loads, and the table is
ignored (story 134.34).

### Log

| Key | Default | Description |
|-----|---------|-------------|
| `access` | `"-"` | Access log: one line per request. `"-"` is standard error, `""` is off, anything else is a file path, relative to the project. |
| `error` | `""` | Error log: the access line again for every response with status 400 or above. Same values as `access`. |
| `accessformat` | `"combined"` | `"combined"` (Apache Combined Log Format) or `"json"` (one JSON object per line). Any other value stops serve at startup. |

A log file that cannot be opened stops serve at startup. ooke does not rotate
logs. `maxlines` and `maxagedays` are no longer read, because the toke
stdlib's rotation loses lines. If they are set, serve names them in a warning
and ignores them. Rotate with an external tool that truncates in place, such
as `logrotate` with `copytruncate`. Details: [docs/logging-and-tls.md](docs/logging-and-tls.md)
(story 134.40).

### TLS

```toml
[tls]
cert = "certs/cert.pem"
key = "certs/key.pem"
```

Set both or neither. When they are set, `ooke serve` speaks HTTPS on
`[server].port`. The paths are relative to the project. If one of the pair is
missing, or a file does not exist or does not load, serve stops with an error.
Under TLS the worker count comes from `TK_HTTP_WORKERS` or the CPU count, not
from `[server].workers`: the toke stdlib's `http.servetls` takes no worker
count.

## Extension API

ooke applications extend functionality through toke modules in the `extensions/` directory. Extensions can register lifecycle hooks (`init`, `onrequest`, `onresponse`, `onshutdown`), add routes, and run middleware.

See [docs/extension-api.md](docs/extension-api.md) for the full API reference.

## Building from Source

### Prerequisites

- [toke compiler](https://github.com/karwalski/toke) (`tkc`), built from `main` —
  the newest tagged toke (3.0.0) builds ooke but fails its test suite (the
  template cache never stores). The floor is 3.0.0 plus commit
  `cee7cc0` (2026-09-27); it is declared in `ooke.toml [requires]` and enforced by
  `make check-versions`, which `make` runs first. See
  [`docs/versioning.md`](docs/versioning.md) for the evidence and for what a
  downstream project should wait for.
- C compiler (clang)
- OpenSSL development headers

### Build

```bash
make
```

This compiles all toke source to LLVM IR, links with the toke stdlib, and produces the `ooke-toke` binary.

## Related Projects

- [toke](https://github.com/karwalski/toke) -- the toke programming language
- [toke-web](https://github.com/karwalski/toke-web) -- tokelang.dev, built with ooke

## Licence

[MIT](LICENSE)
