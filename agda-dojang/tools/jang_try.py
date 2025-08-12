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
# USAGE
#
#    python3 tools/jang_try.py --goal Nat --candidate zero --imports "open import Agda.Builtin.Nat"
#
# If Agda can elaborate `zero : Nat`, you'll see `OK`. Otherwise `FAIL`.
# If Agda modules aren't in the include path, run with `AGDA_INCLUDE=...` or set
# `agda` flags via a small wrapper.

import argparse, subprocess, tempfile, textwrap, sys, os, pathlib, re

TEMPLATE = """\
module AgdaJang.TrySandbox where

open import AgdaJang.Compat
open import AgdaJang.Refine
open import AgdaJang.Debug
{extra_imports}

postulate
  GoalTy : Set
GoalTy = {goal}

test : GoalTy
test = try⟨ {candidate} ⟩
"""

def run_agda(path):
    # Run plain Agda; we only need to scrape emitted messages.
    p = subprocess.Popen(["agda", path], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    out, _ = p.communicate()
    return p.returncode, out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--goal", required=True, help="Agda expression for the goal type, e.g., 'Nat'")
    ap.add_argument("--candidate", required=True, help="Agda term to try, e.g., 'zero'")
    ap.add_argument("--imports", nargs="*", default=[], help="Extra Agda imports, e.g., 'open import Agda.Builtin.Nat'")
    args = ap.parse_args()

    extra_imports = "\n".join(args.imports)
    src = TEMPLATE.format(extra_imports=extra_imports, goal=args.goal, candidate=args.candidate)

    with tempfile.TemporaryDirectory() as d:
        moddir = pathlib.Path(d)
        (moddir / "AgdaJang").mkdir(exist_ok=True)
        # Write the scratch file
        path = moddir / "AgdaJang" / "TrySandbox.agda"
        path.write_text(src, encoding="utf-8")
        # Run agda from repo root so Compat/Refine are discoverable via -i (add as needed)
        rc, out = run_agda(str(path))
        if "AGDAJANG_TRY:OK" in out:
            print("OK")
            sys.exit(0)
        elif "AGDAJANG_TRY:FAIL" in out:
            print("FAIL")
            sys.exit(1)
        else:
            print(out)
            sys.exit(2)

if __name__ == "__main__":
    main()
