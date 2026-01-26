"""
test_dataset_pipeline.py
========================

File: ml_pipeline/python/tests/test_dataset_pipeline.py

Purpose
-------

Tests for dataset filtering and finetune dataset building.

Usage
-----

From the repository root, run:
    pytest -v ml_pipeline/python/tests/test_dataset_pipeline.py
or via Make:
    make test-ml-pipeline
"""

import json
from pathlib import Path

import pandas as pd

from ml_pipeline.python.model.filter_jsonl import filter_dataset
from ml_pipeline.python.model.build_finetune_dataset import build_finetune_dataset


def _write_jsonl(path: Path, rows) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


def test_filter_accepts_canonical_and_legacy(tmp_path: Path) -> None:
    inp = tmp_path / "in.jsonl"
    out = tmp_path / "out.jsonl"

    rows = [
        {"prettyQname": "A.f", "type": "Nat → Nat", "body": "f x = x", "typeAstVersion": "0.3-v0"},
        {"file": "B.agda", "name": "g", "agdaType": "Nat", "proof": "zero"},
        {"prettyQname": "A.f", "type": "Nat → Nat", "body": "f x = x", "typeAstVersion": "0.3-v0"},  # dup
        {"prettyQname": "bad", "type": "", "body": ""},  # filtered out
    ]
    _write_jsonl(inp, rows)

    filter_dataset(inp, out, min_type_len=1, min_proof_len=1)
    df = pd.read_json(out, lines=True)

    # canonical row survives, duplicate removed
    assert (df.get("prettyQname") == "A.f").sum() == 1

    # legacy row survives too
    assert (df.get("name") == "g").sum() == 1


def test_build_finetune_dataset(tmp_path: Path) -> None:
    inp = tmp_path / "filtered.jsonl"
    out = tmp_path / "finetune.jsonl"

    rows = [
        {"module": "M", "name": "f", "type": "Nat → Nat", "body": "f x = x"},
        {"module": "N", "name": "g", "agdaType": "Nat", "proof": "zero"},
    ]
    _write_jsonl(inp, rows)

    build_finetune_dataset(inp, out)
    ex = [json.loads(l) for l in out.read_text(encoding="utf-8").splitlines()]

    assert len(ex) == 2
    assert set(ex[0].keys()) == {"instruction", "input", "output"}
    assert "Nat" in ex[0]["input"]
    assert ex[0]["output"] != ""
