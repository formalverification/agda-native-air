#!/usr/bin/env python3
# agda-jang/tools/search.py

"""
AgdaJang search loop skeleton (BFS/beam), v0.2

Design goals
------------
- *Pure driver* that calls the existing `tools/jang_try.py` as an oracle.
- Functional style, explicit dataclasses & types, tiny helpers.
- Robust subgoal discovery:
  - Prefer structured binders from `applyReport:<lemma>` (AGDAJANG_GOAL tags).
  - Heuristically support `applyWith:<lemma>:[args…]` by dropping the first K
    *visible* binders from that report.
- Beam/BFS over a tiny action set (Nat-focused to start).

Usage Examples
--------------

# Nat demo: should succeed with zero
python3 tools/search.py --goal Nat --imports "open import Agda.Builtin.Nat"

# Turn on beam/depth if you add more tactics later
python3 tools/search.py --goal Nat --beam 8 --max-depth 3 \
  --imports "open import Agda.Builtin.Nat"

# Expected output:

  SUCCESS
  Script:
    - candidate:zero


Notes
-----
- We treat `applyReport:*` as a *peek* only. The recorded script uses the
  corresponding `apply:*` / `applyWith:*` action (so our final script is a
  real proof script, not a reporting script).
- For now we parse binder *domain* types (not fully-instantiated meta types).
  This is good enough for Nat demos; we can add an Agda macro that reports
  *instantiated* metas next.

Updates
-------

Here’s what changed and why:

+  **Stable subgoal discovery.**  Instead of trusting heuristic `?0 : T` lines from
   Agda, the search loop now *peeks* with `applyReport:<lemma>` to parse the
   structured `AGDAJANG_GOAL:` binder lines, then records the **real** script step
   as `apply:<lemma>` (or `applyWith:<lemma>:[…]`). This avoids interleaving
   “report” steps into the proof script (runner already prints those tags—nice).

+  **applyWith support without new macros**.  For `applyWith:<lemma>:[args]`, we
   count the provided **visible** args and drop that many visible binders from the
   report, treating the rest as subgoals. This mirrors what our Agda macro does (fill
   some args, leave metas for the rest), but uses only the existing reporting macro.
   (Existing `applyWith` path in our runner kept returning “present, count unknown”;
   this avoids that ambiguity. )

+  **Functional polish**. Tightened the oracle wrappers and made peek logic explicit
   with a small `Binder` dataclass and regex. I also normalized the action set so `Nat`
   goals try `(zero, suc zero, applyWith _+_ [zero], apply suc)` in that order. (Base
   structure preserved from our original `search.py`.)

+  **Script fidelity**.  We only record *real* tactics/candidates, never
   `applyReport:*`. We get a script we could, in principle, replay (once we add an
   "executor" that stitches steps into a single module).

"""

from __future__ import annotations
import argparse, json, hashlib, subprocess, sys, re
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
    payload: str   # e.g., "zero" or "apply:suc" or "applyWith:_+_:[zero]"

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

# ---------- Oracle wrappers (via jang_try.py) ----------

# We keep these tiny and deterministic.

def _run_json(cmd: List[str]) -> Tuple[int, str]:
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, p.stdout


def oracle_candidate(cfg: OracleCfg, imports: Tuple[str, ...], goal: str, candidate: str) -> StepResult:
    cmd = [
        sys.executable, cfg.jang_try,
        "--goal", goal,
        "--candidate", candidate,
        "--agda-dir", cfg.agda_dir,
        "--agda-bin", cfg.agda_bin,
        "--format", "json",
    ]
    for imp in imports:
        cmd += ["--imports", imp]
    if cfg.timeout is not None:
        cmd += ["--timeout", str(cfg.timeout)]
    rc, out = _run_json(cmd)
    if rc not in (0, 1):
        return StepResult(ok=False, diag=out.strip())
    try:
        data = json.loads(out)
    except Exception:
        return StepResult(ok=False, diag=out.strip())
    ok = bool(data and data[0].get("ok", False))
    return StepResult(ok=ok, diag=out.strip())


