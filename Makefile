# toke-ooke Makefile — toke-only build (story 56.8.2)
#
# All ooke source is now toke (.tk). Build pipeline:
#   1. Compile each module to .tki (interface) + .ll (LLVM IR)
#   2. Compile main.tk to .ll
#   3. Link all .ll + stdlib C + vendor C into the ooke binary

TKC         := /Users/matthew.watt/tk/toke/toke
TOKE_ROOT   := /Users/matthew.watt/tk/toke
TOKE_STDLIB := $(TOKE_ROOT)/src/stdlib
TOKE_VENDOR := $(TOKE_ROOT)/stdlib/vendor

BIN := ooke-toke
SRC := src

# ── Stdlib C sources required by ooke ─────────────────────────────────────
STDLIB_SRCS := \
  $(TOKE_STDLIB)/str.c \
  $(TOKE_STDLIB)/file.c \
  $(TOKE_STDLIB)/env.c \
  $(TOKE_STDLIB)/log.c \
  $(TOKE_STDLIB)/http.c \
  $(TOKE_STDLIB)/router.c \
  $(TOKE_STDLIB)/ws.c \
  $(TOKE_STDLIB)/encoding.c \
  $(TOKE_STDLIB)/tk_web_glue.c \
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
  $(TOKE_STDLIB)/security.c \
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
  $(TOKE_STDLIB)/collections.c

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

BASE_MODS    := config store router template validate repair run
DERIVED_MODS := build serve
API_MODS     := apihealth
ALL_MODS     := $(BASE_MODS) $(DERIVED_MODS) $(API_MODS)

OOKE_LL  := $(addprefix $(IFACE_DIR)/,$(ALL_MODS))
OOKE_TKI := $(addprefix $(IFACE_DIR)/,$(addsuffix .tki,$(ALL_MODS)))
MAIN_LL  := $(SRC)/main.ll

# ── Rules ─────────────────────────────────────────────────────────────────
.PHONY: all clean interfaces check

all: $(BIN)

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
    $(IFACE_DIR)/template.tki $(IFACE_DIR)/store.tki | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ooke/serve serve.tk

# ── API modules ─────────────────────────────────────────────────────────
$(IFACE_DIR)/apihealth.tki $(IFACE_DIR)/apihealth: $(SRC)/apihealth.tk | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out ooke/apihealth apihealth.tk

# ── main.ll ──────────────────────────────────────────────────────────────
$(MAIN_LL): $(SRC)/main.tk $(OOKE_TKI) | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-llvm --out main.ll main.tk

# ── Final binary ─────────────────────────────────────────────────────────
$(BIN): $(MAIN_LL) $(OOKE_LL)
	clang $(CFLAGS) $(LDFLAGS) -x ir $(MAIN_LL) $(OOKE_LL) \
	  -x c $(STDLIB_SRCS) $(VENDOR_SRCS) \
	  -o $@ $(LIBS)

interfaces: $(OOKE_TKI)

check:
	@for f in $(SRC)/config.tk $(SRC)/store.tk $(SRC)/router.tk \
	           $(SRC)/template.tk $(SRC)/validate.tk $(SRC)/repair.tk $(SRC)/build.tk $(SRC)/serve.tk \
	           $(SRC)/run.tk \
	           $(SRC)/apihealth.tk $(SRC)/main.tk; do \
	  echo "--- $$f"; \
	  cd $(SRC) && $(TKC) --check $$(basename $$f) 2>&1 | head -5 || true; \
	  cd ..; \
	done

clean:
	rm -f $(BIN) $(MAIN_LL) $(OOKE_LL) $(OOKE_TKI)
	rmdir $(IFACE_DIR) 2>/dev/null || true

# ── Version check ────────────────────────────────────────────────────────
MIN_TOKE_VERSION := 2.0.0
check-toke-version:
	@if [ -f $(TOKE_ROOT)/VERSION ]; then \
		TOKE_VER=$$(cat $(TOKE_ROOT)/VERSION); \
		TOKE_MAJ=$$(echo $$TOKE_VER | cut -d. -f1); \
		MIN_MAJ=$$(echo $(MIN_TOKE_VERSION) | cut -d. -f1); \
		if [ "$$TOKE_MAJ" -lt "$$MIN_MAJ" ]; then \
			echo "ERROR: ooke v$$(cat VERSION) requires toke >= $(MIN_TOKE_VERSION), found $$TOKE_VER"; \
			exit 1; \
		fi; \
		echo "toke $$TOKE_VER >= $(MIN_TOKE_VERSION) ✓"; \
	else \
		echo "WARNING: toke VERSION file not found, skipping version check"; \
	fi
