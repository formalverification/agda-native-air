##
# AgdaJang Makefile
#
# @file ./agda-jang/Makefile
# @version 0.1

AGDA ?= agda
AGDA_FLAGS ?= -l agda-jang

PYTHON := python3
PYTHON_TOOLS := python/tools
JANG_TRY := $(PYTHON_TOOLS)/jang_try.py
DEMO1 := --goal Nat --candidate "suc zero" --imports "open import Agda.Builtin.Nat"
DEMO2 := --goal Nat --tactic applyReport:_+_ --imports "open import Agda.Builtin.Nat"

.PHONY: check demo1 demo2 clean

check:
	$(AGDA) $(AGDA_FLAGS) agda/AgdaJang/Everything.agda

demo1:
	$(PYTHON) $(JANG_TRY) $(DEMO1) --agda-flags "$(AGDA_FLAGS)"

demo2:
	$(PYTHON) $(JANG_TRY) $(DEMO2) --agda-flags "$(AGDA_FLAGS)"

clean:
	rm -rf .tmp_* .scratch_* __pycache__ */__pycache__
# end
