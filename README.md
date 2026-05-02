# ooke

ooke is a web framework for building websites and web applications using the [toke](https://github.com/karwalski/toke) programming language. It compiles your entire site -- pages, templates, and server -- into a single binary file that runs anywhere without installing extra software.

**toke on ooke** -- build light, ship fast.

## Features

- **File-based routing** -- drop a `.tk` file in `pages/` and it becomes a route. `pages/blog/[slug].tk` handles `/blog/:slug` automatically.
- **Dynamic route handlers** -- define `http.get`, `http.post`, `http.put`, `http.delete`, and `http.patch` handlers with toke function pointers for full control over request/response.
- **Template engine** -- `.tkt` templates with layout inheritance, blocks, partials, and filters. No separate template language to learn.
- **Markdown CMS** -- write content in Markdown with YAML frontmatter. ooke renders it at build time or on request.
- **JSON content** -- `.json` files alongside `.md` for structured content collections.
- **Content validation** -- define TOML models in `models/` with field types and required flags. ooke validates content against them automatically.
- **Island architecture** -- interactive client-side components with `{! island("name"; hydrate="visible") !}` directives and the `ooke-islands.js` hydration loader. Scaffold new islands with `ooke gen island <name>`.
- **SQLite store** -- optional SQLite backend for content storage with automatic migration from the default flat-file store.
- **Static site generation** -- `ooke build` renders your entire site to static HTML in `build/`. Deploy anywhere.
- **TLS/HTTPS** -- built-in TLS support for production serving. No reverse proxy required.
- **Worker scaling** -- set `workers = 0` for automatic CPU-count detection, or override at runtime with `TK_HTTP_WORKERS`.
- **Custom error pages** -- drop templates into `templates/errors/` (e.g. `404.tkt`) for branded error handling.
- **Error log** -- separate `error.log` with rotation and gzip compression for 4xx/5xx responses.
- **JSON access log** -- switch to NDJSON access logging with `log.accessformat("json")` for machine-readable output.
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
imageoptimize = true

[server]
port = 3000
workers = 0        # 0 = auto-detect CPU count
admin = true       # enable admin routes

[store]
backend = "flat"   # "flat" (default) or "sqlite"

[log]
accessformat = "combined"   # "combined" (default) or "json" (NDJSON)
```

### Server

| Key       | Default | Description |
|-----------|---------|-------------|
| `port`    | `3000`  | HTTP listen port. Also configurable with `env.getint("PORT")` in toke. |
| `workers` | `0`     | Worker thread count. `0` auto-detects CPU count. Override at runtime with `TK_HTTP_WORKERS` env var. |
| `admin`   | `false` | Enable the admin interface. |

### Store

| Key       | Default  | Description |
|-----------|----------|-------------|
| `backend` | `"flat"` | Content storage backend. `"flat"` uses the filesystem. `"sqlite"` uses an embedded SQLite database with automatic migration from flat files. |

### Log

| Key              | Default      | Description |
|------------------|--------------|-------------|
| `accessformat`   | `"combined"` | Access log format. `"combined"` for Apache-style lines. `"json"` for NDJSON (one JSON object per request). |

Errors (4xx and 5xx responses) are also written to a separate `error.log` with automatic rotation and gzip compression.

## Extension API

ooke applications extend functionality through toke modules in the `extensions/` directory. Extensions can register lifecycle hooks (`init`, `onrequest`, `onresponse`, `onshutdown`), add routes, and run middleware.

See [docs/extension-api.md](docs/extension-api.md) for the full API reference.

## Building from Source

### Prerequisites

- [toke compiler](https://github.com/karwalski/toke) (`tkc`)
- C compiler (clang)
- OpenSSL development headers

### Build

```bash
make
```

This compiles all toke source to LLVM IR, links with the toke stdlib, and produces the `ooke-toke` binary.

## Related Projects

- [toke](https://github.com/karwalski/toke) -- the toke programming language
- [toke-website](https://github.com/karwalski/toke-website) -- tokelang.dev, built with ooke

## Licence

[MIT](LICENSE)
