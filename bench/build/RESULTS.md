# ooke build-path measurement — 2026-09-19

Story **134.4**: measure ooke with the Epic 131 harness method, then improve
only what the numbers show. Companion to `bench/serving/` (story 134.6), which
measures the serving path; this measures the build path and the source itself.

Every number below names its method, its machine and its sample size, because
134.6 had to withdraw a latency claim that carried none of the three.

## Conditions

| | |
|---|---|
| Machine | `Mac14,10`, 12 CPUs, 16 GB, macOS 26.5.1 (Darwin 25.5.0) |
| Compiler | private `tkc` built from a **clean archive** of toke `47f6cb1`, binary sha256 `01e129962d2bf8cc…`, reports `toke 2.8.0` |
| Why a private compiler | `~/tk/toke/src` was dirty (Epic 136 stdlib glue in flight), so the shared `~/tk/toke/tkc` could not be pinned — the 131.73 discipline |
| Fixture | frozen, symlink-dereferenced copy of `toke-website`, 347 files, tree sha256 `147ca086de30662c…`; `pages/api/` removed (see *Blocker* below) |
| Output | 206 pages / 230 files per build |
| **Load average, 1 min** | **255–268 throughout.** `load_warning: true` on every wall figure |

**The machine was never quiet.** The 131 harness refuses to run above a 1-min
load average of 2.0; this session never saw it below 36, and it rose through
the run. Wall times are therefore **upper bounds and cannot separate variants
whose medians differ by less than about 10%**. Peak RSS, allocation counts,
token counts, output hashes and binary sizes are **load-immune** and carry the
weight of the conclusions. A quiet-machine wall re-measure is outstanding.

## Method

`run_build.py` imports `toke/bench/patterns/run_patterns.py` directly rather
than reimplementing it, so the statistics are the same code Epic 131 uses:

* wall — `time.perf_counter()` around spawn→exit, **2 warm-up + 15 timed runs**
  per variant, median plus a percentile **bootstrap 95% CI** (1000 resamples,
  seed 131);
* peak RSS — `ru_maxrss` from `os.wait4` on the child, the same kernel counter
  `/usr/bin/time -l` prints;
* allocations — one extra run under `liballoccount.dylib`
  (`DYLD_INSERT_LIBRARIES`), which is deterministic and load-immune;
* output identity — sha256 over the sorted built tree, re-checked on **every**
  timed run, so a non-deterministic build fails the measurement rather than
  being averaged;
* the fixture is re-copied from the frozen snapshot before every run, so no run
  sees another run's `build-docs/`.

Token counts use `toke/scripts/patterns/count_tokens.py --whole` over the 13
files of `src/`, same pinned compiler, proxy artefact `proxy8k-5f3f74314ce4`.

## 1. Did 134.3's canonical forms make ooke larger or slower?

Before = `e7a6f60` (134.2), after = `4dd9efc` (134.3). The story asked for an
honest answer including an unfavourable one.

### Tokens — all five lanes available

| lane | before | after | delta |
|---|---:|---:|---:|
| `min_bytes` | 54,889 | 53,898 | **−1.81%** |
| `proxy8k` (decision metric) | 14,775 | 14,668 | **−0.72%** |
| `byte256` (floor) | 45,817 | 44,825 | **−2.17%** |
| `qwen25coder` | 15,612 | 15,551 | −0.39% |
| `cl100k` | 15,527 | 15,466 | −0.39% |
| **`v03`** | **10,575** | **10,811** | **+2.23%** |

**134.3 made ooke smaller on four lanes and larger on one.** The regression is
`v03` — toke's own shipped tokenizer — and it is not spread: `cli.tk` alone
accounts for +159 of the +236, with `serve.tk` +25, `build.tk` +20, `validate.tk`
+19 and `router.tk` +17. Only `template.tk` (−9) and `repair.tk` (−1) improved.
The canonical `str.join("";@(…))` form spells out a call, an array literal and
delimiters where a concatenation chain did not, and `v03` — trained on the old
corpus — has no cheap merge for it while `proxy8k` does.

This does **not** overturn the catalogue: the protocol's decision metric is
`proxy8k`, and `proxy8k` improved. It is recorded because §4 of the protocol
says every verdict cites its numbers, and because **131.50's superword and
byte-patch lanes do not exist yet** — that story is still `planned`, so "every
131.50 lane" could not be measured. The `v03` result is the kind of lane
disagreement 131.50 was filed to expose, and it should be re-checked when the
real v0.4 tokenizer lands (protocol §8).

### Runtime

| variant | wall median | CI95 | peak RSS median | allocated bytes | output sha256 |
|---|---:|---|---:|---:|---|
| before (134.2) | 305.6 ms | [285.0, 377.1] | 45,888 kB | — | `e75768a0115d…` |
| after (134.3) | 286.5 ms | [269.6, 303.1] | 45,568 kB | 70,433,503 | `e75768a0115d…` |

n = 15 timed runs each, 2 warm-ups, `load_warning: true`.

**The two are not separable.** The CIs overlap across [285.0, 303.1], peak RSS
differs by 0.7%, and allocation counts are identical to within 0.004%. The
honest verdict is **no measurable runtime change**, not an improvement. Output
was byte-identical across all 30 timed runs, which is an independent
confirmation of 134.3's golden diff on a different fixture.

