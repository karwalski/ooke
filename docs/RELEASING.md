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

## Publish (owner only — one step)

The GitHub Actions workflow `.github/workflows/release.yml` triggers on any tag
matching `v*`. It builds on four platforms, runs the floor gate and the suite,
and creates the GitHub release with checksums. So the single authorised step is:

    git push origin <branch> && git push origin v3.0.0-rc.2

after creating the tag:

    git tag -a v3.0.0-rc.2 -m "ooke 3.0.0-rc.2"

Pushing the tag **is** the publish. There is no separate upload.

## Before tagging 3.0.0 rather than a candidate

- **The remaining blocker is a toke release that contains `668caa6`** (toke
  story 138.17). 134.15 is resolved — toke tagged `v3.0.0` — but ooke's suite
  fails on that tag (127.226) and ooke now calls serve functions added after it
  (138.1), so rc.2's floor is still a commit. (134.24, the
  P0 that blocked rc.1, was fixed and verified on 2026-09-19.)
- Tag rc.2 only after the toke release it is verified against (138.17), and
  re-run `scripts/package_release.sh` against that toke so the manifest names it.
- Drop the `-rc.N` suffix in `VERSION` — the one place ooke's version is
  written. `ooke --version` prints `floor.ookeversion()`, which the Makefile
  generates from `VERSION` into `src/_floor.tk` (story 121.66); it used to be a
  second literal in `src/cli.tk`, and `make check-ooke-version` now fails if
  one comes back.
- Re-check `ooke.toml [requires]`. It is a commit today; if story 134.15 has
  cut toke's version by then, replace `mintokecommit`/`mintokedate` with a real
  `mintoke` semver and simplify the Makefile gate accordingly.
- Update `docs/release-notes-3.0.0.md` and `CHANGELOG.md` to say released, and
  re-run the packager so the manifest names the tagged commit.
