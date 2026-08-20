"""
goal_report.py

File: agda-dojang/python/utils/goal_report.py

Description:
  Parse the goal/context request block that AgdaDojang's reporting macros write
  into Agda's output, delimited by the marker pair

      AGDADOJANG_REQ_BEGIN … AGDADOJANG_REQ_END

  `AgdaDojang.Debug.reportGoalCtx` emits a v0 line protocol between those
  markers:

      AGDADOJANG_GOAL: <goal>
      AGDADOJANG_CTX_BEGIN
      AGDADOJANG_CTX:<index>:<visibility>:<name>: <type>
      AGDADOJANG_CTX_END

  A JSON object between the same markers is accepted as a forward-compatible
  alternative.  Either shape decodes to `{"goal": str, "context": [...]}`.

Provenance:
  Relocated from `tools/report_parser.py` when the legacy Python bridge
  (`agent_bridge.py`, `report_parser.py`, `dojang_try.py`) was retired in
  favour of the `agda-mcp` server (issue #109).  The parsing behaviour is
  unchanged; only the subgoal-report half of the old module, which served
  `dojang_try.py` alone, was dropped.  The proof-completion evaluator
  (`tools/eval_fixtures.py`) is the remaining caller.

  The marker protocol itself is live and shared, not legacy:
  `agda/AgdaDojang/Debug.agda` writes it, and `AgdaMCP.Agda.parseGoalContext`
  reads it on the Haskell side.

Design notes:
  + Total.  A missing, truncated, or malformed block yields `None`; nothing
    here raises for an expected failure.
  + Pure.  Stdlib only, no I/O, no subprocess, so this module's tests belong
    to the no-Agda unit-test lane.
  + When the output holds several complete blocks, the *last* one wins: a run
    that re-checked a module leaves the freshest report at the end.
"""
from __future__ import annotations

import json
import re
from typing import Any, Dict, List, Optional

_REQ_BEGIN = "AGDADOJANG_REQ_BEGIN"
_REQ_END   = "AGDADOJANG_REQ_END"

_REQ_GOAL_PREFIX = "AGDADOJANG_GOAL:"
_REQ_CTX_PREFIX  = "AGDADOJANG_CTX:"


def _is_req_marker_line(line: str) -> bool:
    s = line.strip()
    return (
        s in {_REQ_BEGIN, _REQ_END, "AGDADOJANG_CTX_BEGIN", "AGDADOJANG_CTX_END"}
        or s.startswith(_REQ_GOAL_PREFIX)
        or s.startswith(_REQ_CTX_PREFIX)
    )


def _parse_req_ctx_line(line: str) -> Optional[Dict[str, Any]]:
    s = line.strip()
    if not s.startswith(_REQ_CTX_PREFIX):
        return None
    rest = s[len(_REQ_CTX_PREFIX):]
    parts = rest.split(":", 3)  # keep colons inside the type
    if len(parts) != 4:
        return None
    idx_s, vis, name, typ = parts
    try:
        idx = int(idx_s)
    except Exception:
        return None
    return {"index": idx, "visibility": vis.strip(), "name": name.strip(), "type": typ.strip()}


def _extract_block(output: str, begin: str, end: str) -> Optional[str]:
    """
    Safe block extraction: return the substring between begin/end, or None.
    If multiple blocks exist, return the *last* complete block.
    """
    start = output.rfind(begin)
    if start < 0:
        return None
    start += len(begin)
    end_i = output.find(end, start)
    if end_i < 0:
        return None
    return output[start:end_i]


def extract_policy_request_from_output(output: str) -> Optional[Dict[str, Any]]:
    """
    Robust extraction:
      - looks for REQ_BEGIN/REQ_END anywhere in output (even if surrounded by other noise),
      - supports either JSON-block or line-protocol,
      - returns a dict if markers exist and JSON parses,
      - returns None if no request found.
    """
    block = _extract_block(output, _REQ_BEGIN, _REQ_END)
    if block is None:
        return None

    obj = _parse_request_as_json(block)
    if obj is not None:
        return obj

    return _parse_request_as_lines(block)


def _parse_request_as_json(block: str) -> Optional[Dict[str, Any]]:
    """
    Optional future format:
      AGDADOJANG_REQ_BEGIN
      { ... JSON ... }
      AGDADOJANG_REQ_END
    """
    payload = block.strip()
    if not payload:
        return None
    try:
        obj = json.loads(payload)
    except Exception:
        return None
    return obj if isinstance(obj, dict) else None


def _parse_request_as_lines(block: str) -> Optional[Dict[str, Any]]:
    """
    Current v0 line protocol (matches AgdaDojang/Debug.agda):
      AGDADOJANG_GOAL: <goal>
      AGDADOJANG_CTX_BEGIN
      AGDADOJANG_CTX:<i>:<vis>:<name>: <type>
      ...
    """
    goal_parts: List[str] = []
    ctx: List[Dict[str, Any]] = []
    current_ctx: Optional[Dict[str, Any]] = None
    mode: Optional[str] = None  # "goal" | "ctx"

    for raw in block.splitlines():
        s = raw.strip()
        if not s:
            continue
        if s.startswith(_REQ_GOAL_PREFIX):
            mode = "goal"
            current_ctx = None
            goal_parts = [s[len(_REQ_GOAL_PREFIX):].strip()]
            continue
        parsed = _parse_req_ctx_line(s)
        if parsed is not None:
            mode = "ctx"
            current_ctx = parsed
            ctx.append(parsed)
            continue
        if s in {"AGDADOJANG_CTX_BEGIN", "AGDADOJANG_CTX_END"}:
            continue
        if _is_req_marker_line(s):
            mode = None
            current_ctx = None
            continue
        # continuation line
        if mode == "goal":
            goal_parts.append(s)
        elif mode == "ctx" and current_ctx is not None:
            current_ctx["type"] = (str(current_ctx.get("type","")) + " " + s).strip()

    if not goal_parts:
        return None
    goal = re.sub(r"\s+", " ", " ".join(goal_parts)).strip()
    for e in ctx:
        e["type"] = re.sub(r"\s+", " ", str(e.get("type",""))).strip()
    ctx_sorted = sorted(ctx, key=lambda d: int(d.get("index", -1)))
    return {"goal": goal, "context": ctx_sorted}
