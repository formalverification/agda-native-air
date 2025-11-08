##
# proof-parser — subproject Makefile
#
# @file agda-ai-prover/proof-parser/Makefile
# @version 0.1
# Focus: Scala utilities (stats, premise benchmark) + local smoke test
##

SBT          ?= sbt
PKG          ?= proofparser
MAIN_STATS   ?= $(PKG).DatasetStats
MAIN_PREM    ?= $(PKG).PremiseEval

# --- knobs ---
# Defaults can be overridden in CLI:
#   make dataset-stats DATASET=../data/train.jsonl TOP=30
#   make premise-eval DATASET=../data/train.jsonl K=10 SPLIT=90
DATASET ?= ../data/train.jsonl
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
	@echo "  make dataset-stats        - summarize a JSONL dataset"
	@echo "  make premise-eval         - run premise-selection baselines"
	@echo "  make premise-eval-quick   - quick run (K=5)"
	@echo "  make smoke                - compile + quick eval (smoke test)"
	@echo ""
	@echo "Knobs: DATASET=../data/train.jsonl TOP=20 K=10 SPLIT=90"
	@echo ""

.PHONY: compile
compile:
	$(SBT) $(SBT_FLAGS) compile

.PHONY: test
test:
	$(SBT) $(SBT_FLAGS) test

# Guard: DATASET must exist and be non-empty for runs that read data
define _require_dataset
	@if [ ! -s "$(DATASET)" ]; then \
	  echo "✖ DATASET missing: $(DATASET)"; \
	  echo "  Provide it or override: make $@ DATASET=../data/train.jsonl"; \
	  exit 1; \
	fi
endef

.PHONY: dataset-stats
dataset-stats:
	$(call _require_dataset)
	@echo "→ DatasetStats on $(DATASET) (TOP=$(TOP))"
	@$(SBT) $(SBT_FLAGS) "runMain $(MAIN_STATS) $(DATASET) --top $(TOP)"

.PHONY: premise-eval
premise-eval:
	$(call _require_dataset)
	@echo "→ PremiseEval on $(DATASET) (K=$(K) SPLIT=$(SPLIT))"
	@$(SBT) $(SBT_FLAGS) "runMain $(MAIN_PREM) $(DATASET) --k $(K) --split $(SPLIT)"

.PHONY: premise-eval-quick
premise-eval-quick:
	$(MAKE) premise-eval K=5 DATASET="$(DATASET)" SPLIT="$(SPLIT)"

# Local smoke test: build + a lightweight run
.PHONY: smoke
smoke: compile premise-eval-quick
	@echo "✓ proof-parser smoke OK"

# --- generate a tiny synthetic dataset ---
.PHONY: gen-sample
gen-sample:
	@mkdir -p ../data
	@echo "→ Generating synthetic dataset: ../data/sample.jsonl (N=$(N))"
	@$(SBT) -error -no-colors "runMain proofparser.SampleGen ../data/sample.jsonl --n $(N)"
	@ls -lh ../data/sample.jsonl || true

# --- local smoke can use the sample if desired ---
.PHONY: smoke-sample
smoke-sample: gen-sample
	$(MAKE) dataset-stats DATASET=../data/sample.jsonl TOP=10
	$(MAKE) premise-eval-quick DATASET=../data/sample.jsonl
	@echo "✓ proof-parser smoke (sample) OK"

# end
