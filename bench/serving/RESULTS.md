# ooke web-serving baseline — 2026-09-19

Story **134.6**, baseline half: what the stack does **before** the Epic 134 uplift.
Method, definitions and every caveat are in `README.md`; the data is
`results/2026-09-19.json`. Read the method before citing a number.

## Conditions (they are part of every row)

| | |
|---|---|
| Machine | `Mac14,10`, 12 CPUs, 16 GB, macOS 26.5.1 (Darwin 25.5.0) |
| Load average, 1 min | **8.92** at run start, **5.4–7.1** during the measured phases, 14.1 during the builds — `load_warning: true` on every row |
| Compiler | toke **2.8.0**, pinned binary `6dc20edee16f…`, toke HEAD `c84eab0e4063` (`src` dirty) |
| Site content | pinned snapshot, **182 files / 18,961,419 bytes**, every route's body sha256 recorded before timing |
| `website` binary | 929,624 B, sha `490efa472d1b…`, built 2026-09-19 03:20 UTC |
| `ooke-toke` binary | 879,928 B, sha `c74d38121b61…`, built 2026-09-19 05:16 UTC |
| `caddy` (reference) | v2.11.3, 46,162,978 B |

**The machine was never quiet.** A pinned core plus concurrent agents put the
floor at ~5; a security-scanner storm took it to 80 mid-session and those runs
were discarded. Latencies below are an **upper bound**, throughput a **lower
bound**, relative to an idle machine.

**Three servers, and they are not interchangeable** (README §6): `website` is
the binary that actually serves tokelang.dev, built on toke's `std.http` but not
on the ooke framework; `ooke` is `ooke-toke serve` on ooke's own 3-page
`testproj` scaffold, because **it could not serve the real site at all**;
`caddy` is the reference.

---

## 1. Cold start — process launch to first byte of the first 200

n = 20 fresh processes each, median [bootstrap CI95].

| Server | Median | CI95 | p95 | Min | Max |
|---|---:|---|---:|---:|---:|
| `ooke-toke serve` (testproj) | **11.87 ms** | [11.60, 12.19] | 15.89 | 10.92 | 19.24 |
| `website` (real site, 182 files) | **16.64 ms** | [16.00, 18.52] | 22.10 | 14.29 | 23.84 |
| caddy file-server | 54.23 ms | [52.50, 56.78] | 67.37 | 48.38 | 68.93 |

The toke binaries reach first byte **3.3–4.6× faster than caddy**, and the
website binary does it while scanning a 182-file content tree and registering
every page route. This is the cleanest win in the whole set.

## 2. Time to first byte

n = 150 fresh connections and 1,000 reused per route, all 200s, after 30
keep-alive warm-ups. "fresh" includes `connect()`; "reused" is service time on
an open connection.

### `website` — the real site

| Route | Class | Body | Fresh median [CI95] | Fresh p95 | Fresh p99 | Fresh max | Reused median | Reused p95 |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `/api/health` | in-memory JSON | 58 B | **0.142** [0.140, 0.144] | 0.174 | 0.247 | 0.374 | 0.027 | 0.041 |
| `/index.html` | file off disk | 63,058 B | **0.194** [0.177, 0.211] | 0.301 | 0.418 | 0.435 | 0.138 | 0.195 |
| `/robots.txt` | file off disk | 66 B | 0.261 [0.247, 0.271] | 0.583 | 1.687 | 1.815 | 0.097 | 0.151 |
| `/ooke` | **rendered per request** | 10,909 B | 0.325 [0.310, 0.345] | 0.444 | 0.664 | 3.568 | 0.215 | 0.372 |
| `/` | **rendered per request** | 63,058 B | **0.422** [0.409, 0.438] | 0.581 | 1.217 | 1.582 | 0.311 | 0.410 |

`/` and `/index.html` are the same 63,058 bytes: **rendering a page from its
`.tkt` on every request costs 0.23 ms more than reading the finished file**
(0.422 vs 0.194 median) — a 2.2× multiplier that is still well under a
millisecond.

### `ooke` — framework, toy site

| Route | Body | Fresh median | Fresh p95 | Reused median |
|---|---:|---:|---:|---:|
| `/` (pre-rendered at startup, served from memory) | 2,242 B | 0.141 | 0.212 | 0.027 |
| `/api/health` | 32 B | 0.155 | 0.208 | 0.029 |

### caddy — reference, same files

| Route | Body | Fresh median [CI95] | Fresh p95 |
|---|---:|---:|---:|
| `/index.html` | 63,058 B | 0.497 [0.479, 0.524] | 0.906 |
| `/robots.txt` | 66 B | 0.339 [0.330, 0.345] | 0.402 |

On the one like-for-like route, **toke's TTFB is 2.6× lower than caddy's**
(0.194 ms vs 0.497 ms median; 0.301 ms vs 0.906 ms p95).

**Across all 1,350 fresh-connection samples in this run (7 toke routes + 2 caddy
routes x 150), the largest single TTFB was 3.57 ms.** For the two toke servers
alone (1,050 samples): worst median **0.422 ms**, worst p95 **0.583 ms**, worst
single sample **3.568 ms**.

