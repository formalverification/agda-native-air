# =============================================================================
# Makefile
# -----------------------------------------------------------------------------
#
# @file agda-native-air/Makefile
# @version 1.0
#
# Description
# -----------
# The top-level Makefile for the agda-native-air project.
#
# Purpose
# -------
#   A single CLI to run the end-to-end loop:
#     1) Extract  (Scala)         : .agda -> raw JSON / JSONL
#     2) Transform (Scala)        : raw JSON -> ML rows (JSONL)
#     3) ETL (Spark or PyArrow)   : JSONL -> Parquet features
#     4) Train (Python)           : features -> model checkpoint
#     5) Serve                    : [archived — see experiments/archive/]
#     6) Bench (AgdaDojang)         : verify suggestions in Agda
#
# Usage
# -----
# Run `make help` to see a list of make targets, optional flags and parameters.
#
# =============================================================================

# =============================================================================
# GLOBAL CONFIGURATION

SHELL := /bin/bash

# ------------------------------------------------------------------------------
# PYTHON
PY                ?= python3
PROJECT_ROOT      := $(PWD)
VENV              ?= $(PROJECT_ROOT)/ml-pipeline/.venv
PIP               ?= $(VENV)/bin/pip
PYTHON            ?= $(VENV)/bin/python
UVICORN           ?= $(VENV)/bin/uvicorn
PY_RUN             = env LD_LIBRARY_PATH="$(WHEEL_LD_LIBRARY_PATH):$$LD_LIBRARY_PATH" $(PYTHON)
#
# --- Environment / venv strategy ---
# USE_VENV=0          : assume we've already activated an env (conda, Nix shell, etc.)
# USE_VENV=1 (default): create/use project-local venv at $(VENV)
USE_VENV ?= 1
ifeq ($(USE_VENV),0)
  PYTHON := $(PY)
  VENV_DEPS :=
else
  VENV_DEPS := $(VENV)
endif
#
# --- Python / pip knobs ---
PIP_QUIET     ?= -q
REQS_FILE     ?= ml-pipeline/python/requirements.txt
CI_SKIP_ML ?= 0
# In CI we run Python tests in the dedicated python job; skip torch/venv here.
#
# --- Torch install mode ---
TORCH_MODE ?= cpu
ifeq ($(TORCH_MODE),cpu)
  TORCH_INDEX   ?= https://download.pytorch.org/whl/cpu
  TORCH_SPEC    ?= torch
  TORCH_INSTALL ?= $(PIP) install $(PIP_QUIET) --prefer-binary $(TORCH_SPEC) --extra-index-url $(TORCH_INDEX)
else ifeq ($(TORCH_MODE),pypi)
  TORCH_SPEC    ?= torch
  TORCH_INSTALL ?= $(PIP) install $(PIP_QUIET) --prefer-binary $(TORCH_SPEC)
else ifeq ($(TORCH_MODE),skip)
  TORCH_INSTALL ?= true
endif


# ------------------------------------------------------------------------------
# ML Benchmark Settings
TOP               ?= 20
K                 ?= 10
SPLIT             ?= 90
MIN_TYPE_LEN      ?=0
MIN_PROOF_LEN     ?=0

# ------------------------------------------------------------------------------
# SCALA/SPARK
#
# Spark local[*] can saturate all cores and starve Cats Effect / OS scheduling.
# Default to a smaller local[N]; override as needed:
#   make extract-lib EXTRACT_SPARK_MASTER=local[8]
EXTRACT_SPARK_MASTER ?= local[4]
# You can also tune extractor parallelism at the CLI (make target may already have PARALLELISM)
# PARALLELISM ?= 12
#
# Logging (log4j2): Spark 3.x uses log4j2; we force a repo-wide config to limit console output.
LOG4J2_CONFIG ?= $(PROJECT_ROOT)/configs/log4j2.properties
SBT ?= sbt
SBT_FLAGS ?= -Dsbt.supershell=false
SBT_DEBUG ?= 0
ifeq ($(SBT_DEBUG),1)
  SBT_FLAGS += -debug
endif
SBT_FLAGS_DEBUG ?= -error -no-colors -batch -Dsbt.supershell=false -debug
PAR ?= $(shell nproc 2>/dev/null || echo 8)
JMO := --add-opens=java.base/java.io=ALL-UNNAMED \
	   --add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
	   --add-opens=java.base/sun.nio.cs=ALL-UNNAMED \
	   --add-opens=java.base/sun.security.action=ALL-UNNAMED \
	   --add-opens=java.base/sun.util.calendar=ALL-UNNAMED \
	   --add-opens=java.security.jgss/sun.security.krb5=ALL-UNNAMED \
	   -Dlog4j.configurationFile=$(LOG4J2_CONFIG)
SPARK_SUBMIT ?= spark-submit
UVICORN ?= uvicorn
#
# pick up JAVA_HOME if it’s set by nix develop, else fail loudly
SBT_JAVA_HOME ?= $(JAVA_HOME)
SBT_RUNNER    ?= $(PROJECT_ROOT)/scripts/run-sbt.sh
#
# Add log4j2 config to the JVM options we already pass through JAVA_TOOL_OPTIONS.
# Note: log4j2 uses the system property name 'log4j.configurationFile'
JMO_LOGGING := $(JMO)
#
# helper: run sbt on a specific JDK (also forces PATH so spawned java matches)
define run_sbt_on_jdk
  env JAVA_HOME="$(SBT_JAVA_HOME)" \
      PATH="$(SBT_JAVA_HOME)/bin:$$PATH" \
      JAVA_TOOL_OPTIONS="$(JMO)" \
      sbt -java-home "$(SBT_JAVA_HOME)" $(1)
endef
#



# ------------------------------------------------------------------------------
# PROJECT DIRS
DATA                    := $(PROJECT_ROOT)/data
RAW_JSON                ?= $(DATA)/agda-example.json
DATA_TRAIN              ?= $(DATA)/train.jsonl
TRAIN_DATA              ?= $(DATA_TRAIN)
DATA_A2T_SIMPLE         ?= $(DATA)/a2t.simple.jsonl
SAMPLE_JSONL            ?= $(DATA)/sample.jsonl
DATA_FILTERED           ?= $(DATA)/train.filtered.jsonl
DATA_FINE_TUNE          ?= $(DATA)/finetune.jsonl
DATA_STDLIB             ?= $(DATA)/train-stdlib-2.2.jsonl
DATA_ALGEBRAS           ?= $(DATA)/train-algebras.jsonl
DATA_CATEGORIES         ?= $(DATA)/train-categories.jsonl
DATA_ALGEBRAS_RAW       ?= $(DATA)/agda-algebras/raw
DATA_ALGEBRAS_JSON      ?= $(DATA)/agda-algebras/json
JSONL_IN                ?= $(DATA_ALGEBRAS_RAW)
JSONL_OUT               ?= $(DATA_ALGEBRAS_RAW)/processed
AGDA_DATA               ?= $(DATA)/agda

# ------------------------------------------------------------------------------
# Nix wrappers that are immune to LD_LIBRARY_PATH poisoning
NIX ?= nix
HASH := \#
# When we run nested `nix develop` from inside a shell that sets LD_LIBRARY_PATH
# (e.g. the default dev shell), nix/curl can explode due to openssl symbol mismatches.
NIX_CLEAN_ENV := env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH
NIX_BACKEND := $(NIX_CLEAN_ENV) $(NIX) develop .$(HASH)backend -c bash -lc
NIX_ALL     := $(NIX_CLEAN_ENV) $(NIX) develop .$(HASH)all     -c bash -lc

# Allow CI to force “no nix”, but also auto-fallback if nix isn't installed.
BACKEND_USE_NIX ?= 1
define run_backend
  if [ "$(BACKEND_USE_NIX)" = "1" ] && command -v "$(NIX)" >/dev/null 2>&1; then \
    $(NIX_BACKEND) '$(1)'; \
  else \
    bash -lc '$(1)'; \
  fi
endef
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# CORPUS EXTRACTION
#
# Outputs under: data/agda-algebras/
LIB_NAME            ?= agda-algebras
LIB_DATA_ROOT       ?= $(DATA)/$(LIB_NAME)
LIB_OUT_ROOT        ?= $(LIB_DATA_ROOT)
LIB_RAW_DIR         ?= $(LIB_DATA_ROOT)/raw
LIB_RAW_ROOT        ?= $(LIB_RAW_DIR)
LIB_JSONL_DIR       ?= $(LIB_RAW_DIR)/jsonl
LIB_LOG_DIR         ?= $(LIB_RAW_DIR)/logs
LIB_MANIFEST_DIR    ?= $(LIB_DATA_ROOT)/manifests
#
# Corpus spec (modules list)
LIB_CORPUS_META_DIR ?= $(DATA)/corpora-metadata/$(LIB_NAME)
LIB_MODULES_FILE    ?= $(LIB_CORPUS_META_DIR)/everything-modules.txt
#
# Extraction inputs
LIB_SRC_DIR         ?= $(AGDA_ALGEBRAS_SRC)
LIB_AGDA_DIR        ?= $(AGDA_LIB_DIR)          # directory containing Agda libraries/defaults file
LIB_PAR             ?= $(PAR)
LIB_RESUME          ?= $(RESUME)
#
# Ensure modules file exists (or generate it).
# Existing target writes into $(AGDA_LIB_METADATA_OUT) and produces everything-modules.txt
$(LIB_MODULES_FILE): agda-algebras-metadata
	@test -s "$(LIB_MODULES_FILE)" || { \
	  echo "ERROR: modules file missing/empty: $(LIB_MODULES_FILE)"; \
	  exit 1; \
	}
#

# -- Strux driver (Scala) --
STRUX_DRIVER            := $(PROJECT_ROOT)/strux-driver
STRUX_DRIVER_DIR        ?= $(STRUX_DRIVER)
STRUX_DRIVER_RESOURCES  := $(STRUX_DRIVER)/src/test/resources

# -- ML pipeline --
ML_PIPE                 := $(PROJECT_ROOT)/ml-pipeline
ML_PIPE_DATA            := $(ML_PIPE)/data
ML_PIPE_FEATURES        := $(ML_PIPE)/features
ML_PIPE_MODELS          := $(ML_PIPE)/models
ML_PIPE_PY              ?= $(ML_PIPE)/python
ML_PIPE_API             ?= $(ML_PIPE_PY)/api
ML_PIPE_PY_MODEL        ?= $(ML_PIPE_PY)/model
ML_PIPE_PY_SCRIPTS      ?= $(ML_PIPE_PY)/scripts

