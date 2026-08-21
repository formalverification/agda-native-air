"""
File: scripts/python/corpus/__init__.py

Description: Corpus packaging tools for agda-strux JSONL extractions.

  `assemble.py` turns a per-module extraction tree into one publishable
  corpus plus its coverage and provenance records; `stats.py` computes the
  summary statistics a dataset card quotes.  Both are pure-core /
  effectful-shell and depend only on the standard library and
  `scripts/python/utils`.
"""
