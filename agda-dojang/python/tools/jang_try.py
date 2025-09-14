"""
file: python/tools/jang_try.py
description: AgdaJang probe & tactics runner (typed, functional style).
copyright: 2025 Thmpr

WHAT IT DOES
------------

Generates a scratch Agda module with your imports and goal.

There are two modes:

(1) CANDIDATE MODE

    Uses `refine⟨ <candidate> ⟩` to check/solve the goal.

    You pass the candidate term on the CLI; e.g.

      $ python3 tools/jang_try.py \
          --goal Nat \
          --candidate "suc zero" \
          --imports "open import Agda.Builtin.Nat"

    We embed `test = refine⟨ <candidate> ⟩`.
    Agda elaborates `<candidate>` against the goal.
    If it type-checks (Agda exit 0), the goal is solved (⇒ OK), else FAIL.
    The example above returns `[OK] suc zero` because `suc zero : Nat`.

    Another example (will fail):

      $ python3 tools/jang_try.py \
          --goal Nat \
          --candidate true \
          --imports "open import Agda.Builtin.Nat" \
          --imports "open import Agda.Builtin.Bool"

    returns `[FAIL] true` because `true : Bool` does not inhabit `Nat`.

(2) TACTIC MODE

    We embed one tactic application as `test = …` and call Agda.

    The runner parses Agda output to:

       +  Return OK/FAIL (candidate), or
       +  Report subgoals from `AGDAJANG_GOAL:` tags or fall back to heuristics.

    Supported tactics (so far):

      • `apply:<lemma>`
          Build `lemma ? ? …` (metas for binders), check vs goal, unify. Usually
          leaves unresolved metas = **subgoals**.

      • `applyWith:<lemma>:[args]`
          Same as `apply:` but fills the first k **visible** arguments with the
          provided terms and leaves metas for the rest.

      • `applyReport:<lemma>`
          Does **not** solve. It prints structured lines that describe the
          binder domains and visibilities of `<lemma>` with stable tags like:

            AGDAJANG_GOAL:<index>:<visibility>: <type>

          The runner parses those lines and returns them as `subgoals`.

    Example:

      $ python3 tools/jang_try.py \
          --goal Nat \
          --tactic applyReport:_+_ \
          --imports "open import Agda.Builtin.Nat"

      Output:  [OK] tactic applyReport:_+_
               → Subgoals:
                   AGDAJANG_GOAL:0:visible: Nat
                   AGDAJANG_GOAL:1:visible: Nat

In short: **you never edit your modules to put `refine⟨ _ ⟩` manually**—the runner
creates a .

N.B. You do NOT edit your own Agda files to use these probes. The runner generates
an ephemeral scratch file each call, including an Agda module that:
  • imports whatever modules you pass via --imports,
  • declares `GoalTy = <goal>`,
  • and sets `test : GoalTy` to either a candidate or a tactic call.
Then it calls `agda` on that scratch file and interprets the result.



CLI EXAMPLES
------------

  CANDIDATES
  ----------
    python3 tools/jang_try.py --goal Nat --candidate "suc zero" \
      --imports "open import Agda.Builtin.Nat"

    OUTPUT:  [OK] suc zero

    python3 tools/jang_try.py --goal Nat \
      --candidates "zero; suc zero; true" \
      --imports "open import Agda.Builtin.Nat" \
      --imports "open import Agda.Builtin.Bool"

    OUTPUT:  [OK] zero
             [OK] suc zero
             [FAIL] true

  TACTICS
  -------
  1.  `apply:`

      python3 tools/jang_try.py --goal Nat --tactic apply:suc \
        --imports "open import Agda.Builtin.Nat" --show-errors

      OUTPUT:  [OK] tactic apply:suc
               Subgoals: (present, count unknown)

  2.  `applyWith:` with args

       python3 tools/jang_try.py --goal Nat --tactic 'applyWith:_+_:[zero]' \
         --imports "open import Agda.Builtin.Nat"

       OUTPUT:  [OK] tactic applyWith:_+_:[zero]
                Subgoals: (present, count unknown)

  3.  `applyReport:` with structured subgoals

      python3 tools/jang_try.py --goal Nat --tactic applyReport:suc \
        --imports "open import Agda.Builtin.Nat" --format text

      OUTPUT:  [OK] tactic applyReport:suc
               Subgoals:
                 - AGDAJANG_GOAL:0:visible: Nat

  4.  `applyReport:` with multiple subgoals

      python3 tools/jang_try.py --goal Nat --tactic 'applyReport:_+_' \
        --imports "open import Agda.Builtin.Nat"

      OUTPUT:  [OK] tactic applyReport:_+_
                  Subgoals:
                      - AGDAJANG_GOAL:0:visible: Nat
                      - AGDAJANG_GOAL:1:visible: Nat

  JSON (for logging)
  ------------------

    python3 tools/jang_try.py --goal Nat --candidates "zero; true" \
      --imports "open import Agda.Builtin.Nat" \
      --imports "open import Agda.Builtin.Bool" \
      --format json

    OUTPUT:  [
               {
                 "candidate": "zero",
                 "ok": true,
                 "rc": 0,
                 "agda_output": "Checking TrySandbox (/tmp/tmpa1a9q12j/TrySandbox.agda).\n"
               },
               {
                 "candidate": "true",
                 "ok": false,
                 "rc": 42,
                 "agda_output": "Checking TrySandbox (/tmp/tmpes3tsttp/TrySandbox.agda).\n/tmp/tmpes3tsttp/TrySandbox.agda:12.8-22: error: [UnequalTerms]\nBool !=< Nat\n"
               }
             ]


   TIMEOUT and ERRORS
   ------------------
     python3 tools/jang_try.py --goal Nat --candidates "true" \
       --imports "open import Agda.Builtin.Nat" \
       --imports "open import Agda.Builtin.Bool" \
       --show-errors --timeout 10

    OUTPUT:  [FAIL] true
             ---- Agda ----
             Checking TrySandbox (./agda-ai-prover/agda-jang/.tmp_1756066729604/TrySandbox.agda).
             ./agda-ai-prover/agda-jang/.tmp_1756066729604/TrySandbox.agda:13.8-22: error: [UnequalTerms]
             Bool !=< Nat
             when checking that the expression true has type GoalTy
             --------------

OPTIONS
-------
  --candidates (repeatable), --imports (repeatable), --format {text,json,csv},
  --timeout <sec>, --keep-scratch.

NOTES
-----

+ We avoid exceptions in control flow (timeout via polling).

+ All functions have explicit types; data flows through small immutable dataclasses.
"""
import shlex
from itertools import chain