# -- Example input / A2T defaults --
AGDA_FILE               ?= agda-example
EXAMPLE_AGDA            ?= $(AGDA_DATA)/$(AGDA_FILE).agda
EXTRACT_INPUT           ?= $(EXAMPLE_AGDA)
A2T_JSON_INPUT          ?= $(STRUX_DRIVER_RESOURCES)/struxdriver/$(AGDA_FILE).json
A2T_OUT                 ?= $(PROJECT_ROOT)/target/a2t.simple.jsonl

# -- Columnar features -- (Parquet)
TRAIN_PARQUET           ?= $(ML_PIPE_FEATURES)/train.parquet

# -- Model checkpoint -- (PyTorch by default).
MODEL_CKPT              ?= $(ML_PIPE_MODELS)/model.pt

# -------------------------------------------------------------------------------
# AgdaJsonlDriver args:
# For passing arguments to Scala programs with helper so $$AGDA_JSON_BIN expands in
# shell, but is a single arg in sbt:
#   - AGDA_JSONL_ARGS_BASE: required args (do not override)
#   - AGDA_JSONL_ARGS: extra args appended by caller (safe), e.g. "--format human"
# -------------------------------------------------------------------------------
AGDA_STDLIB_ROOT        ?= $(HOME)/git/LANG/AGDA/agda-stdlib-2.2
AGDA_STDLIB_SRC         ?= $(AGDA_STDLIB_ROOT)/src
AGDA_ALGEBRAS_ROOT      ?= $(HOME)/git/ualib/agda-algebras/master
AGDA_ALGEBRAS_SRC       ?= $(AGDA_ALGEBRAS_ROOT)/src
AGDA_CATEGORIES_ROOT    ?= $(HOME)/git/LANG/AGDA/agda-categories
AGDA_CATEGORIES_SRC     ?= $(AGDA_CATEGORIES_ROOT)/src
#
# -- agda_lib_metadata.py is a script for generating metadata about Agda libraries
AGDA_LIB_METADATA_SCRIPT    := $(PROJECT_ROOT)/scripts/python/agda_lib_metadata.py
AGDA_LIB_METADATA_OUT       ?= $(DATA)/corpora-metadata/agda-algebras
AGDA_ALGEBRAS_MODULES_FILE  ?= $(AGDA_LIB_METADATA_OUT)/everything-modules.txt
#
# What the driver calls "--agda-dir".
# Should be "directory containing the Agda libraries file".
# flake.nix writes: $(PROJECT_ROOT)/agda-dojang/agda/libraries
AGDA_DOJANG               := $(PROJECT_ROOT)/agda-dojang
AGDA_DOJANG_AGDA          ?= $(AGDA_DOJANG)/agda
AGDA_DOJANG_AGDA_APPLY    ?= $(AGDA_DATA)/ApplyDemo.agda
AGDA_LIB_DIR            ?= $(AGDA_DOJANG_AGDA)
AGDA_STRUX_DIR  ?= $(PROJECT_ROOT)/agda-strux
#
# Resolve agda-json executable path from backend shell.
# Important: nix shell hooks print banners to stdout; filter to the last line
# that ends with "agda-json".
define RESOLVE_AGDA_JSON_BIN
  AGDA_JSON_BIN="$$( \
    $(call run_backend,cd "$(AGDA_STRUX_DIR)" && cabal list-bin exe:agda-json) \
      | tr -d '\r' \
      | awk '/agda-json$$/ {p=$$NF} END {print p}' \
  )"; \
  test -n "$$AGDA_JSON_BIN" || { \
    AGDA_JSON_BIN="$$(command -v agda-json 2>/dev/null || true)"; \
  }; \
  test -n "$$AGDA_JSON_BIN" || { echo "ERROR: could not resolve agda-json path"; exit 1; }
endef

AGDA_JSON_BIN_ARG = "$$AGDA_JSON_BIN"

# -- FAIL FAST KNOB --
# agda-jsonl extractor **continues on failures** unless `FAIL_FAST=1`
# Makefile alias: use `FAIL_FAST=1` for `AGDA_JSONL_FAIL_ON_ERROR=1`.
AGDA_JSONL_FAIL_ON_ERROR ?= $(if $(filter 1,$(FAIL_FAST)),true,false)
# If FAIL_FAST=1, force fail-on-error true. This lets us do:
# `make extract-lib FAIL_FAST=1` and otherwise default continues-on-error.

AGDA_JSONL_ARGS ?=
AGDA_JSONL_ARGS_BASE = \
  --project-root $(PROJECT_ROOT) \
  --agda-dir $(AGDA_LIB_DIR) \
  --src-dir $(LIB_SRC_DIR) \
  --modules-file $(LIB_MODULES_FILE) \
  --out-dir $(LIB_RAW_ROOT) \
  --agda-json $(AGDA_JSON_BIN_ARG) \
  --parallelism $(PAR) \
  --runner spark \
  --spark-master $(EXTRACT_SPARK_MASTER) \
  --fail-on-error $(AGDA_JSONL_FAIL_ON_ERROR) \
  $(if $(filter 0,$(RESUME)),--no-resume,)

# =============================================================================


# ------------------------------------------------------------------------------
# PHONY target list
PHONY_TARGETS := env diag _ensure-dirs check check-nix audit audit-nix test \
                 _check-sbt _check-python _check-spark _check-java-home _check-etl-agda-algebras-contract \
                 extract-lib extract-lib-nix extract-lib-smoke extract-lib-smoke-nix \
                 extract-algebras-backend extract-algebras agda-algebras-metadata metadata \
                 build-agda-json show-agda-json-bin backend-test backend-smoke backend-clean \
                 extract extract-stdlib extract-categories transform a2t \
                 etl-test etl-test-preprocess-agda etl etl-agda-algebras \
                 etl-agda-algebras-smoke train-retrieval-smoke eval-proof-completion-smoke-retrieval \
                 bench pipeline filter test-strux-driver \
                 train-jsonl train-jsonl-sample train-jsonl-head \
                 dataset-stats dataset-stats-sample premise-eval-quick-sample premise-eval premise-eval-quick \
                 smoke smoke-nix gen-sample smoke-sample test-ml-pipeline test-agda-dojang test-all test-integration \
                 extract-algebras-legacy extract-lib-old clean wipe tree probe-all

.PHONY: $(PHONY_TARGETS)


# =========================================================================================
# Section 0 — ci/backend
# =========================================================================================
# ------------------------------------------------------------------------------
# CI smoke target
#
# Mirrors the four CI lanes locally (no Nix required).
# Use this to verify CI will pass before pushing.
#
# Usage:
#   make ci-smoke                    # run all four lanes
#   make ci-smoke CI_SKIP_ML=1       # skip Python (e.g., no venv yet)
# ------------------------------------------------------------------------------
.PHONY: ci-smoke
ci-smoke: ci-smoke-scala ci-smoke-etl ci-smoke-python ci-smoke-haskell
	@echo "✅ ci-smoke: all four lanes passed."

.PHONY: ci-smoke-scala
ci-smoke-scala: _check-sbt
	@echo "── [ci-smoke] Lane 1/4: Scala strux-driver tests ──"
	cd $(STRUX_DRIVER) && $(SBT) -v test

.PHONY: ci-smoke-etl
ci-smoke-etl: _check-sbt
	@echo "── [ci-smoke] Lane 2/4: Scala ml-pipeline ETL smoke ──"
	cd $(ML_PIPE) && $(SBT) -v "project etl" "testOnly etl.PreprocessAgdaSpec"
	$(MAKE) --no-print-directory etl-proof-completion-dataset-smoke PROOF_COMPLETION_SMOKE_LIMIT=200

.PHONY: ci-smoke-python
ci-smoke-python:
ifeq ($(CI_SKIP_ML),1)
	@echo "── [ci-smoke] Lane 3/4: Python ml-pipeline tests (SKIPPED — CI_SKIP_ML=1) ──"
else
	@echo "── [ci-smoke] Lane 3/4: Python ml-pipeline tests ──"
	@cd $(ML_PIPE) && \
	  if [ -d python/tests ] && find python/tests \( -name 'test_*.py' -o -name '*_test.py' \) -print -quit | grep -q .; then \
	    $(PY) -m pytest -q python/tests; \
	  else \
	    echo "  No Python tests found; skipping."; \
	  fi
endif

.PHONY: ci-smoke-haskell
ci-smoke-haskell:
	@echo "── [ci-smoke] Lane 4/4: Haskell agda-strux tests ──"
	$(MAKE) --no-print-directory backend-test BACKEND_USE_NIX=0 BACKEND_TEST_KEEP=0
# ------------------------------------------------------------------------------




