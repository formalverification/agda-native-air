"""
file: agda-jang/python/tools/report_parser.py
description: parsing of Agda subgoal reports from stderr.
"""
from __future__ import annotations
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


+
+# =============================================================================
+# Goal/context request reports (for agent_bridge / Issue #23)
+# =============================================================================
+
+_REQ_BEGIN = "AGDAJANG_REQ_BEGIN"
+_REQ_END   = "AGDAJANG_REQ_END"
+
+# Goal line is intentionally NOT the indexed subgoal line; it has no digits.
+#   AGDAJANG_GOAL: <GOAL_TYPE>
+_REQ_GOAL = re.compile(r"^AGDAJANG_GOAL:\s*(.+?)\s*$")
+
+# Context binder line:
+#   AGDAJANG_CTX:<i>:<visibility>:<name>: <TYPE>
+_REQ_CTX  = re.compile(r"^AGDAJANG_CTX:(\d+):([a-z]+):([^:]+):\s*(.+?)\s*$")
+
+def has_req_markers(s: str) -> bool:
+    """
+    True iff the output contains goal/context request markers.
+    Kept separate from has_markers() to avoid mixing two different report types.
+    """
+    return _REQ_BEGIN in s and _REQ_END in s
+
+
+def _extract_req_block(output: str) -> str:
+    """
+    Extract the substring between AGDAJANG_REQ_BEGIN and AGDAJANG_REQ_END.
+    Raises ValueError if malformed/missing.
+    """
+    try:
+        return output.split(_REQ_BEGIN, 1)[1].split(_REQ_END, 1)[0]
+    except Exception:
+        raise ValueError("Request markers malformed or missing")
+
+
+def parse_goalctx_report(output: str) -> Dict[str, Any]:
+    """
+    Parse a goal/context report emitted by an AgdaJang macro (e.g., reportGoalCtx).
+
+    Expected shapes inside the marker block:
+      AGDAJANG_GOAL: <GOAL_TYPE_RENDERING>
+      AGDAJANG_CTX:0:visible:x: A
+      AGDAJANG_CTX:1:hidden: A: Set
+
+    Returns a stable JSON-like dict:
+      {
+        "kind": "goalctx-request",
+        "goal": "<goal-type>",
+        "context": [ {"index":0,"visibility":"visible","name":"x","type":"A"}, ... ],
+        "raw": {"output": "..."}
+      }
+    """
+    block = _extract_req_block(output)
+
+    goal: Optional[str] = None
+    ctx: List[Dict[str, Any]] = []
+
+    for raw_line in block.splitlines():
+        line = raw_line.strip()
+        if not line:
+            continue
+
+        mg = _REQ_GOAL.match(line)
+        if mg and goal is None:
+            goal = mg.group(1).strip()
+            continue
+
+        mc = _REQ_CTX.match(line)
+        if mc:
+            idx = int(mc.group(1))
+            vis = mc.group(2).strip()
+            name = mc.group(3).strip()
+            typ = mc.group(4).strip()
+            ctx.append({
+                "index": idx,
+                "visibility": vis,
+                "name": name,
+                "type": typ,
+            })
+
+    if goal is None:
+        raise ValueError("Goal/context report missing AGDAJANG_GOAL line")
+
+    # Deterministic ordering by index
+    ctx_sorted = sorted(ctx, key=lambda d: int(d.get("index", 0)))
+
+    return {
+        "kind": "goalctx-request",
+        "goal": goal,
+        "context": ctx_sorted,
+        "raw": {"output": output},
+    }
