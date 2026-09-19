# ooke web-serving benchmark — method

Story **134.6**, baseline half. This directory measures what ooke and the toke
HTTP stack do **today, before the Epic 134 uplift**, so the epic has a "before"
number and so the two published latency claims on the website
(`<5ms TTFB` on `/ooke`, `under 10ms` on `/loke`) can be sourced or withdrawn.

Nothing here modifies ooke, the website, or `toke/docs/`. Every measurement runs
against a **pinned copy** of a binary in a **throwaway copy** of the tree.

- Harness: `run_serving.py`
- Data: `results/<YYYY-MM-DD>.json`
- Reproduce: `python3 run_serving.py --allow-load` (see *Load caveat* below)

---

## 1. Why the method looks the way it does

It is a deliberate mirror of toke's `bench/patterns/run_patterns.py` (story
131.5) rather than a new invention, so results from the two harnesses are read
the same way:

| run_patterns.py (131.5 / 131.39) | run_serving.py (134.6) |
|---|---|
| copies `tkc` to a private temp dir and sha256s it before the first compile, so a concurrent `make` cannot change the compiler mid-run | copies **every measured binary** (`website`, `ooke-toke`, `caddy`) to a private temp dir and sha256s it, for the same reason — two other agents are on `toke-ooke`'s build path while this runs |
| median, never mean; percentile bootstrap 95 % CI of the median, 1000 resamples, fixed seed | identical routine, seed 1346 |
| peak RSS from `os.wait4` rusage (`ru_maxrss`), because `/usr/bin/time -lp` is too coarse | same, **plus** `ps` RSS sampling of the whole process group, because the toke HTTP server forks workers whose rusage is reported to *their* parent, not to us |
| stamps `sysctl -n hw.model`, cpu count, OS, `pmset -g therm`, 1-min load average | identical |
| `--max-load` (default 2.0) refuses to run on a busy machine; `--allow-load` runs anyway and stamps `load_warning: true` | identical |

## 2. Load caveat — read before citing any number

A background process permanently pins a core on this machine, so a 1-minute load
average below 2 is **unreachable**; several agents also build concurrently. Every
run therefore uses `--allow-load` and every results file carries
`"load_warning": true` together with the load average at the moment of the run.

Read the numbers accordingly: **latency medians and p95s are an upper bound**
and **throughput is a lower bound** relative to an idle machine. The reference
server (§5) was measured in the same session under the same load, so the
*comparison* between servers is not affected the way the absolute values are.

## 3. What is measured, and exactly how

**Cold start** — wall from the instant just before `fork`/`exec` to the first
byte of the first HTTP 200. The client busy-polls `connect()` with a 0.2 ms
back-off rather than sleeping on a fixed interval, so the granularity is the
poll, not a timer. 20 trials, each a fresh process on a fresh port; the server
is killed and reaped between trials. The **first trial is always an outlier**
(cold page cache for a ~900 KB binary plus its content tree) and is visible in
the `max` field — the median is the number to cite.

**Time to first byte** — two different things, both reported, never conflated:

- `ttfb_fresh_conn_ms`: `connect()` through to the first response byte, a **new
  TCP connection per sample**. Connection setup is included. This is what a
  browser sees on a cold link, and it is the honest basis for a public "TTFB"
  claim.
- `ttfb_reused_conn_ms`: `send()` through to the first response byte on an
  already-open keep-alive connection — the server's own service time, with no
  connect cost.

150 fresh samples and 1000 reused samples per route, after 30 keep-alive
warm-ups. Median, bootstrap CI, p95, p99, min, max, mean and stdev are all
recorded. Every response's status code is counted and reported; a route whose
`fresh_status_counts` is not `{"200": n}` must not be read as a latency result.

**Routes.** Three classes, chosen because they exercise different code paths:

| class | website binary | what it actually does |
|---|---|---|
| `static` | `/index.html` (63,058 B) | `http.servedir` — read from `build/` off disk per request |
| `templated` | `/` (63,058 B) | `http.servepages` — **re-reads and re-renders the `.tkt` from disk on every request** (`tk_web_glue.c:790`) |
| `templated_small` | `/ooke` (10,909 B) | same, smaller page |
| `api` | `/api/health` (58 B) | `http.getstaticmime` — a constant JSON string held in memory |
| `static_small` | `/robots.txt` (66 B) | `http.servedir`, small file — isolates per-request cost from transfer cost |

