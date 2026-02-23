#!/usr/bin/env python3
"""
train_retrieval.py

File: ml-pipeline/python/model/train_retrieval.py

Description:
  Train a deterministic retrieval artifact (TF-IDF-ish) from a proof-completion
  dataset JSONL.  The output is a pickle file containing the retrieval model, which
  can be loaded and queried by the runtime for proof completion.

  This builds a deterministic retrieval artifact by

  + reading proof-completion dataset JSONL/Parquet,
  + building `vocab/idf/doc_vecs/inverted`,
  + writing the artifact shape the policy expects.

  Input dataset JSONL expected rows (minimal):
    {
      "goal": str,
      "context": [ {"name": str, "type": str}, ... ],
      # proof-completion builder may emit:
      #   targetResolved, target, targetRaw  (prefer in that order)
      # plus lightweight provenance fields (module/name/prettyQname, etc.)
    }

  Output artifact (pickle dict):
    {
      "schema": "agda-ai-prover/retrieval-policy@v0",
      "vocab": { token: int, ... },
      "idf": [float, ...],
      "docs": [ { "target": str, "meta": {...} }, ... ],
      "doc_vecs": [ { int: float, ... }, ... ],
      "inverted": { int: [ (doc_id:int, w:float), ... ], ... }
    }

Notes:
  - stdlib only (no sklearn)
  - determinism: stable doc ordering + sorted vocab + sorted postings
"""

from __future__ import annotations

import argparse
import json
import math
import os
import pickle
import re
import tempfile
from collections import Counter
from itertools import chain, groupby
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple
import logging

RETRIEVAL_MODEL_SCHEMA_V0 = "agda-ai-prover/retrieval-policy@v0"

_TOKEN_RE = re.compile(
    r"_[^\s]+_"                      # Agda mixfix operators like _≡_
    r"|->|=>"
    r"|[A-Za-z][A-Za-z0-9_']*"        # identifiers
    r"|[0-9]+"
    r"|[¬∧∨→≡≈≤≥⊔⊓×λ∀∃ΣΠ]+"
)

def tokenize(text: str) -> List[str]:
    return [
        (t.lower() if re.fullmatch(r"[A-Za-z][A-Za-z0-9_']*", t) else t)
        for t in _TOKEN_RE.findall(text)
    ]

def query_text(goal: str, context: Sequence[Dict[str, str]]) -> str:
    ctx_lines = [
        f"{e.get('name','')} : {e.get('type','')}"
        for e in context
        if isinstance(e, dict) and isinstance(e.get("name"), str) and isinstance(e.get("type"), str)
    ]
    return "\n".join(["GOAL:", goal, "CTX:", *ctx_lines])

def l2_norm(vec: Dict[int, float]) -> float:
    return math.sqrt(sum(v * v for v in vec.values()))

def normalize_l2(vec: Dict[int, float]) -> Dict[int, float]:
    n = l2_norm(vec)
    return {} if n <= 0.0 else {i: v / n for i, v in vec.items()}

def tfidf_vec(tokens: Sequence[str], vocab: Dict[str, int], idf: Sequence[float]) -> Dict[int, float]:
    tf = Counter(vocab[t] for t in tokens if t in vocab)
    raw = {i: math.log1p(c) * float(idf[i]) for (i, c) in tf.items() if c > 0}
    return normalize_l2(dict(sorted(raw.items(), key=lambda kv: kv[0])))

def _first_str(*xs: Any) -> Optional[str]:
    ys = [x for x in xs if isinstance(x, str)]
    zs = [y.strip() for y in ys if y.strip()]
    return (zs[0] if zs else None)

def _provenance(obj: Dict[str, Any]) -> Dict[str, Any]:
    # Some datasets keep these as top-level keys rather than inside meta.
    keys = ["prettyQname", "module", "name", "file", "schemaVersion"]
    return {k: obj[k] for k in keys if k in obj and isinstance(obj[k], (str, int))}

def parse_row(obj: Any) -> Optional[Dict[str, Any]]:
    if not isinstance(obj, dict):
        return None
    goal = obj.get("goal")
    ctx = obj.get("context", [])
    target = _first_str(obj.get("targetResolved"), obj.get("target"), obj.get("targetRaw"))
    if not (isinstance(goal, str) and isinstance(ctx, list) and isinstance(target, str)):
        return None
    ctx_norm = [
        {"name": str(e["name"]), "type": str(e["type"])}
        for e in ctx
        if isinstance(e, dict) and isinstance(e.get("name"), str) and isinstance(e.get("type"), str)
    ]
    meta = obj.get("meta")
    meta_norm = meta if isinstance(meta, dict) else {}
    prov = _provenance(obj)
    return {"goal": goal, "context": ctx_norm, "target": target, "meta": {**prov, **meta_norm}}