from utils.types import RunConfig, TryResult, CommandResult, PipelineError
from utils.result import Ok, Err, Result
from utils.file_ops import temp_dir, write_text_atomic
from utils.rendering import (
    render_module, render_body_for_candidate, render_body_for_tactic
)
from tools.report_parser import has_markers, parse_marked_report
from utils.command_runner import run_command


MODULE_TEMPLATE = """\
module TrySandbox where

open import AgdaJang.Prelude
open import AgdaJang.Refine
open import AgdaJang.Apply
{extra_imports}

GoalTy : Set
GoalTy = {goal}

test : GoalTy
test = {body}
"""

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
    # Supported Tactics:
    #   applyWith⟨ {lemma} , [{args_list}] ⟩
    #   applyReport:<lemma>
    #   apply:<lemma>
    # N.B. the lemma should be in scope via imports.
    if tactic.startswith("applyWith:"):
        spec = tactic[len("applyWith:"):].strip()
        lemma, args = parse_apply_with(spec)
        if len(args) == 1:
            return f"applyWith1⟨ {lemma} , {args[0]} ⟩"
        wrapped = [f"term⟨ {a} ⟩" for a in args]
        args_list = ", ".join(wrapped)
        return f"applyWith⟨ {lemma} , [{args_list}] ⟩"
    if tactic.startswith("applyReport:"):
        lemma = tactic[len("applyReport:"):].strip()
        return f"applyReport⟨ {lemma} ⟩"
    if tactic.startswith("apply:"):
        lemma = tactic[len("apply:"):].strip()
        return f"apply⟨ {lemma} ⟩"
    return 'typeError (strErr "AGDAJANG_BAD_TACTIC" ∷ [])'  # force failure

