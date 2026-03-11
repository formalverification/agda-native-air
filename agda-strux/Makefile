##
# agda-strux
#
# @file agda-strux/Makefile
# @version 0.1

.PHONY: build bin test smoke clean

# Build the executable (no run).
build:
	cabal update
	cabal build exe:agda-json

# Print the resolved path to the built executable.
bin: build
	@cabal list-bin exe:agda-json

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
	  --input  ../data/agda/agda-example.agda \
	  --output "$$out" \
	  --include ../proof-parser/src/test/resources; \
	test -s "$$out"; \
	echo "[smoke] first 5 lines:"; \
	head -n 5 "$$out"

# end
