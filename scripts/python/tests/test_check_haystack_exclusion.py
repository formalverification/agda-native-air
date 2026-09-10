"""
Tests for `scripts/python/corpus/check_haystack_exclusion.py`.

File: scripts/python/tests/test_check_haystack_exclusion.py

Description
-----------
The checker is a pure predicate over index and corpus rows, so the tests
build rows and assert verdicts.  Pinned here: the normalization agrees with
the proposer's documented example (positional renaming makes `+-comm`'s two
spellings equal), the near-alias form catches an expanded-form alias printed
the way the corpus prints it and lets a diagonal instance through, and the
three rules each report the offending qname rather than a bare failure.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_check_haystack_exclusion.py`
"""

from __future__ import annotations

from scripts.python.corpus.check_haystack_exclusion import (
    CorpusRow,
    IndexRow,
    check_row,
    dequalify,
    normalize,
    select,
    tokens,
)

# `+-suc`'s type exactly as the stdlib v0 corpus prints it (qualified, infix,
# parenthesized, line-broken).
PLUS_SUC_TYPE = (
    "(m n : Agda.Builtin.Nat.Nat) →\n(m Agda.Builtin.Nat.+ Agda.Builtin.Nat.Nat.suc n)\n"
    "Agda.Builtin.Equality.≡\nAgda.Builtin.Nat.Nat.suc (m Agda.Builtin.Nat.+ n)"
)

CORPUS = (
    CorpusRow("Data.Nat.Properties.+-suc", "+-suc", "Data.Nat.Properties", PLUS_SUC_TYPE),
    CorpusRow("Data.Nat.Properties.+-comm", "+-comm", "Data.Nat.Properties",
              "Algebra.Definitions.Commutative Agda.Builtin.Equality._≡_ Agda.Builtin.Nat._+_"),
    CorpusRow("Data.Nat.Properties.+-suc-diag", "+-suc-diag", "Data.Nat.Properties", "(m : ℕ) → m ≡ m"),
)


def index(id: str, hole: str, tpe: str, gold: str, tags=("stratum:haystack",)) -> IndexRow:
    return IndexRow(id=id, hole=hole, tpe=tpe, gold_term=gold, tags=tuple(tags))


def test_tokens_split_delimiters_and_whitespace() -> None:
    assert tokens("(m n : ℕ) → m + n") == ("(", "m", "n", ":", "ℕ", ")", "→", "m", "+", "n")


def test_normalize_matches_the_proposers_documented_example() -> None:
    assert normalize("(m n : ℕ) → m + n ≡ n + m") == normalize("(x y : ℕ) → x + y ≡ y + x")
    assert normalize("∀ (m n : ℕ) → m + n ≡ n + m") == normalize("(m n : ℕ) → m + n ≡ n + m")


def test_normalize_keeps_a_diagonal_instance_distinct() -> None:
    assert normalize("∀ (m : ℕ) → m + suc m ≡ suc (m + m)") != normalize("∀ (m n : ℕ) → m + suc n ≡ suc (m + n)")


def test_near_alias_catches_an_expanded_form_alias_as_the_corpus_prints_it() -> None:
    assert dequalify("∀ (m n : ℕ) → m + suc n ≡ suc (m + n)") == dequalify(PLUS_SUC_TYPE)


def test_near_alias_lets_the_diagonal_instance_through() -> None:
    assert dequalify("∀ (m : ℕ) → m + suc m ≡ suc (m + m)") != dequalify(PLUS_SUC_TYPE)


def test_a_haystack_row_passes_and_names_its_needle() -> None:
    v = check_row(index("haystack-nat-plus-suc-diag", "+-suc-diag-hole",
                        "∀ (m : ℕ) → m + suc m ≡ suc (m + m)", "Data.Nat.Properties.+-suc m m"), CORPUS)
    assert v.passed
    assert v.needle == "Data.Nat.Properties.+-suc"
    assert v.needle_in_corpus


def test_the_name_rule_reports_the_colliding_qname() -> None:
    v = check_row(index("x", "+-suc-diag", "∀ (m : ℕ) → m + suc m ≡ suc (m + m)",
                        "Data.Nat.Properties.+-suc m m"), CORPUS)
    assert v.name_hits == ("Data.Nat.Properties.+-suc-diag",)
    assert not v.passed


def test_the_statement_rule_fires_on_an_exact_alias_and_the_near_alias_rule_on_a_dequalified_one() -> None:
    exact = check_row(index("x", "fresh", "(m : ℕ) → m ≡ m", "Data.Nat.Properties.+-suc m m"), CORPUS)
    assert exact.statement_hits == ("Data.Nat.Properties.+-suc-diag",)
    near = check_row(index("y", "fresh", "∀ (m n : ℕ) → m + suc n ≡ suc (m + n)",
                           "Data.Nat.Properties.+-suc m n"), CORPUS)
    assert near.statement_hits == ()
    assert near.near_alias_hits == ("Data.Nat.Properties.+-suc",)


def test_select_by_tag_or_id() -> None:
    rows = (index("a", "h", "T", "g"), index("b", "h", "T", "g", tags=()), index("c", "h", "T", "g", tags=()))
    assert tuple(r.id for r in select(iter(rows), "stratum:haystack", ("c",))) == ("a", "c")
