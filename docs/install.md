# Installing ooke, and depending on it from another project

Story 134.10. Every command here was run from a **fresh clone outside the
development tree**, not from a working copy, because two defects this week
(ooke's `test/support`, story 134.21; toke's `stdlib/vendor`, story 127.85)
were invisible in a working tree and fatal in a clone.

## 0. What you are depending on

| | |
|---|---|
| ooke | **3.0.0-rc.1** — release candidate, see `docs/release-notes-3.0.0.md` |
| toke | **`c2aa278` (2026-09-19) or later**, declared in `ooke.toml [requires]` |

toke has **no released version that works**. `toke/VERSION` has read `2.8.0`
since 2026-06-21 and has not moved across the entire v0.4 language break, so a
semver cannot express the requirement and the floor is a **commit**. Story
134.15 is the owner decision to cut that version; until it lands, pin the
commit. `docs/versioning.md` carries the evidence for the floor, including why
it is `c2aa278` and not the `b66bd8e` an earlier story established.

## 1. System dependencies

    macOS      brew install openssl@3 sqlite        (clang and make ship with Xcode CLT)
    Debian     sudo apt-get install -y clang make zlib1g-dev libssl-dev libsqlite3-dev

## 2. Build toke

    git clone https://github.com/karwalski/toke.git
    cd toke
    git checkout c2aa278          # or later; see ooke.toml [requires]
    make

**A plain clone is sufficient.** toke's third-party sources
(`stdlib/vendor/cmark`, `stdlib/vendor/tomlc99`) are *tracked in the
repository* — there is no submodule to initialise and no fetch step. That was
not always true: before toke's story 127.85 they were ignored, a fresh clone
had zero vendored files, and the build died in clang with an opaque `E9003`
that named neither the dependency nor the cure. If you see that, your toke
predates the fix and is far below ooke's floor.

**Always build toke from clean when you change commit.** `git checkout` followed
by an incremental `make` produces a compiler that behaves like neither commit —
this cost story 134.16 a whole bisect. `make clean && make`.

This leaves the compiler at `toke/toke` (with a `toke/tkc` symlink).

## 3. Build ooke

    git clone https://github.com/karwalski/toke-ooke.git
    cd toke-ooke
    make                          # assumes toke is checked out beside ooke

`make` runs the floor gate first and refuses to build against a toke below
`[requires]`, by name. If toke is somewhere else:

    make TOKE_ROOT=/path/to/toke

`TOKE_ROOT` and `TKC` are both overridable from the environment or the command
line (they were hardcoded absolute paths until 134.16). `TKC` defaults to
`$TOKE_ROOT/toke`; override it alone to run a compiler built elsewhere against
that same tree.

The product is `./ooke-toke`. Rename it to `ooke` on your PATH.

## 4. Check the install

    make test                     # 12/12, 187 live assertions
    ./ooke-toke --version         # ooke 3.0.0-rc.1
    ./ooke-toke new demosite      # scaffolds ooke.toml, pages/index.tk, templates/base.tkt

`make test` is not decoration: until story 134.5 (2026-09-19) the suite had
never executed, and until 134.17 its assertions could not fail. Both are fixed;
running it tells you something now.

**`ooke build` on that scaffold currently fails.** That is story 134.24, a known
open P0 — see `docs/release-notes-3.0.0.md` before you build anything on it.

## 5. From a release tarball instead

    tar xzf ooke-3.0.0-rc.1-darwin-arm64.tar.gz
    cd ooke-3.0.0-rc.1-darwin-arm64
    ./ooke --version

The binary is self-contained: no runtime, and it does not read anything out of
ooke's own source tree. Verify it against `SHA256SUMS`. The accompanying
`*.manifest.txt` records the ooke commit, the toke commit and the **sha256 of
the exact compiler** the binary was produced with — check that against your own
toke if you need to reproduce the build.

The source tarball (`-src.tar.gz`) is a `git archive` of the tagged commit: it
contains the tracked files and nothing else, which is deliberately the same set
a `git clone` gives you.

## 6. Depending on ooke from another toke project

There are two different things people mean by this.

**(a) Using the ooke CLI** — you scaffold with `ooke new`, write `pages/`,
`templates/` and `content/`, and run `ooke serve` / `ooke build`. Your project
depends on the ooke binary and on the conventions in `docs/public-api.md`.
Your own `pages/*.tk` must be **v0.4 toke** (`==` for equality,
expression-`if`); 2.0.0-era sources do not compile.

**(b) Importing ooke's modules** — `i=router:ooke.router;` and friends, which is
what loke does at about 30 sites (story 134.11). Those modules are **not a
supported API surface**; see `docs/public-api.md` §2. If you do it anyway, you
need ooke's source tree, not just the binary: build ooke first, then compile
against its emitted interfaces with `-I <ooke>/src`, and link `<ooke>/src/ooke/*`
alongside the toke stdlib objects. `make print-build-vars` prints the exact
compiler, source lists and flags the ooke binary itself is built with — consume
that rather than copying the lists, which is precisely how ooke's own test
runner drifted out of linkability and reported twelve failures as skips
(story 134.5).