def oracle_tactic(cfg: OracleCfg, imports: Tuple[str, ...], goal: str, tactic: str) -> StepResult:
    cmd = [
        sys.executable, cfg.jang_try,
        "--goal", goal,
        "--tactic", tactic,
        "--agda-dir", cfg.agda_dir,
        "--agda-bin", cfg.agda_bin,
        "--format", "json",
    ]
    for imp in imports:
        cmd += ["--imports", imp]
    if cfg.timeout is not None:
        cmd += ["--timeout", str(cfg.timeout)]
    rc, out = _run_json(cmd)
    if rc not in (0, 1):
        return StepResult(ok=False, diag=out.strip())
    try:
        data = json.loads(out)
    except Exception:
        return StepResult(ok=False, diag=out.strip())
    ok = bool(data.get("ok", False))
    subs = tuple(data.get("subgoals", []))
    return StepResult(ok=ok, subgoals=subs, diag=out.strip())


# ---------- Structured-binder peek via applyReport ----------

_BLINE = re.compile(r"^AGDAJANG_GOAL:(\d+):([^:]+):\s*(.+)$")

@dataclass(frozen=True)
class Binder:
    idx: int
    visibility: str  # "visible" | "hidden" | "instance"
    dom_type: str


def peek_binders(cfg: OracleCfg, imports: Tuple[str, ...], goal: str, lemma: str) -> List[Binder]:
    # Use applyReport:<lemma> (which never solves) to get binder types.
    res = oracle_tactic(cfg, imports, goal, f"applyReport:{lemma}")
    if not res.diag:
        return []
    binders: List[Binder] = []
    try:
        # The JSON from jang_try contains only a small dict; but we asked for json,
        # and jang_try prints subgoals (if structured) in that JSON. Prefer that.
        data = json.loads(res.diag)
        if isinstance(data, dict) and data.get("subgoals"):
            for line in data["subgoals"]:
                m = _BLINE.match(line)
                if m:
                    binders.append(Binder(idx=int(m.group(1)), visibility=m.group(2).strip(), dom_type=m.group(3).strip()))
            return binders
    except Exception:
        pass
    # Fallback: parse raw lines from diag (text), in case JSON path wasn't used.
    for line in res.diag.splitlines():
        m = _BLINE.match(line.strip())
        if m:
            binders.append(Binder(idx=int(m.group(1)), visibility=m.group(2).strip(), dom_type=m.group(3).strip()))
    return binders


def drop_first_k_visible(binders: List[Binder], k: int) -> List[Binder]:
    out: List[Binder] = []
    vis_left = k
    for b in sorted(binders, key=lambda x: x.idx):
        if b.visibility == "visible" and vis_left > 0:
            vis_left -= 1
            continue
        out.append(b)
    return out


# ---------- Proposers (domain-specific for now) ----------

def propose_terms(state: State) -> List[Action]:
    g = state.goal.strip()
    acts: List[Action] = []
    if g == "Nat":
        acts.append(Action("candidate", "zero"))
        acts.append(Action("candidate", "suc zero"))
    return acts


def propose_tactics(state: State) -> List[Action]:
    g = state.goal.strip()
    acts: List[Action] = []
    if g == "Nat":
        # prefer a 1-arg apply for _+_ to create a Nat subgoal
        acts.append(Action("tactic", "applyWith:_+_:[zero]"))
        # and a plain successor step
        acts.append(Action("tactic", "apply:suc"))
    return acts


# ---------- Expansion ----------

