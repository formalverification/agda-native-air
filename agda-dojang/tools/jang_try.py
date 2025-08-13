#!/usr/bin/env python3
# src/tools/agda-jang_try.py
#
# Candidate runner (v0)
#
# +  Generate a scratch test file that:
#
#    +  imports the same modules as the target example;
#    +  recreates a goal with the same context and goal type;
#    +  places `try⟨ CANDIDATE ⟩` inside the goal.
#
# +  Call Agda; parse JSON output for `AGDADOJO_TRY:OK`/`FAIL`.
#
# UPDATES
#
#   Update 1: now with `--candidates`
#
#   +  Accepts one `--candidate` or many `--candidates` (repeatable).
#   +  Accepts multiple `--imports` flags (repeatable). Semicolons are supported as separators too.
#   +  Output formats: `text` (default), `json`, or `csv`.
#   +  Optional `--show-errors` to print Agda's diagnostics when a candidate fails.
#   +  Optional `--timeout` (seconds) to avoid hangs.
#
#   Update 2: now with `--tactic apply:<name>`
#
#   +  `--tactic apply:<name>` a first cut of `apply⟨_⟩` in Agda;
#      see also: the `AgdaJang.Apply` module;
#      v0: auto-insert unknowns for all args; create subgoals; introspect lemma's type,
#      create an application with *unknown* for each binder (keeping the binder's
#      visibility/instance info), and unifies it with the goal; typically leaves
#      *unsolved metas* as new subgoals (one per argument that Agda can't infer outright).
#   +  optional `--keep-scratch` to leave the generated `.agda` around for debugging (added).
#   +  explicit types + functional, no `try/except`.
#
# USAGE
#
#   python3 tools/jang_try.py --goal Nat --candidate zero --imports "open import Agda.Builtin.Nat"
#   # result: OK
#
#   python3 tools/jang_try.py --goal Nat --candidate true \
#     --imports "open import Agda.Builtin.Nat" \
#     --imports "open import Agda.Builtin.Bool"
#   # result: FAIL
#
# EXAMPLES
#
# 1. Single candidate (OK)
#
#    python3 tools/jang_try.py --goal Nat --candidate zero \
#      --imports "open import Agda.Builtin.Nat"
#
#    result: [OK] zero
#
# 2. Multiple candidates (mixed)
#
#    python3 tools/jang_try.py --goal Nat \
#      --candidates "zero; suc zero; true" \
#      --imports "open import Agda.Builtin.Nat" \
#      --imports "open import Agda.Builtin.Bool"
#
#    result:
#      [OK] zero
#      [OK] suc zero
#      [FAIL] true
#
#
# 3. JSON output (for logging)
#
#    python3 tools/jang_try.py --goal Nat --candidates "zero; true" \
#      --imports "open import Agda.Builtin.Nat" \
#      --imports "open import Agda.Builtin.Bool" \
#      --format json
#
#    result:
#      [
#        {
#          "candidate": "zero",
#          "ok": true,
#          "rc": 0,
#          "agda_output": "Checking TrySandbox (/tmp/tmpa1a9q12j/TrySandbox.agda).\n"
#        },
#        {
#          "candidate": "true",
#          "ok": false,
#          "rc": 42,
#          "agda_output": "Checking TrySandbox (/tmp/tmpes3tsttp/TrySandbox.agda).\n/tmp/tmpes3tsttp/TrySandbox.agda:12.8-22: error: [UnequalTerms]\nBool !=< Nat\nwhen checking that the expression true has type GoalTy\n"
#        }
#      ]
#
# 4. With a timeout and errors shown
#
#    python3 tools/jang_try.py --goal Nat --candidates "true" \
#      --imports "open import Agda.Builtin.Nat" \
#      --imports "open import Agda.Builtin.Bool" \
#      --show-errors --timeout 10
#
#    result:
#      [FAIL] true
#      ---- Agda ----
#      Checking TrySandbox (/tmp/tmpws1yzzp4/TrySandbox.agda).
#      /tmp/tmpws1yzzp4/TrySandbox.agda:12.8-22: error: [UnequalTerms]
#      Bool !=< Nat
#      when checking that the expression true has type GoalTy
#      --------------
#

from __future__ import annotations
import argparse, subprocess, sys, pathlib, time, json, csv
# import argparse, subprocess, tempfile, textwrap, sys, os, pathlib, json
from dataclasses import dataclass
from typing import List, Sequence, Tuple, Optional, Iterable, Dict