def read_jsonl(path: str) -> List[Dict[str, Any]]:
    # streaming-ish: still returns a list because we sort for determinism
    p = Path(path)
    return [
        r
        for r in (
            parse_row(json.loads(ln))
            for ln in p.read_text(encoding="utf-8").splitlines()
            if ln.strip()
        )
        if r is not None
    ]

def doc_key(row: Dict[str, Any]) -> Tuple[str, str, str, str, str]:
    meta = row.get("meta") if isinstance(row.get("meta"), dict) else {}
    return (
        str(meta.get("prettyQname", "")),
        str(meta.get("module", "")),
        str(meta.get("name", "")),
        str(row.get("goal", "")),
        str(row.get("target", "")),
    )

def build_vocab(df: Counter[str]) -> Dict[str, int]:
    toks = sorted(df.keys())
    return {tok: i for (i, tok) in enumerate(toks)}

def build_idf(df: Counter[str], n_docs: int, vocab: Dict[str, int]) -> List[float]:
    # Smooth IDF: log((1+n)/(1+df)) + 1
    toks_by_idx = sorted(vocab.items(), key=lambda kv: kv[1])
    return [
        math.log((1.0 + n_docs) / (1.0 + float(df[tok]))) + 1.0
        for (tok, _) in toks_by_idx
    ]

def build_inverted(doc_vecs: Sequence[Dict[int, float]]) -> Dict[int, List[Tuple[int, float]]]:
    triples = sorted(
        [(j, doc_id, w) for (doc_id, vec) in enumerate(doc_vecs) for (j, w) in vec.items()],
        key=lambda t: (t[0], t[1]),
    )
    grouped = groupby(triples, key=lambda t: t[0])
    return {j: [(doc_id, float(w)) for (_, doc_id, w) in grp] for (j, grp) in grouped}

def _repo_root() -> Path:
    # .../ml-pipeline/python/model/train_retrieval.py → repo root is 3 parents up
    return Path(__file__).resolve().parents[3]

def _default_out_path() -> Path:
    env = os.environ.get("AGDA_AI_PROVER_RETRIEVAL_MODEL")
    return (Path(env).expanduser().resolve() if env
            else (_repo_root() / "models" / "proof_completion" / "retrieval_v0.pkl"))

def write_bytes_atomic(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), prefix=path.name + ".tmp_")
    tmp = Path(tmp_name)
    try:
        os.write(fd, content)
        os.close(fd)
        os.replace(tmp, path)
    finally:
        try:
            if tmp.exists():
                tmp.unlink()
        except Exception as e:
            logging.getLogger(__name__).warning(
                "Failed to remove temporary file %s during atomic write cleanup: %s",
                tmp,
                e,
            )

def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Train deterministic retrieval artifact (TF-IDF-ish).")
    p.add_argument("--in", dest="in_path", required=True, help="input proof-completion dataset JSONL")
    p.add_argument("--out", dest="out_path", default=str(_default_out_path()), help="output pickle")
    p.add_argument("--max-docs", type=int, default=0, help="optional cap after deterministic sort (0 = no cap)")
    return p.parse_args(argv)

def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)

    rows0 = read_jsonl(args.in_path)
    rows = sorted(rows0, key=doc_key)
    rows = (rows if args.max_docs <= 0 else rows[: int(args.max_docs)])

    # Build tokenized docs over (goal, context)
    doc_tokens = [tokenize(query_text(r["goal"], r["context"])) for r in rows]
    df = Counter(chain.from_iterable(set(ts) for ts in doc_tokens))
    vocab = build_vocab(df)
    idf = build_idf(df, n_docs=len(rows), vocab=vocab)

    doc_vecs = [tfidf_vec(ts, vocab, idf) for ts in doc_tokens]
    inverted = build_inverted(doc_vecs)

    docs = [{"target": r["target"].strip(), "meta": r.get("meta", {})} for r in rows]

    artifact = {
        "schema": RETRIEVAL_MODEL_SCHEMA_V0,
        "tokenRegex": _TOKEN_RE.pattern,
        "lowercaseIdents": True,
        "vocab": vocab,
        "idf": idf,
        "docs": docs,
        "doc_vecs": doc_vecs,
        "inverted": inverted,
    }

    out_p = Path(args.out_path)
    write_bytes_atomic(out_p, pickle.dumps(artifact, protocol=pickle.HIGHEST_PROTOCOL))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