# =========================================================================================
# Section 1 — Core / current extraction + tests (top of file)
# =========================================================================================
#
# The targets that form the core of the project; they should always be up-to-date.
#
# + 1.1. `help`
# + 1.2. `env/diag`
# + 1.3. nix wrappers
# + 1.4. backend build/test (`build-agda-json`, `backend-test`, `backend-smoke`)
# + 1.5. strux-driver tests
# + 1.6. `extract-lib` + `extract-lib-smoke` (our current extraction path)
# + 1.7. `check`, `check-nix`, `audit`, `audit-nix`, `extract-e2e`
#
# --------------------------------------------------------------------------
# 1.1. `help`, `env/diag`
help:
	@echo ""
	@echo "agda-native-air top-level targets:"
	@echo "  make test                        - Run Scala unit tests in strux-driver/"
	@echo "  make test-all                    - Run Scala, Python, and AgdaDojang tests (if available)"
	@echo "  make metadata                    - Generate metadata for agda-algebras"
	@echo "  make extract                     - strux-driver: .agda|dir -> $(DATA_TRAIN)"
	@echo "  make transform                   - strux-driver: Agda2Train JSON -> $(A2T_OUT)"
	@echo "  make a2t                         - strux-driver: legacy Agda2Train JSON -> $(DATA_A2T_SIMPLE)"
	@echo "  make etl                         - Spark ETL (JSONL -> Parquet) -> $(TRAIN_PARQUET)"
	@echo "  make etl-agda-algebras           - Config-driven ETL for agda-algebras -> ml-pipeline/data/agda-algebras/"
	@echo "  make etl-agda-algebras-smoke     - Fast deterministic ETL slice (CI-friendly)"
	@echo "  make etl-test                    - Run all Scala ETL tests (ml-pipeline/etl)"
	@echo "  make etl-test-preprocess-agda    - Run ETL smoke test (etl.PreprocessAgdaSpec)"
	@echo "  make etl-proof-completion-smoke  - Build proof-completion dataset from fixture JSONL + validate"
	@echo "  make train-retrieval-smoke       - Train a deterministic artifact from smoke dataset; write canonical pickle."
	@echo "  make eval-proof-completion-smoke-retrieval - Run existing smoke evaluator using retrieval policy + model artifact."
	@echo "  make bench                       - Run AgdaDojang tiny benchmark"
	@echo "  make tree                        - Pretty tree view"
	@echo "  make wipe                        - Remove generated artifacts"
	@echo ""
	@echo "Tips:"
	@echo "  - Run inside 'nix develop' to pin Agda/Scala/Python/Spark."
	@echo "  - Override tools, e.g.:"
	@echo "      'SBT=csbt make extract'"
	@echo "      'EXTRACT_INPUT=agda-dojang/agda make extract'"
	@echo "  - Run in normal (quiet-ish) mode: make extract"
	@echo "  - Run in verbose sbt debug mode:  make extract SBT_DEBUG=1"
	@echo ""
	@echo "Knobs (override on the CLI):"
	@echo "  USE_VENV=1 (default)  -> use project venv at $(VENV)"
	@echo "  USE_VENV=0            -> use whatever '$(PY)' points to (e.g. conda env)"
	@echo "  TORCH_MODE=cpu        -> torch CPU wheels from official index (default)"
	@echo "  TORCH_MODE=pypi       -> torch from PyPI (CUDA wheels if available)"
	@echo "  TORCH_MODE=skip       -> don't touch torch at all"
	@echo "  PIP_QUIET=-q (default) or PIP_QUIET= for full pip output"
	@echo ""
	@echo "Examples:"
	@echo "  make train-stdlib"
	@echo "  make train-stdlib TORCH_MODE=pypi"
	@echo "  source ~/venvs/mlpipeline/bin/activate && make train-stdlib USE_VENV=0"
	@echo ""
#
# -------------------------------------------------------------------------------
# + 1.2. `env/diag` (Environment setup and diagnostics)
#
# Print versions of key tools, python runtime info, etc.
env diag: $(VENV_DEPS)
	@echo "================ Environment diagnostics ================"
	@echo "📦 Project root : $(PROJECT_ROOT)"
	@echo "🛠  USE_VENV     : $(USE_VENV)"
	@echo "🔥 TORCH_MODE   : $(TORCH_MODE)"
	@echo ""
	@echo "→ sbt / Scala:"
	@$(SBT) --version 2>/dev/null || echo "  (sbtVersion failed)"
	@echo ""
	@echo "→ Spark:"
	@$(SPARK_SUBMIT) --version 2>/dev/null | head -n 1 || echo "  (spark-submit not found)"
	@echo ""
	@echo "→ Agda:"
	@agda --version 2>/dev/null || echo "  (agda not found on PATH)"
	@echo ""
	@echo "→ Python (outer):"
	@$(PY) -c 'import sys; print(sys.version)' 2>/dev/null || echo "  ($(PY) not available)"
	@echo ""
	@echo "→ Python / torch runtime (training Python):"
	@$(PY_RUN) ml-pipeline/scripts/inspect_runtime.py 2>/dev/null || echo "  (could not run inspect_runtime.py)"
	@echo "========================================================="
#
# --- Create directories we write to (defensive) -----------------------------
_ensure-dirs:
	@mkdir -p $(DATA) $(ML_PIPE_FEATURES) $(ML_PIPE_MODELS)
#
# Tool checks
_check-log4j2:
	@set -euo pipefail; \
	[ -f "$(LOG4J2_CONFIG)" ] || { \
	  echo "❌ ERROR: missing log4j2 config: $(LOG4J2_CONFIG)"; \
	  echo "   Expected a shared Spark log config at conf/log4j2.properties"; \
	  exit 2; \
	}
#
_check-sbt: _check-log4j2
	@command -v $(SBT) >/dev/null || { echo "ERROR: sbt not found. Install or enter 'nix develop'."; exit 1; }
#
_check-python:
	@command -v $(PY) >/dev/null || { \
	  echo "ERROR: $(PY) not found. Install Python 3.10+ or use 'nix develop'."; \
	  exit 1; \
	}

_check-java-home:
	@test -n "$(SBT_JAVA_HOME)" || { \
	  echo "ERROR: JAVA_HOME is empty; cannot pin JDK for sbt"; \
	  exit 2; \
	}
#
# --- Python venv setup --------------------------------------------------------
ifeq ($(CI_SKIP_ML),1)
$(VENV):
	@echo ">> [venv] skipped (CI_SKIP_ML=1)"
else
$(VENV):
	@command -v $(PY) >/dev/null || { \
	  echo "ERROR: $(PY) not found. Install Python 3.10+ or use 'nix develop'."; \
	  exit 1; \
	}
	@echo "🌱 [venv] creating project venv at $(VENV)"
	@echo "   base python: $$($(PY) -c 'import sys; print(sys.executable)')"
	@$(PY) -m venv $(VENV)
	@echo "   upgrading pip (PIP_QUIET=$(PIP_QUIET))"
	@$(PIP) install $(PIP_QUIET) --upgrade pip
	@echo "   installing torch (TORCH_MODE=$(TORCH_MODE))"
	@$(TORCH_INSTALL)
	@if [ -f "$(REQS_FILE)" ]; then \
	  echo "   installing extra deps from $(REQS_FILE)"; \
	  $(PIP) install $(PIP_QUIET) -r "$(REQS_FILE)"; \
	else \
	  echo "⚠️  requirements file '$(REQS_FILE)' not found; skipping."; \
	fi
	@echo "✅ venv ready: $(VENV)"
endif
#
# --- Spark check -------------------------------------------------------------
_check-spark:
	@command -v $(SPARK_SUBMIT) >/dev/null || { echo "ERROR: spark-submit not found. Install Spark or use 'nix develop'."; exit 1; }

# --- Makefile Hygiene --------------------------------------------------------
# Probe all PROBE targets: try all declared targets, keep going, write a
# summary. Usage: make probe-all PROBE_JOBS=1 (or higher, but start at 1)
PROBE_JOBS ?= 1
PROBE_TARGETS := env diag _ensure-dirs _check-sbt _check-python _check-spark \
                 extract-lib-nix extract-lib-smoke extract-lib-smoke-nix \
                 build-agda-json show-agda-json-bin backend-test backend-smoke backend-clean \
                 extract-algebras-backend extract-algebras agda-algebras-metadata metadata extract-lib \
                 check check-nix audit audit-nix test test-strux-driver \
                 extract extract-stdlib extract-categories transform a2t etl \
                 train filter finetune-dataset serve bench \
                 dataset-stats dataset-stats-sample premise-eval-quick-sample premise-eval premise-eval-quick \
                 smoke smoke-nix gen-sample smoke-sample test-ml-pipeline test-agda-dojang test-all test-integration \
                 pipeline train-stdlib train-algebras train-categories extract-algebras-legacy
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

test-doc-howtorun:
	@echo "→ testing documented commands from docs/HowToRun.md"
	python3 scripts/python/doc_check.py docs/HowToRun.md --run -v

# -------------------------------------------------------------------------------
# 1.3. nix wrappers: convenience wrappers for running from outside Nix
#
extract-lib-nix:
	@$(NIX_ALL) '$(MAKE) extract-lib'
#
# Smoke variant: run only first N modules (fast validation)
SMOKE_N ?= 10
extract-lib-smoke: agda-algebras-metadata _ensure-dirs
	@mkdir -p "$(LIB_CORPUS_META_DIR)"
	@head -n "$(SMOKE_N)" "$(LIB_MODULES_FILE)" > "$(LIB_CORPUS_META_DIR)/smoke-modules.txt"
	@$(MAKE) extract-lib LIB_MODULES_FILE="$(LIB_CORPUS_META_DIR)/smoke-modules.txt" LIB_RESUME=0
#
extract-lib-smoke-nix:
	@$(NIX_ALL) '$(MAKE) extract-lib-smoke'
#
#
# -------------------------------------------------------------------------------
# + 1.4. backend build/test (`build-agda-json`, `backend-test`, `backend-smoke`)
# agda-strux (Haskell executable: agda-json)
#
# We intentionally run cabal via the flake backend shell to ensure:
#   - cabal/ghc are compatible with the pinned Agda library (2.8.0)
#   - we don't accidentally pick up a random system cabal
# Backend test output retention
#
# By default we KEEP backend test output (JSONL + fixture copies) so it is easy
# to inspect/share; this can be disabled by setting BACKEND_TEST_KEEP=0.
# ------------------------------------------------------------------------------
BACKEND_TEST_KEEP ?= 1
BACKEND_TEST_OUT_ROOT ?= $(DATA)/test-output/agda-strux

build-agda-json:
	@$(call run_backend,cd "$(AGDA_STRUX_DIR)" && cabal build exe:agda-json)

show-agda-json-bin: build-agda-json
	@$(call run_backend,cd "$(AGDA_STRUX_DIR)" && cabal list-bin exe:agda-json)

backend-test:
	@echo ">> [backend-test] cabal test in $(AGDA_STRUX_DIR)"
	@$(call run_backend,cd "$(AGDA_STRUX_DIR)" && \
	  AGDA_JSON_TEST_KEEP="$(BACKEND_TEST_KEEP)" \
	  AGDA_JSON_TEST_OUT_ROOT="$(BACKEND_TEST_OUT_ROOT)" \
	  cabal test)

backend-test-clean:
	@echo ">> [backend-test-clean] removing $(BACKEND_TEST_OUT_ROOT)"
	@rm -rf "$(BACKEND_TEST_OUT_ROOT)"

backend-smoke:
	@echo ">> [backend-smoke] run agda-json on backend smoke target"
	@$(call run_backend,cd "$(AGDA_STRUX_DIR)" && $(MAKE) smoke)

backend-clean:
	@echo ">> [backend-clean] clean backend build artifacts (cabal)"
	@$(call run_backend,cd "$(AGDA_STRUX_DIR)" && cabal clean)
