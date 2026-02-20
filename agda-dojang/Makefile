# ==============================================================================
# AgdaJang Makefile
#
# @file agda-ai-prover/agda-jang/Makefile
# @version 0.2
#
# WHY this exists
# ---------------
#   Our north star is a closed loop:
#     (1) Extract structured data from Agda  →  (2) Transform to ML-ready rows
#     (3) Try tiny solving passes / search    →  (4) Log + Benchmark
#   These targets give us muscle-memory switches to run the loop end-to-end
#   on a toy example before we scale up to full libraries + models.
#
#   tl;dr
#     Build a tiny, repeatable loop:
#     (1) Extract → (2) Transform → (3) Solve/Report → (4) Benchmark/Log
#     These targets give fast feedback on the whole pipeline.
#
# Notes
# -----
#   - We route Agda interface files into _build/agda so sources stay clean.
#   - Cleaning is split into small, safe targets and a "wipe" for full reset.
#
# LAYOUT assumptions
# ------------------
#   - This file lives in: agda-ai-prover/agda-jang/Makefile
#   - Agda sources here:  agda-ai-prover/agda-jang/agda/AgdaJang/…
#   - Example data lives: agda-ai-prover/data/
#   - Scala tools live:   agda-ai-prover/proof-parser/
#   - Python tools live:  agda-ai-prover/agda-jang/python/tools/
#                         (If some scripts still live at repo root, see variables below.)
#
# Repro tips
# ----------
#   Run everything inside `nix develop` from the repo root for pinned Agda/stdlib/Scala/Python.
#
# ==============================================================================

# --- Tools / flags (overridable via environment) ---
AGDA            ?= agda
AGDA_DIR        := agda
HAVE_IFACE_DIR  := $(shell agda --help 2>/dev/null | grep -q -- '--interface-dir' && echo yes || echo no)
AGDA_IFACE_DIR  ?= _build/agda
BASE_AGDA_FLAGS := -i $(AGDA_DIR) --library-file=agda/libraries -l agda-jang
AGDA_FLAGS      := $(BASE_AGDA_FLAGS) $(if $(filter $(HAVE_IFACE_DIR),yes),--interface-dir=$(AGDA_IFACE_DIR),)
PYTHON          ?= python3
SBT             ?= sbt
PYTHON_DIR      := python
PYTHONPATH      := $(PYTHON_DIR)
PYTHON_TOOLS    := $(PYTHON_DIR)/tools
JANG_TRY        ?= $(PYTHON_TOOLS)/jang_try.py

# Extract / search scripts
EXTRACT_SCRIPT  ?= $(PYTHON_TOOLS)/jang_extract.py
SEARCH_SCRIPT   ?= $(PYTHON_TOOLS)/search.py

# --- Demo arguments ---
DEMO1 := --goal Nat --candidate "suc zero" --imports "open import Agda.Builtin.Nat"
DEMO2 := --goal Nat --tactic applyReport:_+_ --imports "open import Agda.Builtin.Nat"

# --- Data / transform paths ---
REPO_ROOT   := ..
DATA_DIR    := $(REPO_ROOT)/data
EXAMPLE_AGDA:= $(DATA_DIR)/agda/agda-example.agda
RAW_JSON    := $(DATA_DIR)/agda-example.json
TRAIN_JSONL := $(DATA_DIR)/train.jsonl
SOLVE_JSONL := $(DATA_DIR)/solve_report.jsonl

# Absolute paths for safety (don’t rely on cwd)
EXAMPLE_AGDA_ABS := $(abspath $(EXAMPLE_AGDA))
RAW_JSON_ABS     := $(abspath $(RAW_JSON))


# Scala transformer runs from the proof-parser project directory
TRANSFORM_DIR := $(REPO_ROOT)/proof-parser

# --- Housekeeping globs (only within this subproject) ---
SCRATCH_GLOBS   := .tmp_* .scratch_*
PYCACHE_GLOBS   := __pycache__ */__pycache__ $(PYTHON_DIR)/**/__pycache__
AGDAI_FIND_PATH := $(AGDA_DIR)

