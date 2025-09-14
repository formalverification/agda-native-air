##
# AgdaJang Makefile
#
# @file ./agda-jang/Makefile
# @version 0.2
# @copyright 2025 Thmpr
# WHY this exists:
#   Our north star is a closed loop:
#     (1) Extract structured data from Agda  →  (2) Transform to ML-ready rows
#     (3) Try tiny solving passes / search    →  (4) Log + Benchmark
#   These targets give you muscle-memory switches to run the loop end-to-end
#   on a toy example before we scale up to full libraries + models.
#
# LAYOUT assumptions:
#   - This file lives in: agda-ai-prover/agda-jang/Makefile
#   - Agda sources here:  agda-ai-prover/agda-jang/agda/AgdaJang/…
#   - Example data lives: agda-ai-prover/data/
#   - Scala tools live:   agda-ai-prover/proof-parser/
#   - Python tools live:  agda-ai-prover/agda-jang/python/tools/
#                         (If some scripts still live at repo root, see variables below.)
#
# Repro tip:
#   Run everything inside `nix develop` from the repo root for pinned Agda/stdlib/Scala/Python.
#
# ------------------------------------------------------------------------------

# --- Tools / flags (overridable via environment) ---
AGDA        ?= agda
AGDA_FLAGS  ?= -l agda-jang        # Provided by flake shell; resolves stdlib + this project

PYTHON      ?= python3
SBT         ?= sbt

# --- Project paths (relative to this Makefile in agda-jang/) ---
AGDA_DIR        := agda
PYTHON_DIR      := python
PYTHONPATH      := $(PYTHON_DIR)
PYTHON_TOOLS    := $(PYTHON_DIR)/tools

# Primary runner used by demos / solve
JANG_TRY        ?= $(PYTHON_TOOLS)/jang_try.py

# If your extractor/search scripts still live at the repo root,
# set these to "../jang_extract.py", "../search.py", etc.
EXTRACT_SCRIPT  ?= $(PYTHON_TOOLS)/jang_extract.py
SEARCH_SCRIPT   ?= $(PYTHON_TOOLS)/search.py

# --- Demo arguments ---
DEMO1 := --goal Nat --candidate "suc zero" --imports "open import Agda.Builtin.Nat"
DEMO2 := --goal Nat --tactic applyReport:_+_ --imports "open import Agda.Builtin.Nat"

# --- Data / transform paths ---
REPO_ROOT   := ..
DATA_DIR    := $(REPO_ROOT)/data
EXAMPLE_AGDA:= $(DATA_DIR)/agda-example.agda
RAW_JSON    := $(DATA_DIR)/agda-example.json
TRAIN_JSONL := $(DATA_DIR)/train.jsonl

# Scala transformer runs from the proof-parser project directory
TRANSFORM_DIR := $(REPO_ROOT)/proof-parser

# ------------------------------------------------------------------------------

.PHONY: check clean demo demo1 demo2 extract help solve test transform

test:
	@echo ">> Running Python unit tests (rendering)"
	PYTHONPATH=python pytest -q

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
	@echo "  make solve        - Tiny benchmark run (uses search/runner)"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean        - Remove temp scratch dirs and __pycache__"
	@echo ""
	@echo "Tips: run inside 'nix develop' at repo root; override vars like AGDA_FLAGS if needed."

# ------------------------------------------------------------------------------

# 1) Compile-time health check for our Agda macros
check:
	$(AGDA) $(AGDA_FLAGS) $(AGDA_DIR)/AgdaJang/Everything.agda

# 2) Demos (use jang_try.py). We forward the same AGDA_FLAGS the compiler uses.
demo: demo1 demo2

demo1:
	$(PYTHON) $(JANG_TRY) $(DEMO1) --agda-flags "$(AGDA_FLAGS)"

demo2:
	$(PYTHON) $(JANG_TRY) $(DEMO2) --agda-flags "$(AGDA_FLAGS)"

# ------------------------------------------------------------------------------

# 3) Extract: produce intermediate JSON from an example Agda file
#    WHY: Stabilize a canonical intermediate we can diff/test before transforming.
$(DATA_DIR):
	mkdir -p $(DATA_DIR)

extract: | $(DATA_DIR)
	@command -v $(PYTHON) >/dev/null || { echo "Python not found"; exit 1; }
	@if [ ! -f "$(EXAMPLE_AGDA)" ]; then \
	  echo "ERROR: $(EXAMPLE_AGDA) not found. Put a sample there or update EXAMPLE_AGDA."; \
	  exit 1; \
	fi
	@if [ ! -f "$(EXTRACT_SCRIPT)" ]; then \
	  echo "ERROR: EXTRACT_SCRIPT '$(EXTRACT_SCRIPT)' not found. Update the path (e.g., to $(PYTHON_TOOLS)/jang_extract.py)."; \
	  exit 1; \
	fi
	$(PYTHON) $(EXTRACT_SCRIPT) \
	  --input  "$(EXAMPLE_AGDA)" \
	  --output "$(RAW_JSON)"
	@echo "✅ Wrote $(RAW_JSON)"

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
	  echo "ERROR: SEARCH_SCRIPT '$(SEARCH_SCRIPT)' not found. Update it (e.g., to ../search.py if still at repo root)."; \
	  exit 1; \
	fi
	@if [ ! -f "$(EXAMPLE_AGDA)" ]; then \
	  echo "ERROR: $(EXAMPLE_AGDA) not found. Put a sample there or update EXAMPLE_AGDA."; \
	  exit 1; \
	fi
	$(PYTHON) $(SEARCH_SCRIPT) \
	  --suite  "$(EXAMPLE_AGDA)" \
	  --report "$(DATA_DIR)/solve_report.jsonl" \
	  --agda-flags "$(AGDA_FLAGS)"
	@echo "✅ Solve report at $(DATA_DIR)/solve_report.jsonl"

# ------------------------------------------------------------------------------

# Clean up scratch dirs (jang_try.py creates .tmp_* or .scratch_*), plus py caches
clean:
	rm -rf .tmp_* .scratch_* __pycache__ */__pycache__
# end
