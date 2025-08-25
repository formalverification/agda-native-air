##
# AgdaJang
#
# @file Makefile
# @version 0.1

AGDA ?= agda
AGDA_DIR := agda
EXAMPLES := \
	python3 tools/jang_try.py --goal Nat --candidate "suc zero" --imports "open import Agda.Builtin.Nat" && \
	python3 tools/jang_try.py --goal Nat --tactic applyReport:_+_ --imports "open import Agda.Builtin.Nat"

.PHONY: check demo clean

check:
	$(AGDA) -i $(AGDA_DIR) $(AGDA_DIR)/AgdaJang/Everything.agda

demo:
	$(EXAMPLES)

clean:
	rm -rf .tmp_* .scratch_* __pycache__ */__pycache__


# end