def render_module(goal: str, imports: List[str], body: str) -> str:
    extra_imports = "\n".join(imports)
    return MODULE_TEMPLATE.format(extra_imports=extra_imports, goal=goal, body=body)

def split_flags(s: str) -> list[str]:
    return shlex.split(s) if s else []

def run_agda(cfg: RunConfig, path: pathlib.Path, include_dirs: list[str]) -> Result[CommandResult, PipelineError]:
    inc = list(chain.from_iterable(("-i", d) for d in include_dirs))
    cmd = [cfg.agda_bin] + split_flags(cfg.agda_flags) + inc + [str(path)]
    return run_command(cmd, timeout=cfg.timeout, merge_stderr=True)

def try_candidate(cfg: RunConfig, candidate: str) -> TryResult:
    body = render_body_for_candidate(candidate)
    src  = render_module(cfg.goal, cfg.imports, body)
    with temp_dir(cfg.keep_scratch) as d:
        path = d / "TrySandbox.agda"
        write_text_atomic(path, src)
        res = run_agda(cfg, path, [cfg.agda_dir, str(d)])
        if isinstance(res, Ok):
            rc, out = res.value.rc, res.value.stdout
            return TryResult(candidate=candidate, tactic=None, ok=(rc == 0), rc=rc, agda_output=out)
        else:
            err = res.error
            out = (err.stdout or "") + (("\n" + err.stderr) if err.stderr else "")
            return TryResult(candidate=candidate, tactic=None, ok=False, rc=err.rc, agda_output=out)

def try_tactic(cfg: RunConfig, tactic: str) -> TryResult:
    body = render_body_for_tactic(tactic)
    src  = render_module(cfg.goal, cfg.imports, body)
    with temp_dir(cfg.keep_scratch) as d:
        path = d / "TrySandbox.agda"
        write_text_atomic(path, src)
        res = run_agda(cfg, path, [cfg.agda_dir, str(d)])
        if isinstance(res, Ok):
            rc, out = res.value.rc, res.value.stdout
            return TryResult(candidate=None, tactic=tactic, ok=(rc == 0), rc=rc, agda_output=out)
        else:
            err = res.error
            out = (err.stdout or "") + (("\n" + err.stderr) if err.stderr else "")
            return TryResult(candidate=None, tactic=tactic, ok=False, rc=err.rc, agda_output=out)

def parse_subgoals(out: str) -> List[str]:
    # Heuristic: collect lines like "?n : TYPE" after Agda prints unsolved metas
    goals: List[str] = []
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("?") and " : " in line:
            goals.append(line)
    return goals

# a tiny parser to extract lines for `render_body_for_tactic`
def parse_structured_goals(out: str) -> List[str]:
    lines = []
    in_block = False
    for line in out.splitlines():
        if "AGDAJANG_SUBGOALS_BEGIN" in line:
            in_block = True
            continue
        if "AGDAJANG_SUBGOALS_END" in line:
            break
        if in_block and line.startswith("AGDAJANG_GOAL:"):
            lines.append(line.strip())
    return lines

