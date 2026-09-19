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

    git push origin <branch> && git push origin v3.0.0-rc.1

after creating the tag:

    git tag -a v3.0.0-rc.1 -m "ooke 3.0.0-rc.1"

Pushing the tag **is** the publish. There is no separate upload.

## Before tagging 3.0.0 rather than a candidate

- **134.24 must be fixed.** `ooke build` aborts on any project with an API
  route, and `ooke new` scaffolds one. A GA release whose scaffold cannot be
  built is not a release.
- Drop the `-rc.1` suffix in exactly two places — `VERSION` and the string
  `src/cli.tk` prints. `make check-ooke-version` fails if they disagree, so the
  build will catch a half-done bump.
- Re-check `ooke.toml [requires]`. It is a commit today; if story 134.15 has
  cut toke's version by then, replace `mintokecommit`/`mintokedate` with a real
  `mintoke` semver and simplify the Makefile gate accordingly.
- Update `docs/release-notes-3.0.0.md` and `CHANGELOG.md` to say released, and
  re-run the packager so the manifest names the tagged commit.