`/` and `/index.html` are byte-identical in size, which makes them a clean
render-vs-read pair on the same server in the same run.

**Throughput** — a concurrency sweep (1, 2, 4, 8, 16, 32, 64, 128) with
keep-alive, one connection per client thread, 3 s per level, **the server
restarted before every level** so each level starts from a cold process with an
empty rate-limit table. Each row records `connections_opened` and a histogram of
response statuses; the "knee" is computed only over levels that were not rate
limited. Client control: at c=1 the measured requests/second equals
1/mean-latency to three digits, so the Python client adds no measurable
per-request overhead there; above ~8 threads the GIL is a plausible ceiling, and
the caddy rows are the control — wherever caddy goes higher on the same route,
the client was not the limit.

**Memory** — RSS at idle is the sum over the server's whole process group
(`ps -o rss= -g <pgid>`), sampled 1 s after the first 200 and before any load;
under load it is the same sum sampled every 100 ms throughout each level. The
sum double-counts copy-on-write pages shared with forked workers, so the
**per-pid breakdown is kept alongside it** and the parent's own RSS is the
conservative figure. `ru_maxrss` from `os.wait4` is recorded for the parent.

**Binary size** — `stat` on the pinned copy, with its sha256.

**Build time** — one `make clean && make` in a throwaway `rsync` copy of the
repo, so no agent's working tree is touched, with `TKC=` pointed at the pinned
compiler. **n=1, on a loaded machine**: an order of magnitude, not a gate.

## 4. The rate limiter — a measurement constraint *and* a product finding

`toke/src/stdlib/http.c:664-701` defines, hard-coded and not configurable:

```c
#define RATE_LIMIT_WINDOW  60     /* seconds */
#define RATE_LIMIT_MAX     200    /* requests per window per IP */
```

`rate_check()` is called from `handle_connection()`, so the limit is **200 TCP
connections per 60 s per source IP**, not 200 requests — a keep-alive connection
serving 1000 requests (`KEEPALIVE_MAX_REQUESTS`, http.c:561) costs one slot. The
key is the socket peer address from `fd_peer_ip()`; `X-Forwarded-For` is not
consulted. Each forked worker holds its own `g_rate_table`, so a 2-worker server
tolerates roughly 400 connections from one IP before the first rejection.

Consequences for this harness, all of them handled rather than worked around:

- the first attempt at this benchmark silently degraded to **429 Too Many
  Requests** partway through a 400-sample fresh-connection batch and then to
  connection resets; the numbers it produced were meaningless. Fresh-connection
  batches are now capped at 150 and the server is restarted per route, and every
  status code is counted so this cannot recur unnoticed;
- the concurrency sweep restarts the server per level for the same reason, and
  any level that sees a 429 is flagged `rate_limited: true` and excluded from the
  knee;
- `probe_rate_limit()` measures the limit directly — how many fresh connections
  are served before the first non-200, and whether the server recovers after the
  60 s window — and the result is recorded as a characteristic of the server.

It is also worth saying plainly, because it affects production and not just this
benchmark: a connection-counting, per-peer-IP limiter that ignores
`X-Forwarded-For` behaves differently behind a CDN, where every connection
arrives from a small set of edge addresses.

## 5. The comparison, and what it does and does not prove

The reference is **`caddy file-server`** (Go, v2.11.3) serving the **same
`build/` directory**, the **same bytes**, on the **same machine**, in the **same
session**, measured by the **same client and the same code path**.

What that comparison **does** prove: whether toke's HTTP server is in the same
performance class as a mainstream production static file server for a plain file
over loopback, on cold start, on TTFB and on requests/second.

What it **does not** prove, and must not be quoted as proving:

- nothing about template rendering — caddy cannot render a `.tkt`, so only the
  `static` route is a like-for-like comparison;
- nothing about a real network — loopback has no RTT, no packet loss, no TLS
  handshake, no CDN, and no client-side DNS; sub-millisecond loopback TTFB tells
  you about server-side service time, and a real visitor's TTFB is dominated by
  terms this benchmark deliberately excludes;
- nothing about HTTPS, HTTP/2, compression (caddy runs with `--no-compress` to
  match) or vhost routing;
