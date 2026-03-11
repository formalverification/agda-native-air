#!/usr/bin/env python3
"""
test_parse_request.py

File: agda-dojang/python/tests/test_parse_request.py

Description:
  Tests for the parse_request_json function in policy_contract.py, which is
  responsible for parsing and validating incoming JSON requests to the policy.
  Ensures that invalid inputs are rejected with appropriate error messages,
  and that valid inputs are parsed correctly.

Notes:
  parse_request_json wraps json.loads and then calls validate_request_obj which
  + requires `goal` be a string,
  + treats missing `context` as `[]` (legacy compatibility),
  + and enforces `schema` rules (or accepts missing schema if legacy is enabled).
"""


import json
import pytest

from tools.policy_contract import (
    POLICY_REQUEST_SCHEMA_V0,
    parse_request_json,
)


def test_parse_request_json_rejects_invalid_json():
    with pytest.raises(ValueError, match=r"not valid JSON"):
        parse_request_json("{ this is not json")


def test_parse_request_json_requires_goal_string():
    # Missing goal
    with pytest.raises(ValueError, match=r"missing/invalid 'goal'"):
        parse_request_json(json.dumps({"schema": POLICY_REQUEST_SCHEMA_V0, "context": []}))

    # Non-string goal
    with pytest.raises(ValueError, match=r"missing/invalid 'goal'"):
        parse_request_json(json.dumps({"schema": POLICY_REQUEST_SCHEMA_V0, "goal": 123, "context": []}))


def test_parse_request_json_allows_missing_context_as_legacy_empty_list():
    # validate_request_obj treats missing context as [] (legacy compatibility)
    req = parse_request_json(json.dumps({"goal": "A"}))
    assert req["context"] == []


def test_parse_request_json_rejects_non_list_context():
    with pytest.raises(ValueError, match=r"'context' must be a list"):
        parse_request_json(json.dumps({"goal": "A", "context": {"name": "x", "type": "A"}}))


def test_parse_request_json_rejects_unknown_schema():
    with pytest.raises(ValueError, match=r"unsupported policy request schema"):
        parse_request_json(json.dumps({"schema": "agda-native-air/policy-request@v999", "goal": "A", "context": []}))
