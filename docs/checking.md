# Type-checking and linting ooke

Story 134.2. This documents the one invocation detail that makes every `.tk`
file in the repo checkable on its own, and the gates that keep it that way.

## The invocation

ooke's `.tki` interface files live in `src/` (`src/ooke.config.tki`,
`src/ooke.router.tki`, …). `tkc` resolves `.tki` **relative to the current
working directory**, and the Makefile's build rules hide that by doing
`cd src && tkc …` before every compile. Anything run from the repo root — a
human, a linter, CI — therefore cannot see the interfaces and fails with
`E2030` on 18 of the 30 files.

Supply the interface search directory explicitly:

```sh
tkc --check -I src <file>          # -I is repeatable
tkc --lint  -I src <file>
```

The environment equivalent is `TKC_INTERFACE_PATH=src`.

## Gates

| Command | What it does |
|---|---|
| `make check` | `tkc --check -I src` over **every** `.tk` file found by `find . -name '*.tk'`. Exits non-zero on the first file tkc rejects. |
| `make test-check` | The same, restricted to `test/*/test_*.tk`. |
| `make test` | `check-versions` → `check` → build → `test-check` → `test-run`. |
| `scripts/audit_tk.sh check\|lint\|all` | Read-only evidence harness; prints per-file pass/fail and a lint histogram. |

Both `check` and `test-check` use tkc's own exit status. They do **not** filter
diagnostics by code, severity or stage, and they do not end in `|| true`.
Earlier versions did all three, which is why a file that had never parsed
(`testproj/pages/api/hello.tk`) and a struct field that did not exist
(`test/cli/test_cli.tk`) both survived in the tree. If a gate needs to be
quietened, fix the source — do not reintroduce a filter.

CI (`.github/workflows/ci.yml`) runs `make check` and `make test-check` as
ordinary failing steps, on every branch.

## Known accepted warnings

`tkc --check` exits 0 on warnings. Two are present by design and are **not**
suppressed:

- `W1001` lossy cast `i64`→`u64`, `src/serve.tk:158` and `:159`
  (`port as u64`, `workers as u64`). `std.http`'s `serveworkers`/`servetls`
  take `u64`; ooke's config carries both as `i64`. The values are a TCP port
  and a worker count, both small and non-negative. Visible only during
  `--emit-llvm`; invisible to `--check` and `--lint`.