#
#
# -------------------------------------------------------------------------------
# + 1.5. strux-driver tests
#
# Overridable driver knob (override with `make extract-algebras RESUME=0`)
RESUME ?= 1   # 1 => resume (default), 0 => --no-resume
#
# Scala driver (strux-driver) that calls agda-json backend and writes JSONL
extract-algebras-backend: _ensure-dirs _check-sbt _check-java-home build-agda-json
	@echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-algebras-backend] AgdaJsonlDriver"
	@echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-algebras-backend]   project-root : $(PROJECT_ROOT)"
	@echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-algebras-backend]  agda-lib-dir : $(AGDA_LIB_DIR)"
	@echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-algebras-backend]  src-dir      : $(AGDA_ALGEBRAS_SRC)"
	@echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-algebras-backend]  modules-file : $(AGDA_ALGEBRAS_MODULES_FILE)"
	@echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-algebras-backend]  out-dir      : $(DATA_ALGEBRAS_RAW)"
	@echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-algebras-backend]  parallelism  : $(PAR)"
	@mkdir -p "$(DATA_ALGEBRAS_RAW)/jsonl" "$(DATA_ALGEBRAS_RAW)/logs"
	@$(RESOLVE_AGDA_JSON_BIN); \
	"$(SBT_RUNNER)" \
	  --agda-json-bin "$$AGDA_JSON_BIN" \
	  --project-dir "$(STRUX_DRIVER_DIR)" \
	  --java-home   "$(SBT_JAVA_HOME)" \
	  --sbt         "$(SBT)" \
	  --sbt-flags   "$(SBT_FLAGS)" \
	  --jmo         "$(JMO)" \
	  -- \
	  "project StruxDriver" \
	  "runMain struxdriver.extract.AgdaJsonlDriver $(AGDA_JSONL_ARGS_BASE) $(AGDA_JSONL_ARGS)"

# alias: "extract-algebras" means backend by default
extract-algebras: extract-algebras-backend
#
#
# -------------------------------------------------------------------------------
# + 1.6. `extract-lib` + `extract-lib-smoke` (our current extraction path)
#
# ---- Generate metadata for agda-algebras library ----
agda-algebras-metadata:
	@if [ -z "$(AGDA_ALGEBRAS_ROOT)" ]; then \
	  echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make agda-algebras-metadata] ❌ ERROR: AGDA_ALGEBRAS_ROOT is not set."; \
	  echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make agda-algebras-metadata]           Set it in the Makefile or on the command line, e.g."; \
	  echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make agda-algebras-metadata]           make agda-algebras-metadata AGDA_ALGEBRAS_ROOT=/path/to/agda-algebras"; \
	  exit 1; \
	fi
	@echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ)  [agda-algebras-metadata]  - running $(AGDA_LIB_METADATA_SCRIPT)"
	python3 $(AGDA_LIB_METADATA_SCRIPT) "$(AGDA_ALGEBRAS_ROOT)" \
	  --lib-name agda-algebras \
	  --out-dir $(AGDA_LIB_METADATA_OUT) \
	  --format txt
#
metadata: agda-algebras-metadata # alias
#
# Main target: agda-json backend build
# assumes tools available, but will still build backend via nix
extract-lib: _ensure-dirs _check-sbt _check-spark build-agda-json agda-algebras-metadata
	@set -u -o pipefail; \
	mkdir -p "$(LIB_JSONL_DIR)" "$(LIB_LOG_DIR)" "$(LIB_MANIFEST_DIR)"; \
	TS="$$(date -u +%Y%m%dT%H%M%SZ)"; \
	MANIFEST="$(LIB_MANIFEST_DIR)/$$TS.json"; \
	echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-lib] out-root     : $(LIB_OUT_ROOT)"; \
	echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-lib] src-dir      : $(LIB_SRC_DIR)"; \
	echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-lib] modules-file : $(LIB_MODULES_FILE)"; \
	echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-lib] agda-lib-dir : $(AGDA_LIB_DIR)"; \
	$(RESOLVE_AGDA_JSON_BIN); \
	echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-lib] agda-json    : $$AGDA_JSON_BIN"; \
	echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-lib] manifest     : $$MANIFEST"; \
	test -n "$$AGDA_JSON_BIN"; \
	START="$$(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
	GITREV="$$(git rev-parse HEAD 2>/dev/null || echo unknown)"; \
	AGDAVER="$$(agda --version 2>/dev/null | head -n1 || echo unknown)"; \
	JAVA17_HOME="$${JAVA_HOME:-}"; \
	if [ -z "$$JAVA17_HOME" ]; then \
	  echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-lib] ERROR: JAVA_HOME is empty; cannot pin JDK for sbt"; \
	  exit 2; \
	fi; \
	echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-lib] java -version before:"; java -version 2>&1 | head -n1 || true; \
	echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-lib] arg --agda-json: $$AGDA_JSON_BIN"; \
	\
	$(SBT_RUNNER) \
	  --agda-json-bin "$$AGDA_JSON_BIN" \
	  --project-dir "$(STRUX_DRIVER_DIR)" \
	  --java-home   "$(SBT_JAVA_HOME)" \
	  --sbt         "$(SBT)" \
	  --sbt-flags   "$(SBT_FLAGS)" \
	  --jmo         "$(JMO)" \
	  -- \
	  "project StruxDriver" \
	  "runMain struxdriver.extract.AgdaJsonlDriver $(AGDA_JSONL_ARGS_BASE) $(AGDA_JSONL_ARGS)"; \
	EXIT_CODE="$$?" ; \
	set -e; \
	JSONL_FILES="$$(find "$(LIB_RAW_ROOT)" -type f -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"; \
	if [ "$$EXIT_CODE" -eq 0 ] && [ "$$JSONL_FILES" -eq 0 ]; then \
	  echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-lib] ERROR: AgdaJsonlDriver exited 0 but produced no JSONL files"; \
	  EXIT_CODE=2; \
	fi; \
	\
	END="$$(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
	printf '{\n'                                      > "$$MANIFEST"; \
	printf '  "lib": "%s",\n'        "$(LIB_NAME)"     >> "$$MANIFEST"; \
	printf '  "start": "%s",\n'      "$$START"         >> "$$MANIFEST"; \
	printf '  "end": "%s",\n'        "$$END"           >> "$$MANIFEST"; \
	printf '  "exit_code": %s,\n'    "$$EXIT_CODE"     >> "$$MANIFEST"; \
	printf '  "git_rev": "%s",\n'    "$$GITREV"        >> "$$MANIFEST"; \
	printf '  "agda": "%s",\n'       "$$AGDAVER"        >> "$$MANIFEST"; \
	printf '  "modules_file": "%s",\n' "$(LIB_MODULES_FILE)" >> "$$MANIFEST"; \
	printf '  "jsonl_files": %s\n'   "$$JSONL_FILES"   >> "$$MANIFEST"; \
	printf '}\n'                                     >> "$$MANIFEST"; \
	echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-lib]  ✅ wrote $$MANIFEST"; \
	\
	if [ "$$EXIT_CODE" -ne 0 ]; then \
	  echo "[info] $$(date -u +%Y-%m-%dT%H:%M:%SZ) - [make extract-lib] ❌ FAIL (exit $$EXIT_CODE)"; \
	  exit "$$EXIT_CODE"; \
	fi
#
#
# -------------------------------------------------------------------------------
# 1.7. Tests
#
# Use:
# + `make check` when already in the right shell
# + `make check-nix` when outside a Nix shell
check:
	@echo "→ check (fast): strux-driver tests + backend tests + backend smoke"
	@$(MAKE) --no-print-directory test-strux-driver
	@$(MAKE) --no-print-directory backend-test
	@$(MAKE) --no-print-directory backend-smoke
	@echo "✓ check OK"

check-nix:
	@echo "→ check-nix: run strux-driver checks in .#all, backend checks in .#backend"
	@$(NIX_ALL)     '$(MAKE) --no-print-directory test-strux-driver'
	@$(NIX_BACKEND) '$(MAKE) --no-print-directory backend-test'
	@$(NIX_BACKEND) '$(MAKE) --no-print-directory backend-smoke'
	@echo "✓ check-nix OK"

#
# Audit: full suite of reliable targets
# A curated list of targets that should always work.
AUDIT_TARGETS ?= diag test-strux-driver backend-test backend-smoke build-agda-json show-agda-json-bin extract-lib-smoke
#
audit:
	@echo "→ audit $(AUDIT_TARGETS)"
	@set -e; \
	for t in $(AUDIT_TARGETS); do \
	  echo "------------------------------------------------------------"; \
	  echo ">>> make $$t"; \
	  $(MAKE) --no-print-directory $$t; \
	done; \
	echo "✓ audit OK"
#
audit-nix:
	@echo "→ audit $(AUDIT_TARGETS)"
	@set -e; \
	for t in $(AUDIT_TARGETS); do \
	  echo "------------------------------------------------------------"; \
	  echo ">>> make $$t"; \
	  $(NIX_ALL) "$(MAKE) --no-print-directory $$t"; \
	done; \
	echo "✓ audit OK"
#
# ---- Run tests ----
# Keep `make test` as the canonical Scala test entrypoint
test: test-strux-driver
#
test-strux-driver: _check-sbt build-agda-json
	@echo ">> [test-strux-driver] sbt test in strux-driver/ (with AGDA_JSON_BIN if available)"
	@set -e; \
	$(RESOLVE_AGDA_JSON_BIN); \
	cd $(STRUX_DRIVER) && AGDA_JSON_BIN="$$AGDA_JSON_BIN" AGDA_DIR="$(AGDA_LIB_DIR)" $(SBT) test
#
# ==============================================================================