def run_tactic(cfg: RunConfig, tactic: str) -> TacticResult:
    body = render_body_for_tactic(tactic)
    src  = render_module(cfg.goal, cfg.imports, body)

    with scratch_module("tactic", cfg.keep_scratch) as sc:
        sc.path.write_text(src, encoding="utf-8")
        rc, out = run_agda(cfg, sc.path, [cfg.agda_dir, str(sc.root)], cfg.timeout)

    subs = parse_structured_goals(out) or parse_subgoals(out)
    ok   = (rc == 0) or bool(subs) or ("[UnsolvedMetaVariables]" in out) or ("Unsolved metas" in out)
    return TacticResult(tactic=tactic, ok=ok, rc=rc, subgoals=subs, agda_output=out)

def parse_apply_with(spec: str) -> Tuple[str, List[str]]:
    # spec like: "_+_:[zero; suc zero]" or "suc:[]"
    if ":" not in spec:
        return spec.strip(), []
    lemma, rest = spec.split(":", 1)
    lemma = lemma.strip()
    args: List[str] = []
    m = re.match(r"\s*\[(.*)\]\s*$", rest)
    if m:
        inner = m.group(1)
        for piece in inner.replace("\r", "\n").split("\n"):
            for sub in re.split(r"[;,]", piece):
                s = sub.strip()
                if s:
                    args.append(s)
    return lemma, args


def main() -> None:
    ap = argparse.ArgumentParser(description="Probe Agda candidates or run simple tactics against a goal type.")
    ap.add_argument("--goal", required=True, help="Agda expression for the goal type, e.g. 'Nat'")
    ap.add_argument("--candidate", help="Single Agda term to test, e.g. 'zero'")
    ap.add_argument("--candidates", action="append", help="Repeatable; semicolons/newlines allowed in each")
    ap.add_argument("--tactic", help="e.g., apply:suc (lemma must be in scope via imports)")
    ap.add_argument("--imports", action="append", default=[], help="Repeatable; e.g., 'open import Agda.Builtin.Nat'")
    ap.add_argument("--agda-dir", default="agda", help="Path to repo Agda sources (default: ./agda)")
    ap.add_argument("--agda-bin", default="agda", help="Path to Agda binary")
    ap.add_argument("--agda-flags", default="", help="Extra flags to pass to Agda (e.g., \'-l agda-jang\')")
    ap.add_argument("--format", choices=["text", "json", "csv"], default="text")
    ap.add_argument("--show-errors", action="store_true", help="Include Agda diagnostics for failures")
    ap.add_argument("--timeout", type=float, default=None, help="Per-run timeout (seconds)")
    ap.add_argument("--keep-scratch", action="store_true", help="Keep the generated TrySandbox.agda for inspection")
    args = ap.parse_args()

    imports = unique(normalize_lines(args.imports))
    cfg = RunConfig(goal=args.goal, imports=imports, agda_dir=args.agda_dir, agda_bin=args.agda_bin,
                    timeout=args.timeout, keep_scratch=args.keep_scratch, agda_flags=args.agda_flags)

    if args.tactic:
        t = args.tactic.strip()
        res = run_tactic(cfg, t)

        # First: if markers are present, treat as success and emit structured JSON if requested
        if has_markers(res.agda_output):
            source = "applySolveReport" if ":?arg:" in res.agda_output else "applyReport"
            rep = parse_marked_report(res.agda_output, source)
            if args.format == "json":
                print(json.dumps({"ok": True, **rep}, ensure_ascii=False, indent=2))
            elif args.format == "csv":
                w = csv.writer(sys.stdout)
                w.writerow(["index", "visibility", "type"])
                for g in rep["goals"]:
                    w.writerow([g["index"], g["visibility"], g["type"]])
            else:
                print(f"[OK] tactic {t}")
                print("Subgoals:")
                for g in rep["goals"]:
                    print(f"  - AGDAJANG_GOAL:{g['index']}:{g['visibility']}: {g['type']}")
            sys.exit(0)

        # Otherwise fall back to your existing rendering:
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
            elif ("[UnsolvedMetaVariables]" in res.agda_output) or ("Unsolved metas" in res.agda_output):
                print("Subgoals: (present, count unknown)")
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