**No catalogue verdict is re-opened by this.**

## 2. What the numbers then showed, and what changed

With 134.3 measured, the question became where the 70.4 MB allocated to emit
~4 MB of HTML actually goes. Three controlled, load-immune experiments:

1. **Layout re-lexing.** Padding `templates/docs.tkt` with a `{# … #}` comment
   block — lexed, never emitted, output sha unchanged — added **15.55 MB of
   allocation for 19.75 KB of padding**. The layout is read and lexed once per
   page, 205 times.
2. **Caching it does not pay.** A pre-lexed token cache threaded through
   `tplrender` (output byte-identical) made things **worse**: caching every
   template cost **+4.0 MB**, and caching only the repeatedly-rendered ones
   still cost **+0.55 MB**. A control build with the threading in place but the
   cache always empty came in at +867 bytes of 70 MB, which proves the cost is
   the eager lexing, not the threading. **The cache was rejected on its
   numbers and is not in the tree.**
3. **So lexing is not the hot path; rendering is.** Replacing the 7,924-byte
   layout with a 60-byte one saved 11.29 MB — a figure that conflates lexing
   with *rendering*, and experiment 2 showed the lexing half is small.

That pointed at `tplrender`'s accumulators, which were
`buf = str.concat(buf; part)` on every token — the `str-build-loop` form the
catalogue measures as **`worse-bigO`** (form `a` timed out at 30,000 ms; the
canonical `str.builder`/`str.add`/`str.build` form ran in 58.83 ms). It is one
of the 15 string-building loops 134.3 deliberately left, because **no lint rule
covers them** (131.64). Converting it (`2afd191`):

| | after (134.3) | + builder | delta |
|---|---:|---:|---:|
| **peak RSS median** | 45,568 kB | **38,560 kB** | **−15.4%** |
| peak RSS range, 15 runs | 45,520–45,952 | 38,368–38,832 | **disjoint** |
| wall median | 286.5 ms | 261.8 ms | −8.6% |
| wall CI95 | [269.6, 303.1] | [253.4, 271.5] | marginal overlap |
| allocated bytes | 70,433,503 | 69,775,211 | −0.93% |
| output sha256 | `e75768a0115d…` | `e75768a0115d…` | **identical** |
| ooke test suite | 12/12 | 12/12 | — |

**Peak RSS is the result that stands**: a 15.4% reduction with completely
disjoint ranges over 15 runs each, on a counter that load cannot move. The wall
improvement points the same way but the CIs touch, so it is reported and not
claimed.

The allocation saving is only 0.93% at the site's current template shape, and
that is the interesting part: the catalogue's `worse-bigO` verdict is real but
**does not bite at ooke's scale today**. Add tokens to the layout and it does —
−10.3% at +500 tokens, −21.5% at +2,000. The change was made because it is the
catalogue's canonical form and it is asymptotically better, not because it wins
big now.

## 3. A toke limitation, not an ooke one

`tpllex` is **O(tokens × length)**: every token does
`str.slice(afteropen; closepos+2; str.len(afteropen))`, copying the whole
remaining source, because **`str.indexof(s; sub)` takes no start offset**
(`tk_str_indexof_w` is 2-arity; there is no 3-arity form). A scanner written in
toke therefore cannot advance a cursor — it must re-slice the tail on every
token. The scaling test shows this term dominating: at +2,000 layout tokens the
build allocates 14.8 GB even with the string builder in place, so the builder
fixes the renderer's quadratic term and leaves the lexer's untouched.

Every tokenizer, parser, CSV reader and template engine written in toke pays
this. **→ Epic 127**: add a start-offset parameter to `str.indexof` (and
`str.lastindex`). Until then `str.charat` scanning is the only linear option,
and it costs one runtime call per byte.

## 4. Blocker found while setting the fixture up

`ooke build` **aborts on any project containing an API route.** `routerscan`
computes `route.isapi`, and `buildrun` never reads it, so an API page is handed
to `buildpage`, which tries to render a `.tk` handler as a template and
propagates `$builderr` out of the whole build. `cli.runbuild` discards the
error and logs the single word `build failed`.

Bisected across four builds of ooke against the same pinned compiler: it works
at `81b4fb3` (134.8) and `b663797`, and fails from **`e7a6f60` (134.2)**
onward. 134.2 did not cause it — it *exposed* it. Before 134.2, `buildpage`
returned `:void` and the error was swallowed; giving it an `:i64` return made
the failure propagate honestly. The bug was always there.

This means **134.8's "195 pages, exit 0" no longer reproduces at HEAD**, and
`ooke new` scaffolds a project that cannot be built. Removing the single
`pages/api/` route makes all four binaries build identically (206 pages, 230
files), which is how this fixture is configured.

**Filed for the backlog, not fixed here** — it is a correctness bug in
`src/build.tk`, which a concurrent story (134.20) was editing at the time.

## Reproducing

```sh
python3 bench/build/run_build.py --runs 15 --variants before,after,bld \
        --fixture /path/to/frozen/site --outdir build-docs
```

It refuses to run above a 1-min load average of 2.0. `--allow-load` overrides
and stamps `load_warning: true` into the results, which is what happened here.
