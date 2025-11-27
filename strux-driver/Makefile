# ==============================================================================
# Makefile
# --------
#
# @file agda-ai-prover/proof-parser/Makefile
# @version 0.2
#
# Description
# -----------
# Makefile for the proofparser package.
#
# Focus
# -----
# -  Scala utilities (extract/transform/reduce/stats/benchmark):
#    -  Extract / transform / reduce Agda JSON
#    -  Dataset stats + premise-selection baselines
# -  Local smoke tests
# ==============================================================================
SBT          ?= sbt
PKG          ?= proofparser
MAIN_STATS   ?= $(PKG).DatasetStats
MAIN_PREM    ?= $(PKG).PremiseEval

# --- knobs (overridable from the top-level) -----------------------------------
DATA_DIR        ?= ../data
TRAIN_JSONL     ?= $(DATA_DIR)/train.jsonl

# Example Agda + JSON fixtures
EXTRACT_INPUT   ?= src/test/resources/agda-example.agda
A2T_JSON_INPUT  ?= src/test/resources/proofparser/agda-example.json
A2T_OUT         ?= ../target/a2t.simple.jsonl
DATA_A2T_SIMPLE ?= $(DATA_DIR)/a2t.simple.jsonl

DATASET ?= $(TRAIN_JSONL)
TOP     ?= 20
K       ?= 10
SPLIT   ?= 90
N       ?= 16     # rows for synthetic generator

SBT_FLAGS ?= -error -no-colors

.PHONY: help
help:
	@echo ""
	@echo "proof-parser targets:"
	@echo "  make compile              - sbt compile (this subproject)"
	@echo "  make test                 - sbt test"
	@echo "  make extract              - AgdaExtractorMain (.agda|dir -> TRAIN_JSONL)"
	@echo "  make transform            - Agda2TrainTransformer (JSON -> A2T_OUT)"
	@echo "  make a2t                  - Agda2TrainReducer (JSON -> DATA_A2T_SIMPLE)"
	@echo "  make dataset-stats        - summarize a JSONL dataset"
	@echo "  make premise-eval         - run premise-selection baselines"
	@echo "  make premise-eval-quick   - quick run (K=5)"
	@echo "  make gen-sample           - generate ../data/sample.jsonl (synthetic)"
	@echo "  make smoke                - compile + quick eval (smoke test)"
	@echo ""
	@echo "Knobs: DATASET=$(DATASET) TOP=$(TOP) K=$(K) SPLIT=$(SPLIT)"
	@echo "       TRAIN_JSONL=$(TRAIN_JSONL)"
	@echo "       EXTRACT_INPUT=$(EXTRACT_INPUT)"
	@echo "       A2T_JSON_INPUT=$(A2T_JSON_INPUT)"
	@echo ""

.PHONY: compile
compile:
	$(SBT) $(SBT_FLAGS) compile

.PHONY: test
test:
	$(SBT) $(SBT_FLAGS) test

# ------------------------------------------------------------------------------
# Extract: AgdaExtractorMain
.PHONY: extract
extract:
	@if [ ! -e "$(EXTRACT_INPUT)" ]; then \
	  echo "✖ EXTRACT_INPUT missing: $(EXTRACT_INPUT)"; \
	  echo "  Override with: make extract EXTRACT_INPUT=/path/to/foo.agda"; \
	  exit 1; \
	fi
	@mkdir -p $(dir $(TRAIN_JSONL))
	@echo "→ AgdaExtractorMain: $(EXTRACT_INPUT) -> $(TRAIN_JSONL)"
	@$(SBT) $(SBT_FLAGS) "runMain proofparser.AgdaExtractorMain $(abspath $(EXTRACT_INPUT)) $(abspath $(TRAIN_JSONL))"
	@[ -s "$(TRAIN_JSONL)" ] || { echo "❌ Expected $(TRAIN_JSONL)."; exit 1; }

# Transform: Agda2TrainTransformer
.PHONY: transform
transform:
	@if [ ! -e "$(A2T_JSON_INPUT)" ]; then \
	  echo "✖ A2T_JSON_INPUT missing: $(A2T_JSON_INPUT)"; \
	  exit 1; \
	fi
	@mkdir -p $(dir $(A2T_OUT))
	@echo "→ Agda2TrainTransformer: $(A2T_JSON_INPUT) -> $(A2T_OUT)"
	@$(SBT) $(SBT_FLAGS) "runMain proofparser.Agda2TrainTransformer $(abspath $(A2T_JSON_INPUT)) $(abspath $(A2T_OUT))"
	@[ -s "$(A2T_OUT)" ] || { echo "❌ Expected $(A2T_OUT)."; exit 1; }

# Reducer: Agda2TrainReducer
.PHONY: a2t
a2t:
	@if [ ! -e "$(A2T_JSON_INPUT)" ]; then \
	  echo "✖ A2T_JSON_INPUT missing: $(A2T_JSON_INPUT)"; \
	  exit 1; \
	fi
	@mkdir -p $(dir $(DATA_A2T_SIMPLE))
	@echo "→ Agda2TrainReducer: $(A2T_JSON_INPUT) -> $(DATA_A2T_SIMPLE)"
	@$(SBT) $(SBT_FLAGS) "runMain proofparser.Agda2TrainReducer $(abspath $(A2T_JSON_INPUT)) $(abspath $(DATA_A2T_SIMPLE))"
	@[ -s "$(DATA_A2T_SIMPLE)" ] || { echo "❌ Expected $(DATA_A2T_SIMPLE)."; exit 1; }

# ------------------------------------------------------------------------------
# Guard: DATASET must exist and be non-empty
define _require_dataset
	@if [ ! -s "$(DATASET)" ]; then \
	  echo "✖ DATASET missing or empty: $(DATASET)"; \
	  echo "  Provide it or override: make $@ DATASET=../data/train.jsonl"; \
	  exit 1; \
	fi
endef

.PHONY: dataset-stats
dataset-stats:
	$(call _require_dataset)
	@echo "📊 DatasetStats on $(DATASET) (TOP=$(TOP))"
	@$(SBT) $(SBT_FLAGS) "runMain $(MAIN_STATS) $(DATASET) --top $(TOP)"

.PHONY: premise-eval
premise-eval:
	$(call _require_dataset)
	@echo "→ PremiseEval on $(DATASET) (K=$(K) SPLIT=$(SPLIT))"
	@$(SBT) $(SBT_FLAGS) "runMain $(MAIN_PREM) $(DATASET) --k $(K) --split $(SPLIT)"

.PHONY: premise-eval-quick
premise-eval-quick:
	$(MAKE) premise-eval K=5 DATASET="$(DATASET)" SPLIT="$(SPLIT)"

# Local smoke test: build + quick eval
.PHONY: smoke
smoke: compile premise-eval-quick
	@echo "✓ proof-parser smoke OK"

# --- generate a tiny synthetic dataset ---
.PHONY: gen-sample
gen-sample:
	@mkdir -p ../data
	@echo "→ Generating synthetic dataset: ../data/sample.jsonl (N=$(N))"
	@$(SBT) $(SBT_FLAGS) "runMain proofparser.SampleGen ../data/sample.jsonl --n $(N)"
	@ls -lh ../data/sample.jsonl || true

.PHONY: smoke-sample
smoke-sample: gen-sample
	$(MAKE) dataset-stats DATASET=../data/sample.jsonl TOP=10
	$(MAKE) premise-eval-quick DATASET=../data/sample.jsonl
	@echo "✓ proof-parser smoke (sample) OK"

# end
