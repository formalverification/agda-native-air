##
# agda-backend-jsonl
#
# @file agda-backend-jsonl/Makefile
# @version 0.1

.PHONY: test smoke clean

test:
	cabal update
	cabal test

# Runs the backend on the shared proof-parser test file.
# Fails if the output is empty.
smoke:
	@set -eu; \
	tmp="$$(mktemp -d)"; \
	out="$$tmp/agda-example.jsonl"; \
	echo "[smoke] writing $$out"; \
	cabal run agda-json -- \
	  --input  ../proof-parser/src/test/resources/agda-example.agda \
	  --output "$$out" \
	  --include ../proof-parser/src/test/resources; \
	test -s "$$out"; \
	echo "[smoke] first 5 lines:"; \
	head -n 5 "$$out"


# end
