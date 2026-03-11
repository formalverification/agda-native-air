"""
test_rendering.py

File: agda-dojang/python/tests/test_rendering.py

Description: tests for the rendering.py utilities
"""
# -*- coding: utf-8 -*-
from __future__ import annotations

import re
import pytest

from utils.rendering import (
    normalize_tactic_syntax,
    render_body_for_candidate,
    render_body_for_tactic,
    render_module,
)

# -----------------------
# normalize_tactic_syntax
# -----------------------

@pytest.mark.parametrize(
    "inp, expected",
    [
        ("applyReport:_+_", "applyReport⟨ _+_ ⟩"),
        ("applyWith1:_+_, zero", "applyWith1⟨ _+_, zero ⟩"),
        ("applyWith:_+_, [ zero , suc zero ]", "applyWith⟨ _+_, [ zero , suc zero ] ⟩"),
        ("intro", "intro"),  # nullary: pass through unchanged
    ],
)
def test_normalize_tactic_wraps_when_needed(inp, expected):
    assert normalize_tactic_syntax(inp) == expected


def test_normalize_tactic_is_idempotent_when_already_wrapped():
    src = "applyReport⟨ _+_ ⟩"
    assert normalize_tactic_syntax(src) == src


# ----------------------------
# render_body_for_candidate/_t
# ----------------------------

def test_render_body_for_candidate_is_passthrough():
    assert render_body_for_candidate("suc zero") == "suc zero"


@pytest.mark.parametrize(
    "inp, expected",
    [
        ("applyReport:_+_", "applyReport⟨ _+_ ⟩"),
        ("intro", "intro"),
    ],
)
def test_render_body_for_tactic_normalizes(inp, expected):
    assert render_body_for_tactic(inp) == expected


# ---------------
# render_module()
# ---------------

def test_render_module_contains_module_header_and_goal_and_body():
    goal = "Nat"
    imports = ["open import Agda.Builtin.Nat"]
    body = "suc zero"

    src = render_module(goal, imports, body)

    assert "module TrySandbox where" in src
    assert "open import Agda.Builtin.Nat" in src
    # Check AgdaDojang imports are included
    for req in [
        "open import AgdaDojang.Prelude",
        "open import AgdaDojang.Refine",
        "open import AgdaDojang.Apply",
        "open import AgdaDojang.Debug",
    ]:
        assert req in src

    # goal & body present in the canonical position
    assert re.search(r"_\s*:\s*Nat", src)            # type line
    assert re.search(r"_\s*=\s*suc zero", src)       # value line


def test_render_module_dedupes_imports_and_preserves_user_order():
    goal = "(A : Set) → A"
    user_imports = [
        "open import Agda.Builtin.Unit",
        "open import Agda.Builtin.Nat",
        "open import AgdaDojang.Apply",  # duplicated on purpose to test dedupe
    ]
    body = "intro"

    src = render_module(goal, user_imports, body)

    # User imports appear once, in the same relative order
    pos_unit = src.find("open import Agda.Builtin.Unit")
    pos_nat  = src.find("open import Agda.Builtin.Nat")
    assert pos_unit != -1 and pos_nat != -1 and pos_unit < pos_nat

    # The duplicate AgdaDojang import should not appear twice
    assert src.count("open import AgdaDojang.Apply") == 1

    # All required Jang imports are still present (deduped)
    for req in [
        "open import AgdaDojang.Prelude",
        "open import AgdaDojang.Refine",
        "open import AgdaDojang.Apply",
        "open import AgdaDojang.Debug",
    ]:
        assert req in src


def test_render_module_whitespace_is_harmless():
    goal = "   (x : Nat) → Nat   "
    imports = ["  open import Agda.Builtin.Nat  "]
    body = "   intro   "
    src = render_module(goal, imports, body)

    # Stripped occurrences should appear
    assert "open import Agda.Builtin.Nat" in src
    assert re.search(r"_\s*:\s*\(x\s*:\s*Nat\)\s*→\s*Nat", src)
    assert re.search(r"_\s*=\s*intro", src)