# Nice clean tree: hide transient/build stuff
TREE_IGNORE := '_build|.tmp_*|.scratch_*|__pycache__|*.agdai|share|.git|.direnv|.venv|.mypy_cache|.pytest_cache'

ROWS_IN  := $(REPO_ROOT)/data/tasks.jsonl
ROWS_OUT := $(REPO_ROOT)/data/rows.jsonl

.PHONY: help check demo demo1 demo2 extract transform solve test \
        clean clean-scratch clean-pycache clean-agda clean-build clean-data \
        wipe tree peek-extract


# ------------------------------------------------------------------------------

test:
	@echo ">> Running Python unit tests (rendering)"
	PYTHONPATH=$(PYTHONPATH) pytest -q

help:
	@echo ""
	@echo "AgdaJang targets:"
	@echo "  make check        - Type-check AgdaJang macros"
	@echo "  make demo1        - Run simple candidate: suc zero : Nat"
	@echo "  make demo2        - Run reporting tactic: applyReport:_+_"
	@echo ""
	@echo "End-to-end loop (toy example):"
	@echo "  make extract      - Agda → JSON (AGDA2TRAIN-style) at $(RAW_JSON)"
	@echo "  make transform    - JSON → JSONL (ML-ready) at $(TRAIN_JSONL)"
	@echo "  make solve        - Tiny benchmark run → $(SOLVE_JSONL) (uses search/runner)"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean        - Remove scratch, __pycache__, stray .agdai"
	@echo "  make wipe         - HARD reset: also _build + generated data"
	@echo "  make tree         - Pretty tree view (ignores build/cache/junk)"
	@echo ""
	@echo "Tips: run inside 'nix develop'; override AGDA_FLAGS if needed."
	@echo "      Current AGDA_FLAGS: '$(AGDA_FLAGS)'"

# ------------------------------------------------------------------------------

# --- Makefile Hygiene --------------------------------------------------------
# Probe all PROBE targets: try all declared targets, keep going, write a
# summary. Usage: make probe-all PROBE_JOBS=1 (or higher, but start at 1)
PROBE_JOBS ?= 1
PROBE_TARGETS := check peek-extract test-python-unittest test-python \
                 eval-proof-completion eval-proof-completion-smoke demo-agent-bridge \
                 extract demo demo1 demo2 rows help tree transform solve test

LOG_DIR := probe-logs
probe-all:
	@mkdir -p "$(LOG_DIR)"
	@echo "→ probe-all: attempting (almost) all targets; logs in $(LOG_DIR)"
	@set +e; \
	fail=0; \
	for t in $(PROBE_TARGETS); do \
	  echo "------------------------------------------------------------"; \
	  echo ">>> make $$t"; \
	  log="$(LOG_DIR)/probe.$$t.log"; \
	  $(MAKE) --no-print-directory $$t >"$$log" 2>&1; \
	  rc="$$?"; \
	  if [ "$$rc" -ne 0 ]; then \
	    echo "✖ $$t (rc=$$rc)"; \
	    tail -n 30 "$$log" || true; \
	    fail=1; \
	  else \
	    echo "✓ $$t"; \
	  fi; \
	done; \
	exit "$$fail"


# 0) Compile-time health check for our Agda macros
check:
	$(AGDA) $(AGDA_FLAGS) $(AGDA_DIR)/AgdaJang/Everything.agda

# 1) Demos (use jang_try.py). We forward the same AGDA_FLAGS the compiler uses.
demo: demo1 demo2

demo1:
	PYTHONPATH=$(PYTHONPATH) $(PYTHON) $(JANG_TRY) $(DEMO1) --agda-flags "$(AGDA_FLAGS)"

demo2:
	PYTHONPATH=$(PYTHONPATH) $(PYTHON) $(JANG_TRY) $(DEMO2) --agda-flags "$(AGDA_FLAGS)"

