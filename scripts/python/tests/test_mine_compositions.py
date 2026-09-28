"""
Tests for `scripts/python/corpus/mine_compositions.py`.

File: scripts/python/tests/test_mine_compositions.py

Description
-----------
The miner's core is pure, so the tests build a small library in the
corpus's own row shape and assert what the miner makes of it.  The library
has a subalgebra-like order `≤` with its transitivity law (the connective),
an isomorphism-like `≅` with a conversion `≅→≤` into the order, a closure
operator `S` with a monotonicity law (a step the goal determines), and a
lemma `≤-trans-≅` that closes one composite in a single step.  Pinned here:
the transitivity law is a connective and the conversion is not; the
one-step closure the loop's saturated form makes; the loop-reachability
search finds `S-mono (≤-trans h1 h2)` and cannot find a chain through a
middle point; a composite through the conversion is kept, and an alias of
the conversion (a second lemma doing the same step) is reported as its
alternative and drops the row; the gold sketch writes `_` for what
unification solves; and the source-layout nameability check tells a
top-level declaration (including agda-algebras' two-line `_≤_` signature)
from a `where` helper and a `private` one.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_mine_compositions.py`
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, Optional, Sequence

from scripts.python.corpus.mine_compositions import (
    Index,
    Options,
    assess,
    closes,
    code_lines,
    compositions,
    gold,
    hypothesis_names,
    is_connective,
    layout_nameable,
    lemma_of,
    load_rows,
    loop_reachable,
    middle,
    mine,
    statement_text,
)
from scripts.python.corpus.typeast import telescope

# ---------------------------------------------------------------------------
# A small library, in the corpus's row shape
# ---------------------------------------------------------------------------


def ty(term: Dict[str, Any]) -> Dict[str, Any]:
    return {"tag": "Type", "sort": {"tag": "Inf"}, "term": term}


def pi(name: Optional[str], hiding: str, dom: Dict[str, Any], cod: Dict[str, Any]) -> Dict[str, Any]:
    return {"tag": "Pi", "binder": {"hiding": hiding, "nameHint": name}, "dom": ty(dom), "cod": ty(cod)}


def app(term: Dict[str, Any], hiding: str = "explicit") -> Dict[str, Any]:
    return {"tag": "Apply", "hiding": hiding, "term": term}


def var(ix: int) -> Dict[str, Any]:
    return {"tag": "Var", "ix": ix, "elims": []}


def df(qname: str, *args: Dict[str, Any]) -> Dict[str, Any]:
    return {"tag": "Def", "qname": qname, "elims": [app(a) for a in args]}


ALG = df("L.Algebra")


def le(a: Dict[str, Any], b: Dict[str, Any]) -> Dict[str, Any]:
    return df("L._≤_", a, b)


def iso(a: Dict[str, Any], b: Dict[str, Any]) -> Dict[str, Any]:
    return df("L._≅_", a, b)


def S(a: Dict[str, Any]) -> Dict[str, Any]:
    return df("L.S", a)


def implicits(names: Sequence[str], body: Dict[str, Any]) -> Dict[str, Any]:
    """`{n₁ … : Algebra} → body`, as a raw term (a row wraps it with `ty`)."""
    return body if not names else pi(names[0], "implicit", ALG, implicits(names[1:], body))


def premise(dom: Dict[str, Any], cod: Dict[str, Any]) -> Dict[str, Any]:
    return pi(None, "explicit", dom, cod)


def row(name: str, type_ast: Dict[str, Any]) -> Dict[str, Any]:
    return {"prettyQname": f"L.{name}", "qname": f"L.{name}", "prettyName": name, "prettyModule": "L",
            "file": "/lib/src/L.agda", "defKind": "function", "typeAst": type_ast}


# (Indices count only the dependent binders: a premise opens none.)
LE_TRANS = row("≤-trans", ty(implicits("ABC", premise(le(var(2), var(1)), premise(le(var(1), var(0)), le(var(2), var(0)))))))
ISO_LE = row("≅→≤", ty(implicits("AB", premise(iso(var(1), var(0)), le(var(1), var(0))))))
ISO_LE_ALIAS = row("≅⇒≤", ty(implicits("AB", premise(iso(var(1), var(0)), le(var(1), var(0))))))
LE_TRANS_ISO = row("≤-trans-≅", ty(implicits("ABC", premise(le(var(2), var(1)), premise(iso(var(1), var(0)), le(var(2), var(0)))))))
S_MONO = row("S-mono", ty(implicits("AB", premise(le(var(1), var(0)), le(S(var(1)), S(var(0)))))))
S_SUB = row("S-sub", ty(implicits("A", le(S(var(0)), var(0)))))

LIBRARY = (LE_TRANS, ISO_LE, LE_TRANS_ISO, S_MONO, S_SUB)


def lemmas(rows: Sequence[Dict[str, Any]] = LIBRARY):
    return {r["prettyName"]: lemma_of(r) for r in rows}


def everything_nameable(_: str) -> Optional[bool]:
    return True


def opts(**kw: Any) -> Options:
    base = dict(corpus=Path("c"), library_src=Path("s"), out=Path("o"), namespaces=("L",), connectives=None,
                max_hypotheses=4, depth=4, everything=True)
    return Options(**{**base, **kw})


def by_gold(records: Sequence[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    return {r["gold"]: r for r in records}


# ---------------------------------------------------------------------------
# Lemmas and connectives
# ---------------------------------------------------------------------------


def test_a_transitivity_law_is_a_connective_and_a_conversion_is_not() -> None:
    ls = lemmas()
    assert ls["≤-trans"].slots == (3, 4)
    assert middle(ls["≤-trans"]) == frozenset({1})          # B, the middle point
    assert is_connective(ls["≤-trans"], ("L",))
    assert not is_connective(ls["≅→≤"], ("L",))
    assert not is_connective(ls["≤-trans"], ("Other",))     # a relation the library does not define


def test_an_explicit_middle_point_does_not_make_a_connective() -> None:
    # (A B C : Algebra) → A ≤ B → B ≤ C → A ≤ C: the refinement form gives the
    # explicit B a hole of its own, which the loop can fill with a context
    # name, so this law does not block the loop (agda-algebras' `coord-iso`
    # has such a middle binder, its homomorphism `h`).
    explicit = row("≤-trans′", ty(pi("A", "explicit", ALG, pi("B", "explicit", ALG, pi("C", "explicit", ALG,
        premise(le(var(2), var(1)), premise(le(var(1), var(0)), le(var(2), var(0)))))))))
    lem = lemma_of(explicit)
    assert lem.slots == (3, 4)
    assert middle(lem) == frozenset()
    assert not is_connective(lem, ("L",))


def test_one_step_closure_is_the_loops_saturated_form() -> None:
    ls = lemmas()
    # (h1 : A ≤ B) (h2 : B ≅ C) → A ≤ C, with A B C rigid statement parameters 0 1 2.
    binders, _ = telescope(LE_TRANS_ISO["typeAst"])
    facts = (binders[3][2], binders[4][2])
    goal = ("def", "L._≤_", (("app", "explicit", ("meta", 0, ())), ("app", "explicit", ("meta", 2, ()))))
    rigid = frozenset({0, 1, 2})
    assert closes(ls["≤-trans-≅"], goal, facts, rigid)
    assert not closes(ls["≤-trans"], goal, facts, rigid)    # needs B ≤ C, not B ≅ C


# ---------------------------------------------------------------------------
# The loop's reach
# ---------------------------------------------------------------------------


def m(k: int) -> tuple:
    return ("meta", k, ())


def rel(q: str, a: tuple, b: tuple) -> tuple:
    return ("def", q, (("app", "explicit", a), ("app", "explicit", b)))


def s_of(a: tuple) -> tuple:
    return ("def", "L.S", (("app", "explicit", a),))


def test_a_determined_chain_is_within_the_loops_reach() -> None:
    index = Index.of(tuple(lemmas().values()))
    # (h1 : A ≤ B) (h2 : B ≤ C) → S A ≤ S C: S-mono fixes its premise from the
    # goal, and ≤-trans then closes it from the two hypotheses.
    facts = (rel("L._≤_", m(0), m(1)), rel("L._≤_", m(1), m(2)))
    goal = rel("L._≤_", s_of(m(0)), s_of(m(2)))
    assert loop_reachable(index, goal, facts, frozenset({0, 1, 2}), depth=4)
    assert not loop_reachable(index, goal, facts, frozenset({0, 1, 2}), depth=1)


def test_a_chain_through_a_middle_point_is_not() -> None:
    index = Index.of(tuple(lemmas((LE_TRANS, ISO_LE, S_MONO, S_SUB)).values()))
    # (h1 : A ≅ B) (h2 : B ≤ C) → A ≤ C needs ≤-trans with its middle point B
    # supplied, which no move of the loop can do.
    facts = (rel("L._≅_", m(0), m(1)), rel("L._≤_", m(1), m(2)))
    assert not loop_reachable(index, rel("L._≤_", m(0), m(2)), facts, frozenset({0, 1, 2}), depth=4)


# ---------------------------------------------------------------------------
# Compositions, checks, and records
# ---------------------------------------------------------------------------


def test_a_composite_through_a_conversion_is_kept() -> None:
    records = by_gold(mine(LIBRARY, opts(), everything_nameable))
    r = records["≤-trans (≅→≤ h1) h2"]
    assert r["statement"] == "(h1 : A ≅ B) (h2 : B ≤ C) → A ≤ C"
    assert r["needles"] == ["L.≤-trans", "L.≅→≤"]
    assert r["novel"] and r["loopReachable"] is False and r["unique"] and r["keep"]
    # Fed in the second premise instead, the composite IS a library lemma.
    q = records["≤-trans h1 (≅→≤ h2)"]
    assert q["closers"] == ["L.≤-trans-≅"] and not q["keep"]


def test_an_alias_of_a_needle_is_its_alternative_and_drops_the_row() -> None:
    records = by_gold(mine(LIBRARY + (ISO_LE_ALIAS,), opts(), everything_nameable))
    r = records["≤-trans (≅→≤ h1) h2"]
    assert r["alternatives"]["L.≅→≤"] == ["L.≅⇒≤"]
    assert not r["unique"] and not r["keep"]


def test_the_kept_records_are_only_the_ones_that_pass_every_check() -> None:
    kept = mine(LIBRARY, opts(everything=False), everything_nameable)
    assert kept and all(r["keep"] for r in kept)
    assert "≤-trans (≅→≤ h1) h2" in by_gold(kept)


def test_the_gold_sketch_writes_an_underscore_for_what_unification_solves() -> None:
    ls = lemmas()
    feeders = Index.of(tuple(ls.values())).by_head
    c = next(c for c in compositions(ls["≤-trans"], feeders, 4) if c.needles == ("L.≤-trans", "L.S-sub"))
    assert gold(c.root, hypothesis_names(c)) in ("≤-trans (S-sub) h1", "≤-trans h1 (S-sub)")
    assert statement_text(c).startswith("(h1 : ")


def test_a_needle_that_is_not_nameable_drops_the_row() -> None:
    def hidden(q: str) -> Optional[bool]:
        return False if q == "L.≅→≤" else True
    index = Index.of(tuple(lemmas().values()))
    ls = lemmas()
    feeders = Index.of(tuple(ls.values())).by_head
    c = next(c for c in compositions(ls["≤-trans"], feeders, 4) if c.needles == ("L.≤-trans", "L.≅→≤"))
    assert not assess(c, index, hidden, 4).nameable


# ---------------------------------------------------------------------------
# Nameability from the source layout
# ---------------------------------------------------------------------------

SOURCE = """\
# A literate module

