#!/usr/bin/env python3
"""
AgdaJang Trace extractor (v0, safe CLI)
=======================================

FILE: python/tools/jang_extract.py

DESCRIPTION

  +  Walk `--root` for `.agda` files.

  +  For each file:

     +  Send a `load` command to Agda's JSON interaction.

     +  Request **goals/metas** and **constraints**.

     +  If a goal is already solved (e.g., after `C-c C-a`), we can reconstruct the
        term by asking Agda for the definition of the name or by parsing the file region.
        In v0, we focus on *holes filled during a session* and capture *final gives*.

     +  Record `(context, goal_type, solution_term)` when a goal gets solved via `give`.

FEATURES

  + Non-destructive: never opens the input for writing.
  + Flagged CLI: --input <.agda>  --output <.json>
  + Emits a minimal JSON object we can grow iteratively.

NOTES

  Agda's JSON protocol provides:

  +  Interaction points (metas),
  +  "Give" results (when a hole is filled),
  +  Goal types and contexts.

  For a tight first pass, we can also extract examples offline by scanning Agda
  repo for patterns like:

      _ : (context) → goalType
      _ = refine⟨ CANDIDATE ⟩

  where we (or the LLM) replaced holes via `refine⟨_⟩`.  Then the extractor just
  parses the file to read `CANDIDATE` and the goal type around it. That's the
  quickest "walking skeleton."

SCHEMA (v0)

  {
    "version": "agda-jang-extract-v0",
    "timestamp": "...",
    "file": "/abs/path/to/file.agda",
    "module": "agda-example" | null,
    "size_bytes": 1234,
    "num_lines": 42,
    "raw": "<verbatim source text>"
  }



"""
import argparse, json, sys, re
from pathlib import Path
from datetime import datetime

def parse_args():
    p = argparse.ArgumentParser(description="Extract minimal info from an Agda file.")
    p.add_argument("--input",  required=True, help="Path to a single .agda file")
    p.add_argument("--output", required=True, help="Path to JSON output file")
    p.add_argument("--agda-bin", default="agda", help="Agda binary (unused in v0)")
    p.add_argument("--include", action="append", default=[], help="Extra include paths (unused in v0)")
    return p.parse_args()

MODULE_RE = re.compile(r'^\s*module\s+([A-Za-z0-9_.\-]+)\s+where\b', re.UNICODE | re.MULTILINE)

def main():
    args = parse_args()
    inp = Path(args.input).resolve()
    out = Path(args.output).resolve()

    # Safety rails
    if not inp.exists():
        print(f"ERROR: input file not found: {inp}", file=sys.stderr); sys.exit(1)
    if inp.suffix.lower() != ".agda":
        print(f"ERROR: expected a .agda file, got: {inp}", file=sys.stderr); sys.exit(1)
    if inp == out:
        print("ERROR: input and output paths are identical (would overwrite input!).", file=sys.stderr)
        sys.exit(1)

    text = inp.read_text(encoding="utf-8", errors="strict")
    if not text.strip():
        print(f"ERROR: input file exists but is empty: {inp}", file=sys.stderr); sys.exit(2)

    m = MODULE_RE.search(text)
    module_name = m.group(1) if m else None
    num_lines = text.count("\n") + (0 if text.endswith("\n") else 1)
    size_bytes = len(text.encode("utf-8", errors="strict"))

    payload = {
        "version":   "agda-jang-extract-v0",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "file":      str(inp),
        "module":    module_name,
        "size_bytes": size_bytes,
        "num_lines":  num_lines,
        "raw":       text,
    }

    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    print(f"✅ wrote {out} (module={module_name!r}, lines={num_lines}, bytes={size_bytes})")

if __name__ == "__main__":
    main()
