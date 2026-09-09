"""
Tests for `scripts/python/corpus/mine_benchmark_candidates.py`.

File: scripts/python/tests/test_mine_benchmark_candidates.py

Description
-----------
The miner is a pure predicate over corpus rows, so the tests build rows and
assert membership.  The cases pinned here are the ones curation depends on:
a term-mode gold must survive, and the three ways a row can only look like
one — clause concatenation (length), cubical transport helpers (markers),
and Agda-generated definitions (name segments) — must not.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_mine_benchmark_candidates.py`
"""

from __future__ import annotations

import json
from typing import Dict

from scripts.python.corpus.mine_benchmark_candidates import (
    candidates_in,
    is_candidate,
    is_candidate_body,
    is_generated_name,
)

NAMESPACES = ("Overture", "Setoid")


def row(**overrides: object) -> Dict:
    """A corpus row shaped like the real extraction's, tier-1-seed flavored."""
    base: Dict = {
        "prettyQname": "Overture.Basic.lift∼lower",
        "prettyModule": "Overture.Basic",
        "defKind": "function",
        "hasBody": True,
        "body": "Agda.Builtin.Equality._≡_.refl",
        "type": "{a b : Level} → ...",
        "astSize": 172,
    }
    return {**base, **overrides}


def test_term_mode_seed_survives() -> None:
    assert is_candidate(row(), NAMESPACES, 250)


def test_wrong_kind_and_missing_body_are_rejected() -> None:
    assert not is_candidate(row(defKind="record"), NAMESPACES, 250)
    assert not is_candidate(row(hasBody=False, body=None), NAMESPACES, 250)


def test_namespace_fence() -> None:
    assert not is_candidate(row(prettyQname="FLRP.Parachute.huge"), NAMESPACES, 250)
    # A namespace must match as a dotted prefix, not a string prefix.
    assert not is_candidate(row(prettyQname="OvertureX.Basic.f"), NAMESPACES, 250)


def test_transport_noise_is_rejected() -> None:
    body = "Agda.Primitive.Cubical.primTransp (λ i → @9) @1"
    assert not is_candidate_body(body, 250)


def test_long_clause_concatenation_is_length_bounded() -> None:
    assert not is_candidate_body("Setoid.X.f " * 40, 250)
    assert not is_candidate_body("", 250)


def test_wrapped_single_term_with_newline_is_kept() -> None:
    # The internal printer wraps long single terms across lines; on the v0.1
    # corpus 12 of the tier's 21 single-term source lemmas carry such layout
    # newlines, so a newline must never be read as a clause separator (#132
    # review).  This body is the real (wrapped) `Setoid.Functions.Basic.
    # lift∼lower` shape.
    body = (
        "Relation.Binary.Structures.IsEquivalence.refl\n"
        "(Relation.Binary.Bundles.Setoid.isEquivalence @2)"
    )
    assert is_candidate_body(body, 250)


def test_short_multi_clause_body_passes_by_design() -> None:
    # DOCUMENTED LIMITATION (#132 review): clause bodies are joined with
    # newlines, and a short multi-clause definition therefore passes the
    # length-bounded approximation — indistinguishable from a wrapped single
    # term without a per-row clause count in the corpus schema.  Single-term-
    # ness is established when the gold is authored and type-checked as one
    # term; this test pins the filter's deliberate inclusiveness.
    body = "Agda.Builtin.Nat.Nat.zero\nAgda.Builtin.Nat.Nat.suc @0"
    assert is_candidate_body(body, 250)


def test_generated_definitions_are_rejected() -> None:
    assert is_generated_name("Setoid.Functions.Inverses.f.with-12")
    assert is_generated_name("Classical.Structures.Ring.x.absurdlambda")  # via marker
    assert not is_generated_name("Overture.Basic.lift∼lower")


def test_streaming_projection() -> None:
    lines = iter([json.dumps(row()), json.dumps(row(prettyQname="Legacy.Old.f")), " "])
    out = list(candidates_in(lines, NAMESPACES, 250))
    assert [c.pretty_qname for c in out] == ["Overture.Basic.lift∼lower"]
    assert out[0].body == "Agda.Builtin.Equality._≡_.refl"
