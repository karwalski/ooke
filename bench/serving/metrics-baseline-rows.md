# Proposed rows for `toke/docs/metrics-baseline.md` (story 134.6)

**Not applied.** `metrics-baseline.md` lives in the toke repo and other agents are
editing it. This is the exact text to paste, for the owner or whoever holds that
file. Insert as a new dated section after `## 2026-09-18 — v0.4 tokenizer
baseline`, and make the two edits in §2 and §3 below.

---

## 1. New section — paste verbatim

```markdown
## 2026-09-19 — web-serving baseline (story 134.6, PRE-uplift)

**What this is.** The first measurement of toke's HTTP stack serving a real
site. It exists to source or withdraw the two latency claims 132.22 flagged.
Harness, method and every caveat: `toke-ooke/bench/serving/README.md`; data:
`toke-ooke/bench/serving/results/2026-09-19.json`; narrative:
`toke-ooke/bench/serving/RESULTS.md`. Reproduce with
`python3 toke-ooke/bench/serving/run_serving.py --allow-load --site-snapshot <dir>`.

**Read these four caveats before citing any row.**

1. **Loopback, not the internet.** Every latency here is server-side on
   `127.0.0.1`: no DNS, no TLS handshake, no network RTT, no CDN — the terms
   that dominate a real visitor's TTFB. These numbers bound *service time*, and
   a user-observed TTFB is **not** measured and not measurable this way.
2. **Loaded machine.** `Mac14,10`, 12 CPUs, 16 GB, macOS 26.5.1. A background
   process permanently pins a core, so the 1-minute load average floor is ~5;
   it was 5.4–7.1 during the measured phases and `load_warning: true` is stamped
   on every row. Latencies are an upper bound and throughput a lower bound
   relative to an idle machine. Not the production Lightsail host.
3. **`ooke` is not the row that served the site.** The site is served by the
   `website` binary (`toke-website`, built on `std.http` directly). `ooke-toke
   serve` **could not serve the toke website at all** — it hung after route
   registration and needed `SIGKILL` (same area as the 132.20 / 134.8 RT005
   blocker). The `ooke` rows are its own 3-page `testproj` scaffold, whose pages
   are rendered once at startup and served from memory.
4. **Comparison scope.** The reference is `caddy file-server` v2.11.3 over the
   same `build/` directory, the same bytes, the same machine, the same session
   and the same client. It proves whether toke's server is in the same class as
   a mainstream production static file server for a plain file over loopback.
   It proves nothing about template rendering (caddy cannot render a `.tkt`),
   real networks, TLS, HTTP/2, compression, production hardware, or sustained
   traffic — the longest load window here is 3 s.

### Latency and throughput

| Metric | `website` (real site) | `ooke` (testproj) | caddy (reference) | Basis |
|---|---:|---:|---:|---|
| Cold start, launch → first byte of first 200 | **16.64 ms** [16.00, 18.52] | **11.87 ms** [11.60, 12.19] | 54.23 ms [52.50, 56.78] | median of n=20 fresh processes, bootstrap CI95 |
| TTFB, static file, 63,058 B | **0.194 ms** median / 0.301 p95 | — | 0.497 median / 0.906 p95 | n=150 fresh connections, connect included |
| TTFB, page rendered per request, 63,058 B | **0.422 ms** median / 0.581 p95 | — | n/a (cannot render) | n=150 fresh connections |
| TTFB, API route (in-memory JSON, 58 B) | **0.142 ms** median / 0.174 p95 | 0.155 / 0.208 | n/a | n=150 fresh connections |
| TTFB, service time on a reused connection | 0.027–0.311 ms median | 0.027–0.029 ms | 0.215–0.246 ms | n=1,000 per route |
| Throughput, static 63 KB file | **3,294 rps** @ c=8 | — | 7,139 rps @ c=8 | keep-alive, 3 s/level, server restarted per level |
| Throughput, API route | **31,863 rps** @ c=64 | 26,689 @ c=2 | n/a | as above |
| Latency stability, static 63 KB, c=1→128 | p50 **0.185–0.227 ms** (flat) | — | p50 0.250 → **34.6 ms** (p95 193 ms) | same sweep |
| Resident memory, idle | **10.3 MB** (3 procs; parent 6.4 MB) | **3.8 MB** (5 procs; parent 1.5 MB) | 41.9 MB (1 proc) | sum of `ps` RSS over the process group, 1 s after first 200 |
| Resident memory after 20,000 requests, 58 B constant response, one connection | 10.3 → **36.0 MB** | 7.7 → **37.4 MB** | 42.0 → **48.9 MB** | single keep-alive connection |
| Resident memory, peak across the c=1→128 sweep | **718 MB** | 106 MB | 64 MB | max of 100 ms RSS samples |
| Binary size | **929,624 B** | **879,928 B** | 46,162,978 B | `stat`, sha256 in the results file |
| Clean build, `make clean && make` | **10.83 s** | **9.93 s** | — | n=1, throwaway copy, pinned tkc 2.8.0, machine at load ~15 |

### Findings the baseline hands to other stories

- **Memory grows with requests served.** RSS climbs monotonically — about
  **1.3 KB per request** (`website`) and **1.5 KB per request** (`ooke`) — even
  when the response is a 58-byte constant string held in memory. caddy over the
  same 20,000 requests moves 42.0 → 48.9 MB and stops. On larger responses the
  figure rises and falls (allocator churn, peaking at 668 MB), so only the
  constant-response routes are evidence of growth rather than high-water. For
  **134.2 / 134.4**.
- **~1 MB is allocated and zeroed per request.** `http.c:731-740` mallocs
  `max_header + max_body + 8` = 1,056,776 B per connection
  (`HTTP_DEFAULT_MAX_BODY_SIZE` 1 MiB, `http.h:167-169`) and `memset`s the whole
  buffer on **every** request in the keep-alive loop — consistent with the
  measured 27 µs floor on reused-connection service time. For **134.4**.
- **A hard-coded per-IP connection limiter.** `http.c:664-701`: 200 connections
  per 60 s per source IP, applied per TCP connection, keyed on the socket peer
  with no `X-Forwarded-For`, one table per forked worker. Measured: 396 fresh
  connections in 0.057 s, then HTTP 429, full recovery after 62 s. Behind a CDN
  every connection arrives from a small set of edge addresses. For **134.2 /
  134.8**.
- **Neither toke server exits on `SIGTERM`** — `SIGKILL` was required in every
  trial. caddy exits cleanly. For **134.2**.
- **Rendering costs 2.2×.** `/` and `/index.html` are the same 63,058 bytes;
  rendering the `.tkt` per request costs 0.23 ms more than reading the finished
  file (0.422 vs 0.194 ms median). For **134.4**.
- **No real-site ooke number exists.** Blocked on **134.8**.
```