def expand(cfg: OracleCfg, s: State, beam_k: int, cache: Dict[str, StepResult]) -> List[State]:
    next_states: List[State] = []

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
        # Candidates: terminal if OK
        if a.kind == "candidate":
            res = cache_get(a)
            if res.ok:
                next_states.append(State(s.imports, goal="⊤", script=s.script + (f"{a.kind}:{a.payload}",)))
            continue

        # Tactics: we *peek* with applyReport to derive subgoals when possible,
        # and record the *real* tactic in the script.
        if a.payload.startswith("apply:"):
            lemma = a.payload.split(":", 1)[1]
            binders = peek_binders(cfg, s.imports, s.goal, lemma)
            # Only create children if the peek finds any binders
            if binders:
                for b in binders:
                    next_states.append(State(
                        s.imports,
                        goal=b.dom_type.strip(),
                        script=s.script + (f"tactic:apply:{lemma}",)
                    ))
            else:
                # Fallback to whatever the oracle extracted (rare on well-formed goals)
                res = cache_get(a)
                if res.ok and res.subgoals:
                    for line in res.subgoals:
                        # Heuristic: last colon tail is a type
                        tail = line.split(":")[-1].strip()
                        next_states.append(State(
                            s.imports,
                            goal=tail,
                            script=s.script + (f"tactic:apply:{lemma}",)
                        ))
            continue

        if a.payload.startswith("applyWith:"):
            # applyWith:<lemma>:[args]
            spec = a.payload[len("applyWith:"):]
            if ":" in spec:
                lemma, rest = spec.split(":", 1)
            else:
                lemma, rest = spec, "[]"
            # Count provided *visible* args in the list literal
            # Format could be [zero] or [term⟨ zero ⟩, term⟨ suc zero ⟩]
            given_terms = re.findall(r"term⟨.*?⟩|[^,\[\]]+", rest)
            # Crude but robust: count items between [ ] ignoring whitespace
            k_vis = 0
            if "[" in rest and "]" in rest:
                inner = rest[rest.find("[")+1:rest.rfind("]")].strip()
                if inner:
                    # split on commas; tolerate either wrapped or raw tokens
                    k_vis = len([x for x in re.split(r",", inner) if x.strip()])
            # Peek binders and drop K visible
            binders = peek_binders(cfg, s.imports, s.goal, lemma.strip())
            if binders:
                rem = drop_first_k_visible(binders, k_vis)
                for b in rem:
                    next_states.append(State(
                        s.imports,
                        goal=b.dom_type.strip(),
                        script=s.script + (f"tactic:applyWith:{lemma}:{rest}",)
                    ))
            else:
                # As a fallback, actually run the tactic and trust the oracle
                res = cache_get(a)
                if res.ok and res.subgoals:
                    for line in res.subgoals:
                        tail = line.split(":")[-1].strip()
                        next_states.append(State(
                            s.imports,
                            goal=tail,
                            script=s.script + (f"tactic:{a.payload}",)
                        ))
            continue

    # beam pruning (keep first K)
    return next_states[:beam_k]


# ---------- BFS ----------

def bfs(cfg: OracleCfg, start: State, max_depth: int, beam_k: int) -> Optional[State]:
    from collections import deque
    cache: Dict[str, StepResult] = {}
    q = deque([start])
    depth = 0
    while q and depth <= max_depth:
        level_count = len(q)
        for _ in range(level_count):
            s = q.popleft()
            if s.goal == "⊤":
                return s
            for ns in expand(cfg, s, beam_k, cache):
                q.append(ns)
        depth += 1
    return None


# ---------- CLI ----------

def main() -> None:
    ap = argparse.ArgumentParser(description="AgdaJang search loop skeleton (BFS/beam), v0.2")
    ap.add_argument("--agda-dir", default="agda")
    ap.add_argument("--agda-bin", default="agda")
    ap.add_argument("--goal", default="Nat")
    ap.add_argument("--imports", action="append", default=["open import Agda.Builtin.Nat"])
    ap.add_argument("--max-depth", type=int, default=3)
    ap.add_argument("--beam", type=int, default=8)
    ap.add_argument("--timeout", type=float, default=None)
    args = ap.parse_args()

    cfg = OracleCfg(agda_dir=args.agda_dir, agda_bin=args.agda_bin, timeout=args.timeout)
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
