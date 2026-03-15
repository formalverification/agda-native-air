#!/usr/bin/env python3
"""
doc_check.py — Extract and run testable commands from markdown documentation.

File: scripts/python/doc_check.py

Description
-----------
Scans a markdown file for fenced code blocks annotated with a special
`<!-- doc-test: TAG -->` comment and extracts the shell commands from them.
It can either print the commands (dry-run), generate a Makefile target, or
run them directly with pass/fail reporting.

The annotation convention is lightweight: place an HTML comment *immediately
before* a fenced code block to mark it as testable:

    <!-- doc-test: check -->
    ```sh
    make check
    ```

The TAG (e.g., "check") is used as a label in output.  Multiple commands
inside a single block are run sequentially; if any fails, the block fails.

Blocks without the `<!-- doc-test: ... -->` annotation are silently skipped.
This keeps the markdown readable while giving precise control over what gets
tested.

Usage
-----
    # Dry-run: list extracted commands
    python3 scripts/python/doc_check.py docs/HowToRun.md --dry-run

    # Run all tagged blocks and report pass/fail
    python3 scripts/python/doc_check.py docs/HowToRun.md --run -v

    # Generate a Makefile fragment
    python3 scripts/python/doc_check.py docs/HowToRun.md --makefile

    # Run only blocks matching a tag pattern
    python3 scripts/python/doc_check.py docs/HowToRun.md --run --filter 'check|backend'

How it fits into the project
----------------------------
This script supports Issue M0-2 (verify and document the clone → nix develop →
test → eval workflow) by making documentation claims testable.  It is invoked
by the `make test-doc-howtorun` target in the top-level Makefile.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional, Sequence


# ---------------------------------------------------------------------------
# Data types
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class DocBlock:
    """A single testable code block extracted from a markdown file."""
    tag: str
    commands: tuple[str, ...]
    source_line: int  # 1-based line number of the annotation comment

    def label(self) -> str:
        return f"{self.tag} (line {self.source_line})"


@dataclass
class RunResult:
    """Result of running a single DocBlock."""
    block: DocBlock
    passed: bool
    elapsed_s: float
    outputs: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Extraction
# ---------------------------------------------------------------------------

_ANNOTATION_RE: re.Pattern[str] = re.compile(
    r"<!--\s*doc-test:\s*(\S+)\s*-->", re.IGNORECASE
)

_FENCE_OPEN_RE: re.Pattern[str] = re.compile(
    r"^```(?:sh|bash|zsh)\s*$"
)

_FENCE_CLOSE_RE: re.Pattern[str] = re.compile(
    r"^```\s*$"
)


def extract_blocks(path: Path) -> list[DocBlock]:
    """Parse a markdown file and return all annotated code blocks."""
    lines: list[str] = path.read_text(encoding="utf-8").splitlines()
    blocks: list[DocBlock] = []

    i: int = 0
    while i < len(lines):
        line: str = lines[i].strip()
        m = _ANNOTATION_RE.search(line)
        if m is None:
            i += 1
            continue

        tag: str = m.group(1)
        annotation_line: int = i + 1  # 1-based

        # Advance past optional blank lines to find the fence opener.
        j: int = i + 1
        while j < len(lines) and lines[j].strip() == "":
            j += 1

        if j >= len(lines) or not _FENCE_OPEN_RE.match(lines[j].strip()):
            # Annotation without a following code block — skip.
            i = j
            continue

        # Collect lines inside the fence.
        k: int = j + 1
        cmds: list[str] = []
        while k < len(lines):
            if _FENCE_CLOSE_RE.match(lines[k].strip()):
                break
            raw: str = lines[k].rstrip()
            # Skip empty lines and comments inside the block.
            stripped: str = raw.strip()
            if stripped and not stripped.startswith("#"):
                cmds.append(stripped)
            k += 1

        if cmds:
            blocks.append(DocBlock(
                tag=tag,
                commands=tuple(cmds),
                source_line=annotation_line,
            ))

        i = k + 1

    return blocks


# ---------------------------------------------------------------------------
# Filtering
# ---------------------------------------------------------------------------

def filter_blocks(
    blocks: list[DocBlock],
    pattern: Optional[str],
) -> list[DocBlock]:
    """Return blocks whose tag matches the given regex pattern (or all)."""
    if pattern is None:
        return blocks
    rx: re.Pattern[str] = re.compile(pattern, re.IGNORECASE)
    return [b for b in blocks if rx.search(b.tag)]


# ---------------------------------------------------------------------------
# Execution
# ---------------------------------------------------------------------------

def run_block(block: DocBlock, verbose: bool = False) -> RunResult:
    """Run all commands in a block sequentially; stop on first failure."""
    start: float = time.monotonic()
    outputs: list[str] = []
    errors: list[str] = []
    passed: bool = True

    for cmd in block.commands:
        if verbose:
            print(f"  $ {cmd}", flush=True)
        try:
            result: subprocess.CompletedProcess[str] = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=300,  # 5-minute ceiling per command
            )
            outputs.append(result.stdout)
            if result.returncode != 0:
                errors.append(
                    f"rc={result.returncode} for: {cmd}\n"
                    f"  stderr: {result.stderr.strip()[:500]}"
                )
                passed = False
                break
        except subprocess.TimeoutExpired:
            errors.append(f"TIMEOUT (300s) for: {cmd}")
            passed = False
            break
        except Exception as e:
            errors.append(f"EXCEPTION for: {cmd}\n  {e}")
            passed = False
            break

    elapsed: float = time.monotonic() - start
    return RunResult(
        block=block,
        passed=passed,
        elapsed_s=elapsed,
        outputs=outputs,
        errors=errors,
    )


def run_all(
    blocks: list[DocBlock],
    verbose: bool = False,
) -> list[RunResult]:
    """Run all blocks and return results."""
    results: list[RunResult] = []
    for block in blocks:
        print(f">>> {block.label()}", flush=True)
        r: RunResult = run_block(block, verbose=verbose)
        status: str = "✓" if r.passed else "✖"
        print(f"  {status} ({r.elapsed_s:.1f}s)", flush=True)
        if not r.passed:
            for err in r.errors:
                for line in err.splitlines():
                    print(f"    {line}")
        results.append(r)
    return results


# ---------------------------------------------------------------------------
# Output: dry-run
# ---------------------------------------------------------------------------

def print_dry_run(blocks: list[DocBlock]) -> None:
    """Print extracted blocks without running them."""
    for block in blocks:
        print(f"[{block.label()}]")
        for cmd in block.commands:
            print(f"  {cmd}")
        print()


# ---------------------------------------------------------------------------
# Output: Makefile fragment
# ---------------------------------------------------------------------------

def print_makefile(blocks: list[DocBlock], doc_path: Path) -> None:
    """Print a Makefile target that runs the extracted commands."""
    safe_name: str = doc_path.stem.replace("-", "_").lower()
    target: str = f"test-doc-{safe_name}"

    print(f"# Auto-generated from {doc_path}")
    print(f"# Blocks: {len(blocks)}")
    print(f".PHONY: {target}")
    print(f"{target}:")
    print(f'\t@echo "→ testing documented commands from {doc_path} ({len(blocks)} blocks)"')

    for block in blocks:
        print(f'\t@echo ">>> {block.tag} (line {block.source_line})"')
        for cmd in block.commands:
            # Escape dollar signs for Make.
            escaped: str = cmd.replace("$", "$$")
            print(f"\t{escaped}")

    print(f'\t@echo "✓ {target}: all {len(blocks)} blocks passed"')


# ---------------------------------------------------------------------------
# Output: summary
# ---------------------------------------------------------------------------

def print_summary(results: list[RunResult]) -> int:
    """Print a summary table and return exit code (0 = all pass)."""
    passed: int = sum(1 for r in results if r.passed)
    failed: int = len(results) - passed

    print()
    print(f"{'tag':<30} {'status':<8} {'time':>8}")
    print("-" * 50)
    for r in results:
        s: str = "PASS" if r.passed else "FAIL"
        print(f"{r.block.tag:<30} {s:<8} {r.elapsed_s:>7.1f}s")
    print("-" * 50)
    print(f"Total: {passed} passed, {failed} failed")

    return 0 if failed == 0 else 1


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    ap: argparse.ArgumentParser = argparse.ArgumentParser(
        description="Extract and test shell commands from annotated markdown.",
    )
    ap.add_argument(
        "doc",
        type=Path,
        help="Path to the markdown file to scan.",
    )

    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--dry-run",
        action="store_true",
        help="List extracted blocks without running them.",
    )
    mode.add_argument(
        "--run",
        action="store_true",
        help="Run all extracted blocks and report pass/fail.",
    )
    mode.add_argument(
        "--makefile",
        action="store_true",
        help="Print a Makefile target fragment to stdout.",
    )

    ap.add_argument(
        "--filter",
        type=str,
        default=None,
        help="Regex to filter blocks by tag (e.g., 'check|backend').",
    )
    ap.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Print each command before running it.",
    )

    return ap.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    """Entry point."""
    args: argparse.Namespace = parse_args(argv)

    if not args.doc.is_file():
        print(f"ERROR: file not found: {args.doc}", file=sys.stderr)
        return 2

    blocks: list[DocBlock] = extract_blocks(args.doc)
    blocks = filter_blocks(blocks, args.filter)

    if not blocks:
        print(f"No annotated blocks found in {args.doc}")
        print("Annotate testable blocks with: <!-- doc-test: TAG -->")
        return 0

    if args.dry_run:
        print_dry_run(blocks)
        return 0

    if args.makefile:
        print_makefile(blocks, args.doc)
        return 0

    # --run
    results: list[RunResult] = run_all(blocks, verbose=args.verbose)
    return print_summary(results)


if __name__ == "__main__":
    raise SystemExit(main())
