#!/usr/bin/env python3
# file: python/tools/search.py
"""
AgdaJang search loop (BFS/beam), v0.3

Highlights
----------
- Pure driver that shells out to `python/tools/jang_try.py` as an oracle.
- Prefers structured subgoal tags from `applyReport:` / `applySolveReport:`.
- Simple scoring so the beam keeps promising children first.
- Dedup/caching across oracle calls and enqueued states.

CLI
---
  python3 python/tools/search.py \
    --goal Nat \
    --imports "open import Agda.Builtin.Nat" \
    --agda-dir agda --agda-bin agda

Notes
-----
- The recorded script contains only **real actions** (candidates / apply / applyWith).
  Report-actions are used internally to peek and are not recorded.
- If you add the Agda macro `applySolveReport⟨_⟩`, this driver will try it first
  (post-unification subgoals) and fall back to `applyReport⟨_⟩` automatically.
"""
from __future__ import annotations

from dataclasses  import dataclass, field
from typing       import Dict, Iterable, List, Optional, Sequence, Tuple

import argparse, hashlib, json, re, subprocess, sys

# ========= Core types =========

@dataclass(frozen=True)
class State:
    imports: Tuple[str, ...]
    goal: str
    script: Tuple[str, ...]  # sequence of recorded actions

@dataclass(frozen=True)
class Action:
    kind: str      # "candidate" | "tactic"
    payload: str   # e.g., "zero", "apply:suc", "applyWith:_+_:[zero]"

@dataclass(frozen=True)
class OracleCfg:
    agda_dir: str
    agda_bin: str = "agda"
    jang_try: str = "python/tools/jang_try.py"
    timeout: Optional[float] = None

@dataclass(frozen=True)
class StepResult:
    ok: bool
    subgoals: Tuple[str, ...] = field(default_factory=tuple)
    diag: str = ""  # raw stdout if you want to log

# ========= Small helpers =========

def hash_key(imports: Tuple[str, ...], goal: str, action: Action) -> str:
    h = hashlib.sha1()
    h.update("\n".join(imports).encode())
    h.update(b"\x00"); h.update(goal.encode()); h.update(b"\x00")
    h.update((action.kind + ":" + action.payload).encode())
    return h.hexdigest()

# ========= Oracle (via jang_try.py) =========

def _run_json(cmd: List[str]) -> Tuple[int, str]:
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, p.stdout


def oracle_candidate(cfg: OracleCfg, imports: Tuple[str, ...], goal: str, candidate: str) -> StepResult:
    cmd = [sys.executable, cfg.jang_try, "--goal", goal, "--candidate", candidate,
           "--agda-dir", cfg.agda_dir, "--agda-bin", cfg.agda_bin, "--format", "json"]
    for imp in imports: cmd += ["--imports", imp]
    if cfg.timeout is not None: cmd += ["--timeout", str(cfg.timeout)]
    rc, out = _run_json(cmd)
    try:
        data = json.loads(out)
        ok = bool(data and data[0].get("ok", False))
        return StepResult(ok=ok, subgoals=tuple(), diag=out.strip())
    except Exception:
        return StepResult(ok=False, diag=out.strip())


def oracle_tactic(cfg: OracleCfg, imports: Tuple[str, ...], goal: str, tactic: str) -> StepResult:
    cmd = [sys.executable, cfg.jang_try, "--goal", goal, "--tactic", tactic,
           "--agda-dir", cfg.agda_dir, "--agda-bin", cfg.agda_bin, "--format", "json"]
    for imp in imports: cmd += ["--imports", imp]
    if cfg.timeout is not None: cmd += ["--timeout", str(cfg.timeout)]
    rc, out = _run_json(cmd)
    try:
        data = json.loads(out)
        ok = bool(data.get("ok", False))
        subs = tuple(data.get("subgoals", []) or [])
        return StepResult(ok=ok, subgoals=subs, diag=out.strip())
    except Exception:
        return StepResult(ok=False, diag=out.strip())

# ========= Structured binder peek =========

_BLINE = re.compile(r"^AGDAJANG_GOAL:(\d+):([^:]+):\s*(.+)$")