MODULE_TEMPLATE = """\
module TrySandbox where

open import AgdaJang.Compat
open import AgdaJang.Refine
open import AgdaJang.Apply
{extra_imports}

GoalTy : Set
GoalTy = {goal}

test : GoalTy
test = {body}
"""

@dataclass(frozen=True)
class RunConfig:
    goal: str
    imports: List[str]
    agda_dir: str
    timeout: Optional[float]
    keep_scratch: bool

@dataclass(frozen=True)
class TryResult:
    candidate: str
    ok: bool
    rc: int
    agda_output: str

@dataclass(frozen=True)
class TacticResult:
    tactic: str
    ok: bool
    rc: int
    subgoals: List[str]
    agda_output: str

def normalize_lines(chunks: Optional[Sequence[str]]) -> List[str]:
    lines: List[str] = []
    if not chunks:
        return lines
    for c in chunks:
        for piece in c.replace("\r", "\n").split("\n"):
            for sub in piece.split(";"):
                s = sub.strip()
                if s:
                    lines.append(s)
    return lines

def unique(seq: Iterable[str]) -> List[str]:
    seen: Dict[str, None] = {}
    out: List[str] = []
    for s in seq:
        if s not in seen:
            seen[s] = None
            out.append(s)
    return out

def render_body_for_candidate(candidate: str) -> str:
    # Succeeds iff candidate solves the goal → exit code 0
    return f"refine⟨ {candidate} ⟩"

def render_body_for_tactic(tactic: str) -> str:
    # Only tactic supported now: apply:<lemma>
    if tactic.startswith("apply:"):
        lemma = tactic[len("apply:") :].strip()
        # We rely on the lemma being in scope via imports; quote resolves it.
        return f"apply⟨ (quote {lemma}) ⟩"
    return f"typeError (strErr \"AGDAJANG_BAD_TACTIC\" ∷ [])"  # force failure

def render_module(goal: str, imports: List[str], body: str) -> str:
    extra_imports = "\n".join(imports)
    return MODULE_TEMPLATE.format(extra_imports=extra_imports, goal=goal, body=body)

def run_agda(path: pathlib.Path, include_dirs: Sequence[str], timeout: Optional[float]) -> Tuple[int, str]:
    cmd: List[str] = ["agda"]
    for d in include_dirs:
        cmd.extend(["-i", d])
    cmd.append(str(path))
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    # Exception-free timeout: poll loop
    deadline: Optional[float] = (time.monotonic() + timeout) if timeout else None
    out_chunks: List[str] = []
    while True:
        rc = p.poll()
        chunk = p.stdout.readline() if p.stdout else ""
        if chunk:
            out_chunks.append(chunk)
        if rc is not None:
            break
        if deadline is not None and time.monotonic() >= deadline:
            p.kill()
            rc = 124
            # Drain remaining output
            if p.stdout:
                out_chunks.extend(p.stdout.readlines())
            break
        # tiny sleep to avoid busy spin
        time.sleep(0.01)
    return rc if rc is not None else 1, "".join(out_chunks)

def try_candidate(cfg: RunConfig, candidate: str) -> TryResult:
    body = render_body_for_candidate(candidate)
    src = render_module(cfg.goal, cfg.imports, body)
    tmpdir = pathlib.Path.cwd() if cfg.keep_scratch else pathlib.Path.cwd()  # placeholder
    # Always create a fresh temp dir unless keeping scratch
    if cfg.keep_scratch:
        tmpdir = pathlib.Path(".scratch_try")
        tmpdir.mkdir(exist_ok=True)
    else:
        tmpdir = pathlib.Path(pathlib.Path.cwd() / f".tmp_{int(time.time()*1000)}")
        tmpdir.mkdir(parents=True, exist_ok=True)

    path = tmpdir / "TrySandbox.agda"
    path.write_text(src, encoding="utf-8")
    rc, out = run_agda(path, [cfg.agda_dir, str(tmpdir)], cfg.timeout)
    ok = (rc == 0)
    if not cfg.keep_scratch:
        try:
            for f in tmpdir.glob("*"):
                f.unlink()
            tmpdir.rmdir()
        except Exception:
            pass  # best effort cleanup without polluting
    return TryResult(candidate=candidate, ok=ok, rc=rc, agda_output=out)

def parse_subgoals(out: str) -> List[str]:
    # Heuristic: collect lines like "?n : TYPE" after Agda prints unsolved metas
    goals: List[str] = []
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("?") and " : " in line:
            goals.append(line)
    return goals

