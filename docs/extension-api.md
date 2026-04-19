# ooke Extension API

## Overview

ooke is a toke-native CMS and web framework. Applications extend ooke through filesystem conventions and toke module imports. There is no plugin registry — extensions are toke modules compiled into the binary.

## Project Structure

```
myapp/
  ooke.toml          # configuration
  pages/             # file-based routing
    index.tk         # → /
    about.tk         # → /about
    blog/
      [slug].tk      # → /blog/:slug (dynamic)
    api/
      status.tk      # → /api/status (API route)
  templates/         # template files (.tkt)
    base.tkt         # layout template
    partials/        # reusable fragments
  content/           # markdown content with frontmatter
    blog/            # content type = directory name
      hello.md       # slug = filename
  static/            # served at /static/*
  models/            # data types
  islands/           # client-side interactive components
  extensions/        # custom extension modules
```

## Extension Module Interface

### Registration

Extensions are toke modules that export an `init` function. ooke discovers them by scanning the `extensions/` directory at build time.

```toke
m=extensions.analytics;
i=http:std.http;
i=log:std.log;

(* Called once during server startup *)
f=init(cfg:$ookecfg):void{
  (log.info("analytics extension loaded";@()))
};

(* Called on each request — middleware hook *)
f=onrequest(req:$http.req):$http.req{
  (log.info(str.concat("track: ";req.path);@()));
  <req
};

(* Called during graceful shutdown *)
f=onshutdown():void{
  (log.info("analytics: flushing";@()))
};
```

### Lifecycle Hooks

| Hook | Signature | When |
|------|-----------|------|
| `init` | `(cfg:$ookecfg):void` | Server startup, after config load |
| `onrequest` | `(req:$http.req):$http.req` | Before route handler, per request |
| `onresponse` | `(req:$http.req;res:$http.res):$http.res` | After route handler, before send |
| `onshutdown` | `():void` | Graceful shutdown |

All hooks are optional. If a module does not export a hook, it is skipped.

### Custom Route Registration

Extensions can register additional routes in their `init` function:

```toke
f=init(cfg:$ookecfg):void{
  (http.get("/api/metrics";fn(req:$http.req):$http.res=
    http.res.json(200;"{\"requests\":42}")
  ));
  (http.post("/api/webhook";fn(req:$http.req):$http.res=
    http.res.ok("received")
  ))
};
```

### Middleware Chains

Middleware functions transform requests or responses. They are registered via `onrequest` and `onresponse` hooks. Multiple extensions run in filesystem-sorted order.

```toke
(* extensions/auth.tk — runs before extensions/logging.tk *)
f=onrequest(req:$http.req):$http.req{
  let token=http.header(req;"authorization")|{$ok:v v;$err:e ""};
  if(str.len(token)=0){
    <req  (* let route handler decide *)
  }el{
    <req  (* token validated, pass through *)
  }
};
```

## API Route Framework

Routes in `pages/api/` are treated as JSON API endpoints. They receive the raw request and return a response — no template rendering.

### Convention

```toke
(* pages/api/items.tk *)
m=pages.api.items;
i=http:std.http;
i=json:std.json;

f=get(req:$http.req):$http.res{
  <http.res.json(200;"{\"items\":[]}")
};

f=post(req:$http.req):$http.res{
  let body=req.body;
  <http.res.json(201;body)
};
```

API routes export functions named after HTTP verbs: `get`, `post`, `put`, `delete`, `patch`. ooke auto-registers each as a handler for the corresponding method at the derived URL pattern.

### Route Groups

Group related endpoints under a directory:

```
pages/api/
  users.tk          → GET/POST /api/users
  users/
    [id].tk         → GET/PUT/DELETE /api/users/:id
    [id]/
      posts.tk      → GET /api/users/:id/posts
```

### Authentication Hooks

API routes can be protected by middleware. The `onrequest` hook in an auth extension checks tokens before the route handler runs:

```toke
(* extensions/jwt_auth.tk *)
f=onrequest(req:$http.req):$http.req{
  let isapi=str.starts(req.path;"/api/");
  if(!isapi){ <req }el{
    let auth=http.header(req;"authorization")|{$ok:v v;$err:e ""};
    if(str.starts(auth;"Bearer ")){
      <req  (* valid — pass through *)
    }el{
      <req  (* invalid — handler checks req.headers for auth status *)
    }
  }
};
```