@dataclass(frozen=True)
class Binder:
    idx: int
    visibility: str  # "visible" | "hidden" | "instance" | "?arg"
    dom_type: str

def _parse_binder_lines(lines: Iterable[str]) -> List[Binder]:
    out: List[Binder] = []
    for line in lines:
        m = _BLINE.match(line.strip())
        if m:
            out.append(Binder(idx=int(m.group(1)), visibility=m.group(2).strip(), dom_type=m.group(3).strip()))
    return out


def peek_binders(cfg: OracleCfg, imports: Tuple[str, ...], goal: str, lemma: str) -> List[Binder]:
    """Try applySolveReport first (post-unification metas), fallback to applyReport."""
    res1 = oracle_tactic(cfg, imports, goal, f"applySolveReport:{lemma}")
    subs = list(res1.subgoals)
    if not subs:
        res2 = oracle_tactic(cfg, imports, goal, f"applyReport:{lemma}")
        subs = list(res2.subgoals)
    return _parse_binder_lines(subs)


def drop_first_k_visible(binders: List[Binder], k: int) -> List[Binder]:
    out: List[Binder] = []
    vis_left = k
    for b in sorted(binders, key=lambda x: x.idx):
        if b.visibility == "visible" and vis_left > 0:
            vis_left -= 1
            continue
        out.append(b)
    return out

# ========= Proposers (Nat domain first) =========

def propose_terms(s: State) -> List[Action]:
    g = s.goal.strip()
    acts: List[Action] = []
    if g == "Nat":
        acts.append(Action("candidate", "zero"))
        acts.append(Action("candidate", "suc zero"))
    return acts


def propose_tactics(s: State) -> List[Action]:
    g = s.goal.strip()
    acts: List[Action] = []
    if g == "Nat":
        acts.append(Action("tactic", "applyWith:_+_:[zero]"))
        acts.append(Action("tactic", "apply:suc"))
    return acts

# ========= Scoring =========

def score_for_child(base_goal: str, action: Action, binders: Optional[List[Binder]]) -> Tuple[int, int, int]:
    """Lower is better. Returns a tuple used for sorting.
       (term_ok, remaining_visible, total_binders)
       - term_ok: 0 for candidate (terminal), 1 otherwise
       - remaining_visible: count of visible binders (from peek), else big
       - total_binders: tie-breaker
    """
    if action.kind == "candidate":
        return (0, 0, 0)
    if binders is None:
        return (1, 999, 999)
    vis = sum(1 for b in binders if b.visibility == "visible")
    return (1, vis, len(binders))

# ========= Expansion =========

