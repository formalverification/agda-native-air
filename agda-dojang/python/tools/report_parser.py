"""
report_parser.py

File: agda-jang/python/tools/report_parser.py

Description:
  - Parse Agda's stderr for subgoal reports (marked by AGDAJANG_SUBGOALS_BEGIN/END).
  - Extract structured goal information (index, visibility, type) from lines like
    AGDAJANG_GOAL:0:visible: <TYPE>.
  - Also support a separate marker pair AGDAJANG_REQ_BEGIN/END for policy requests
    (goal + context) used by agent_bridge (Issue #23).
"""
from __future__ import annotations
import json
import re
from typing import List, Dict, Any, Optional

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
# Policy request markers (goal + context) for agent_bridge (Issue #23)
# =============================================================================

_REQ_BEGIN = "AGDAJANG_REQ_BEGIN"
_REQ_END   = "AGDAJANG_REQ_END"

_REQ_GOAL_PREFIX = "AGDAJANG_GOAL:"
_REQ_CTX_PREFIX  = "AGDAJANG_CTX:"

def _is_req_marker_line(line: str) -> bool:
    s = line.strip()
    return (
        s in {_REQ_BEGIN, _REQ_END, "AGDAJANG_CTX_BEGIN", "AGDAJANG_CTX_END"}
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

def has_request_markers(s: str) -> bool:
    """
    True iff the output contains goal/context request markers.
    Kept separate from has_markers() to avoid mixing two different report types.
    """
    return _REQ_BEGIN in s and _REQ_END in s

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
        if s in {"AGDAJANG_CTX_BEGIN", "AGDAJANG_CTX_END"}:
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