## 3. Throughput

Keep-alive, 3 s per level, server restarted before each level. `degrades_at` is
the first concurrency **above** the peak that falls 5 % below it; `null` means
it never did inside the sweep.

| Server / route | rps @ c=1 | Peak rps | @ c= | Degrades at | rps @ c=128 |
|---|---:|---:|---:|---:|---:|
| `website` `/api/health` | 20,474 | **31,863** | 64 | 128 | 27,886 |
| `website` `/robots.txt` | 7,717 | **12,118** | 4 | 8 | 11,967 |
| `website` `/index.html` | 1,080 | **3,294** | 8 | 16 | 2,373 |
| `website` `/` (rendered) | 2,323 | **2,985** | 128 | — | 2,985 |
| `ooke` `/` (pre-rendered) | 18,044 | **24,383** | 128 | — | 24,383 |
| `ooke` `/api/health` | 18,676 | **26,689** | 2 | 4 | 18,796 |
| caddy `/index.html` | 3,566 | **7,139** | 8 | 16 | **2,131** |
| caddy `/robots.txt` | 4,028 | **8,203** | 4 | 8 | **2,306** |

Two honest readings, not one:

- **On raw peak for the like-for-like route, caddy wins**: 7,139 rps vs toke's
  3,294 — toke reaches **46 %** of the reference. Zero errors on either side.
- **On behaviour under concurrency, toke wins decisively.** Across the whole
  sweep toke's p50 latency on `/index.html` stays between 0.185 and 0.227 ms;
  caddy's rises from 0.250 ms at c=1 to **34.6 ms** at c=128 (p95 **193 ms**).
  At c=128 toke serves *more* requests per second than caddy (2,373 vs 2,131)
  with 180× lower p50.

**Client ceiling.** The load client is Python threads. At c=1 measured rps
equals 1/mean-latency to three digits, so it adds nothing there. The client
demonstrably sustains **≥ 31,863 rps** (the `/api/health` peak), so the 3,294 rps
`/index.html` figure is a server limit, not a client one. Above c≈8 on the toke
server, measured p50 stays flat while aggregate rps falls — that pattern means
the client, not the server, is pacing, so **the toke rows above c=8 are floors**.
The caddy rows are not affected: its own p50 rises, so its degradation is real.

## 4. Memory

**Idle**, 1 s after the first 200, sum over the process group (RSS sums
double-count copy-on-write pages, so the parent figure is the conservative one):

| Server | Processes | Sum RSS | Parent RSS | `ru_maxrss` |
|---|---:|---:|---:|---:|
| `website` | 3 (parent + 2 workers) | **10.3 MB** | 6.4 MB | 6.4 MB |
| `ooke` (testproj, 4 workers) | 5 | **3.8 MB** | 1.5 MB | 2.3 MB |
| caddy | 1 | 41.9 MB | 41.9 MB | — |

**Under sustained load — one keep-alive connection, 20,000 requests** (the
concurrency sweep varies rate and connection count together and cannot separate
a leak from churn; this can):

| Server / route | 0 req | 2,000 | 5,000 | 10,000 | 20,000 |
|---|---:|---:|---:|---:|---:|
| `website` `/api/health` (58 B constant) | 10.3 MB | 14.4 | 17.9 | 23.7 | **36.0 MB** |
| `website` `/robots.txt` (66 B file) | 10.2 MB | 15.8 | 20.7 | 27.0 | **40.1 MB** |
| `website` `/ooke` (10.9 KB rendered) | 10.2 MB | 46.9 | 99.7 | 185.9 | **308.2 MB** |
| `website` `/index.html` (63 KB file) | 10.3 MB | 143.1 | 339.4 | 231.9 | 226.1 MB |
| `website` `/` (63 KB rendered) | 10.3 MB | 143.9 | 340.4 | 667.6 | 162.0 MB |
| `ooke` `/` | 7.7 MB | 11.6 | 17.7 | 23.6 | **37.4 MB** |
| caddy `/index.html` | 42.0 MB | 47.2 | 48.3 | 48.7 | **48.9 MB** |

This is the clearest defect the baseline found. **RSS grows with the number of
requests served, monotonically, on routes where the response is a 58-byte
constant string held in memory** — roughly **1.3 KB per request** for `website`
and **1.5 KB per request** for `ooke`, which share the same `std.http` backing.
On the larger routes the figure rises and falls (allocator churn, peaking at
**668 MB**), so those are high-water marks rather than proof of a leak; the small
constant-response routes have nothing to churn, and they still climb. caddy over
the same 20,000 requests moves 42.0 → 48.9 MB and then stops.

Peak RSS across the whole concurrency sweep: `website` **718 MB**, `ooke`
**106 MB**, caddy **64 MB**.