def expand(cfg: OracleCfg, s: State, beam_k: int, cache: Dict[str, StepResult], visited: set[str]) -> List[State]:
    candidates: List[Tuple[Tuple[int, int, int], State]] = []

    def cache_get(a: Action) -> StepResult:
        k = hash_key(s.imports, s.goal, a)
        r = cache.get(k)
        if r is None:
            if a.kind == "candidate":
                r = oracle_candidate(cfg, s.imports, s.goal, a.payload)
            else:
                r = oracle_tactic(cfg, s.imports, s.goal, a.payload)
            cache[k] = r
        return r

    actions = propose_terms(s) + propose_tactics(s)

    for a in actions:
        # Terminal candidate
        if a.kind == "candidate":
            res = cache_get(a)
            if res.ok:
                ns = State(s.imports, goal="⊤", script=s.script + (f"candidate:{a.payload}",))
                candidates.append((score_for_child(s.goal, a, None), ns))
            continue

        # Tactic: prefer structured peek
        if a.payload.startswith("applyWith:"):
            # applyWith:<lemma>:[args]
            spec = a.payload[len("applyWith:"):]
            if ":" in spec:
                lemma, rest = spec.split(":", 1)
            else:
                lemma, rest = spec, "[]"
            # count visible args provided
            inner = rest[rest.find("[")+1:rest.rfind("]")] if ("[" in rest and "]" in rest) else ""
            k_vis = len([x for x in re.split(r",", inner) if x.strip()]) if inner else 0

            binders = peek_binders(cfg, s.imports, s.goal, lemma.strip())
            if binders:
                rem = drop_first_k_visible(binders, k_vis)
                # One child per remaining binder (naïve but simple)
                for _ in rem:
                    ns = State(s.imports, goal=_.dom_type.strip(), script=s.script + (f"tactic:applyWith:{lemma}:{rest}",))
                    key = ("\n".join(ns.imports), ns.goal, "|".join(ns.script))
                    if key in visited: continue
                    visited.add(key)
                    candidates.append((score_for_child(s.goal, a, rem), ns))
                continue
            # Fallback: actually run tactic and use oracle subgoals
            res = cache_get(a)
            if res.ok and res.subgoals:
                for line in res.subgoals:
                    tail = line.split(":")[-1].strip()
                    ns = State(s.imports, goal=tail, script=s.script + (f"tactic:{a.payload}",))
                    key = ("\n".join(ns.imports), ns.goal, "|".join(ns.script))
                    if key in visited: continue
                    visited.add(key)
                    candidates.append(((1, 998, 998), ns))
            continue

        if a.payload.startswith("apply:"):
            lemma = a.payload.split(":", 1)[1].strip()
            binders = peek_binders(cfg, s.imports, s.goal, lemma)
            if binders:
                for _ in binders:
                    ns = State(s.imports, goal=_.dom_type.strip(), script=s.script + (f"tactic:apply:{lemma}",))
                    key = ("\n".join(ns.imports), ns.goal, "|".join(ns.script))
                    if key in visited: continue
                    visited.add(key)
                    candidates.append((score_for_child(s.goal, a, binders), ns))
                continue
            # Fallback to oracle subgoal text
            res = cache_get(a)
            if res.ok and res.subgoals:
                for line in res.subgoals:
                    tail = line.split(":")[-1].strip()
                    ns = State(s.imports, goal=tail, script=s.script + (f"tactic:apply:{lemma}",))
                    key = ("\n".join(ns.imports), ns.goal, "|".join(ns.script))
                    if key in visited: continue
                    visited.add(key)
                    candidates.append(((1, 999, 999), ns))
            continue

    # Beam: sort by score then cut
    candidates.sort(key=lambda x: x[0])
    return [ns for _, ns in candidates[:beam_k]]

# ========= BFS =========

def bfs(cfg: OracleCfg, start: State, max_depth: int, beam_k: int) -> Optional[State]:
    from collections import deque
    cache: Dict[str, StepResult] = {}
    visited: set[str] = set()
    q = deque([start])
    depth = 0
    while q and depth <= max_depth:
        level_count = len(q)
        for _ in range(level_count):
            s = q.popleft()
            if s.goal == "⊤":
                return s
            for ns in expand(cfg, s, beam_k, cache, visited):
                q.append(ns)
        depth += 1
    return None

# ========= CLI =========

def main() -> None:
    ap = argparse.ArgumentParser(description="AgdaJang search loop (BFS/beam), v0.3")
    ap.add_argument("--agda-dir", default="agda")
    ap.add_argument("--agda-bin", default="agda")
    ap.add_argument("--jang-try", default="python/tools/jang_try.py")
    ap.add_argument("--goal", default="Nat")
    ap.add_argument("--imports", action="append", default=["open import Agda.Builtin.Nat"])
    ap.add_argument("--max-depth", type=int, default=3)
    ap.add_argument("--beam", type=int, default=8)
    ap.add_argument("--timeout", type=float, default=None)
    args = ap.parse_args()

    cfg = OracleCfg(agda_dir=args.agda_dir, agda_bin=args.agda_bin, jang_try=args.jang_try, timeout=args.timeout)
    start = State(imports=tuple(args.imports), goal=args.goal, script=tuple())
    res = bfs(cfg, start, max_depth=args.max_depth, beam_k=args.beam)
    if res:
        print("SUCCESS")
        print("Script:")
        for step in res.script:
            print("  -", step)
        sys.exit(0)
    else:
        print("NO PROOF FOUND (within limits)")
        sys.exit(1)

if __name__ == "__main__":
    main()