# ==============================================================================
# Section 2 — Pipeline / ML
# ==============================================================================
#
# 2.1. extract: call Scala main directly (AgdaExtractorMain)
# 2.2. transform: Scala Agda2TrainTransformer (reflection JSON → AgdaData JSONL)
# 2.3. a2t: legacy reducer (Agda2Train JSON → canonical AgdaData)
# 2.4. etl: Spark ETL (JSONL -> Parquet)
# 2.5.a. train: Python trainer (JSONL-based for now).
# 2.5.b. filter: create a cleaned dataset (non-empty type/proof, optional length thresholds)
# 2.5.c. finetune-dataset: builder that turns AgdaData into instruction/output pairs
# 2.6. serve: FastAPI (uvicorn) using trained model.
# 2.7. bench: AgdaDojang dojo (still delegated for now)
# 2.8. dataset-stats: Dataset utilities (Scala mains in strux-driver/)
# 2.9. smoke: Top-level smoke tests
#
# ------------------------------------------------------------------------------
# 2.1. AgdaExtractorMain
#    Input:  $(EXTRACT_INPUT)
#    Output: $(TRAIN_DATA)
extract: _ensure-dirs _check-sbt
	@if [ ! -e "$(EXTRACT_INPUT)" ]; then \
	  echo "ERROR: '$(EXTRACT_INPUT)' does not exist."; exit 1; fi
	@echo ">> [extract] $(EXTRACT_INPUT) -> $(TRAIN_DATA)"
	@mkdir -p $(dir $(TRAIN_DATA))
	cd $(STRUX_DRIVER) && \
	  $(SBT) $(SBT_FLAGS) "runMain struxdriver.extract.AgdaExtractorMain $(EXTRACT_INPUT) $(TRAIN_DATA)"
	@[ -s "$(TRAIN_DATA)" ] || { echo "❌ Expected $(TRAIN_DATA)."; exit 1; }
	@echo "✅ wrote $(TRAIN_DATA)"

# Library-specific extract targets (wrappers around `extract`)
extract-stdlib: _ensure-dirs _check-sbt
	@if [ ! -d "$(AGDA_STDLIB_SRC)" ]; then \
	  echo "ERROR: AGDA_STDLIB_SRC not found at '$(AGDA_STDLIB_SRC)'."; \
	  echo "       Override AGDA_STDLIB_ROOT=/path/to/agda-stdlib-2.2"; \
	  exit 1; \
	fi
	@$(MAKE) extract EXTRACT_INPUT="$(AGDA_STDLIB_SRC)" DATA_TRAIN="$(DATA_STDLIB)"

extract-categories: _ensure-dirs _check-sbt
	@if [ ! -d "$(AGDA_CATEGORIES_SRC)" ]; then \
	  echo "ERROR: AGDA_CATEGORIES_SRC not found at '$(AGDA_CATEGORIES_SRC)'."; \
	  echo "       Override AGDA_CATEGORIES_ROOT=/path/to/agda-categories"; \
	  exit 1; \
	fi
	@$(MAKE) extract EXTRACT_INPUT="$(AGDA_CATEGORIES_SRC)" DATA_TRAIN="$(DATA_CATEGORIES)"

# ------------------------------------------------------------------------------
# 2.2. Agda2TrainTransformer (reflection JSON → AgdaData JSONL)
transform: _check-sbt
	@if [ ! -e "$(A2T_JSON_INPUT)" ]; then \
	  echo "ERROR: '$(A2T_JSON_INPUT)' does not exist."; exit 1; fi
	@mkdir -p $(dir $(A2T_OUT))
	@echo ">> [transform] $(A2T_JSON_INPUT) -> $(A2T_OUT)"
	cd $(STRUX_DRIVER) && \
	  $(SBT) $(SBT_FLAGS) "runMain struxdriver.transform.Agda2TrainTransformer $(A2T_JSON_INPUT) $(A2T_OUT)"
	@[ -s "$(A2T_OUT)" ] || { echo "❌ Expected $(A2T_OUT)."; exit 1; }
	@echo "✅ wrote $(A2T_OUT)"

# ------------------------------------------------------------------------------
# 2.3. Agda2TrainReducer: legacy Agda2Train JSON → canonical AgdaData
a2t: _ensure-dirs _check-sbt
	@if [ ! -e "$(A2T_JSON_INPUT)" ]; then \
	  echo "ERROR: '$(A2T_JSON_INPUT)' does not exist."; exit 1; fi
	@echo ">> [a2t] $(A2T_JSON_INPUT) -> $(DATA_A2T_SIMPLE)"
	cd $(STRUX_DRIVER) && \
	  $(SBT) $(SBT_FLAGS) "runMain struxdriver.reduce.Agda2TrainReducer $(A2T_JSON_INPUT) $(DATA_A2T_SIMPLE)"
	@[ -s "$(DATA_A2T_SIMPLE)" ] || { echo "❌ Expected $(DATA_A2T_SIMPLE)."; exit 1; }
	@echo "✅ wrote $(DATA_A2T_SIMPLE)"

# ------------------------------------------------------------------------------
# 2.4. ProcessAgda (Spark ETL): JSONL -> Parquet
etl: _ensure-dirs _check-sbt
	@if [ ! -s "$(DATA_TRAIN)" ]; then \
	  echo "ERROR: '$(DATA_TRAIN)' not found. Run 'make extract' first."; \
	  exit 1; \
	fi
	@echo ">> [etl] Spark: JSONL -> Parquet -> $(TRAIN_PARQUET)"
	cd ml-pipeline && \
	  $(SBT) $(SBT_FLAGS) "project etl" "runMain etl.PreprocessAgda"
	@[ -s "$(TRAIN_PARQUET)" ] || { echo "❌ Expected $(TRAIN_PARQUET) to be written by ETL."; exit 1; }
	@echo "✅ wrote $(TRAIN_PARQUET)"

# ------------------------------------------------------------------------------
# 2.5. ETL
#
# Example usage:
#   # test run
#   make extract-lib
#   make train-jsonl-sample
#   cd ml-pipeline && sbt -batch "project etl" test
#   # real runs
#	make train-jsonl
#   cd ml-pipeline && sbt -batch "project etl" "runMain etl.PreprocessAgda ../../data/train.jsonl ../features"
#
# Where backend JSONL shards live (agda-json outputs)
RAW_JSONL_DIR ?= data/agda-algebras/raw/jsonl
#
# Outputs
TRAIN_JSONL      ?= data/train.jsonl
TRAIN_JSONL_SAMP ?= data/train.sample.jsonl
#
# ------------------------------------------------------------------------------
# 2.5.0  Corpus ETL: agda-algebras (config-driven contract)
CONFIG_AGDA_ALGEBRAS ?= $(PROJECT_ROOT)/configs/agda-algebras.yaml

# We follow Issue #19 convention (inside ml-pipeline/)
ALG_CORPUS_OUT_DIR   ?= $(ML_PIPE)/data/agda-algebras

# Temporary merged JSONL location (matches config contract; OK if it already exists)
ALG_MERGED_JSONL     ?= $(DATA)/agda-algebras/raw/jsonl/combined.jsonl

# Smoke controls for CI / quick dev
ALG_SMOKE_SHARDS ?= 3
ALG_SMOKE_LINES  ?= 2000

# Sample controls (tweak as needed)
SAMPLE_SHARDS ?= 5      # number of shard files (sorted) to include
SAMPLE_LINES  ?= 2000   # max lines in sample output
HEAD_LINES    ?= 20000  # max lines for "head of full"
#
train-jsonl: _ensure-dirs
	@echo ">> [train-jsonl] concatenate ALL backend shards -> $(TRAIN_JSONL)"
	@rm -f "$(TRAIN_JSONL)"
	@find "$(RAW_JSONL_DIR)" -name '*.jsonl' -type f -print0 \
	  | sort -z | xargs -0 cat >> "$(TRAIN_JSONL)"
	@[ -s "$(TRAIN_JSONL)" ] || { echo "❌ Expected non-empty $(TRAIN_JSONL)"; exit 1; }
	@echo "✅ wrote $(TRAIN_JSONL)"

# Deterministic, small subset for rapid ETL dev.
# Uses the first SAMPLE_SHARDS shard files (after sort), then caps to SAMPLE_LINES lines.
train-jsonl-sample: _ensure-dirs
	@echo ">> [train-jsonl-sample] $(SAMPLE_SHARDS) shards (sorted) -> $(TRAIN_JSONL_SAMP) (<= $(SAMPLE_LINES) lines)"
	@rm -f "$(TRAIN_JSONL_SAMP)"
	@find "$(RAW_JSONL_DIR)" -name '*.jsonl' -type f -print0 \
	  | sort -z | head -z -n $(strip $(SAMPLE_SHARDS)) | xargs -0 -r cat \
	  | head -n $(strip $(SAMPLE_LINES)) >> "$(TRAIN_JSONL_SAMP)"
	@[ -s "$(TRAIN_JSONL_SAMP)" ] || { echo "❌ Expected non-empty $(TRAIN_JSONL_SAMP)"; exit 1; }
	@echo "✅ wrote $(TRAIN_JSONL_SAMP)"
#
# Quick smoke: build full stream then take first HEAD_LINES lines.
train-jsonl-head: _ensure-dirs
	@echo ">> [train-jsonl-head] head $(HEAD_LINES) of full -> $(TRAIN_JSONL_SAMP)"
	@rm -f "$(TRAIN_JSONL_SAMP)"
	@find "$(RAW_JSONL_DIR)" -name '*.jsonl' -type f -print0 \
	  | sort -z | xargs -0 -r cat | head -n $(strip $(HEAD_LINES)) >> "$(TRAIN_JSONL_SAMP)"
	@[ -s "$(TRAIN_JSONL_SAMP)" ] || { echo "❌ Expected non-empty $(TRAIN_JSONL_SAMP)"; exit 1; }
	@echo "✅ wrote $(TRAIN_JSONL_SAMP)"

## ------------------------------------------------------------------------------
# 2.5.1. ETL for agda-algebras corpus (config-driven contract)
#
# Produces:
#   ml-pipeline/data/agda-algebras/train.parquet
#   ml-pipeline/data/agda-algebras/test.parquet
#
# Smoke mode:
#   make etl-agda-algebras-smoke
#
AGDA_ALGEBRAS_JSONL_DIR ?= $(DATA)/agda-algebras/raw/jsonl
AGDA_ALGEBRAS_COMBINED  ?= $(AGDA_ALGEBRAS_JSONL_DIR)/combined.jsonl
AGDA_ALGEBRAS_ETL_OUT   ?= $(ML_PIPE)/data/agda-algebras
AGDA_ALGEBRAS_TRAIN_PQ  ?= $(AGDA_ALGEBRAS_ETL_OUT)/train.parquet
AGDA_ALGEBRAS_TEST_PQ   ?= $(AGDA_ALGEBRAS_ETL_OUT)/test.parquet

# Smoke controls
AGDA_ALGEBRAS_SMOKE_SHARDS ?= 3
AGDA_ALGEBRAS_SMOKE_LINES  ?= 2000