# 2) The agent bridge is a sanity check for the whole loop (Agda → Python agent → Agda)
#    on a fixed example before we add any model.
FIXTURE_DIR := $(REPO_ROOT)/data/agda
FIXTURE_IN  := $(FIXTURE_DIR)/FixtureHoles.agda
FIXTURE_OUT := $(abspath _build/FixtureHoles.agda)
#
# --- Proof-completion evaluator knobs (overridable) ---
EVAL_FIXTURES   ?= $(FIXTURE_DIR)/Fixture*.agda
EVAL_OUT_DIR    ?= _build/eval-proof-completion
EVAL_RUN_ID     ?= latest
EVAL_POLICY     ?= $(PYTHON) python/tools/policy_fixture.py
EVAL_MAX_HOLES  ?= 4
EVAL_K          ?= 5
EVAL_TIMEOUT    ?= 20
EVAL_REPORT_EXPR?= reportGoalCtx
EVAL_CLEAN      ?= 1
EVAL_XFAIL      ?=
# ^ after support for this is added in eval_fixtures.py
EVAL_CLEAN_FLAG := $(if $(filter 1,$(EVAL_CLEAN)),--clean,)
#
# 2.1) Run the agent bridge on the fixture file, keeping the workdir for inspection.
demo-agent-bridge:
	@mkdir -p _build
	PYTHONPATH=$(PYTHONPATH) $(PYTHON) python/tools/agent_bridge.py \
	  --input "$(FIXTURE_IN)" \
	  --output "$(FIXTURE_OUT)" \
	  --policy "$(EVAL_POLICY)" \
	  --max-holes "$(EVAL_MAX_HOLES)" \
	  --keep-workdir \
	  --k "$(EVAL_K)" \
	  --agda-bin "$(AGDA)" \
	  --agda-flags "$(AGDA_FLAGS) -i $(FIXTURE_DIR)" \
	  --report-expr "$(EVAL_REPORT_EXPR)"
	$(AGDA) $(AGDA_FLAGS) -i "$(dir $(FIXTURE_OUT))" "$(FIXTURE_OUT)"
#
# 2.2) Run the full eval loop on the fixture file, writing JSONL + logs + scoreboard.
## eval-proof-completion: Run fixture evaluator; writes JSONL + logs + scoreboard.
eval-proof-completion:
	@mkdir -p "$(EVAL_OUT_DIR)"
	PYTHONPATH=$(PYTHONPATH) $(PYTHON) python/tools/eval_fixtures.py \
	  --fixtures "$(EVAL_FIXTURES)" \
	  --out-dir "$(EVAL_OUT_DIR)" \
	  --run-id "$(EVAL_RUN_ID)" \
	  $(EVAL_CLEAN_FLAG) \
	  --policy "$(EVAL_POLICY)" \
	  --max-holes "$(EVAL_MAX_HOLES)" \
	  --k "$(EVAL_K)" \
	  --timeout "$(EVAL_TIMEOUT)" \
	  --agda-bin "$(AGDA)" \
	  --agda-flags "$(AGDA_FLAGS) -i $(FIXTURE_DIR)" \
	  --report-expr "$(EVAL_REPORT_EXPR)"
#
## demo-proof-completion: Alias for eval-proof-completion (kept for docs/checklists).
demo-proof-completion: eval-proof-completion
#
# 2.3) A smoke test with tighter limits for quick feedback (e.g., in CI).
eval-proof-completion-smoke:
	$(MAKE) eval-proof-completion \
	  EVAL_FIXTURES="$(FIXTURE_DIR)/Fixture01.agda" \
	  EVAL_RUN_ID=smoke \
	  EVAL_MAX_HOLES=2 EVAL_K=3 EVAL_TIMEOUT=10

# 3) Extract: produce intermediate JSON from an example Agda file
#    WHY: Stabilize a canonical intermediate we can diff/test before transforming.
$(DATA_DIR):
	mkdir -p $(DATA_DIR)