## Theming and Branding

### Template Inheritance

Templates use `{!layout("name")!}` to declare a parent layout and `{!block("name")!}...{!end!}` to define overridable sections:

```html
(* templates/base.tkt — root layout *)
<!DOCTYPE html>
<html lang="{=site.language=}">
<head>
  <title>{!block("title")!}{=site.name=}{!end!}</title>
  <style>{!block("styles")!}{!end!}</style>
</head>
<body>
  {!block("content")!}{!end!}
</body>
</html>
```

```html
(* templates/blog.tkt — extends base *)
{!layout("base")!}
{!block("title")!}{=title=} | {=site.name=}{!end!}
{!block("content")!}
<article>{=body|md=}</article>
{!end!}
```

### CSS Variable Theming

Define theme variables in a CSS partial:

```html
(* templates/partials/theme.tkt *)
<style>
:root {
  --color-primary: {=theme.primary|escape=};
  --color-bg: {=theme.bg|escape=};
  --font-body: {=theme.font|escape=};
}
</style>
```

Set values in `ooke.toml`:

```toml
[theme]
primary = "#2563eb"
bg = "#ffffff"
font = "Inter, system-ui, sans-serif"
```

### Custom Partials

Place reusable fragments in `templates/partials/`. Include them with `{!partial("name")!}`:

```html
{!partial("header")!}
<main>{!block("content")!}{!end!}</main>
{!partial("footer")!}
```

### Filters

| Filter | Effect |
|--------|--------|
| `md` | Render markdown to HTML |
| `escape` | HTML-escape special characters |
| `upper` | Uppercase |
| `lower` | Lowercase |
| `trim` | Strip leading/trailing whitespace |

## Database Integration

ooke applications access databases through `std.db` in route handlers:

```toke
(* pages/api/items.tk *)
i=db:std.db;

f=get(req:$http.req):$http.res{
  let conn=db.open("sqlite:data.db")|{$ok:c c;$err:e <http.res.err("db error")};
  let rows=db.query(conn;"SELECT id, name FROM items";@())|{$ok:r r;$err:e <http.res.err("query error")};
  <http.res.json(200;db.tojson(rows))
};
```

Backend selection is via connection string prefix: `sqlite:`, `postgres://`, `mysql://`. See Epic 57.10 for multi-backend details.

### Migrations

Place SQL migration files in `migrations/`:

```
migrations/
  001_create_items.sql
  002_add_status.sql
```

Run with: `ooke migrate` (planned CLI extension).

## LLM Integration

Server-side LLM calls from ooke handlers via `std.llm` or HTTP API:

```toke
(* extensions/ai_summary.tk *)
i=http:std.http;
i=json:std.json;

f=summarize(text:$str):$str!$httperr{
  let body=json.enc(@("model":"claude-sonnet-4-5-20250514";"prompt":text));
  let resp=http.post("https://api.anthropic.com/v1/messages";body);
  <resp
};
```

### Prompt Templates

Store prompts in `content/prompts/` as markdown files with frontmatter:

```markdown
---
model: claude-sonnet-4-5-20250514
max_tokens: 1024
---
Summarize the following text in 3 bullet points:

{{input}}
```

Load and render with the template engine, then send via HTTP.

## Building an ooke Application (loke example)

loke is an ooke-based application. Its structure demonstrates all extension points:

```
loke/
  ooke.toml
  pages/
    index.tk              # landing page
    docs/[slug].tk        # documentation (dynamic)
    api/
      search.tk           # search API endpoint
  templates/
    base.tkt              # root layout
    docs.tkt              # docs layout (extends base)
    partials/
      nav.tkt             # navigation partial
      footer.tkt          # footer partial
  content/
    docs/                 # documentation markdown
  extensions/
    search_index.tk       # builds search index on init
  static/
    css/theme.css
  models/
    doc.tk                # document type definition
```

### Build and Deploy

```bash
# Development
ooke serve

# Production build
ooke build
# Deploy build/ directory to any static host

# Or run as server for dynamic features
./ooke-app serve --port 8080
```
