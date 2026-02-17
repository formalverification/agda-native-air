"""
policy_fixture.py

File: agda-jang/python/tools/policy_fixture.py

Description:
  A simple deterministic oracle policy backend for testing fixture-driven proof
  completion.

Goal:
  Given a goal identifier (name) coming from the evaluator, return a list
  of candidate expressions (strings) to try in the hole.

This policy is *deterministic* and is intended to make the end-to-end
"propose → Agda-check → metrics" demo pass before any ML exists.

How it works:
  - For known holes in FixtureStdlibBooleanAlgebra, return the true proof first.
  - Fill the remaining slots with deterministic distractors that parse but
    (usually) do not typecheck.

"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Sequence, Tuple

from tools.policy_contract import (
    POLICY_REQUEST_SCHEMA_V0,
    POLICY_RESPONSE_SCHEMA_V0,
    parse_request_json,
)

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

def _has_name(ctx: List[CtxEntry], name: str) -> bool:
    """
    True iff a context entry with the given name exists.
    """
    return any(e.name == name for e in ctx)


def _pick_vars_with_type_substr(ctx: List[CtxEntry], type_substr: str, n: int) -> List[str]:
    """
    Pick up to n variable names whose *type* mentions `type_substr`.
    We prefer *most local* binders, so we scan from the end.
    """
    out: List[str] = []
    for e in reversed(ctx):
        if len(out) >= n:
            break
        if type_substr in e.type:
            # Avoid picking oracle constants themselves.
            if e.name.startswith("oracle-"):
                continue
            out.append(e.name)
    out.reverse()
    return out


def _try_stdlib_boolalg(goal_norm: str, ctx: List[CtxEntry]) -> List[Dict[str, Any]]:
    """
    FixtureStdlibBooleanAlgebra helper (stdlib-backed):
      - ¬ ⊥ ≈ ⊤          solved by `⊥≉⊤`
      - deMorgan₁ goal    solved by `deMorgan₁ x y`
      - deMorgan₂ goal    solved by `deMorgan₂ x y`

    We deliberately use binder names from the local context to avoid introducing metas.
    """
    out: List[Dict[str, Any]] = []

    # ¬ ⊥ ≈ ⊤  (context is empty here)
    if ("¬⊥" in goal_norm and "≈⊤" in goal_norm) or ("¬ ⊥" in goal_norm and "≈ ⊤" in goal_norm):
        out.append({"term": "⊥≉⊤", "score": 1.2, "meta": {"rule": "stdlib-boolalg-⊥≉⊤"}})
        return out

    xs = _pick_vars_with_type_substr(ctx, "Bool", 2)
    if len(xs) != 2:
        return out
    x, y = xs[0], xs[1]

    # deMorgan₁ : ¬ (x ∧ y) ≈ ¬ x ∨ ¬ y
    if ("¬(" in goal_norm or "¬ (" in goal_norm) and "∧" in goal_norm and "∨" in goal_norm:
        if ("¬" in goal_norm and "∨" in goal_norm) and ("¬" in goal_norm and "∧" in goal_norm):
            # Prefer deMorgan₁ if RHS mentions ∨
            if "∨" in goal_norm and "∧" in goal_norm and ("¬ x ∨ ¬ y" in goal_norm or "∨ ¬" in goal_norm):
                out.append({"term": f"deMorgan₁ {x} {y}", "score": 1.1, "meta": {"rule": "stdlib-boolalg-deMorgan₁"}})

    # deMorgan₂ : ¬ (x ∨ y) ≈ ¬ x ∧ ¬ y
    if ("¬(" in goal_norm or "¬ (" in goal_norm) and "∨" in goal_norm and "∧" in goal_norm:
        if ("¬ x ∧ ¬ y" in goal_norm) or ("∧ ¬" in goal_norm):
            out.append({"term": f"deMorgan₂ {x} {y}", "score": 1.1, "meta": {"rule": "stdlib-boolalg-deMorgan₂"}})

    return out


def _goal_id_from_request(req: Dict[str, Any]) -> Optional[str]:
    """
    Best-effort: extract a stable per-goal identifier from request.meta.
    We try common keys used across prototypes.
    """
    meta = req.get("meta")
    if not isinstance(meta, dict):
        return None
    for key in ("goalName", "holeName", "name", "defName", "qname", "prettyQname"):
        v = meta.get(key)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return None


def _oracle_candidates(goal_id: Optional[str]) -> List[Dict[str, Any]]:
    """
    Fixture-specific oracle hook:
      - if the request includes a recognizable goal name, emit a direct oracle term.

    Notes:
      - This is intentionally conservative: it only fires when we see a known suffix.
      - It composes with generic heuristics (assumption/refl/tt) below.
    """
    if goal_id is None:
        return []

    # Allow either bare names or qualified names; match by suffix.
    if goal_id.endswith("goal-¬⊥≈⊤"):
        return [{
            "term": "oracle-¬⊥≈⊤",
            "score": 1.1,
            "meta": {"rule": "oracle-by-name", "goalId": goal_id},
        }]

    # IMPORTANT: these holes are in an argument context (inside lambda / binder),
    # so the oracle must be applied (or use underscores) to match the goal type.
    if goal_id.endswith("goal-deMorgan₁"):
        return [
            {"term": "oracle-deMorgan₁ _ _", "score": 1.1, "meta": {"rule": "oracle-by-name", "goalId": goal_id}},
            {"term": "oracle-deMorgan₁ x y", "score": 1.0, "meta": {"rule": "oracle-by-name", "goalId": goal_id}},
        ]

    if goal_id.endswith("goal-deMorgan₂"):
        return [
            {"term": "oracle-deMorgan₂ _ _", "score": 1.1, "meta": {"rule": "oracle-by-name", "goalId": goal_id}},
            {"term": "oracle-deMorgan₂ x y", "score": 1.0, "meta": {"rule": "oracle-by-name", "goalId": goal_id}},
        ]
    return []


def propose_terms(goal: str, ctx: List[CtxEntry], req: Dict[str, Any], k: int = 5) -> List[Dict[str, Any]]:
    goal_n = _normalize(goal)
    cands: List[Dict[str, Any]] = []

    # 0) FixtureStdlibBooleanAlgebra hook (stdlib-backed).
    cands.extend(_try_stdlib_boolalg(goal_n, ctx))

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


def _validate_request_schema(req: Dict[str, Any]) -> Optional[str]:
    """
    Return None if the request is acceptable, else return an error message.

    We accept:
      - schema-tagged v0 requests
      - legacy requests with no 'schema' key (optional transitional support)
    We reject:
      - any unknown schema string
      - non-string schema
    """
    sch = req.get("schema")
    if sch is None:
        # Legacy request (pre-freeze). Keep acceptance for now to avoid breakage.
        return None
    if not isinstance(sch, str):
        return "policy request 'schema' must be a string"
    if sch != POLICY_REQUEST_SCHEMA_V0:
        return f"unsupported policy request schema: {sch!r} (expected: {POLICY_REQUEST_SCHEMA_V0!r})"
    return None


def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(description="Deterministic fixture policy backend (no ML).")
    p.add_argument("--in", dest="in_path", default="-", help="input JSON path or '-' for stdin")
    p.add_argument("--out", dest="out_path", default="-", help="output JSON path or '-' for stdout")
    p.add_argument("--k", type=int, default=5, help="top-k candidates to emit")
    args = p.parse_args(argv)

    # raw_in = sys.stdin.read() if args.in_path == "-" else open(args.in_path, "r", encoding="utf-8").read()
    if args.in_path == "-":
        raw_in = sys.stdin.read()
    else:
        with open(args.in_path, "r", encoding="utf-8") as f:
            raw_in = f.read()

    try:
        req = parse_request_json(raw_in)
    except Exception as ex:
        print(f"ERROR: {ex}", file=sys.stderr)
        return 2

    if not isinstance(req, dict):
        print("ERROR: policy request must be a JSON object", file=sys.stderr)
        return 2

    err = _validate_request_schema(req)
    if err is not None:
        print(f"ERROR: {err}", file=sys.stderr)
        return 2

    goal = str(req.get("goal", ""))
    ctx = _parse_ctx(req.get("context", []))
    candidates = propose_terms(goal, ctx, req=req, k=args.k)

    resp = {
        # Preferred contract key:
        "schema": POLICY_RESPONSE_SCHEMA_V0,
        # Transitional legacy key (optional; remove once all callers enforce 'schema'):
        "schemaVersion": "policy_fixture.v0",
        "candidates": candidates,
        "meta": {
            "policy": "fixture",
            "deterministic": True,
            "requestSchema": req.get("schema", None),
        },
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
