##
# AgdaJang
#
# @file Makefile
# @version 0.1

AGDA ?= agda
AGDA_DIR := agda
PYTHON_DIR := python
PYTHON := python3
JANG_TRY := $(PYTHON_DIR)/tools/jang_try.py
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
