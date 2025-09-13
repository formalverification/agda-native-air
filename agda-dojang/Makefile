##
# AgdaJang Makefile
#
# @file ./agda-jang/Makefile
# @version 0.1

AGDA ?= agda
AGDA_DIR := agda
AGDA_FLAGS ?= -l agda-jang
#AGDA_FLAGS ?= -l standard-library -i agda

export PYTHONPATH := python

PYTHON_DIR := python
PYTHON := python3
PYTHON_TOOLS := python/tools
JANG_TRY := $(PYTHON_TOOLS)/jang_try.py
DEMO1 := --goal Nat --candidate "suc zero" --imports "open import Agda.Builtin.Nat"
DEMO2 := --goal Nat --tactic applyReport:_+_ --imports "open import Agda.Builtin.Nat"


.PHONY: check demo clean

check:
	$(AGDA) -i $(AGDA_DIR) $(AGDA_DIR)/AgdaJang/Everything.agda

demo1:
	$(PYTHON) $(JANG_TRY) $(DEMO1)

demo2:
	$(PYTHON) $(JANG_TRY) $(DEMO2)

clean:
	rm -rf .tmp_* .scratch_* __pycache__ */__pycache__

# end
