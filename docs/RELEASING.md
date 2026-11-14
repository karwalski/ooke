# Releasing ooke

Story 134.10. **Nothing in this repository publishes anything.**
`scripts/package_release.sh` builds tarballs into `dist/`, which is ignored.
Publishing is one authorised command, run by the owner.

## Prepare (anyone, no authority needed)

    make TOKE_ROOT=/path/to/toke          # floor gate + build
    make test                             # 12/12
    scripts/package_release.sh            # -> dist/

The packager refuses a dirty working tree, runs the floor gate and the suite
before it packages anything, and records in `dist/ooke-<ver>.manifest.txt` the
ooke commit, the toke commit, and the **sha256 of the exact compiler** used.

The source tarball is `git archive`, not `tar .`: it can only ever contain
tracked files. That is deliberate — the two defects that most recently escaped
review (ooke `test/support`, 134.21; toke `stdlib/vendor`, 127.85) were both
files present in a working tree and absent from a clone.

## Building against a candidate toke (story 121.76)

ooke links toke's stdlib C files, and the list of them is toke's: the Makefile
asks `tkc --emit-deps` (toke's module manifest, `src/stdlib_deps.c`) instead of
keeping a copy, so a toke change that adds, moves or splits a stdlib C file
needs no edit here. To confirm that before such a toke change merges -- or
before tagging against a new toke -- build ooke against the candidate tree:

    make -C /path/to/candidate-toke                         # build its compiler
    make check-toke-candidate TOKE_CANDIDATE=/path/to/candidate-toke

It checks out ooke's HEAD into a temporary worktree (this checkout's build is
untouched), builds the binary, links and runs the unit tests, and builds an
`ooke compile` app -- the three link paths. It skips the floor gate, since a
candidate branch need not contain `mintokecommit` yet. A toke merge that
touches `src/stdlib/*.c` or `src/stdlib_deps.c` should run it (and the same
for toke-website, whose `make website` also links from `--emit-deps`).

## Publish (owner only — one step)

The GitHub Actions workflow `.github/workflows/release.yml` triggers on any tag
matching `v*`. It builds on four platforms, runs the floor gate and the suite,
and creates the GitHub release with checksums. So the single authorised step is:

    git push origin <branch> && git push origin v3.0.0

after creating the tag:

    git tag -a v3.0.0 -m "ooke 3.0.0"

Pushing the tag **is** the publish. There is no separate upload.

## Before tagging 3.0.0 (done 2026-11-15)

All four steps below were done on 2026-11-15: toke `v3.2.0` was tagged at
`ea7ddf22`, the pin moved to it, `make test` and `scripts/package_release.sh`
ran against it, and `release/3.0.0` was merged and tagged `v3.0.0`.

### The checklist as written (state on `release/3.0.0`, 2026-11-14)

Done on the branch: `VERSION` reads `3.0.0`; `mintoke = "3.2.0"`; the
CHANGELOG, release notes, versioning, install, public-api and README say
3.0.0. Still to do, in this order:

1. **toke's `v3.2.0` tag exists** (and is pushed before ooke's, since the
   workflows clone toke from GitHub).
2. **Point `mintokecommit`/`mintokedate` at toke's 3.2.0 version commit**
   (the commit that sets toke's `VERSION` to 3.2.0, and its date) — or at the
   tag name `v3.2.0`, which `git checkout` and the Makefile gate accept.
   They name `db47d591` today, and CI and the release workflow `git checkout`
   that commit, whose `VERSION` is 3.1.0: `check-versions` would refuse it.
3. Re-run `make test` and `scripts/package_release.sh` against the tagged
   toke, so the manifest names it; say "released" in `CHANGELOG.md` and the
   release notes.
4. Merge `release/3.0.0` to main, then tag `v3.0.0` on the merged commit.

The checklist below is the rc-era record.

## Before tagging 3.0.0 rather than a candidate (rc-era record)

- **The toke release is 3.1.0** (toke story 138.17): the first toke release
  that contains `668caa6`, and the floor `ooke.toml [requires]` declares.
  (134.15 is resolved — toke tagged `v3.0.0` — but ooke's suite fails on that
  tag (127.226) and ooke calls serve functions added after it (138.1). 134.24,
  the P0 that blocked rc.1, was fixed and verified on 2026-09-19.)
- Tag a candidate only after toke's `v3.1.0` tag exists, and re-run
  `scripts/package_release.sh` against that tagged toke so the manifest names it.
- Drop the `-rc.N` suffix in `VERSION` — the one place ooke's version is
  written. `ooke --version` prints `floor.ookeversion()`, which the Makefile
  generates from `VERSION` into `src/_floor.tk` (story 121.66); it used to be a
  second literal in `src/cli.tk`, and `make check-ooke-version` now fails if
  one comes back.
- Re-check `ooke.toml [requires]`. `mintoke = "3.1.0"` is the floor (138.17);
  once toke's `v3.1.0` tag is published, drop `mintokecommit`/`mintokedate`
  (or point CI at the tag) and simplify the Makefile gate accordingly.
- Update `docs/release-notes-3.0.0.md` and `CHANGELOG.md` to say released, and
  re-run the packager so the manifest names the tagged commit.