extract: | $(DATA_DIR)
	@command -v $(PYTHON) >/dev/null || { echo "Python not found"; exit 1; }
	@if [ ! -f "$(EXAMPLE_AGDA_ABS)" ]; then \
	  echo "ERROR: $(EXAMPLE_AGDA_ABS) not found. Put a sample there or update EXAMPLE_AGDA."; \
	  exit 1; \
	fi
	@if [ ! -s "$(EXAMPLE_AGDA_ABS)" ]; then \
	  echo "ERROR: $(EXAMPLE_AGDA_ABS) exists but is empty; add content."; \
	  exit 1; \
	fi
	@if [ ! -f "$(EXTRACT_SCRIPT)" ]; then \
	  echo "ERROR: EXTRACT_SCRIPT '$(EXTRACT_SCRIPT)' not found. Update the path (e.g., to $(PYTHON_TOOLS)/jang_extract.py)."; \
	  exit 1; \
	fi
	@echo ">> CWD           : $$(pwd)"
	@echo ">> INPUT (Agda)  : $(EXAMPLE_AGDA_ABS)"
	@echo ">> OUTPUT (JSON) : $(RAW_JSON_ABS)"
	PYTHONPATH=$(PYTHONPATH) $(PYTHON) $(EXTRACT_SCRIPT) \
	  --input  "$(EXAMPLE_AGDA_ABS)" \
	  --output "$(RAW_JSON_ABS)"
	@[ -s "$(RAW_JSON_ABS)" ] || { \
	   echo "❌ Extractor returned but $(RAW_JSON_ABS) is missing or empty."; \
	   exit 1; \
	}
	@echo "✅ Wrote $(RAW_JSON_ABS)"

# a tiny "peek" target to verify content
peek-extract:
	@echo ">> head of $(RAW_JSON_ABS)"; head -n 40 "$(RAW_JSON_ABS)" || true


# 4) Transform: run Scala transformer to emit ML-ready JSONL
#    WHY: Freeze the training-row schema (e.g., file/module/name/agdaType/proof/premises).
transform:
	@command -v $(SBT) >/dev/null || { echo "sbt not found (use nix shell or install sbt)"; exit 1; }
	@if [ ! -d "$(TRANSFORM_DIR)" ]; then \
	  echo "ERROR: $(TRANSFORM_DIR) not found. Update TRANSFORM_DIR."; \
	  exit 1; \
	fi
	@if [ ! -f "$(RAW_JSON)" ]; then \
	  echo "ERROR: $(RAW_JSON) not found. Run 'make extract' first."; \
	  exit 1; \
	fi
	cd $(TRANSFORM_DIR) && \
	  $(SBT) 'runMain proofparser.Agda2TrainTransformer ../data/agda-example.json ../data/train.jsonl'
	@echo "✅ Wrote $(TRAIN_JSONL)"

# 5) Solve: tiny benchmark loop (stub-friendly)
#    WHY: Quick pass/fail snapshot on a fixed suite before we add any model.
solve:
	@command -v $(PYTHON) >/dev/null || { echo "Python not found"; exit 1; }
	@if [ ! -f "$(SEARCH_SCRIPT)" ]; then \
	  echo "ERROR: SEARCH_SCRIPT '$(SEARCH_SCRIPT)' not found."; \
	  exit 1; \
	fi
	@echo ">> running search (this may legitimately find no proof)"
	@PYTHONPATH=$(PYTHONPATH) $(PYTHON) $(SEARCH_SCRIPT) \
	  --agda-dir "$(AGDA_DIR)" \
	  --agda-bin "$(AGDA)" \
	  --jang-try "$(JANG_TRY)" \
	  --imports "open import Agda.Builtin.Nat" \
	  --goal "Nat" \
	  --max-depth 3 \
	  --beam 8 ; \
	rc=$$?; \
	if [ $$rc -eq 0 ]; then \
	  echo "✅ Solve run complete"; \
	else \
	  echo "ℹ️  No proof found within limits (exit $$rc) — not fatal for bench."; \
	fi

