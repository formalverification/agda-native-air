"""
file: agda-jang/python/tools/report_parser.py
description: parsing of Agda subgoal reports from stderr.
"""
from __future__ import annotations
import json
import re
from typing import List, Dict, Any, Optional, Tuple

_BEGIN = "AGDAJANG_SUBGOALS_BEGIN"
_END   = "AGDAJANG_SUBGOALS_END"
# Lines look like either:
#   AGDAJANG_GOAL:0:visible:  <TYPE>
#   AGDAJANG_GOAL:1:?arg:     <TYPE>          (solve-report variant)
_LINE  = re.compile(r"^AGDAJANG_GOAL:(\d+):([a-z?]+):\s+(.*)$")

def has_markers(s: str) -> bool:
    return _BEGIN in s and _END in s

def parse_marked_report(stderr: str, source: str) -> Dict[str, Any]:
    # Isolate the block between BEGIN/END, but stay robust to extra noise
    try:
        block = stderr.split(_BEGIN, 1)[1].split(_END, 1)[0]
    except Exception:
        raise ValueError("Report markers malformed or missing")

    goals: List[Dict[str, Any]] = []
    for raw_line in block.splitlines():
        m = _LINE.match(raw_line.strip())
        if not m:
            continue
        idx, vis, typ = m.group(1), m.group(2), m.group(3)
        goals.append({
            "index": int(idx),
            "visibility": vis,      # visible|hidden|instance|?arg
            "type": typ             # keep Agda’s rendering verbatim
        })
    return {
        "kind": "subgoal-report",
        "source": source,
        "goals": goals,
        "raw": {"stderr": stderr}
    }


# =============================================================================
# Policy request markers (goal + context)
# Goal/context request reports for agent_bridge (Issue #23)
# =============================================================================

_REQ_BEGIN = "AGDAJANG_REQ_BEGIN"
_REQ_END   = "AGDAJANG_REQ_END"

# Goal line is intentionally NOT the indexed subgoal line; it has no digits.
#   AGDAJANG_GOAL: <GOAL_TYPE>
_REQ_GOAL = re.compile(r"^AGDAJANG_GOAL:\s*(.+?)\s*$")

# Debug.agda emits:
#   AGDAJANG_GOAL: <goal-rendering>
_REQ_GOAL_LINE = re.compile(r"^\s*AGDAJANG_GOAL:\s*(.*)\s*$")

# Debug.agda emits:
#   AGDAJANG_CTX:<i>:<vis>:<name>: <type-rendering>
_REQ_CTX_LINE = re.compile(r"^\s*AGDAJANG_CTX:(\d+):([^:]+):([^:]+):\s*(.*)\s*$")

# Context binder line:
#   AGDAJANG_CTX:<i>:<visibility>:<name>: <TYPE>
_REQ_CTX  = re.compile(r"^AGDAJANG_CTX:(\d+):([a-z]+):([^:]+):\s*(.+?)\s*$")

def has_request_markers(s: str) -> bool:
    """
    True iff the output contains goal/context request markers.
    Kept separate from has_markers() to avoid mixing two different report types.
    """
    return _REQ_BEGIN in s and _REQ_END in s


def _extract_req_block(output: str) -> str:
    """
    Extract the substring between AGDAJANG_REQ_BEGIN and AGDAJANG_REQ_END.
    Raises ValueError if malformed/missing.
    """
    try:
        return output.split(_REQ_BEGIN, 1)[1].split(_REQ_END, 1)[0]
    except Exception:
        raise ValueError("Request markers malformed or missing")


def _extract_block(output: str, begin: str, end: str) -> Optional[str]:
    """
    Safe block extraction: return the substring between begin/end, or None.
    """
    if begin not in output or end not in output:
        return None
    try:
        return output.split(begin, 1)[1].split(end, 1)[0]
    except Exception:
        return None



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