_check-etl-agda-algebras-contract:
	@set -euo pipefail; \
	CONF="$(CONFIG_AGDA_ALGEBRAS)"; \
	[ -f "$$CONF" ] || { echo "❌ ERROR: missing config: $$CONF"; exit 1; }; \
	grep -Eq '^[[:space:]]*merged_path:[[:space:]]*"?data/agda-algebras/raw/jsonl/combined\.jsonl"?$$' "$$CONF" \
	  || { echo "❌ ERROR: $$CONF missing/changed input.merged_path (expected combined.jsonl contract)"; exit 2; }; \
	grep -Eq '^[[:space:]]*base_path:[[:space:]]*"?ml-pipeline/data/agda-algebras"?$$' "$$CONF" \
	  || { echo "❌ ERROR: $$CONF missing/changed output.base_path (expected ml-pipeline/data/agda-algebras contract)"; exit 2; }

## ------------------------------------------------------------------------------
# ETL tests (Scala)
#
# These validate:
#   - Parquet outputs exist
#   - schema matches PreprocessAgdaSchema (contract)
#   - rowcount > 0
#
# Run all ETL tests:
#   make etl-test
# Run just the Agda ETL smoke spec:
#   make etl-test-preprocess-agda
etl-test: _check-sbt _check-java-home _check-spark
	@set -euo pipefail; \
	echo ">> [etl-test] sbt project etl test"; \
	cd "$(ML_PIPE)" && $(SBT) $(SBT_FLAGS) "project etl" test

etl-test-preprocess-agda: _check-sbt _check-java-home _check-spark
	@set -euo pipefail; \
	echo ">> [etl-test-preprocess-agda] testOnly etl.PreprocessAgdaSpec"; \
	cd "$(ML_PIPE)" && $(SBT) $(SBT_FLAGS) "project etl" "testOnly etl.PreprocessAgdaSpec"


## ------------------------------------------------------------------------------
# Proof-completion dataset builder (smoke)
#
# Runs the Scala builder against a committed fixture JSONL and validates:
#   - rowcount > 0
#   - every row has schemaVersion == proof-completion.v0
#
# Fixture file suggestion:
#   ml-pipeline/etl/src/test/resources/proof-completion.smoke.jsonl
#   (You can populate it by copying the JSONL lines used in BuildProofCompletionDatasetSpec.)
#
PROOF_COMPLETION_SCHEMA             ?= proof-completion.v0
PROOF_COMPLETION_FIXTURE_JSONL      ?= $(ML_PIPE)/etl/src/test/resources/proof-completion.smoke.jsonl
PROOF_COMPLETION_SMOKE_LIMIT        ?= 200
PROOF_COMPLETION_SMOKE_OUTDIR       ?= $(ML_PIPE)/data/proof-completion-smoke
PROOF_COMPLETION_SMOKE_OUT_JSONL    ?= $(PROOF_COMPLETION_SMOKE_OUTDIR)/proof_completion.jsonl
PROOF_COMPLETION_VALIDATE           ?= $(PROJECT_ROOT)/scripts/python/utils/validate_proof_completion_dataset.py

etl-proof-completion-dataset-smoke: _ensure-dirs _check-sbt _check-java-home
	@set -euo pipefail; \
	IN="$(PROOF_COMPLETION_FIXTURE_JSONL)"; \
	OUT="$(PROOF_COMPLETION_SMOKE_OUT_JSONL)"; \
	[ -f "$$IN" ] || { \
	  echo "❌ ERROR: missing fixture JSONL: $$IN"; \
	  echo "   Add a small committed fixture (e.g. copy lines from BuildProofCompletionDatasetSpec)."; \
	  exit 1; \
	}; \
	[ -f "$(PROOF_COMPLETION_VALIDATE)" ] || { \
	  echo "❌ ERROR: missing validator script: $(PROOF_COMPLETION_VALIDATE)"; \
	  echo "   Expected: scripts/python/utils/validate_proof_completion_dataset.py"; \
	  exit 1; \
	}; \
	mkdir -p "$(PROOF_COMPLETION_SMOKE_OUTDIR)"; \
	rm -f "$$OUT"; \
	echo ">> [etl-proof-completion-dataset-smoke] in     : $$IN"; \
	echo ">> [etl-proof-completion-dataset-smoke] out    : $$OUT"; \
	echo ">> [etl-proof-completion-dataset-smoke] limit  : $(strip $(PROOF_COMPLETION_SMOKE_LIMIT))"; \
	cd "$(ML_PIPE)" && \
	  $(SBT) $(SBT_FLAGS) "project etl" \
	    "runMain etl.BuildProofCompletionDataset --in $$IN --out $$OUT --limit $(strip $(PROOF_COMPLETION_SMOKE_LIMIT)) --strict"; \
	[ -s "$$OUT" ] || { echo "❌ ERROR: output missing/empty: $$OUT"; exit 2; }; \
	python3 "$(PROOF_COMPLETION_VALIDATE)" \
	  --in "$$OUT" \
	  --schema-version "$(PROOF_COMPLETION_SCHEMA)" \
	  --min-rows 1; \
	echo "✅ proof-completion dataset smoke OK"



## ------------------------------------------------------------------------------
# Full ETL (merges all shards -> combined.jsonl, then runs Spark ETL)
etl-agda-algebras: _ensure-dirs _check-sbt _check-java-home _check-spark _check-etl-agda-algebras-contract
	@set -euo pipefail; \
	echo ">> [etl-agda-algebras] config : $(CONFIG_AGDA_ALGEBRAS)"; \
	[ -d "$(AGDA_ALGEBRAS_JSONL_DIR)" ] || { \
	  echo "❌ ERROR: Input directory '$(AGDA_ALGEBRAS_JSONL_DIR)' does not exist."; \
	  echo "   Run 'make extract-lib LIB_NAME=agda-algebras' first to generate JSONL shards."; \
	  exit 1; \
	}; \
	rm -f "$(AGDA_ALGEBRAS_COMBINED)"; \
	SHARDS_N="$$(find "$(AGDA_ALGEBRAS_JSONL_DIR)" -type f -name '*.jsonl' ! -name 'combined.jsonl' | wc -l | tr -d ' ')"; \
	echo ">> [etl-agda-algebras] merge  : $$SHARDS_N shards -> $(AGDA_ALGEBRAS_COMBINED)"; \
	[ "$$SHARDS_N" -gt 0 ] || { \
	  echo "❌ ERROR: no shard .jsonl files found under $(AGDA_ALGEBRAS_JSONL_DIR)"; \
	  echo "   Try: find data/agda-algebras/raw -name '*.jsonl' -type f"; \
	  exit 2; \
	}; \
	find "$(AGDA_ALGEBRAS_JSONL_DIR)" -type f -name '*.jsonl' ! -name 'combined.jsonl' -print0 \
	  | LC_ALL=C sort -z \
	  | xargs -0 -r cat > "$(AGDA_ALGEBRAS_COMBINED)"; \
	[ -s "$(AGDA_ALGEBRAS_COMBINED)" ] || { \
	  echo "❌ ERROR: merged JSONL is missing/empty: $(AGDA_ALGEBRAS_COMBINED)"; \
	  exit 2; \
	}; \
	echo "✅ wrote $(AGDA_ALGEBRAS_COMBINED)"; \
	echo ">> [etl-agda-algebras] etl    : $(AGDA_ALGEBRAS_ETL_OUT)/{train,test}.parquet"; \
	mkdir -p "$(AGDA_ALGEBRAS_ETL_OUT)"; \
	cd "$(ML_PIPE)" && \
	  $(SBT) $(SBT_FLAGS) "project etl" "runMain etl.PreprocessAgda $(AGDA_ALGEBRAS_COMBINED) $(AGDA_ALGEBRAS_ETL_OUT)"; \
	[ -s "$(AGDA_ALGEBRAS_TRAIN_PQ)" ] || { echo "❌ ERROR: missing $(AGDA_ALGEBRAS_TRAIN_PQ)"; exit 2; }; \
	[ -s "$(AGDA_ALGEBRAS_TEST_PQ)"  ] || { echo "❌ ERROR: missing $(AGDA_ALGEBRAS_TEST_PQ)"; exit 2; }; \
	echo ">> [etl-agda-algebras] test   : etl.PreprocessAgdaSpec"; \
	cd "$(ML_PIPE)" && \
	  $(SBT) $(SBT_FLAGS) "project etl" "testOnly etl.PreprocessAgdaSpec"; \
	echo "✅ ETL + tests complete"

## ------------------------------------------------------------------------------
# Smoke ETL (bounded merge) + tests
etl-agda-algebras-smoke: _ensure-dirs _check-sbt _check-java-home _check-spark _check-etl-agda-algebras-contract
	@set -euo pipefail; \
	echo ">> [etl-agda-algebras-smoke] config : $(CONFIG_AGDA_ALGEBRAS)"; \
	[ -d "$(AGDA_ALGEBRAS_JSONL_DIR)" ] || { \
	  echo "❌ ERROR: Input directory '$(AGDA_ALGEBRAS_JSONL_DIR)' does not exist."; \
	  echo "   Run 'make extract-lib-smoke' or 'make extract-lib' first."; \
	  exit 1; \
	}; \
	rm -f "$(AGDA_ALGEBRAS_COMBINED)"; \
	SHARDS_N="$$(find "$(AGDA_ALGEBRAS_JSONL_DIR)" -type f -name '*.jsonl' ! -name 'combined.jsonl' | wc -l | tr -d ' ')"; \
	echo ">> [etl-agda-algebras-smoke] merge  : $$SHARDS_N shards (smoke) -> $(AGDA_ALGEBRAS_COMBINED)"; \
	[ "$$SHARDS_N" -gt 0 ] || { \
	  echo "❌ ERROR: no shard .jsonl files found under $(AGDA_ALGEBRAS_JSONL_DIR)"; \
	  echo "   Try: find data/agda-algebras/raw -name '*.jsonl' -type f"; \
	  exit 2; \
	}; \
	find "$(AGDA_ALGEBRAS_JSONL_DIR)" -type f -name '*.jsonl' ! -name 'combined.jsonl' -print0 \
	  | LC_ALL=C sort -z \
	  | head -z -n $(strip $(AGDA_ALGEBRAS_SMOKE_SHARDS)) \
	  | xargs -0 -r cat \
	  | head -n $(strip $(AGDA_ALGEBRAS_SMOKE_LINES)) > "$(AGDA_ALGEBRAS_COMBINED)"; \
	[ -s "$(AGDA_ALGEBRAS_COMBINED)" ] || { echo "❌ ERROR: smoke merged JSONL empty: $(AGDA_ALGEBRAS_COMBINED)"; exit 2; }; \
	echo ">> [etl-agda-algebras-smoke] etl  : $(AGDA_ALGEBRAS_ETL_OUT)/{train,test}.parquet"; \
	cd "$(ML_PIPE)" && \
	  $(SBT) $(SBT_FLAGS) "project etl" "runMain etl.PreprocessAgda $(AGDA_ALGEBRAS_COMBINED) $(AGDA_ALGEBRAS_ETL_OUT)"; \
	[ -s "$(AGDA_ALGEBRAS_TRAIN_PQ)" ] || { echo "❌ ERROR: missing $(AGDA_ALGEBRAS_TRAIN_PQ)"; exit 2; }; \
	[ -s "$(AGDA_ALGEBRAS_TEST_PQ)"  ] || { echo "❌ ERROR: missing $(AGDA_ALGEBRAS_TEST_PQ)"; exit 2; }; \
	echo ">> [etl-agda-algebras-smoke] test : etl.PreprocessAgdaSpec"; \
	cd "$(ML_PIPE)" && \
	  $(SBT) $(SBT_FLAGS) "project etl" "testOnly etl.PreprocessAgdaSpec"; \
	echo "✅ smoke ETL + tests complete"
