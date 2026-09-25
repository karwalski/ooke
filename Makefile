# toke-ooke Makefile — toke-only build (story 56.8.2)
#
# All ooke source is now toke (.tk). Build pipeline:
#   1. Compile each module to .tki (interface) + .ll (LLVM IR)
#   2. Compile main.tk to .ll
#   3. Link all .ll + stdlib C + vendor C into the ooke binary

# ── Where toke lives (story 134.10) ───────────────────────────────────────
# These were absolute paths into one developer's home directory, so nobody
# else could build ooke and the floor could not be re-tested against an older
# toke (story 134.16).  They are now `?=`, so the environment or the command
# line wins:
#
#     make TOKE_ROOT=/path/to/toke
#     TOKE_ROOT=/path/to/toke make          # exported env also works
#
# The default assumes toke is checked out beside ooke, which is the layout
# README and docs/install.md describe.  TKC defaults to the compiler that
# TOKE_ROOT's own `make` produces, so pointing TOKE_ROOT at a different toke
# moves the compiler with it; override TKC alone to pin a compiler built
# elsewhere (e.g. a floor build) against that same tree.
TOKE_ROOT   ?= $(abspath $(CURDIR)/../toke)
TKC         ?= $(TOKE_ROOT)/toke
TOKE_STDLIB := $(TOKE_ROOT)/src/stdlib
TOKE_VENDOR := $(TOKE_ROOT)/stdlib/vendor

BIN := ooke-toke
SRC := src

# ── Stdlib C sources required by ooke ─────────────────────────────────────
# Implementation files (core logic)
STDLIB_SRCS := \
  $(TOKE_STDLIB)/str.c \
  $(TOKE_STDLIB)/file.c \
  $(TOKE_STDLIB)/env.c \
  $(TOKE_STDLIB)/log.c \
  $(TOKE_STDLIB)/http.c \
  $(TOKE_STDLIB)/router.c \
  $(TOKE_STDLIB)/ws.c \
  $(TOKE_STDLIB)/encoding.c \
  $(TOKE_STDLIB)/tk_runtime.c \
  $(TOKE_STDLIB)/args.c \
  $(TOKE_STDLIB)/path.c \
  $(TOKE_STDLIB)/md.c \
  $(TOKE_STDLIB)/toml.c \
  $(TOKE_STDLIB)/http2.c \
  $(TOKE_STDLIB)/acme.c \
  $(TOKE_STDLIB)/proxy.c \
  $(TOKE_STDLIB)/cache.c \
  $(TOKE_STDLIB)/content.c \
  $(TOKE_STDLIB)/metrics.c \
  $(TOKE_STDLIB)/server_ops.c \
  $(TOKE_STDLIB)/ws_server.c \
  $(TOKE_STDLIB)/hooks.c \
  $(TOKE_STDLIB)/tk_time.c \
  $(TOKE_STDLIB)/crypto.c \
  $(TOKE_STDLIB)/math.c \
  $(TOKE_STDLIB)/net.c \
  $(TOKE_STDLIB)/sys.c \
  $(TOKE_STDLIB)/mem.c \
  $(TOKE_STDLIB)/os.c \
  $(TOKE_STDLIB)/db.c \
  $(TOKE_STDLIB)/json.c \
  $(TOKE_STDLIB)/process.c \
  $(TOKE_STDLIB)/task.c \
  $(TOKE_STDLIB)/collections.c \
  $(TOKE_STDLIB)/toon.c \
  $(TOKE_STDLIB)/yaml.c \
  $(TOKE_STDLIB)/i18n.c \
  $(TOKE_STDLIB)/auth.c \
  $(TOKE_STDLIB)/encrypt.c \
  $(TOKE_STDLIB)/canvas.c \
  $(TOKE_STDLIB)/chart.c \
  $(TOKE_STDLIB)/html.c \
  $(TOKE_STDLIB)/svg.c \
  $(TOKE_STDLIB)/image.c \
  $(TOKE_STDLIB)/dashboard.c \
  $(TOKE_STDLIB)/dataframe.c \
  $(TOKE_STDLIB)/csv.c \
  $(TOKE_STDLIB)/analytics.c \
  $(TOKE_STDLIB)/ml.c \
  $(TOKE_STDLIB)/llm.c \
  $(TOKE_STDLIB)/llm_tool.c \
  $(TOKE_STDLIB)/sse.c \
  $(TOKE_STDLIB)/template.c \
  $(TOKE_STDLIB)/capabilities.c

