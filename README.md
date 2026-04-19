# ooke

ooke is a web framework for building websites and web applications using the [toke](https://github.com/karwalski/toke) programming language. It compiles your entire site -- pages, templates, and server -- into a single binary file that runs anywhere without installing extra software.

**toke on ooke** -- build light, ship fast.

## Features

- **File-based routing** -- drop a `.tk` file in `pages/` and it becomes a route. `pages/blog/[slug].tk` handles `/blog/:slug` automatically.
- **Template engine** -- `.tkt` templates with layout inheritance, blocks, partials, and filters. No separate template language to learn.
- **Markdown CMS** -- write content in Markdown with YAML frontmatter. ooke renders it at build time or on request.
- **Static site generation** -- `ooke build` renders your entire site to static HTML in `build/`. Deploy anywhere.
- **TLS/HTTPS** -- built-in TLS support for production serving. No reverse proxy required.
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
    errors/          # error pages (404, 500)
  content/           # markdown content with frontmatter
    posts/           # content collection
    pages/           # static pages
  static/            # served at /static/*
    css/
    images/
  extensions/        # custom extension modules
  models/            # data type definitions
  islands/           # client-side interactive components
  src/               # framework source (internal)
```

## Template Syntax

ooke templates use `{= =}` for expressions and `{! !}` for directives.

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
```

### Filters

| Filter   | Effect                              |
|----------|-------------------------------------|
| `md`     | Render Markdown to HTML             |
| `escape` | HTML-escape special characters      |
| `upper`  | Uppercase                           |
| `lower`  | Lowercase                           |
| `trim`   | Strip leading/trailing whitespace   |

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
inline_css = true

[server]
port = 3000
```

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