Prose that mentions ≤-trans : is not code.

```agda
module L where

module _ {A : Set} where
  _≤_   -- alias
    _IsSub_ : A → A → Set
  x ≤ y = x IsSub y

  ≤-trans : Set
  ≤-trans = helper
    where
    helper : Set
    helper = ≤-trans

  private
    secret : Set
    secret = ≤-trans

record R : Set where
  field
    fld : Set
```
"""


def test_nameability_follows_the_source_layout() -> None:
    lines = code_lines(SOURCE, literate=True)
    assert layout_nameable(lines, "≤-trans") is True
    assert layout_nameable(lines, "_≤_") is True           # agda-algebras' two-line signature
    assert layout_nameable(lines, "helper") is False       # a where helper
    assert layout_nameable(lines, "secret") is False       # private
    assert layout_nameable(lines, "fld") is True           # a record field
    assert layout_nameable(lines, "absent") is None


def test_literate_prose_is_not_code() -> None:
    lines = code_lines(SOURCE, literate=True)
    assert len(lines) == len(SOURCE.split("\n"))           # line numbers kept
    assert not any("Prose" in line for line in lines)


def test_a_binder_solved_through_a_type_is_not_a_middle_point() -> None:
    # {I : Set} {F : I → Algebra} (i : I)-style: a family's index type is
    # fixed once the family is, although the conclusion never names it
    # (agda-algebras' `coord-iso` concludes `𝑨 ≅ 𝒜 i` with `I` implicit).
    # Here {I : Set} {B : I} → B ≤ B → B ≤ B → B ≤ B: I occurs in no premise
    # and B's type mentions it, so nothing is a middle point.
    typed = row("typed", ty(pi("I", "implicit", {"tag": "Sort", "sort": {"tag": "Inf"}},
        pi("B", "implicit", var(0), premise(le(var(0), var(0)), premise(le(var(0), var(0)), le(var(0), var(0))))))))
    lem = lemma_of(typed)
    assert lem.from_goal == frozenset({0, 1})
    assert middle(lem) == frozenset()


def test_deepening_feeds_a_hypothesis_and_raises_k() -> None:
    # ≤-trans (≅→≤ h1) h2 : A ≅ B → B ≤ C → A ≤ C; deepened, its B ≤ C comes
    # from S-sub at B = S C (C is then named after S-sub's own binder, A2):
    # A ≅ S A2 → A ≤ A2, with three needles.
    records = by_gold(mine(LIBRARY, opts(deepen="≤-trans"), everything_nameable))
    r = records["≤-trans (≅→≤ h1) (S-sub)"]
    assert r["k"] == 3 and r["needles"] == ["L.≤-trans", "L.≅→≤", "L.S-sub"]
    assert r["statement"] == "(h1 : A ≅ (S A2)) → A ≤ A2"


def test_a_step_that_concludes_a_hypothesis_is_superfluous() -> None:
    # ≤-trans (≅→≤ h1) (≤-id h2), with ≤-id : A ≤ B → A ≤ B, passes h2 through
    # unchanged: the step does no work, so the composite is dropped...
    refl = row("≤-id", ty(implicits("AB", premise(le(var(1), var(0)), le(var(1), var(0))))))
    ls = lemmas(LIBRARY + (refl,))
    index = Index.of(tuple(ls.values()))
    padded = next(c for c in compositions(ls["≤-trans"], index.by_head, 4)
                  if c.needles == ("L.≤-trans", "L.≅→≤", "L.≤-id"))
    a = assess(padded, index, everything_nameable, 4)
    assert a.superfluous == ("L.≤-id",) and not a.unique and not a.keep(padded)
    # ...and the statement is still mined, with the lean gold.
    r = next(r for r in mine(LIBRARY + (refl,), opts(), everything_nameable)
             if r["statement"] == "(h1 : A ≅ B) (h2 : B ≤ C) → A ≤ C")
    assert r["gold"] == "≤-trans (≅→≤ h1) h2" and r["keep"]


def test_a_malformed_corpus_line_fails_the_load_and_is_named(tmp_path: Path) -> None:
    # Not JSON (line 2) and JSON without a prettyQname (line 4, which used to
    # raise KeyError): both are named, and nothing is skipped.
    corpus = tmp_path / "corpus.jsonl"
    corpus.write_text("\n".join([json.dumps({"prettyQname": "L.a"}), "{not json",
                                  json.dumps({"prettyQname": "L.b"}), json.dumps({"no": "name"}), ""]),
                      encoding="utf-8")
    loaded = load_rows(corpus)
    assert loaded.is_err
    assert "at line(s) 2, 4;" in loaded.unwrap_err().message


def test_the_last_row_per_name_wins(tmp_path: Path) -> None:
    corpus = tmp_path / "corpus.jsonl"
    corpus.write_text("\n".join(json.dumps({"prettyQname": q, "n": n}) for q, n in (("L.a", 1), ("L.b", 2), ("L.a", 3))),
                      encoding="utf-8")
    assert sorted((r["prettyQname"], r["n"]) for r in load_rows(corpus).unwrap()) == [("L.a", 3), ("L.b", 2)]
