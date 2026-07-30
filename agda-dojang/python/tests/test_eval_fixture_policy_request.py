#!/usr/bin/env python3

"""
test_eval_fixture_policy_request.py

File: agda-dojang/python/tests/test_eval_fixture_policy_request.py

Description:
    Tests that the policy request emitted by eval_fixtures.py for a particular goal
    has the expected shape and content, ensuring that the policy receives the right
    information to make informed decisions.  This is a critical part of the
    incremental-hole workflow.  Locks down the "policy receives goal and context in
    expected shape" behavior.

Notes:
  This test is somewhat brittle, as it depends on the exact formatting of the
  goal and context as emitted by eval_fixtures.py, which in turn depends on the exact
  formatting of Agda's error messages.  However, this is intentional, as we want to
  lock down the behavior of the policy request formatting to ensure the policy receives
  the information it needs in a consistent way.
"""

import json
import re
import subprocess
from pathlib import Path

def test_policy_request_for_boolean_algebra_deMorgan1(tmp_path: Path):
    # Skip if agda isn’t available (CI should have it)
    if subprocess.call(["bash", "-lc", "command -v agda >/dev/null 2>&1"]) != 0:
        return

    repo = Path(__file__).resolve().parents[3]          # adjust if your layout differs
    agda_jang = repo / "agda-dojang"
    fixture = repo / "agda-dojang" / "data" / "fixtures" / "FixtureStdlibBooleanAlgebra.agda"

    out_dir = tmp_path / "eval-out"
    run_id = "t"

    cmd = [
        "bash", "-lc",
        " ".join([
            "PYTHONPATH=python",
            "python3 python/tools/eval_fixtures.py",
            f'--fixtures "{fixture}"',
            f'--out-dir "{out_dir}"',
            f'--run-id "{run_id}"',
            "--clean",
            '--policy "python3 python/tools/policy_fixture.py"',
            "--max-holes 2",
            "--k 5",
            "--timeout 20",
            '--agda-bin "agda"',
            # The generated libraries file lives at the repo root (agda/libraries),
            # one level above the agda-dojang/ cwd this test runs in.
            '--agda-flags "-i agda --library-file=../agda/libraries -l agda-dojang -i data/fixtures"',
            '--report-expr "reportGoalCtx ?"',
        ])
    ]

    proc = subprocess.run(cmd, cwd=str(agda_jang), text=True, capture_output=True)
    # rc==1 is fine here: we intentionally stop early (--max-holes 1),
    # so the fixture will remain unsolved and eval_fixtures reports "unexpected failures".
    assert proc.returncode in (0, 1), (
        f"eval_fixtures exited {proc.returncode}\n"
        f"stdout:\n{proc.stdout}\n"
        f"stderr:\n{proc.stderr}\n"
    )

    # hole-00 is goal-¬⊥≈⊤ (no binders, empty ctx)
    # hole-01 is goal-deMorgan₁ (binders x y : Bool)
    req_path = out_dir / run_id / "logs" / "FixtureStdlibBooleanAlgebra" / "hole-01" / "policy_request.json"
    assert req_path.exists(), (
        f"missing policy_request.json at {req_path}\n"
        f"stdout:\n{proc.stdout}\n"
        f"stderr:\n{proc.stderr}\n"
    )
    data = json.loads(req_path.read_text(encoding="utf-8"))

    # Context sanity: not Set₀, does mention Bool.
    by_name = {e["name"]: e["type"] for e in data["context"]}
    assert set(by_name.keys()) >= {"x", "y"}
    assert "Set₀" not in by_name["x"]
    assert "Set₀" not in by_name["y"]
    assert re.search(r"\bBool\b", by_name["x"])
    assert re.search(r"\bBool\b", by_name["y"])

    # Goal sanity (stable): normalize whitespace, then check for required structure.
    goal = data["goal"]
    g = re.sub(r"\s+", " ", goal).strip()

    # must be an equality-ish goal
    assert ("≡" in g) or ("_≡_" in g)

    # must mention not / and / or (qualified or not)
    assert ("not" in g) or ("¬" in g)
    assert ("∧" in g) or ("_∧_" in g)
    assert ("∨" in g) or ("_∨_" in g)

    # must reference both x and y somewhere (as identifiers)
    assert re.search(r"\bx\b", g)
    assert re.search(r"\by\b", g)