# ------------------------------------------------------------------------------


# === LEGACY — archived to experiments/archive/ (Issue M0-1) ====================
## ------------------------------------------------------------------------------
## 2.5.2.0. Legacy Python trainer (JSONL-based for now).
# train: $(VENV_DEPS)
#	@if [ ! -s "$(TRAIN_DATA)" ]; then \
#	  echo "ERROR: no training data found at $(TRAIN_DATA)."; \
#	  echo "       Run 'make extract' or override TRAIN_DATA=..."; \
#	  exit 1; \
#	fi
#	@if [ ! -f "$(ML_PIPE_PY_MODEL)/train.py" ]; then \
#	  echo "WARN: $(ML_PIPE_PY_MODEL)/train.py not found. Creating a stub model."; \
#	  mkdir -p $(ML_PIPE_MODELS); \
#	  echo "stub" > $(MODEL_CKPT); \
#	  echo "✅ wrote stub $(MODEL_CKPT) (replace this with a real trainer)"; \
#	else \
#	  echo ">> [train] USE_VENV=$(USE_VENV) TORCH_MODE=$(TORCH_MODE)"; \
#	  echo "   TRAIN_DATA=$(TRAIN_DATA)"; \
#	  echo "🐍 inspecting Python / torch runtime..."; \
#	  $(PY_RUN) $(ML_PIPE_PY_SCRIPTS)/inspect_runtime.py || true; \
#	  echo ">> [train] training -> $(MODEL_CKPT) (input=$(TRAIN_DATA))"; \
#	  $(PY_RUN) $(ML_PIPE_PY_MODEL)/train.py \
#	    --input "$(TRAIN_DATA)" \
#	    --out "$(MODEL_CKPT)" || { \
#	      echo "TIP: trainer expects JSONL at --input (we passed $(TRAIN_DATA))."; \
#	      exit 1; }; \
#	fi
#	@[ -s "$(MODEL_CKPT)" ] || { echo "❌ Expected model at $(MODEL_CKPT)."; exit 1; }
#	@echo "✅ model ready: $(MODEL_CKPT)"
# ==========================================================================


# 2.5.2.1. Python Filter (filter_jsonl.py): create cleaned dataset
#        (non-empty type/proof, optional length thresholds)
filter: $(VENV_DEPS)
	@if [ ! -s "$(TRAIN_DATA)" ]; then \
	  echo "ERROR: TRAIN_DATA missing at $(TRAIN_DATA). Set TRAIN_DATA=... or run 'make extract'."; \
	  exit 1; \
	fi
	@echo ">> [filter] $(TRAIN_DATA) -> $(DATA_FILTERED)"
	@$(PY_RUN) $(ML_PIPE_PY_MODEL)/filter_jsonl.py \
	  --input "$(TRAIN_DATA)" \
	  --out "$(DATA_FILTERED)" \
	  --min-type-len "$(MIN_TYPE_LEN)" \
	  --min-proof-len "$(MIN_PROOF_LEN)"
	@ROWS="$$(wc -l < "$(DATA_FILTERED)" | tr -d ' ')"; \
	if [ "$$ROWS" -eq 0 ]; then \
	  echo "❌ filter produced 0 rows: lower MIN_TYPE_LEN/MIN_PROOF_LEN or ensure proofs exist"; \
	  exit 2; \
	fi
	@echo "✅ filtered dataset: $(DATA_FILTERED)"


# === LEGACY — archived to experiments/archive/ (Issue M0-1) ====================
## ------------------------------------------------------------------------------
## 2.5.2.2. Python fine-tuning dataset builder (build_finetune_dataset.py): turn
##          AgdaData into instruction/output pairs.
#finetune-dataset: $(VENV_DEPS)
#	@if [ ! -s "$(DATA_FILTERED)" ]; then \
#	  echo "ERROR: DATA_FILTERED missing at $(DATA_FILTERED). Run 'make filter' first."; \
#	  exit 1; \
#	fi
#	@echo ">> [finetune] $(DATA_FILTERED) -> $(DATA_FINE_TUNE)"
#	@$(PY_RUN) $(ML_PIPE_PY_MODEL)/build_finetune_dataset.py \
#	  --input "$(DATA_FILTERED)" \
#	  --out "$(DATA_FINE_TUNE)"
#	@[ -s "$(DATA_FINE_TUNE)" ] || { echo "❌ Expected $(DATA_FINE_TUNE)."; exit 1; }
#	@echo "✅ fine-tuning dataset: $(DATA_FINE_TUNE)"
# ==========================================================================


# ------------------------------------------------------------------------------
# 2.5.3. New Python Trainer
#
# Committed smoke dataset (override if/when moved)
RETRIEVAL_DATASET_SMOKE ?= ml-pipeline/etl/src/test/resources/proof-completion.smoke.jsonl
# Canonical artifact path (checked into _build? no: this is a generated artifact)
RETRIEVAL_MODEL ?= models/proof_completion/retrieval_v0.pkl

# 2.5.3.0. Train target: `train-retrieval-smoke`
# Train a deterministic artifact from committed smoke dataset and writes canonical pickle.
train-retrieval-smoke:
	@set -euo pipefail; \
	if [ ! -f "$(RETRIEVAL_DATASET_SMOKE)" ]; then \
	  echo "ERROR: missing smoke dataset: $(RETRIEVAL_DATASET_SMOKE)"; \
	  echo "       (override RETRIEVAL_DATASET_SMOKE=... if needed)"; \
	  exit 1; \
	fi
	@mkdir -p "$(dir $(RETRIEVAL_MODEL))"
	@echo ">> training retrieval artifact"
	cd ml-pipeline && $(PY) python/model/train_retrieval.py \
	  --in  "$(abspath $(RETRIEVAL_DATASET_SMOKE))" \
	  --out "$(abspath $(RETRIEVAL_MODEL))"
	@test -s "$(RETRIEVAL_MODEL)" || { echo "ERROR: artifact missing/empty: $(RETRIEVAL_MODEL)"; exit 1; }
	@echo "✅ wrote $(RETRIEVAL_MODEL)"

# 2.5.3.1. Eval wrapper: `eval-proof-completion-smoke-retrieval`
# Run existing smoke evaluator using retrieval policy + model artifact.
eval-proof-completion-smoke-retrieval: train-retrieval-smoke
	@echo ">> eval-proof-completion-smoke (retrieval policy)"
	$(MAKE) -C agda-dojang eval-proof-completion-smoke \
	  EVAL_RUN_ID=smoke-retrieval \
	  EVAL_POLICY="python3 python/tools/policy_retrieval.py --model $(abspath $(RETRIEVAL_MODEL))" \
	  EVAL_XFAIL=FixtureLambda


# === LEGACY — archived to experiments/archive/ (Issue M0-1) ===============
## ------------------------------------------------------------------------------
## 2.6. Python Serve (app.py): FastAPI (uvicorn) using trained model.
#serve:
#	@set -e; \
#	if [ ! -s "$(MODEL_CKPT)" ]; then \
#	  echo "ERROR: model missing at $(MODEL_CKPT). Run 'make train' first."; \
#	  exit 1; \
#	fi; \
#	if [ ! -f "$(ML_PIPE_API)/app.py" ]; then \
#	  echo "⚠️  $(ML_PIPE_API)/app.py not found; skipping serve."; \
#	  exit 0; \
#	fi; \
#	echo ">> [serve] starting FastAPI (Ctrl-C to stop)"; \
#	cd "$(ML_PIPE_PY)" && \
#	  PYTHONPATH="$(ML_PIPE_PY)" \
#	  MODEL_PATH="$(abspath $(MODEL_CKPT))" \
#	  $(UVICORN) api.app:app --reload
# ==========================================================================

# ------------------------------------------------------------------------------
# 2.7. Bench: AgdaDojang dojo (still delegated for now)
bench:
	@echo ">> [bench] running AgdaDojang tiny benchmark"
	@$(MAKE) -C $(AGDA_DOJANG) solve

# ------------------------------------------------------------------------------
# 2.8. Scala Dataset Utilities (DatasetStats, PremiseEval)
DATASET ?= $(DATA_TRAIN)

dataset-stats:
	@if [ ! -s "$(DATASET)" ]; then \
	  echo "✖ DATASET missing or empty: $(DATASET)"; \
	  echo "  Provide it or override: make dataset-stats DATASET=../data/train.jsonl"; \
	  exit 1; \
	fi
	@echo "📊 [dataset-stats] on $(DATASET) (TOP=$(TOP))"
	cd $(STRUX_DRIVER) && \
	  $(SBT) $(SBT_FLAGS) "runMain struxdriver.util.DatasetStats $(DATASET) --top $(TOP)"

dataset-stats-sample: gen-sample
	@$(MAKE) dataset-stats DATASET="$(SAMPLE_JSONL)" TOP="$(TOP)"

premise-eval-quick-sample: gen-sample
	@$(MAKE) premise-eval-quick DATASET="$(SAMPLE_JSONL)" SPLIT="$(SPLIT)"

premise-eval: extract
	@$(MAKE) premise-eval-quick DATASET="$(DATA_TRAIN)" K="$(K)" SPLIT="$(SPLIT)"