def run_tactic(cfg: RunConfig, tactic: str) -> TacticResult:
    body = render_body_for_tactic(tactic)
    src = render_module(cfg.goal, cfg.imports, body)
    tmpdir = pathlib.Path(".scratch_tactic") if cfg.keep_scratch else pathlib.Path.cwd() / f".tmp_{int(time.time()*1000)}"
    tmpdir.mkdir(parents=True, exist_ok=True)
    path = tmpdir / "TrySandbox.agda"
    path.write_text(src, encoding="utf-8")
    rc, out = run_agda(path, [cfg.agda_dir, str(tmpdir)], cfg.timeout)
    subs = parse_subgoals(out)
    ok = (rc == 0) or (len(subs) > 0)  # treat “has subgoals” as partial success
    if not cfg.keep_scratch:
        try:
            for f in tmpdir.glob("*"):
                f.unlink()
            tmpdir.rmdir()
        except Exception:
            pass
    return TacticResult(tactic=tactic, ok=ok, rc=rc, subgoals=subs, agda_output=out)

def main() -> None:
    ap = argparse.ArgumentParser(description="Probe Agda candidates or run simple tactics against a goal type.")
    ap.add_argument("--goal", required=True, help="Agda expression for the goal type, e.g. 'Nat'")
    ap.add_argument("--candidate", help="Single Agda term to test, e.g. 'zero'")
    ap.add_argument("--candidates", action="append", help="Repeatable; semicolons/newlines allowed in each")
    ap.add_argument("--tactic", help="e.g., apply:suc (lemma must be in scope via imports)")
    ap.add_argument("--imports", action="append", default=[], help="Repeatable; e.g., 'open import Agda.Builtin.Nat'")
    ap.add_argument("--agda-dir", default="agda", help="Path to repo Agda sources (default: ./agda)")
    ap.add_argument("--format", choices=["text", "json", "csv"], default="text")
    ap.add_argument("--show-errors", action="store_true", help="Include Agda diagnostics for failures")
    ap.add_argument("--timeout", type=float, default=None, help="Per-run timeout (seconds)")
    ap.add_argument("--keep-scratch", action="store_true", help="Keep the generated TrySandbox.agda for inspection")
    args = ap.parse_args()

    imports = unique(normalize_lines(args.imports))
    cfg = RunConfig(goal=args.goal, imports=imports, agda_dir=args.agda_dir,
                    timeout=args.timeout, keep_scratch=args.keep_scratch)

    if args.tactic:
        t = args.tactic.strip()
        res = run_tactic(cfg, t)
        if args.format == "json":
            print(json.dumps({
                "tactic": res.tactic,
                "ok": res.ok,
                "rc": res.rc,
                "subgoals": res.subgoals,
            }, indent=2))
        elif args.format == "csv":
            w = csv.writer(sys.stdout)
            w.writerow(["tactic", "ok", "rc", "num_subgoals"])
            w.writerow([res.tactic, "OK" if res.ok else "FAIL", res.rc, len(res.subgoals)])
        else:
            status = "OK" if res.ok else "FAIL"
            print(f"[{status}] tactic {res.tactic}")
            if res.subgoals:
                print("Subgoals:")
                for g in res.subgoals:
                    print(f"  - {g}")
            if args.show_errors and not res.ok:
                print("---- Agda ----")
                print(res.agda_output.rstrip())
                print("--------------")
        sys.exit(0 if res.ok else 1)

    # Candidate mode
    cand_list: List[str] = []
    if args.candidate:
        cand_list.append(args.candidate)
    cand_list += normalize_lines(args.candidates)
    cand_list = unique([c.strip() for c in cand_list if c and c.strip()])

    if not cand_list:
        print("error: provide --candidate or --candidates or --tactic", file=sys.stderr)
        sys.exit(2)

    results: List[TryResult] = [try_candidate(cfg, c) for c in cand_list]

    if args.format == "json":
        print(json.dumps([r.__dict__ for r in results], indent=2))
        sys.exit(0 if all(r.ok for r in results) else 1)
    if args.format == "csv":
        w = csv.writer(sys.stdout)
        w.writerow(["candidate", "ok", "rc"])
        for r in results:
            w.writerow([r.candidate, "OK" if r.ok else "FAIL", r.rc])
        sys.exit(0 if all(r.ok for r in results) else 1)

    for r in results:
        print(f"[{'OK' if r.ok else 'FAIL'}] {r.candidate}")
        if args.show_errors and not r.ok:
            print("---- Agda ----")
            print(r.agda_output.rstrip())
            print("--------------")
    sys.exit(0 if all(r.ok for r in results) else 1)

if __name__ == "__main__":
    main()
