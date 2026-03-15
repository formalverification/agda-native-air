# doc_check.py — annotation guide

## How it works

Place an HTML comment `<!-- doc-test: TAG -->` immediately before any fenced
code block that should be tested.  The TAG is a short label (no spaces).

Blocks WITHOUT the annotation are silently skipped — so most of HowToRun.md
remains untouched.

## Example: annotating HowToRun.md

You only need to annotate the blocks you actually want tested.  For instance:

### Quick Start (skip `git clone` and `cd`, test the rest)

The Quick Start block includes `git clone` which isn't runnable in a test.
So instead, annotate a separate "just the make commands" block:

    <!-- doc-test: quick-check -->
    ```sh
    make check
    ```

    <!-- doc-test: quick-eval-smoke -->
    ```sh
    make eval-proof-completion-smoke
    ```

### §2.2 (check)

    <!-- doc-test: check -->
    ```sh
    make check
    ```

### §3 (backend)

    <!-- doc-test: backend-test -->
    ```sh
    make backend-test
    ```

    <!-- doc-test: backend-smoke -->
    ```sh
    make backend-smoke
    ```

### §4 (strux-driver)

    <!-- doc-test: strux-driver -->
    ```sh
    make test-strux-driver
    ```

### §5.2.1 (eval smoke)

    <!-- doc-test: eval-smoke -->
    ```sh
    make eval-proof-completion-smoke
    ```

### Blocks to NOT annotate (examples with placeholders)

These are illustrative and shouldn't be tested:

    ```sh
    make extract EXTRACT_INPUT=/path/to/Thing.agda TRAIN_DATA=/tmp/out.jsonl
    ```

    ```sh
    make dataset-stats DATASET=/path/to/train.jsonl TOP=50
    ```

## Usage

    # See what would be tested:
    python3 scripts/python/doc_check.py docs/HowToRun.md --dry-run

    # Run all annotated blocks:
    python3 scripts/python/doc_check.py docs/HowToRun.md --run -v

    # Generate a Makefile target:
    python3 scripts/python/doc_check.py docs/HowToRun.md --makefile >> Makefile

    # Test only backend-related blocks:
    python3 scripts/python/doc_check.py docs/HowToRun.md --run --filter 'backend'

## Suggested Makefile target

    test-doc-howtorun:
    	@echo "→ testing documented commands from docs/HowToRun.md"
    	python3 scripts/python/doc_check.py docs/HowToRun.md --run -v
