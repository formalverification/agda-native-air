##
# proof-parser — subproject Makefile
#
# @file agda-ai-prover/proof-parser/Makefile
# @version 0.2
# Focus: Scala utilities (extract/transform/reduce/stats/benchmark) + local smoke
##

SBT          ?= sbt
PKG          ?= proofparser

MAIN_STATS   ?= $(PKG).DatasetStats
MAIN_PREM    ?= $(PKG).PremiseEval
MAIN_EXTRACT ?= $(PKG).AgdaExtractorMain
MAIN_A2T_XFM ?= $(PKG).Agda2TrainTransformer
MAIN_A2T_RED ?= $(PKG).Agda2TrainReducer

SBT_FLAGS    ?= -error -no-colors

# --- knobs / defaults (overridable) ------------------------------------------
# DATASET knobs are for stats/benchmark
DATASET ?= ../data/train.jsonl
TOP     ?= 20
K       ?= 10
SPLIT   ?= 90
N       ?= 16     # rows for synthetic generator

# Extraction / transform defaults (relative to this dir)
EXTRACT_INPUT   ?= src/test/resources/agda-example.agda
EXTRACT_OUTPUT  ?= ../data/train.jsonl

A2T_JSON        ?= src/test/resources/proofparser/agda-example.json
A2T_OUT         ?= ../target/a2t.simple.jsonl
A2T_REDUCED_OUT ?= ../data/a2t.simple.jsonl

.PHONY: help compile test \
        dataset-stats premise-eval premise-eval-quick \
        smoke gen-sample smoke-sample \
        extract transform a2t

help:
	@echo ""
	@echo "proof-parser targets:"
	@echo "  make compile              - sbt compile (this subproject)"
	@echo "  make test                 - sbt test"
	@echo "  make extract              - .agda -> AgdaData JSONL (AgdaExtractorMain)"
	@echo "  make transform            - agda2train JSON -> AgdaData JSONL (Agda2TrainTransformer)"
	@echo "  make a2t                  - agda2train JSON -> TrainRecord JSONL (Agda2TrainReducer)"
	@echo "  make dataset-stats        - summarize a JSONL dataset"
	@echo "  make premise-eval         - run premise-selection baselines"
	@echo "  make premise-eval-quick   - quick run (K=5)"
	@echo "  make gen-sample           - generate ../data/sample.jsonl"
	@echo "  make smoke                - compile + quick eval (smoke test)"
	@echo "  make smoke-sample         - sample-based smoke"
	@echo ""
	@echo "Knobs (override on CLI):"
	@echo "  DATASET=$(DATASET) TOP=$(TOP) K=$(K) SPLIT=$(SPLIT)"
	@echo "  EXTRACT_INPUT=$(EXTRACT_INPUT)"
	@echo "  EXTRACT_OUTPUT=$(EXTRACT_OUTPUT)"
	@echo "  A2T_JSON=$(A2T_JSON)"
	@echo "  A2T_OUT=$(A2T_OUT)"
	@echo "  A2T_REDUCED_OUT=$(A2T_REDUCED_OUT)"
	@echo ""

compile:
	$(SBT) $(SBT_FLAGS) compile

test:
	$(SBT) $(SBT_FLAGS) test

# ------------------------------------------------------------------------------
# Extract: .agda -> AgdaData JSONL
extract:
	@if [ ! -e "$(EXTRACT_INPUT)" ]; then \
	  echo "✖ EXTRACT_INPUT missing: $(EXTRACT_INPUT)"; \
	  echo "  Override: make extract EXTRACT_INPUT=path/to/YourFile.agda"; \
	  exit 1; \
	fi
	@echo "→ AgdaExtractorMain: $(EXTRACT_INPUT) -> $(EXTRACT_OUTPUT)"
	@mkdir -p $$(dirname "$(EXTRACT_OUTPUT)")
	@$(SBT) $(SBT_FLAGS) "runMain $(MAIN_EXTRACT) $(abspath $(EXTRACT_INPUT)) $(abspath $(EXTRACT_OUTPUT))"
	@[ -s "$(EXTRACT_OUTPUT)" ] || { echo "✖ Expected non-empty $(EXTRACT_OUTPUT)"; exit 1; }