Two mechanisms in `toke/src/stdlib/http.c` are worth handing to 134.2/134.4
rather than diagnosing here: each connection mallocs
`max_header + max_body + 8` = **1,056,776 bytes** by default
(`HTTP_DEFAULT_MAX_BODY_SIZE` 1 MiB, http.h:167-169) and `memset`s the whole
buffer **on every request** in the keep-alive loop (http.c:731-740). A ~1 MB
memset per request is also consistent with the measured 27 µs floor on reused-
connection service time.

## 5. Binary size and build time

| | `website` | `ooke-toke` | caddy |
|---|---:|---:|---:|
| Binary | **929,624 B** (908 KB) | **879,928 B** (859 KB) | 46,162,978 B (44 MB) |
| Clean build (`make clean && make`, n=1) | **10.83 s** | **9.93 s** | — |

Both toke binaries are **~50× smaller than caddy** and each is a single static
native binary with no runtime. Build times are n=1 on a machine at load ~15 —
an order of magnitude, not a gate.

## 6. The rate limiter

`toke/src/stdlib/http.c:664-701`: **200 connections per 60 s per source IP**,
hard-coded, applied per TCP connection in `handle_connection()`, keyed on the
socket peer address with no `X-Forwarded-For` consultation, with a separate
table per forked worker.

| Server | Fresh connections served before first non-200 | Then | Recovered after 62 s |
|---|---:|---|---|
| `website` (2 workers) | **396** in 0.057 s | HTTP 429 | yes |
| `ooke` (4 workers) | 600 (probe cap, never tripped) | — | — |
| caddy | 600 (probe cap) | — | — |

It first showed up as a silently corrupted benchmark run (README §4). It is
worth a look from 134.2/134.8 for a second reason: behind a CDN every connection
arrives from a small set of edge addresses, and this limiter counts peer IPs.

## 7. Coverage gap

`ooke-toke serve` **cannot serve the toke website**. Pointed at a copy of
`toke-website`, it registered the static routes and the `/docs/learn/*` dynamic
group, then stopped: 0 % CPU, ~1.5 MB RSS, never reached `starting listen`,
never accepted a connection, and ignored `SIGTERM` (`SIGKILL` required). Same
area as the 132.20 / 134.8 `ooke build` RT005 blocker, and that story's to
diagnose.

So **there is no measurement of the ooke framework serving a real-sized site**,
and there cannot be until 134.8 lands. Every ooke row above is a 3-page scaffold
whose pages are rendered once at startup and served from memory.

Both toke servers also needed `SIGKILL` at shutdown in every trial
(`needed_sigkill: true`): neither exits on `SIGTERM`. caddy exits cleanly.

---

## 8. The two published claims

### `<5ms TTFB` — the stat tile on `/ooke` (`templates/ooke.tkt:16`)

**The number is true with a wide margin; the claim as published is not
supportable.**

Every TTFB measured on the two toke servers is far inside 5 ms. Over 1,050
fresh-connection samples across 7 routes: worst median **0.422 ms**, worst p95
**0.583 ms**, worst single sample **3.568 ms**. A 5 ms ceiling has roughly an
**8.6x margin** over the worst p95 and still clears the worst single sample.

It still fails as published, for three separate reasons:

1. **Wrong subject.** The tile is on the *ooke* page and reads as a property of
   ooke. ooke cannot serve the real site (§7). The real-site numbers come from
   the `website` binary, which uses toke's `std.http` directly and is not the
   ooke framework. The only ooke TTFB that exists is from a 3-page scaffold.
2. **Wrong quantity.** Presented bare beside "0 runtime deps" and "1 binary",
   `<5ms TTFB` reads as what a visitor experiences. This is loopback,
   server-side, no DNS, no TLS handshake, no network RTT, no CDN — exactly the
   terms that dominate a real visitor's TTFB. A user-observed figure is not
   measured here and is not measurable here.
3. **No method ever attached** — no machine, no workload, no sample size, no
   date. That is the condition 132.14 removes claims for.

**Recommendation: replace, do not keep.** Either withdraw the tile, or restate
it with its basis, e.g. *"0.42 ms median server-side TTFB rendering a 63 KB page
per request (loopback, Mac14,10, n=150, 2026-09-19 — see
`toke/docs/metrics-baseline.md`)"* — and only once ooke itself, rather than the
website binary, can produce it.

### `under 10ms` — loke intent classification (`templates/loke.tkt:119`)

**Not supportable, and 134.6 cannot source it. Withdraw.**

It is not a web-serving claim at all: *"A lightweight local classifier analyses
each prompt in under 10ms."* That is loke's prompt intent classifier. This
benchmark measures HTTP serving and says nothing about it. loke is not in this
workspace and no artefact in any repo measures classifier latency — the same
condition under which 132.14 deleted loke's "698 `.tk` files / 87,318 lines".
132.22 grouped the two claims together; they are different kinds of claim and
only one of them is in 134.6's reach.

---

## 9. Proposed rows for `toke/docs/metrics-baseline.md`

Not applied here — `metrics-baseline.md` belongs to the toke repo and other
agents are in it. Exact text in `metrics-baseline-rows.md` alongside this file.