premise-eval-quick:
	@if [ ! -s "$(DATASET)" ]; then \
	  echo "✖ DATASET missing or empty: $(DATASET)"; \
	  echo "  Provide it or override: make premise-eval-quick DATASET=../data/train.jsonl"; \
	  exit 1; \
	fi
	@echo "→ [premise-eval] on $(DATASET) (K=$(K) SPLIT=$(SPLIT))"
	cd $(STRUX_DRIVER) && \
	  $(SBT) $(SBT_FLAGS) "runMain struxdriver.util.PremiseEval $(DATASET) --k $(K) --split $(SPLIT)"

# ------------------------------------------------------------------------------
# 2.9. Top-level smoke tests
SMOKE_TARGETS  ?= gen-sample dataset-stats-sample premise-eval-quick-sample extract test backend-smoke
LOG_DIR        ?= $(DATA)/make-logs/$(shell date -u +"%Y%m%dT%H%M%SZ")
export LOG_DIR

smoke:
	@mkdir -p "$(LOG_DIR)"
	@echo "→ Top-level smoke on $$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")"
	@echo "→ logs: $(LOG_DIR)"
	@set -e; \
	for t in $(SMOKE_TARGETS); do \
	  echo "------------------------------------------------------------"; \
	  echo ">>> make $$t"; \
	  start=$$(date +%s); \
	  log="$(LOG_DIR)/$$t.log"; \
	  $(MAKE) --no-print-directory $$t >"$$log" 2>&1 || { \
	    echo "✖ Smoke failed at target: $$t"; \
	    echo "  see: $$log"; \
	    tail -n 60 "$$log" || true; \
	    exit 1; }; \
	  end=$$(date +%s); \
	  echo "✓ $$t ($$((end-start))s)"; \
	done; \
	echo "✓ smoke passed: $(SMOKE_TARGETS)"

smoke-nix:
	@mkdir -p "$(LOG_DIR)"
	@echo "→ Top-level smoke on $$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")"
	@echo "→ logs: $(LOG_DIR)"
	@set -e; \
	for t in $(SMOKE_TARGETS); do \
	  echo "------------------------------------------------------------"; \
	  echo ">>> make $$t"; \
	  start=$$(date +%s); \
	  log="$(LOG_DIR)/$$t.log"; \
	  $(NIX_ALL) "$(MAKE) --no-print-directory $$t" > "$$log" 2>&1 || { \
	    echo "✖ Smoke failed at target: $$t"; \
	    echo "  see: $$log"; \
	    tail -n 60 "$$log" || true; \
	    exit 1; }; \
	  end=$$(date +%s); \
	  echo "✓ $$t ($$((end-start))s)"; \
	done; \
	echo "✓ smoke-nix passed: $(SMOKE_TARGETS)"

gen-sample:
	@echo "→ Generating synthetic dataset: $(SAMPLE_JSONL)"
	cd $(STRUX_DRIVER) && \
	  $(SBT) $(SBT_FLAGS) "runMain struxdriver.util.SampleGen $(SAMPLE_JSONL) --n 16"
	@ls -lh "$(SAMPLE_JSONL)" || true

smoke-sample:
	@$(MAKE) gen-sample
	@$(MAKE) dataset-stats-sample TOP=10
	@$(MAKE) premise-eval-quick-sample

# -----------------------------------------------------------------------------
# 2.10. Proof Completion
#
.PHONY: eval-proof-completion eval-proof-completion-smoke demo-proof-completion demo-agent-bridge
#
eval-proof-completion eval-proof-completion-smoke demo-proof-completion demo-agent-bridge:
	$(MAKE) -C agda-dojang $@

# ------------------------------------------------------------------------------
ifeq ($(CI_SKIP_ML),1)
test-ml-pipeline:
	@echo ">> [test-ml-pipeline] skipped (CI_SKIP_ML=1)"
else
test-ml-pipeline: $(VENV_DEPS)
	@if [ ! -d "$(ML_PIPE)" ]; then \
	  echo "⚠️  ml-pipeline directory $(ML_PIPE) not found; skipping Python tests."; \
	else \
	  echo ">> [test-ml-pipeline] pytest in ml-pipeline/ (if tests present)"; \
	  cd $(ML_PIPE) && \
	    . "$(VENV)/bin/activate" && \
	    if find . \( -name 'test_*.py' -o -name '*_test.py' \) | grep -q .; then \
	      python -m pytest -q; \
	    else \
	      echo "No Python tests found in ml-pipeline; skipping pytest."; \
	    fi; \
	fi
endif

test-agda-dojang:
	@if ! command -v agda >/dev/null 2>&1; then \
	  echo "⚠️  Agda not found on PATH; skipping AgdaDojang tests."; \
	else \
	  if [ -d "$(AGDA_DOJANG)" ]; then \
	    echo ">> [test-agda-dojang] make -C $(AGDA_DOJANG) check"; \
	    $(MAKE) -C $(AGDA_DOJANG) check; \
	  else \
	    echo "⚠️  AgdaDojang directory $(AGDA_DOJANG) not found; skipping."; \
	  fi; \
	fi

test-all: test-strux-driver test-ml-pipeline test-agda-dojang backend-test
	@echo "✅ test-all completed."

test-integration: ## Run strux-driver end-to-end integration tests
	@echo ">> [test-integration] sbt testOnly *AgdaEndToEndSpec in strux-driver/"
	cd strux-driver && sbt "testOnly *AgdaEndToEndSpec"


#--------------------------------------------
# Library-specific train targets + `pipeline`
pipeline:
	@echo "→ Pipeline starting (EXTRACT_INPUT=$(EXTRACT_INPUT), TRAIN_DATA=$(TRAIN_DATA))"
	@echo "   USE_VENV=$(USE_VENV) TORCH_MODE=$(TORCH_MODE)"
	@echo "   SBT=$(SBT) SPARK_SUBMIT=$(SPARK_SUBMIT) PY=$(PY)"
	$(MAKE) extract
	$(MAKE) dataset-stats DATASET="$(TRAIN_DATA)"
	$(MAKE) filter TRAIN_DATA="$(TRAIN_DATA)"
	$(MAKE) finetune-dataset DATA_FILTERED="$(DATA_FILTERED)"
	$(MAKE) train TRAIN_DATA="$(DATA_FILTERED)"
	@echo "✓ Pipeline complete (TRAIN_DATA=$(TRAIN_DATA), DATA_FILTERED=$(DATA_FILTERED), DATA_FINE_TUNE=$(DATA_FINE_TUNE))"

pipeline-smoke:
	$(MAKE) pipeline MIN_TYPE_LEN=0 MIN_PROOF_LEN=0

# === LEGACY — archived to experiments/archive/ (Issue M0-1) ===============
#train-stdlib:
#	$(MAKE) pipeline \
#	  EXTRACT_INPUT="$(AGDA_STDLIB_SRC)" \
#	  TRAIN_DATA="$(DATA_STDLIB)" \
#	  DATA_FILTERED="$(DATA)/train-stdlib-2.2.filtered.jsonl" \
#	  DATA_FINE_TUNE="$(DATA)/train-stdlib-2.2.finetune.jsonl"
#
#train-algebras:
#	$(MAKE) pipeline \
#	  EXTRACT_INPUT="$(AGDA_ALGEBRAS_SRC)" \
#	  TRAIN_DATA="$(DATA_ALGEBRAS)" \
#	  DATA_FILTERED="$(DATA)/train-algebras.filtered.jsonl" \
#	  DATA_FINE_TUNE="$(DATA)/train-algebras.finetune.jsonl"
#
#train-categories:
#	$(MAKE) pipeline \
#	  EXTRACT_INPUT="$(AGDA_CATEGORIES_SRC)" \
#	  TRAIN_DATA="$(DATA_CATEGORIES)" \
#	  DATA_FILTERED="$(DATA)/train-categories.filtered.jsonl" \
#	  DATA_FINE_TUNE="$(DATA)/train-categories.finetune.jsonl"
# ==========================================================================



# ==============================================================================
# Section 3 — Legacy and misc
# ==============================================================================
#
# + `extract-algebras-legacy`
# + older ETL demos / stats if not used
# + `tree`, `wipe`, `clean`
#
# LEGACY TARGETS (keep for now, for reference and backward compatibility)
#
# Keep the old wrapper, but rename it so it stops clobbering the backend target
extract-algebras-legacy: _ensure-dirs _check-sbt
	@if [ ! -d "$(AGDA_ALGEBRAS_SRC)" ]; then \
	  echo "ERROR: AGDA_ALGEBRAS_SRC not found at '$(AGDA_ALGEBRAS_SRC)'."; \
	  echo "       Override AGDA_ALGEBRAS_ROOT=/path/to/agda-algebras"; \
	  exit 1; \
	fi
	@$(MAKE) extract EXTRACT_INPUT="$(AGDA_ALGEBRAS_SRC)" DATA_TRAIN="$(DATA_ALGEBRAS)"


# ------------------------------------------------------------------------------
# 10) Cleaning
clean:
	@rm -f $(DATA_TRAIN) $(RAW_JSON)

wipe:
	@echo "🧹 wipe generated artifacts"
	@rm -f $(RAW_JSON) $(DATA_TRAIN)
	@rm -rf $(ML_PIPE_FEATURES) $(ML_PIPE_MODELS)
	@echo "✅ wipe complete"

# ------------------------------------------------------------------------------
# 11) Utility: tree
TREE_IGNORE := .gitignore|.venv-cu121|.vscode|_build|.metals|.bloop|.tmp_*|.scratch_*|__pycache__|*.agdai|share|.git|.direnv|.venv|.mypy_cache|.pytest_cache|target|project|node_modules

tree:
	@echo ">> Clean directory tree (excluding: '$(TREE_IGNORE)')"
	@if command -v tree >/dev/null 2>&1; then \
	  tree -a -I '$(TREE_IGNORE)' -F; \
	else \
	  echo "(hint: install 'tree' for nicer output)"; \
	  find . \
	    -path "*/_build" -prune -o \
	    -path "./.metals" -prune -o \
	    -path "*/.bloop" -prune -o \
	    -path "*/__pycache__" -prune -o \
	    -name "*.agdai" -prune -o \
	    -name ".git" -prune -o \
	    -name ".direnv" -prune -o \
	    -name ".venv" -prune -o \
	    -name ".mypy_cache" -prune -o \
	    -name ".pytest_cache" -prune -o \
	    -name "target" -prune -o \
	    -print | sed -e 's|^\./||' | awk -F/ '{indent=""; for (i=1;i<NF;i++) indent=indent"  "; print indent "└─ " $$NF}'; \
	fi

# end