# ------------------------------------------------------------------------------
# Transform: agda2train JSON -> AgdaData JSONL
transform:
	@if [ ! -e "$(A2T_JSON)" ]; then \
	  echo "✖ A2T_JSON missing: $(A2T_JSON)"; \
	  echo "  Override: make transform A2T_JSON=path/to/agda2train.json"; \
	  exit 1; \
	fi
	@echo "→ Agda2TrainTransformer: $(A2T_JSON) -> $(A2T_OUT)"
	@mkdir -p $$(dirname "$(A2T_OUT)")
	@$(SBT) $(SBT_FLAGS) "runMain $(MAIN_A2T_XFM) $(abspath $(A2T_JSON)) $(abspath $(A2T_OUT))"
	@[ -s "$(A2T_OUT)" ] || { echo "✖ Expected non-empty $(A2T_OUT)"; exit 1; }

# ------------------------------------------------------------------------------
# Reducer: agda2train JSON -> TrainRecord JSONL (simplified schema)
a2t:
	@if [ ! -e "$(A2T_JSON)" ]; then \
	  echo "✖ A2T_JSON missing: $(A2T_JSON)"; \
	  echo "  Override: make a2t A2T_JSON=path/to/agda2train.json"; \
	  exit 1; \
	fi
	@echo "→ Agda2TrainReducer: $(A2T_JSON) -> $(A2T_REDUCED_OUT)"
	@mkdir -p $$(dirname "$(A2T_REDUCED_OUT)")
	@$(SBT) $(SBT_FLAGS) "runMain $(MAIN_A2T_RED) $(abspath $(A2T_JSON)) $(abspath $(A2T_REDUCED_OUT))"
	@[ -s "$(A2T_REDUCED_OUT)" ] || { echo "✖ Expected non-empty $(A2T_REDUCED_OUT)"; exit 1; }

# ------------------------------------------------------------------------------
# Guard: DATASET must exist and be non-empty for runs that read data
define _require_dataset
	@if [ ! -s "$(DATASET)" ]; then \
	  echo "✖ DATASET missing: $(DATASET)"; \
	  echo "  Provide it or override: make $@ DATASET=../data/train.jsonl"; \
	  exit 1; \
	fi
endef

dataset-stats:
	$(call _require_dataset)
	@echo "→ DatasetStats on $(DATASET) (TOP=$(TOP))"
	@$(SBT) $(SBT_FLAGS) "runMain $(MAIN_STATS) $(DATASET) --top $(TOP)"

premise-eval:
	$(call _require_dataset)
	@echo "→ PremiseEval on $(DATASET) (K=$(K) SPLIT=$(SPLIT))"
	@$(SBT) $(SBT_FLAGS) "runMain $(MAIN_PREM) $(DATASET) --k $(K) --split $(SPLIT)"

premise-eval-quick:
	$(MAKE) premise-eval K=5 DATASET="$(DATASET)" SPLIT="$(SPLIT)"

# Local smoke test: build + quick eval
smoke: compile premise-eval-quick
	@echo "✓ proof-parser smoke OK"

# --- generate a tiny synthetic dataset ---
gen-sample:
	@mkdir -p ../data
	@echo "→ Generating synthetic dataset: ../data/sample.jsonl (N=$(N))"
	@$(SBT) $(SBT_FLAGS) "runMain proofparser.SampleGen ../data/sample.jsonl --n $(N)"
	@ls -lh ../data/sample.jsonl || true

smoke-sample: gen-sample
	$(MAKE) dataset-stats DATASET=../data/sample.jsonl TOP=10
	$(MAKE) premise-eval-quick DATASET=../data/sample.jsonl
	@echo "✓ proof-parser smoke (sample) OK"

# end
