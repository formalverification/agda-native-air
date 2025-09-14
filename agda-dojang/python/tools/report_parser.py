"""
file: agda-jang/python/tools/report_parser.py
description: parsing of Agda subgoal reports from stderr.
copyright: 2025 Thmpr
"""
from __future__ import annotations
import re
from typing import List, Dict, Any

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
