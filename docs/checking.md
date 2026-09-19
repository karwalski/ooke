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

---

# Lint state (story 134.3)

`scripts/audit_tk.sh lint`, compiler pinned to a build of toke `ba67f2a`
(sha256 `9ab273c7…e2e3c`).

| | before 134.3 | after |
|---|---|---|
| errors | 0 (2 cleared by 134.2) | **0** |
| warnings | 96 | **2** |
| hints | 309 | 310 |

## Warnings cleared

| Rule | Was | Now | How |
|---|---|---|---|
| `string-concat-chain` | 63 | 0 | 63 nested `str.concat` chains flattened to `str.join("";@(…))` — pattern `str-interp-vs-join`, catalogue **form b** |
| `unused-let` | 29 | 0 | every site was a side-effecting call (`file.mkdir`, `file.write`, `process.wait`) — converted to the discard-statement form `(expr);`, never deleted |
| `W1020` `:void` | 7 | 0 | story 134.2 |
| `unused-import` | 2 | 2 | **not fixable — see below** |
| `mut-flag-if` | 1 | 0 | `src/template.tk` `closedelim` → expression `el if` chain (`cond-elif-chain` form a) |
| `mutable-never-mutated` | 1 | 0 | `src/validate.tk` `warnings` lost its `mut.` |

`str.fromint(x)` became `x as str` (`str-num-format` **form c**) at every site
inside a flattened chain where `x` is a simple lvalue; proven byte-identical
including negative values.

## Why not interpolation

The catalogue's canonical form for `str-interp-vs-join` is **form a**,
interpolation. It is not used here, and must not be adopted until the compiler
is fixed: `"\(x)"` prints the *pointer* as a decimal number whenever `x` is a
`$str` that came from outside `std.str`. Confirmed corrupting: `path.join`,
`path.dir`, a map `.get` through `mt`, and a user `T!$err` function through
`mt`. Confirmed correct: `std.str` calls, plain user functions, parameters,
locals, array `.get`, and `i64`. Exit 0, no diagnostic.

A whole-repo interpolation rewrite was built, applied to a scratch copy, and
rejected on the evidence: a golden-output diff of the resulting binary showed
three live ooke log lines silently corrupted
(`Created page: 4314946480`, `unknown command: 6136001339`). Form b is in the
catalogue, is byte-identical to the nested form here, and beats it on both wall
time (85.0 ms vs 104.1 ms) and tokens (15 vs 20 proxy8k).

## The two remaining warnings

`unused-import` on `src/build.tk:6` (`cfg`) and `test/cli/test_cli.tk:7`
(`cfgmod`). **Both are false positives and removing either breaks ooke.**

- `src/build.tk` uses `ooke.config` only for the *type* `$ookecfg`
  (`buildrun(…;config:$ookecfg)`). Dropping the import gives
  `error[E3011]: identifier 'ookecfg' is not declared`.
- `test/cli/test_cli.tk` type-checks without the import, but the binary built
  without it **fails at run time**: `file.write` stops taking effect while
  `cligen` still logs success, and the test exits 1. The emitted IR is 723
  bytes smaller. Codegen depends on the import list beyond name resolution.

Do not "fix" these. They are compiler defects, filed in the 134.3 report.

## Hints left, recorded

| Count | Rule |
|---|---|
| 307 | `single-use-let` |
| 3 | `loop-rebuilds-array` |

Left deliberately, per 134.3's own terms. `single-use-let` interacts with the
concat pass and should be re-measured now that the chains are flattened.

## Pattern work NOT done, and why

`cond-elif-chain` (31 nested-`if` sites), `err-validate-early` (22),
`str-build-loop` (15 → `s.builder`), `iter-filter`/`iter-map`/`iter-find-first`
/`coll-membership` (13 loop sites) have **no lint rule in this compiler** and no
test coverage in ooke that would prove a rewrite behaviour-preserving. They are
a separate increment, not part of this one.