# Glue files (i64-ABI wrappers)
STDLIB_SRCS += \
  $(TOKE_STDLIB)/str_glue.c \
  $(TOKE_STDLIB)/file_glue.c \
  $(TOKE_STDLIB)/json_glue.c \
  $(TOKE_STDLIB)/time_glue.c \
  $(TOKE_STDLIB)/crypto_glue.c \
  $(TOKE_STDLIB)/encoding_glue.c \
  $(TOKE_STDLIB)/math_glue.c \
  $(TOKE_STDLIB)/db_glue.c \
  $(TOKE_STDLIB)/path_glue.c \
  $(TOKE_STDLIB)/args_glue.c \
  $(TOKE_STDLIB)/toml_glue.c \
  $(TOKE_STDLIB)/md_glue.c \
  $(TOKE_STDLIB)/log_glue.c \
  $(TOKE_STDLIB)/env_glue.c \
  $(TOKE_STDLIB)/process_glue.c \
  $(TOKE_STDLIB)/collections_glue.c \
  $(TOKE_STDLIB)/io_glue.c \
  $(TOKE_STDLIB)/tk_web_glue.c

# ── Vendor C sources ───────────────────────────────────────────────────────
CMARK_SRCS := $(filter-out $(TOKE_VENDOR)/cmark/src/main.c, \
                $(wildcard $(TOKE_VENDOR)/cmark/src/*.c))
TOML_SRCS  := $(TOKE_VENDOR)/tomlc99/toml.c

VENDOR_SRCS := $(CMARK_SRCS) $(TOML_SRCS)

# ── Compiler / linker flags ────────────────────────────────────────────────
UNAME := $(shell uname -s)
CFLAGS := -std=c99 -D_GNU_SOURCE -O1 -iquote $(TOKE_STDLIB) \
          -I$(TOKE_VENDOR)/cmark/src \
          -I$(TOKE_VENDOR)/tomlc99 \
          -Wno-pedantic -DTK_HAVE_OPENSSL
LDFLAGS :=
LIBS := -lssl -lcrypto -lz -lm -lsqlite3

ifeq ($(UNAME), Darwin)
  CFLAGS  += -I/opt/homebrew/include
  LDFLAGS += -L/opt/homebrew/lib
endif

# ── LLVM IR targets ────────────────────────────────────────────────────────
IFACE_DIR := $(SRC)/ooke

BASE_MODS    := config store router template validate repair run floor
DERIVED_MODS := build serve
API_MODS     := apihealth
GEN_MODS     := handlers
CLI_MODS     := cli
ALL_MODS     := $(BASE_MODS) $(DERIVED_MODS) $(API_MODS) $(GEN_MODS) $(CLI_MODS)

OOKE_LL  := $(addprefix $(IFACE_DIR)/,$(ALL_MODS))
OOKE_TKI := $(addprefix $(IFACE_DIR)/,$(addsuffix .tki,$(ALL_MODS)))
MAIN_LL  := $(SRC)/main.ll

# ── Rules ─────────────────────────────────────────────────────────────────
.PHONY: all dev clean interfaces check test test-check test-run test-cwd test-serve-cwd test-serve-logs test-compile-app test-run-cli test-deps test-cli-contract test-support-check print-build-vars

all:
	@$(MAKE) --no-print-directory check-versions
	@$(MAKE) --no-print-directory $(BIN)

dev: $(BIN)
	@echo "Development server: http://localhost:3000"
	./$(BIN) serve

$(IFACE_DIR):
	mkdir -p $(IFACE_DIR)

# ── Base modules ─────────────────────────────────────────────────────────
$(IFACE_DIR)/config.tki $(IFACE_DIR)/config: $(SRC)/config.tk | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ooke/config config.tk

$(IFACE_DIR)/store.tki $(IFACE_DIR)/store: $(SRC)/store.tk | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ooke/store store.tk

$(IFACE_DIR)/router.tki $(IFACE_DIR)/router: $(SRC)/router.tk | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ooke/router router.tk

$(IFACE_DIR)/template.tki $(IFACE_DIR)/template: $(SRC)/template.tk | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ooke/template template.tk

$(IFACE_DIR)/validate.tki $(IFACE_DIR)/validate: $(SRC)/validate.tk | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ooke/validate validate.tk

$(IFACE_DIR)/repair.tki $(IFACE_DIR)/repair: $(SRC)/repair.tk | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ooke/repair repair.tk

$(IFACE_DIR)/run.tki $(IFACE_DIR)/run: $(SRC)/run.tk | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ooke/run run.tk

# ── Generated toke floor (story 134.35) ──────────────────────────────────
# `ooke new` writes a [requires] block into every project it scaffolds.  It
# used to carry its own literal copy in cli.tk, which stayed at the 134.7
# compile floor (b66bd8e, 2026-07-06) after ooke.toml moved to 6cc9061, so new
# projects declared a floor ooke itself does not build on.  The block is now
# generated from ooke.toml [requires] -- the same three keys check-toke-version
# and the release workflow read -- so there is one source.  Build OUTPUT, like
# _handlers.tk: not tracked, regenerated whenever ooke.toml changes.
# Regenerated on every make (FORCE) but only rewritten when its content changes,
# so a same-second edit of ooke.toml cannot leave a stale floor behind and an
# unchanged floor does not trigger a relink.
.PHONY: FORCE
FORCE:
$(SRC)/_floor.tk: FORCE
	@test -n "$(MIN_TOKE_VERSION)" -a -n "$(MIN_TOKE_DATE)" -a -n "$(MIN_TOKE_COMMIT)" || \
	  { echo "ERROR: ooke.toml [requires] must set mintoke, mintokedate and mintokecommit" >&2; exit 1; }
	@printf '%s\n' \
	  '(* GENERATED from ooke.toml [requires] by the Makefile (story 134.35). Do not edit. *)' \
	  'm=ooke.floor;' \
	  'f=floortoml():$$str{' \
	  '  <"[requires]\nmintoke = \"$(MIN_TOKE_VERSION)\"\nmintokedate = \"$(MIN_TOKE_DATE)\"\nmintokecommit = \"$(MIN_TOKE_COMMIT)\"\n"' \
	  '};' > $@.tmp
	@if cmp -s $@.tmp $@; then rm -f $@.tmp; else mv $@.tmp $@; \
	  echo "Generated: $@ (toke floor $(MIN_TOKE_VERSION) / $(MIN_TOKE_COMMIT) / $(MIN_TOKE_DATE))"; fi

$(IFACE_DIR)/floor.tki $(IFACE_DIR)/floor: $(SRC)/_floor.tk | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ooke/floor _floor.tk

# ── Derived modules ──────────────────────────────────────────────────────
$(IFACE_DIR)/build.tki $(IFACE_DIR)/build: \
    $(SRC)/build.tk \
    $(IFACE_DIR)/config.tki $(IFACE_DIR)/router.tki \
    $(IFACE_DIR)/template.tki $(IFACE_DIR)/store.tki \
    $(IFACE_DIR)/validate.tki | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ooke/build build.tk

$(IFACE_DIR)/serve.tki $(IFACE_DIR)/serve: \
    $(SRC)/serve.tk \
    $(IFACE_DIR)/config.tki $(IFACE_DIR)/router.tki \
    $(IFACE_DIR)/template.tki $(IFACE_DIR)/store.tki \
    $(IFACE_DIR)/build.tki | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ooke/serve serve.tk

# ── API modules ─────────────────────────────────────────────────────────
$(IFACE_DIR)/apihealth.tki $(IFACE_DIR)/apihealth: $(SRC)/apihealth.tk | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ooke/apihealth apihealth.tk

# ── Generated handler registry (auto-scans pages/ for get/post handlers) ──
# Story 134.37: this used `$(wildcard pages/**/*.tk) $(wildcard pages/*.tk)`.
# make's wildcard has no recursive `**` -- it is a plain `*`, one directory --
# so pages/a/b/c.tk was never a prerequisite and editing it did not regenerate
# the registry, although gen_handlers.sh itself scans recursively with find.
# Use the same find here, so the prerequisites are exactly what the generator
# reads.
PAGES_TK := $(shell find pages -name '*.tk' -type f 2>/dev/null)

$(SRC)/_handlers.tk: scripts/gen_handlers.sh $(PAGES_TK) | $(IFACE_DIR)
	./scripts/gen_handlers.sh pages $(SRC)/_handlers.tk

$(IFACE_DIR)/handlers.tki $(IFACE_DIR)/handlers: $(SRC)/_handlers.tk $(IFACE_DIR)/apihealth.tki | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ooke/handlers _handlers.tk

# ── CLI logic module (no f=main; the testable command library) ───────────
$(IFACE_DIR)/cli.tki $(IFACE_DIR)/cli: \
    $(SRC)/cli.tk \
    $(IFACE_DIR)/config.tki $(IFACE_DIR)/serve.tki \
    $(IFACE_DIR)/build.tki $(IFACE_DIR)/handlers.tki \
    $(IFACE_DIR)/floor.tki | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ooke/cli cli.tk

# ── main.ll ──────────────────────────────────────────────────────────────
$(MAIN_LL): $(SRC)/main.tk $(OOKE_TKI) | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-llvm --out main.ll main.tk

# ── Final binary ─────────────────────────────────────────────────────────
$(BIN): $(MAIN_LL) $(OOKE_LL)
	clang $(CFLAGS) $(LDFLAGS) -x ir $(MAIN_LL) $(OOKE_LL) \
	  -x c $(STDLIB_SRCS) $(VENDOR_SRCS) \
	  -o $@ $(LIBS)

interfaces: $(OOKE_TKI)

# ── Test-only assertion helper (story 134.17) ────────────────────────────
# ookeassert is not part of the product, so it is not in ALL_MODS and is not
# linked into $(BIN). It is built here rather than in test/run_tests.sh so
# that `check` and `test-check` can resolve `i=chk:ookeassert;` as well.
# tkc writes the .tki beside the SOURCE, hence test/support/ookeassert.tki and
# the -I test/support on every rule that type-checks a test.
ASSERT_SRC := test/support/ookeassert.tk
ASSERT_TKI := test/support/ookeassert.tki
ASSERT_LL  := build/ookeassert
ASSERT_INC := test/support

# ── Story 134.21: test-support preflight ─────────────────────────
# $(ASSERT_SRC) is TRACKED (see .gitignore).  It had never been added, so
# test/support/ was absent from every fresh clone and the suite died on
# `make: *** No rule to make target 'test/support/ookeassert.tk'` before a
# single test ran — a message that names the file but not the cause or the
# cure.  Stop here instead, by name.  Cheap enough to run every time.
TEST_SUPPORT_FILES := $(ASSERT_SRC)

test-support-check:
	@missing=""; \
	for f in $(TEST_SUPPORT_FILES); do \
	  [ -f "$$f" ] || missing="$$missing $$f"; \
	done; \
	if [ -n "$$missing" ]; then \
	  echo "" >&2; \
	  echo "ERROR: ooke's test-support sources are missing from this checkout." >&2; \
	  echo "" >&2; \
	  for f in $$missing; do echo "  missing: $$f" >&2; done; \
	  echo "" >&2; \
	  echo "  test/support holds the assertion helpers every test under" >&2; \
	  echo "  test/*/test_*.tk imports as 'i=chk:ookeassert;'.  Without them" >&2; \
	  echo "  'make check', 'make test-check' and test/run_tests.sh all abort" >&2; \
	  echo "  before a single test runs." >&2; \
	  echo "" >&2; \
	  echo "  These files are TRACKED in this repository - they are not a" >&2; \
	  echo "  submodule, not generated and there is no fetch step.  If they are" >&2; \
	  echo "  missing, the checkout is incomplete or they were deleted locally." >&2; \
	  echo "  Restore them with:" >&2; \
	  echo "      git checkout -- test/support" >&2; \
	  echo "" >&2; \
	  echo "  (test/support/ookeassert.tki is NOT tracked and is not the problem:" >&2; \
	  echo "   this Makefile regenerates it from ookeassert.tk.  See .gitignore.)" >&2; \
	  echo "" >&2; \
	  exit 1; \
	fi

# test-support-check comes FIRST: make walks prerequisites in order, so the
# named error above beats make's own "No rule to make target" for $(ASSERT_SRC).
$(ASSERT_TKI) $(ASSERT_LL): test-support-check $(ASSERT_SRC)
	@mkdir -p build
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ../$(ASSERT_LL) ../$(ASSERT_SRC)

# check — type-check EVERY .tk file in the repo, standalone, from the repo root.
#
# Story 134.2. The old rule covered 12 of 30 files, piped through `head -5` and
# ended in `|| true`, so it could not fail (defect D7). This one covers all of
# them and exits non-zero on the first error.
#
# The invocation that makes a repo-root check work is `-I $(SRC)`: ooke's .tki
# interfaces live in src/, and tkc resolves .tki relative to the working
# directory. The build rules hide this by doing `cd $(SRC)` first; anything run
# from the repo root — a human, a linter, CI — needs the flag (defect D10).
# The environment equivalent is TKC_INTERFACE_PATH=src.
# src/_handlers.tk is generated build output (story 134.22), so a fresh clone
# does not have it until the build runs.  Name it explicitly and make `check`
# generate it, so it is type-checked whether or not `make` ran first.
TK_SOURCES := $(sort $(shell find . -name '*.tk' -not -path './.git/*') ./$(SRC)/_handlers.tk ./$(SRC)/_floor.tk)

check: test-support-check $(ASSERT_TKI) $(SRC)/_handlers.tk $(SRC)/_floor.tk
	@echo "=== tkc --check -I $(SRC) over $(words $(TK_SOURCES)) file(s) ==="
	@pass=0; fail=0; \
	for f in $(TK_SOURCES); do \
	  if out=$$($(TKC) --check --diag-text -I $(SRC) -I $(ASSERT_INC) "$$f" 2>&1); then \
	    pass=$$((pass+1)); \
	  else \
	    fail=$$((fail+1)); echo "  FAIL $$f"; echo "$$out" | sed 's/^/        /'; \
	  fi; \
	done; \
	echo "  $$pass passed, $$fail failed"; \
	[ "$$fail" = "0" ]

# Test targets
test: check-versions check $(BIN) test-check test-run test-cwd test-serve-cwd test-serve-logs test-compile-app test-run-cli test-deps test-cli-contract

# test-cwd — story 134.25: `ooke build <path>` from a parent, a sibling and an
# unrelated directory must write the same site, into the project, as a build
# run from the project root, and must write nothing where it was run.
test-cwd: $(BIN)
	@test/build/build_from_parent.sh ./$(BIN)

# test-serve-cwd — story 134.37: `ooke serve <path>` from a parent and from /
# must render the project's templates exactly as a serve from the project root.
test-serve-cwd: $(BIN)
	@test/serve/serve_from_parent.sh ./$(BIN)

# test-serve-logs — story 134.40: serve writes the [log] access/error logs it
# is configured with, and serves HTTPS with a [tls] cert/key (a self-signed
# pair made locally with openssl; nothing leaves the machine).
test-serve-logs: $(BIN)
	@test/serve/serve_logs_tls.sh ./$(BIN)

# test-compile-app — story 134.44: `ooke compile` on a copy of testproj builds
# a per-app binary that serves the app's own handlers and [log]; and `ooke
# serve` (and that binary) exit non-zero on a port they cannot bind. TOKE_ROOT
# and TKC are passed through because `ooke compile` generates a Makefile that
# builds against them.
test-compile-app: $(BIN)
	@TOKE_ROOT=$(TOKE_ROOT) TKC=$(TKC) test/serve/compile_app.sh ./$(BIN)

# test-run-cli — story 134.45: `ooke run` exits 0 for a program that exits 0,
# with the program's own status when it fails, and non-zero on a compile
# error; `ooke build --cli` writes the binary. ooke run spawns tkc, so
# TOKE_ROOT is passed through.
test-run-cli: $(BIN)
	@TOKE_ROOT=$(TOKE_ROOT) test/run/run_cli.sh ./$(BIN)

# test-cli-contract — stories 134.42 and 134.43: `--version` on stdout exactly,
# and a malformed ooke.toml fails `build` and `serve` instead of falling back
# to defaults.
test-cli-contract: $(BIN)
	@test/cli/cli_contract.sh ./$(BIN)

# test-deps — story 134.37: a page at any depth under pages/ is a prerequisite
# of src/_handlers.tk. Needs no compiler.
test-deps:
	@test/build/handlers_deps.sh

# test-check — type-check the test programs.
#
# Story 134.2. The old rule counted only diagnostics that were simultaneously
# severity=error AND stage=parse AND not E2030 — i.e. it filtered out the very
# errors that were breaking the repo, and ignored every name-resolution, type
# and codegen error (defect D8). It is now just `check` restricted to test/,
# with no filtering: tkc's own exit status decides.
test-check: test-support-check $(ASSERT_TKI) $(SRC)/_floor.tk
	@echo "=== Type check all test files ==="
	@pass=0; fail=0; for f in test/*/test_*.tk; do \
	  if out=$$($(TKC) --check --diag-text -I $(SRC) -I $(ASSERT_INC) "$$f" 2>&1); then \
	    pass=$$((pass+1)); \
	  else \
	    fail=$$((fail+1)); echo "  FAIL: $$f"; echo "$$out" | sed 's/^/        /'; \
	  fi; \
	done; \
	echo "  $$pass passed, $$fail failed"; \
	[ "$$fail" = "0" ]

test-run: test-support-check $(BIN)
	@echo "=== Run test suite ==="
	@test/run_tests.sh

# print-build-vars — the single source of truth for anything that has to link
# against ooke (story 134.5). test/run_tests.sh consumes this rather than
# keeping its own copy of the stdlib list, which is how the suite drifted out
# of linkability and went unnoticed (defects D6, D24).
print-build-vars:
	@echo 'TKC="$(TKC)"'
	@echo 'TOKE_STDLIB="$(TOKE_STDLIB)"'
	@echo 'STDLIB_SRCS="$(STDLIB_SRCS)"'
	@echo 'VENDOR_SRCS="$(VENDOR_SRCS)"'
	@echo 'OOKE_LL="$(OOKE_LL)"'
	@echo 'CFLAGS="$(CFLAGS)"'
	@echo 'LDFLAGS="$(LDFLAGS)"'
	@echo 'LIBS="$(LIBS)"'

# $(SRC)/_handlers.tk is generated from pages/ and is NOT tracked (story
# 134.22, see .gitignore), so removing it here is correct: `make` regenerates it.
clean:
	rm -f $(BIN) $(MAIN_LL) $(OOKE_LL) $(OOKE_TKI) $(SRC)/_handlers.tk $(SRC)/_floor.tk \
	      $(ASSERT_TKI) $(ASSERT_LL)
	rmdir $(IFACE_DIR) 2>/dev/null || true

# ── Version and dependency gate (story 134.7) ────────────────────────────
# Single source of truth: ooke.toml [requires]. Never restate the floor here.
MIN_TOKE_VERSION := $(shell sed -n 's/^mintoke *= *"\(.*\)"/\1/p' ooke.toml)
MIN_TOKE_DATE    := $(shell sed -n 's/^mintokedate *= *"\(.*\)"/\1/p' ooke.toml)
MIN_TOKE_COMMIT  := $(shell sed -n 's/^mintokecommit *= *"\(.*\)"/\1/p' ooke.toml)
OOKE_VERSION     := $(shell cat VERSION)

.PHONY: check-versions check-toke-version check-ooke-version

check-versions: check-toke-version check-ooke-version

# Why three checks and not one semver: toke/VERSION has read 2.8.0 since
# 2026-06-21, and the v0.4 syntax break (Epic 116) plus the ADR-0010 capability
# model (Epic 124) both shipped under that same string. A semver compare alone
# therefore cannot express ooke's real floor. See docs/versioning.md.
check-toke-version:
	@set -e; \
	if [ ! -f $(TOKE_ROOT)/VERSION ]; then \
		echo "ERROR: no toke checkout at $(TOKE_ROOT) (no VERSION file)"; exit 1; \
	fi; \
	TOKE_VER=$$(cat $(TOKE_ROOT)/VERSION); \
	LOWEST=$$(printf '%s\n%s\n' "$$TOKE_VER" "$(MIN_TOKE_VERSION)" | sort -V | head -1); \
	if [ "$$LOWEST" != "$(MIN_TOKE_VERSION)" ] && [ "$$TOKE_VER" != "$(MIN_TOKE_VERSION)" ]; then \
		echo "ERROR: ooke $(OOKE_VERSION) requires toke >= $(MIN_TOKE_VERSION), found $$TOKE_VER"; exit 1; \
	fi; \
	if [ ! -f $(TOKE_STDLIB)/capabilities.c ]; then \
		echo "ERROR: $(TOKE_STDLIB)/capabilities.c is missing — that toke predates ADR-0010 (2026-07-06)."; \
		echo "       ooke links capabilities.c and compiles with src/tkc.toml [capabilities];"; \
		echo "       toke >= $(MIN_TOKE_COMMIT) ($(MIN_TOKE_DATE)) is required. See docs/versioning.md."; exit 1; \
	fi; \
	if git -C $(TOKE_ROOT) rev-parse --git-dir >/dev/null 2>&1; then \
		HEAD_SHA=$$(git -C $(TOKE_ROOT) rev-parse --short HEAD); \
		HEAD_DATE=$$(git -C $(TOKE_ROOT) log -1 --format=%cs HEAD); \
		if git -C $(TOKE_ROOT) cat-file -e $(MIN_TOKE_COMMIT)^{commit} 2>/dev/null; then \
			if ! git -C $(TOKE_ROOT) merge-base --is-ancestor $(MIN_TOKE_COMMIT) HEAD; then \
				echo "ERROR: toke $$HEAD_SHA ($$HEAD_DATE) does not contain $(MIN_TOKE_COMMIT) — ooke's floor. See docs/versioning.md."; exit 1; \
			fi; \
		elif [ "$$HEAD_DATE" \< "$(MIN_TOKE_DATE)" ]; then \
			echo "ERROR: toke $$HEAD_SHA is dated $$HEAD_DATE, before ooke's floor $(MIN_TOKE_DATE). See docs/versioning.md."; exit 1; \
		fi; \
		echo "toke $$TOKE_VER @ $$HEAD_SHA ($$HEAD_DATE) >= floor $(MIN_TOKE_VERSION) / $(MIN_TOKE_COMMIT) ($(MIN_TOKE_DATE)) OK"; \
	else \
		echo "toke $$TOKE_VER (not a git checkout; capabilities.c present) >= floor $(MIN_TOKE_VERSION) OK"; \
	fi

# The version ooke prints must match the version it declares; src/cli.tk said
# "ooke 2.0.0" for three months while VERSION moved, so this is a real gate.
check-ooke-version:
	@set -e; \
	if ! grep -q '"ooke $(OOKE_VERSION)"' src/cli.tk; then \
		echo "ERROR: VERSION is $(OOKE_VERSION) but src/cli.tk does not print it:"; \
		grep -n 'ooke [0-9]' src/cli.tk || true; exit 1; \
	fi; \
	echo "ooke $(OOKE_VERSION) declared consistently (VERSION, src/cli.tk) OK"
