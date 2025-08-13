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
#   python3 tools/jang_try.py --goal Nat --candidate zero --imports "open import Agda.Builtin.Nat"
#   # result: OK
#
#   python3 tools/jang_try.py --goal Nat --candidate true \
#     --imports "open import Agda.Builtin.Nat" \
#     --imports "open import Agda.Builtin.Bool"
#   # result: FAIL
#
import argparse, subprocess, tempfile, textwrap, sys, os, pathlib

TEMPLATE = """\
module TrySandbox where

open import AgdaJang.Compat
open import AgdaJang.Refine
{extra_imports}

GoalTy : Set
GoalTy = {goal}

test : GoalTy
test = refine⟨ {candidate} ⟩
"""

def run_agda(path, include_dirs):
    # Run plain Agda; we only need to scrape emitted messages.
    cmd = ["agda"] + sum([["-i", d] for d in include_dirs], []) + [path]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    out, _ = p.communicate()
    return p.returncode, out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--goal", required=True, help="Agda expression for the goal type, e.g., 'Nat'")
    ap.add_argument("--candidate", required=True, help="Agda term to try, e.g., 'zero'")
    ap.add_argument("--imports", nargs="*", default=[], help="Extra Agda imports (lines), e.g., 'open import Agda.Builtin.Nat'")
    ap.add_argument("--agda-dir", default="agda", help="Path to your repo's Agda sources (default: ./agda)")
    args = ap.parse_args()

    extra_imports = "\n".join(args.imports)
    src = TEMPLATE.format(extra_imports=extra_imports, goal=args.goal, candidate=args.candidate)

    with tempfile.TemporaryDirectory() as d:
        tmp = pathlib.Path(d)
        # Write the scratch file
        path = tmp / "TrySandbox.agda"
        path.write_text(src, encoding="utf-8")
        include_dirs = [args.agda_dir, str(tmp)]

        # Run agda from repo root so Compat/Refine are discoverable via -i (add as needed)
        rc, out = run_agda(str(path), include_dirs)
        if rc == 0:
            print("OK")
            sys.exit(0)
        else:
            print("FAIL")
            # If you want to see Agda's message on failure:
            # print(out)
            sys.exit(1)
        # rc, out = run_agda(str(path), include_dirs)

        # if "AGDAJANG_TRY:OK" in out:
        #     print("OK")
        #     sys.exit(0)
        # elif "AGDAJANG_TRY:FAIL" in out:
        #     print("FAIL")
        #     sys.exit(1)
        # else:
        #     print(out)
        #     sys.exit(2)

if __name__ == "__main__":
    main()
