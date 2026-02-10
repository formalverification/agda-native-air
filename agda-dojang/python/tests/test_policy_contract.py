#!/usr/bin/env python3
"""
test_policy_contract.py

File: agda-jang/python/tests/test_policy_contract.py

Description:
    Tests for the policy contract defined in policy_contract.py, using the policy fixture.
"""
from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.policy_contract import (
    POLICY_REQUEST_SCHEMA_V0,
    POLICY_RESPONSE_SCHEMA_V0,
    parse_response_json,
)


class TestPolicyContract(unittest.TestCase):
    def _policy_fixture_path(self) -> Path:
        # This test file lives at: python/tests/test_policy_contract.py
        # So python/ is parents[1], and tools/policy_fixture.py is under it.
        here = Path(__file__).resolve()
        py_root = here.parents[1]
        return py_root / "tools" / "policy_fixture.py"

    def test_fixture_policy_emits_schema_v0(self) -> None:
        policy = self._policy_fixture_path()
        self.assertTrue(policy.exists(), f"missing policy fixture: {policy}")

        req = {
            "schema": POLICY_REQUEST_SCHEMA_V0,
            "goal": "x ≡ x",
            "context": [{"name": "x", "type": "Nat"}],
            "meta": {"test": True},
        }

        with tempfile.TemporaryDirectory() as td:
            req_path = Path(td) / "req.json"
            req_path.write_text(json.dumps(req, ensure_ascii=False), encoding="utf-8")

            cp = subprocess.run(
                ["python3", str(policy), "--in", str(req_path), "--out", "-", "--k", "5"],
                capture_output=True,
                text=True,
            )

        self.assertEqual(cp.returncode, 0, msg=f"stderr:\n{cp.stderr}")
        resp = parse_response_json(cp.stdout)
        self.assertEqual(resp.schema, POLICY_RESPONSE_SCHEMA_V0)
        self.assertTrue(any(c.term == "refl" for c in resp.candidates), "expected 'refl' among candidates")

    def test_fixture_policy_rejects_unknown_request_schema(self) -> None:
        policy = self._policy_fixture_path()

        req = {
            "schema": "agda-ai-prover/policy-request@v999",
            "goal": "⊤",
            "context": [],
        }

        with tempfile.TemporaryDirectory() as td:
            req_path = Path(td) / "req.json"
            req_path.write_text(json.dumps(req, ensure_ascii=False), encoding="utf-8")

            cp = subprocess.run(
                ["python3", str(policy), "--in", str(req_path), "--out", "-", "--k", "5"],
                capture_output=True,
                text=True,
            )

        self.assertNotEqual(cp.returncode, 0)
        self.assertIn("unsupported policy request schema", cp.stderr)


if __name__ == "__main__":
    unittest.main()