---

## 2. Edit to the existing `### Claims deleted rather than corrected (132.14)`

Append this sentence to that section:

```markdown
Added 2026-09-19 (134.6): loke's **"a lightweight local classifier analyses each
prompt in under 10ms"** (`toke-website/templates/loke.tkt:119`). It is a claim
about loke's prompt intent classifier, not about web serving; loke is not in
this workspace, no artefact in any repo measures classifier latency, and the
134.6 serving benchmark cannot source it. Deleted on the same grounds as loke's
"698 `.tk` files / 87,318 lines".
```

---

## 3. Edit to `## What is NOT yet measured (gaps that block honest claims)`

Add these three bullets:

```markdown
- **User-observed TTFB.** 134.6 measures server-side service time on loopback.
  Nothing measures a real visitor's time to first byte through DNS, TLS, the
  network and the CDN, and no published page may state one until something does.
- **ooke serving a real-sized site.** `ooke-toke serve` cannot serve the toke
  website (134.6 §7); every ooke serving number is from a 3-page scaffold.
  Blocked on 134.8.
- **Sustained-load behaviour.** The longest load window in 134.6 is 3 s, and RSS
  is still climbing at 20,000 requests. Nothing measures an hour, a day, or
  production hardware.
```

---

## 4. The `<5ms TTFB` stat tile on `/ooke`

Not a `metrics-baseline.md` edit — a site edit for **134.8 / 134.9**, recorded
here so the decision is not lost.

`toke-website/templates/ooke.tkt:16` publishes
`<div class="stat"><div class="num">&lt;5ms</div><div class="lbl">TTFB</div></div>`.

The number clears with a wide margin as *server-side loopback* TTFB — over 1,050
fresh-connection samples across 7 routes on the two toke servers the worst median
is 0.422 ms, the worst p95 0.583 ms and the worst single sample 3.568 ms — but
the claim as published is not supportable: it is attributed to ooke (which cannot
serve the site), it reads as user-observed (which is not measured), and it carries
no method, machine or sample size.

**Recommended: remove the tile.** If a latency stat is wanted on that page, it
must be qualified and must come from ooke itself once 134.8 lands, e.g.

> 0.42 ms median server-side TTFB rendering a 63 KB page per request
> (loopback, `Mac14,10`, n=150, 2026-09-19 — see `docs/metrics-baseline.md`)

A bare `<5ms` beside "0 runtime deps" and "1 binary" is exactly the shape of
claim Epic 132 was created to stop.
