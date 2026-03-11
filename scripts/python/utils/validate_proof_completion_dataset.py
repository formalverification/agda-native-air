#!/usr/bin/env python3
"""
validate_proof_completion_dataset.py

File: scripts/python/utils/validate_proof_completion_dataset.py

Validate a proof-completion dataset JSONL file.

Checks:
  - file exists and is non-empty
  - rowcount >= --min-rows (default: 1)
  - every non-empty line parses as JSON
  - every row has schemaVersion == --schema-version

Exits nonzero with a helpful error message on first failure.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any, Dict


def die(msg: str, code: int = 2) -> None:
    print(f"❌ ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="validate_proof_completion_dataset.py",
        description="Validate proof-completion dataset JSONL (rowcount + schemaVersion).",
    )
    p.add_argument("--in", dest="in_path", required=True, help="Path to output JSONL to validate.")
    p.add_argument(
        "--schema-version",
        dest="schema_version",
        required=True,
        help='Expected schemaVersion, e.g. "proof-completion.v0".',
    )
    p.add_argument(
        "--min-rows",
        dest="min_rows",
        type=int,
        default=1,
        help="Minimum number of non-empty JSON rows required (default: 1).",
    )
    p.add_argument(
        "--show-line-on-error",
        action="store_true",
        help="Include the offending JSONL line in error output (can be noisy).",
    )
    return p.parse_args()


def _as_obj(x: Any) -> Dict[str, Any]:
    if isinstance(x, dict):
        return x
    die(f"Expected JSON object per line, got {type(x).__name__}.", 2)
    raise AssertionError("unreachable")


def main() -> int:
    ns = parse_args()
    path = ns.in_path
    want = ns.schema_version
    min_rows = ns.min_rows

    if not os.path.exists(path):
        die(f"missing output file: {path}")
    if os.path.isdir(path):
        die(f"expected a file, got a directory: {path}")
    if os.path.getsize(path) <= 0:
        die(f"output file is empty: {path}")

    rows = 0
    with open(path, "r", encoding="utf-8") as f:
        for lineno, raw in enumerate(f, start=1):
            line = raw.strip()
            if not line:
                continue

            rows += 1
            try:
                obj = _as_obj(json.loads(line))
            except json.JSONDecodeError as e:
                msg = f"invalid JSON at line {lineno}: {e.msg} (col {e.colno})"
                if ns.show_line_on_error:
                    msg += f"\n  line: {line}"
                die(msg)

            got = obj.get("schemaVersion")
            if got != want:
                msg = f"schemaVersion mismatch at line {lineno}: got={got!r}, want={want!r}"
                if ns.show_line_on_error:
                    msg += f"\n  line: {line}"
                die(msg)

    if rows < min_rows:
        die(f"rowcount too small: rows={rows}, want >= {min_rows} (file: {path})")

    print(f"✅ OK: rows={rows}, schemaVersion={want}, file={path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