# 6) Pretty-print a *clean* directory tree for this subproject.
#    Uses the 'tree' utility if available; otherwise falls back to a portable renderer.
tree:
	@echo ">> Clean directory tree (excluding: $(TREE_IGNORE))"
	@if command -v tree >/dev/null 2>&1; then \
	  tree -a -I "$(TREE_IGNORE)" -F; \
	else \
	  echo "(hint: install 'tree' for nicer output)"; \
	  find . \
	    -path "./_build" -prune -o \
	    -path "./agda/share" -prune -o \
	    -path "*/__pycache__" -prune -o \
	    -name ".tmp_*" -prune -o \
	    -name ".scratch_*" -prune -o \
	    -name "*.agdai" -prune -o \
	    -name ".git" -prune -o \
	    -name ".direnv" -prune -o \
	    -name ".venv" -prune -o \
	    -name ".mypy_cache" -prune -o \
	    -name ".pytest_cache" -prune -o \
	    -print \
	    | sed -e 's|^\./||' \
	    | awk -F/ '{ \
	        indent=\"\"; \
	        for (i=1;i<NF;i++) indent=indent\"  \"; \
	        print indent \"└─ \" $$NF \
	      }'; \
	fi

# 7) Generate baseline rows from a tiny seed tasks.jsonl (if missing)
rows:
	@command -v $(PYTHON) >/dev/null || { echo "Python not found"; exit 1; }
	@if [ ! -f "$(ROWS_IN)" ]; then \
	  echo 'Creating a tiny seed tasks.jsonl...'; \
	  mkdir -p $(DATA_DIR); \
	  printf '{"imports":["open import Agda.Builtin.Nat"], "goal":"Nat", "candidate":"suc zero"}\n' > $(ROWS_IN); \
	  printf '{"imports":["open import Agda.Builtin.Nat"], "goal":"Nat", "tactic":"applyReport:_+_"}\n' >> $(ROWS_IN); \
	  printf '{"imports":["open import Agda.Builtin.Nat","open import Agda.Builtin.Bool"], "goal":"Nat", "candidate":"true"}\n' >> $(ROWS_IN); \
	fi
	$(PYTHON) $(PYTHON_TOOLS)/prompt_baseline.py \
	  $(ROWS_IN) $(ROWS_OUT) \
	  --agda-flags "$(AGDA_FLAGS)"
	@echo "✅ Wrote $(ROWS_OUT)"


## test-python: Run Python unittests with friendly output.
test-python-unittest:
	PYTHONPATH=python python3 python/utils/run_unittests.py

## test-python: Run Python tests (pytest runs both pytest + unittest tests).
test-python:
	PYTHONPATH=python python3 -m pytest -q python/tests

# ------------------------------------------------------------------------------

# Cleaning (small brooms)
clean: clean-scratch clean-pycache clean-agda
	@echo "✅ Cleaned scratch, pycache, and stray .agdai"

clean-scratch:
	rm -rf $(SCRATCH_GLOBS)

clean-pycache:
	# Local pycaches only (don’t touch outside this subproject)
	find . -type d -name '__pycache__' -prune -exec rm -rf {} +

clean-agda:
	# If interfaces are centralized, this is a no-op except _build
	@if [ -d "$(AGDA_IFACE_DIR)" ]; then rm -rf "$(AGDA_IFACE_DIR)"; fi
	# Also delete any stray .agdai beside sources (defensive)
	@if [ -d "$(AGDAI_FIND_PATH)" ]; then find "$(AGDAI_FIND_PATH)" -name '*.agdai' -delete; fi

# Big broom: also remove build dir + generated data
wipe: clean
	# Remove build dir(s) and local share cache if present
	rm -rf _build
	@if [ -d "agda/share" ]; then rm -rf agda/share; fi
	# Generated data artifacts (safe to regenerate)
	@if [ -f "$(RAW_JSON)"     ]; then rm -f "$(RAW_JSON)";     fi
	@if [ -f "$(TRAIN_JSONL)"  ]; then rm -f "$(TRAIN_JSONL)";  fi
	@if [ -f "$(SOLVE_JSONL)"  ]; then rm -f "$(SOLVE_JSONL)";  fi
	@echo "🧹 wipe complete"
