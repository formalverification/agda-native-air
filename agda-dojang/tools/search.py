#!/usr/bin/env python3
# tools/search.py
#
# Search loop skeleton (BFS/beam)
#
# A minimal, typed, functional search program that uses our jang_try.py runner as the
# oracle.  It targets simple `Nat` goals with a couple of proposals; the structure is
# generic so we can extend it (`Bool`, `Σ`/`×`, etc.).
#
# Notes / limitations (intentional for v0)
#
# +  For tactics we use `applyReport:*` to get *binder types* as subgoals.
#    For real search we'll want the *instantiated meta types* after unification.
#    We'll add a macro that *applies* the lemma then prints the *actual meta types*.
# +  The Nat proposers are trivial, but enough to exercise the loop. We'll add more.
# +  Everything is pure except the oracle subprocess calls.

from __future__ import annotations
import argparse, json, hashlib, subprocess, sys
from dataclasses import dataclass, field
from typing import List, Tuple, Optional, Iterable, Dict

# ---------- Core types ----------

@dataclass(frozen=True)
class State:
    imports: Tuple[str, ...]
    goal: str
    script: Tuple[str, ...]  # sequence of actions (strings for now)

@dataclass(frozen=True)
class Action:
    kind: str      # "candidate" or "tactic"
    payload: str   # e.g., "zero" or "apply:suc" or "applyWith:_+_:[term⟨ zero ⟩]"

@dataclass(frozen=True)
class OracleCfg:
    agda_dir: str
    jang_try: str = "tools/jang_try.py"
    agda_bin: str = "agda"
    timeout: Optional[float] = None

@dataclass(frozen=True)
class StepResult:
    ok: bool
    subgoals: Tuple[str, ...] = field(default_factory=tuple)
    diag: str = ""  # optional diagnostic or message

# ---------- Helpers ----------

def hash_key(imports: Tuple[str, ...], goal: str, action: Action) -> str:
    h = hashlib.sha1()
    h.update("\n".join(imports).encode())
    h.update(b"\x00")
    h.update(goal.encode())
    h.update(b"\x00")
    h.update((action.kind + ":" + action.payload).encode())
    return h.hexdigest()

def unique(seq: Iterable[State]) -> List[State]:
    seen: Dict[Tuple, None] = {}
    out: List[State] = []
    for s in seq:
        k = (s.imports, s.goal, s.script)
        if k not in seen:
            seen[k] = None
            out.append(s)
    return out

# ---------- Proposers (domain-specific for now) ----------

def propose_terms(state: State) -> List[Action]:
    g = state.goal.strip()
    acts: List[Action] = []
    if g == "Nat":
        acts.append(Action("candidate", "zero"))
        acts.append(Action("candidate", "suc zero"))
    # Extend here for Bool, Σ, ×, etc.
    return acts

def propose_tactics(state: State) -> List[Action]:
    g = state.goal.strip()
    acts: List[Action] = []
    if g == "Nat":
        acts.append(Action("tactic", "apply:suc"))
        # first-arg template; runner will wrap arg with term⟨_⟩
        acts.append(Action("tactic", "applyWith:_+_:[zero]"))
        # also allow reporting-only (helps decide follow-ups)
        acts.append(Action("tactic", "applyReport:suc"))
    return acts

# ---------- Oracle calls (via jang_try.py CLI) ----------

def run_candidate(cfg: OracleCfg, imports: Tuple[str, ...], goal: str, candidate: str) -> StepResult:
    cmd = [
        sys.executable, cfg.jang_try,
        "--goal", goal,
        "--candidate", candidate,
        "--agda-dir", cfg.agda_dir,
        "--format", "json"
    ]
    for imp in imports:
        cmd += ["--imports", imp]
    if cfg.timeout:
        cmd += ["--timeout", str(cfg.timeout)]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode not in (0,1):  # 0 OK, 1 FAIL, others unexpected
        return StepResult(ok=False, diag=p.stdout.strip())
    try:
        data = json.loads(p.stdout)
    except Exception:
        return StepResult(ok=False, diag=p.stdout.strip())
    ok = bool(data and data[0].get("ok", False))
    return StepResult(ok=ok, diag=p.stdout.strip())

def run_tactic(cfg: OracleCfg, imports: Tuple[str, ...], goal: str, tactic: str) -> StepResult:
    cmd = [
        sys.executable, cfg.jang_try,
        "--goal", goal,
        "--tactic", tactic,
        "--agda-dir", cfg.agda_dir,
        "--format", "json"
    ]
    for imp in imports:
        cmd += ["--imports", imp]
    if cfg.timeout:
        cmd += ["--timeout", str(cfg.timeout)]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode not in (0,1):
        return StepResult(ok=False, diag=p.stdout.strip())
    try:
        data = json.loads(p.stdout)
    except Exception:
        return StepResult(ok=False, diag=p.stdout.strip())
    ok = bool(data.get("ok", False))
    subs = tuple(data.get("subgoals", []))
    return StepResult(ok=ok, subgoals=subs, diag=p.stdout.strip())

# ---------- Search (BFS/beam) ----------

def expand(cfg: OracleCfg, s: State, beam_k: int, cache: Dict[str, StepResult]) -> List[State]:
    next_states: List[State] = []
    # Try candidates first
    for a in propose_terms(s) + propose_tactics(s):
        k = hash_key(s.imports, s.goal, a)
        res = cache.get(k)
        if res is None:
            if a.kind == "candidate":
                res = run_candidate(cfg, s.imports, s.goal, a.payload)
            else:
                res = run_tactic(cfg, s.imports, s.goal, a.payload)
            cache[k] = res
        if a.kind == "candidate" and res.ok:
            # terminal success: solved the goal
            next_states.append(State(s.imports, goal="⊤", script=s.script + (f"{a.kind}:{a.payload}",)))
        elif a.kind == "tactic" and (res.ok and len(res.subgoals) > 0):
            # enqueue each subgoal as a new state
            for g in res.subgoals:
                # g is the printed TYPE; for Nat it will be "AGDAJANG_GOAL:i:vis: Nat" from applyReport
                # parse a minimal "tail" type if tagged:
                tail = g.split(":")[-1].strip()
                next_states.append(State(s.imports, goal=tail, script=s.script + (f"{a.kind}:{a.payload}",)))
    # beam pruning (keep first K)
    return next_states[:beam_k]

def bfs(cfg: OracleCfg, start: State, max_depth: int, beam_k: int) -> Optional[State]:
    from collections import deque
    cache: Dict[str, StepResult] = {}
    q = deque([start])
    depth = 0
    while q and depth <= max_depth:
        level_count = len(q)
        for _ in range(level_count):
            s = q.popleft()
            if s.goal == "⊤":  # solved
                return s
            for ns in expand(cfg, s, beam_k, cache):
                q.append(ns)
        depth += 1
    return None

# ---------- CLI ----------

def main() -> None:
    ap = argparse.ArgumentParser(description="AgdaJang search loop skeleton (BFS/beam).")
    ap.add_argument("--agda-dir", default="agda")
    ap.add_argument("--goal", default="Nat")
    ap.add_argument("--imports", action="append", default=["open import Agda.Builtin.Nat"])
    ap.add_argument("--max-depth", type=int, default=3)
    ap.add_argument("--beam", type=int, default=8)
    ap.add_argument("--timeout", type=float, default=None)
    args = ap.parse_args()

    cfg = OracleCfg(agda_dir=args.agda_dir, timeout=args.timeout)
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
