"""
policy_fixture.py

File: agda-jang/python/tools/policy_fixture.py

Description:
  A simple deterministic policy backend for testing and demonstration purposes.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from typing import Any, Dict, List, Optional


@dataclass(frozen=True)
class CtxEntry:
    name: str
    type: str


def _normalize(s: str) -> str:
    # cheap normalization: collapse whitespace
    return re.sub(r"\s+", " ", s).strip()


def _parse_ctx(raw: Any) -> List[CtxEntry]:
    if not isinstance(raw, list):
        return []
    out: List[CtxEntry] = []
    for item in raw:
        if isinstance(item, dict) and "name" in item and "type" in item:
            name = str(item["name"])
            typ = str(item["type"])
            out.append(CtxEntry(name=name, type=typ))
    return out


def propose_terms(goal: str, ctx: List[CtxEntry], k: int = 5) -> List[Dict[str, Any]]:
    goal_n = _normalize(goal)
    cands: List[Dict[str, Any]] = []

    # 1) Assumption rule: if some binder has exactly the goal type, return it.
    # Prefer later binders (often the most local one).
    for e in reversed(ctx):
        if _normalize(e.type) == goal_n:
            cands.append(
                {
                    "term": e.name,
                    "score": 1.0,
                    "meta": {"rule": "assumption", "name": e.name},
                }
            )
            break  # one is enough for the demo

    # 2) Unit goal
    # (Agda.Builtin.Unit uses ⊤ and tt)
    if "⊤" in goal_n or goal_n.endswith("Top") or goal_n == "Unit":
        cands.append({"term": "tt", "score": 0.9, "meta": {"rule": "unit"}})

    # 3) Equality goal
    # refl will typecheck for definitional equalities like x ≡ x (fixture-friendly)
    if "≡" in goal_n or "_≡_" in goal_n:
        cands.append({"term": "refl", "score": 0.8, "meta": {"rule": "refl"}})

    # Deduplicate by term, keep best score
    best: Dict[str, Dict[str, Any]] = {}
    for c in cands:
        t = c["term"]
        if t not in best or float(c["score"]) > float(best[t]["score"]):
            best[t] = c

    ranked = sorted(best.values(), key=lambda d: float(d["score"]), reverse=True)
    return ranked[:k]


def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(description="Deterministic fixture policy backend (no ML).")
    p.add_argument("--in", dest="in_path", default="-", help="input JSON path or '-' for stdin")
    p.add_argument("--out", dest="out_path", default="-", help="output JSON path or '-' for stdout")
    p.add_argument("--k", type=int, default=5, help="top-k candidates to emit")
    args = p.parse_args(argv)

    raw_in = sys.stdin.read() if args.in_path == "-" else open(args.in_path, "r", encoding="utf-8").read()
    req = json.loads(raw_in)

    goal = str(req.get("goal", ""))
    ctx = _parse_ctx(req.get("context", []))
    candidates = propose_terms(goal, ctx, k=args.k)

    resp = {
        "schemaVersion": "policy.v0",
        "candidates": candidates,
        "meta": {"policy": "fixture", "deterministic": True},
    }

    raw_out = json.dumps(resp, ensure_ascii=False, indent=2) + "\n"
    if args.out_path == "-":
        sys.stdout.write(raw_out)
    else:
        with open(args.out_path, "w", encoding="utf-8") as f:
            f.write(raw_out)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