def parse_policy_request_block(output: str) -> Dict[str, Any]:
    """
    Extract and parse the JSON object inside:

      AGDAJANG_REQ_BEGIN
      { ...json... }
      AGDAJANG_REQ_END

    Returns the parsed JSON dict.
    Raises ValueError on malformed blocks or invalid JSON.
    """
    try:
        block = output.split(_REQ_BEGIN, 1)[1].split(_REQ_END, 1)[0]
    except Exception:
        raise ValueError("Request markers malformed or missing")

    # We allow surrounding whitespace/newlines.
    payload = block.strip()
    if not payload:
        raise ValueError("Request block empty")

    try:
        obj = json.loads(payload)
    except Exception as e:
        raise ValueError(f"Request block is not valid JSON: {e}") from e

    if not isinstance(obj, dict):
        raise ValueError("Request JSON must be an object")
    return obj



def parse_goalctx_report(output: str) -> Dict[str, Any]:
    """
    Parse a goal/context report emitted by an AgdaJang macro (e.g., reportGoalCtx).

    Expected shapes inside the marker block:
      AGDAJANG_GOAL: <GOAL_TYPE_RENDERING>
      AGDAJANG_CTX:0:visible:x: A
      AGDAJANG_CTX:1:hidden: A: Set

    Returns a stable JSON-like dict:
      {
        "kind": "goalctx-request",
        "goal": "<goal-type>",
        "context": [ {"index":0,"visibility":"visible","name":"x","type":"A"}, ... ],
        "raw": {"output": "..."}
      }
    """
    block = _extract_req_block(output)

    goal: Optional[str] = None
    ctx: List[Dict[str, Any]] = []

    for raw_line in block.splitlines():
        line = raw_line.strip()
        if not line:
            continue

        mg = _REQ_GOAL.match(line)
        if mg and goal is None:
            goal = mg.group(1).strip()
            continue

        mc = _REQ_CTX.match(line)
        if mc:
            idx = int(mc.group(1))
            vis = mc.group(2).strip()
            name = mc.group(3).strip()
            typ = mc.group(4).strip()
            ctx.append({
                "index": idx,
                "visibility": vis,
                "name": name,
                "type": typ,
            })

    if goal is None:
        raise ValueError("Goal/context report missing AGDAJANG_GOAL line")

    # Deterministic ordering by index
    ctx_sorted = sorted(ctx, key=lambda d: int(d.get("index", 0)))

    return {
        "kind": "goalctx-request",
        "goal": goal,
        "context": ctx_sorted,
        "raw": {"output": output},
    }



def _parse_request_as_json(block: str) -> Optional[Dict[str, Any]]:
    """
    Optional future format:
      AGDAJANG_REQ_BEGIN
      { ... JSON ... }
      AGDAJANG_REQ_END
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
    Current v0 line protocol (matches your Debug.agda):
      AGDAJANG_GOAL: <goal>
      AGDAJANG_CTX_BEGIN
      AGDAJANG_CTX:<i>:<vis>:<name>: <type>
      ...
    """
    goal: Optional[str] = None
    ctx: List[Dict[str, Any]] = []

    for raw in block.splitlines():
        line = raw.strip()
        if not line:
            continue

        mg = _REQ_GOAL_LINE.match(line)
        if mg:
            goal = mg.group(1).strip()
            continue

        mc = _REQ_CTX_LINE.match(line)
        if mc:
            idx_s, vis, name, typ = mc.group(1), mc.group(2), mc.group(3), mc.group(4)
            try:
                idx = int(idx_s)
            except Exception:
                idx = -1
            ctx.append({
                "index": idx,
                "visibility": vis.strip(),
                "name": name.strip(),
                "type": typ.strip(),
            })
            continue

        # ignore other lines like AGDAJANG_CTX_BEGIN
        continue

    if goal is None:
        return None

    # Deterministic order: sort by index if present
    ctx_sorted = sorted(ctx, key=lambda d: int(d.get("index", -1)))

    return {
        "goal": goal,
        "context": ctx_sorted,
    }