- nothing about production hardware — this is an M4 Max laptop-class machine
  under load, not the Lightsail instance the site runs on;
- nothing about sustained real traffic — the longest load window here is 3 s.

A single static file server on loopback is the *simplest honest* comparison
available, not a complete one. It was chosen for exactly that reason.

## 6. Coverage gap: ooke cannot serve the real site

`ooke-toke serve` was run against a copy of `toke-website` (which has an
`ooke.toml`, `pages/`, `templates/` and `content/`). It **registered routes and
then stopped**: the log ends mid-way through the dynamic `/docs/learn/*` group,
the process sat at 0 % CPU with ~1.5 MB RSS, never reached
`starting listen`, never accepted a connection, and did not die on `SIGTERM` —
`SIGKILL` was required. This is the same area as the 132.20 / 134.8 `ooke build`
RT005 blocker and is that story's to diagnose; it is recorded here because it
sets the coverage of these numbers.

So the results have two ooke-family rows, and they are **not interchangeable**:

- **`website`** — the `website` binary from `toke-website`, which is what
  actually serves tokelang.dev. It is built on toke's `std.http` (the same C
  server `ooke/src/serve.tk` calls) but **not** on the ooke framework. Real
  content, real page sizes, per-request template rendering.
- **`ooke`** — `ooke-toke serve` on ooke's own `testproj` scaffold. This is the
  ooke framework itself, but on a 3-page toy site. Note that ooke renders each
  page **once at startup** (`serveregisterstatic` → `http.getstatic`) and serves
  the rendered HTML from memory, so its page route is an in-memory static
  response, **not** a per-request render. Its numbers must not be compared
  head-to-head with the website binary's `templated` route.

Until 134.8 lands, there is no measurement of the ooke framework serving a
real-sized site. Any claim that needs one is unsourced.

## 7. Things that made the measurement unreliable, and what was done

Recorded because a benchmark that hides its own failures is worth less than none.

1. **The content moved under the harness.** A concurrent agent (134.8) rebuilt
   `toke-website/build/` while a run was in flight. `build/index.html` ceased to
   exist and 150 TTFB samples were collected against `404`s before anyone
   noticed. Fixes: (a) `--site-snapshot DIR` stages from a pinned copy of the
   site rather than the live tree, and the `website` binary is then pinned from
   that same snapshot so binary and content are one instant of the tree; (b) a
   `precondition` phase serves every route once and records its status, size and
   **body sha256** before any timing happens, and the server is skipped entirely
   if any route is not a non-empty 200; (c) every TTFB and throughput row now
   carries its own status histogram.

2. **The rate limiter silently truncated a run.** See §4. Now probed, bounded
   and flagged.

3. **The machine storms.** Beyond the permanently pinned core, this machine runs
   an endpoint-security scanner, an asset daemon and a management agent that
   together drove the 1-minute load average from ~5 to **80** during this work;
   at load 80 the same server measured 2 requests/second on a route that does
   ~2,500. Every phase therefore stamps its own `loadavg_1min` — a row's load is
   part of the row, not a footnote — and the run was taken when the storm had
   passed. Compare rows at similar load, or not at all.

4. **`ooke serve` had to be `SIGKILL`ed.** It ignored `SIGTERM` in the hung
   state described in §6. The harness escalates to `SIGKILL` after 3 s and
   records `needed_sigkill` so this is visible in the data.

5. **n=1 for build time**, on a shared machine. It is an order of magnitude.

## 8. Files

```
run_serving.py             the harness
results/<date>.json        one run; the meta block carries machine, load, pins,
                           the site content pin and the method
RESULTS.md                 the numbers from the 2026-09-19 run, with their caveats
metrics-baseline-rows.md   the exact rows proposed for toke/docs/metrics-baseline.md
                           (not applied — that file belongs to the toke repo)
```

### On the harness being Python

`AGENTS.md` §2 requires that **ooke** contain zero non-toke code. That rule is
about ooke's product source — the framework compiled into the binary — not about
repo tooling: `scripts/` already carries four shell scripts, and toke's own
measurement harnesses (`bench/patterns/run_patterns.py`, `scripts/patterns/*.py`)
are Python by the same reasoning. `bench/serving/` measures the binary from
outside and links nothing into it. If ooke later grows a toke-native HTTP load
client, this harness is the specification of what it must reproduce.
