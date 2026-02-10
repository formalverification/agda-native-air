#!/usr/bin/env python3
"""
policy_contract.py

File: agda-jang/python/tools/policy_contract.py

Purpose
-------
Canonical, versioned request/response contract for policy backends used by AgdaJang.

"Freeze v0" means:
  - There is exactly one place that defines schema identifiers.
  - Callers always emit requests with a schema tag.
  - Backends always respond with a schema tag.
  - Parsers validate required keys and normalize candidates.

Versioning
----------
- Breaking changes MUST bump the schema string suffix (e.g. @v1).
- Unknown schema versions should be rejected by default.

This module intentionally has *no* dependency on project Result/Error types;
callers can catch ValueError and map to PipelineError as appropriate.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple

# -----------------------------------------------------------------------------
# Schema identifiers (the "frozen" part)
# -----------------------------------------------------------------------------

POLICY_REQUEST_SCHEMA_V0 = "agda-ai-prover/policy-request@v0"
POLICY_RESPONSE_SCHEMA_V0 = "agda-ai-prover/policy-response@v0"

SUPPORTED_REQUEST_SCHEMAS = {POLICY_REQUEST_SCHEMA_V0}
SUPPORTED_RESPONSE_SCHEMAS = {POLICY_RESPONSE_SCHEMA_V0}

# For transitional compatibility with earlier prototypes:
LEGACY_REQUEST_HAS_NO_SCHEMA_OK = True
LEGACY_RESPONSE_SCHEMA_VERSION_KEYS = {"schemaVersion"}  # e.g. "policy.v0"


# -----------------------------------------------------------------------------
# Small normalized structures
# -----------------------------------------------------------------------------

@dataclass(frozen=True)
class Candidate:
    term: str
    score: float
    meta: Dict[str, Any]


@dataclass(frozen=True)
class Response:
    schema: str
    candidates: List[Candidate]
    meta: Dict[str, Any]


# -----------------------------------------------------------------------------
# Request helpers
# -----------------------------------------------------------------------------

def build_request(
    *,
    goal: str,
    context: List[Dict[str, str]],
    module: Optional[str] = None,
    meta: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    Build a v0 policy request object. The caller can json.dumps() it.
    """
    ctx_norm: List[Dict[str, str]] = []
    for e in context:
        if not isinstance(e, dict):
            continue
        n = e.get("name")
        t = e.get("type")
        if isinstance(n, str) and isinstance(t, str):
            ctx_norm.append({"name": n, "type": t})

    out: Dict[str, Any] = {
        "schema": POLICY_REQUEST_SCHEMA_V0,
        "goal": str(goal),
        "context": ctx_norm,
    }
    if module is not None:
        out["module"] = str(module)
    if meta is not None and isinstance(meta, dict):
        out["meta"] = meta
    return out


def validate_request_obj(obj: Any) -> None:
    if not isinstance(obj, dict):
        raise ValueError("policy request must be a JSON object")

    sch = obj.get("schema")
    if sch is None:
        if LEGACY_REQUEST_HAS_NO_SCHEMA_OK:
            # Accept legacy requests but strongly prefer schema-tagged v0.
            return
        raise ValueError("policy request missing required key: 'schema'")

    if not isinstance(sch, str):
        raise ValueError("policy request 'schema' must be a string")

    if sch not in SUPPORTED_REQUEST_SCHEMAS:
        raise ValueError(f"unsupported policy request schema: {sch!r} (supported: {sorted(SUPPORTED_REQUEST_SCHEMAS)!r})")


# -----------------------------------------------------------------------------
# Response helpers
# -----------------------------------------------------------------------------

def _coerce_meta(raw: Any) -> Dict[str, Any]:
    if not isinstance(raw, dict):
        return {}
    return {str(k): v for k, v in raw.items()}


def validate_response_obj(obj: Any) -> None:
    if not isinstance(obj, dict):
        raise ValueError("policy response must be a JSON object")

    # Prefer 'schema'. Allow transitional 'schemaVersion' only as a fallback.
    sch = obj.get("schema")
    if sch is None:
        # If schema is missing, we treat this as legacy and require schemaVersion.
        sv = obj.get("schemaVersion")
        if isinstance(sv, str):
            # We do not attempt to map arbitrary schemaVersion strings.
            # Callers may choose to accept legacy by special-case mapping.
            return
        raise ValueError("policy response missing required key: 'schema' (or legacy 'schemaVersion')")

    if not isinstance(sch, str):
        raise ValueError("policy response 'schema' must be a string")
    if sch not in SUPPORTED_RESPONSE_SCHEMAS:
        raise ValueError(f"unsupported policy response schema: {sch!r} (supported: {sorted(SUPPORTED_RESPONSE_SCHEMAS)!r})")

    cands = obj.get("candidates")
    if not isinstance(cands, list):
        raise ValueError("policy response missing/invalid 'candidates' (must be a list)")

    for i, c in enumerate(cands):
        if not isinstance(c, dict):
            raise ValueError(f"policy response candidate[{i}] must be an object")
        term = c.get("term")
        if not isinstance(term, str) or not term.strip():
            raise ValueError(f"policy response candidate[{i}] missing/invalid 'term'")


def parse_response_json(text: str) -> Response:
    """
    Parse + validate a response JSON string and normalize it to Response/Candidate.

    Accepts a *transitional legacy* response lacking 'schema' if it provides
    a known 'schemaVersion' value that can be mapped to v0.
    """
    try:
        obj = json.loads(text)
    except Exception as ex:
        raise ValueError(f"policy response is not valid JSON: {ex}") from ex

    validate_response_obj(obj)

    # Schema handling: prefer 'schema'; map legacy schemaVersion if needed.
    sch = obj.get("schema")
    if isinstance(sch, str):
        schema = sch
    else:
        # Legacy mapping
        sv = obj.get("schemaVersion")
        if isinstance(sv, str) and sv in {"policy.v0", "policy_fixture.v0"}:
            schema = POLICY_RESPONSE_SCHEMA_V0
        else:
            raise ValueError("policy response missing 'schema' and has unknown legacy 'schemaVersion'")

    cands_raw = obj.get("candidates") or []
    cands: List[Candidate] = []
    for raw in cands_raw:
        if not isinstance(raw, dict):
            continue
        term = str(raw.get("term", "")).strip()
        if not term:
            continue
        score_raw = raw.get("score", 0.0)
        try:
            score = float(score_raw)
        except Exception:
            score = 0.0
        meta = _coerce_meta(raw.get("meta"))
        cands.append(Candidate(term=term, score=score, meta=meta))

    meta = _coerce_meta(obj.get("meta"))
    return Response(schema=schema, candidates=cands, meta=meta)
