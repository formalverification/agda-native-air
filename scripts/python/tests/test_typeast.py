"""
Tests for `scripts/python/corpus/typeast.py`.

File: scripts/python/tests/test_typeast.py

Description
-----------
The module is pure, so the tests build `typeAst` trees in the corpus's own
shape and assert terms.  Pinned here: a non-dependent arrow (`nameHint:
null`) opens no de Bruijn binder, so the conclusion of a transitivity lemma
names its first and last algebras by the indices the v0.1 corpus prints
(measured on `Setoid.Subalgebras.Properties.≤-trans`); a dependent binder
inside a type is a local variable, not a telescope binder; unification binds
metas, refuses to bind a rigid one or to build a cyclic term, lets levels
through, and lets a meta absorb a spine prefix; a lambda applied to an
argument reduces; and rendering puts mixfix operators and projections in
place and drops hidden arguments.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_typeast.py`
"""

from __future__ import annotations

from typing import Any, Dict

from scripts.python.corpus.typeast import (
    apply_elims,
    has_free_bv,
    head,
    heads_of,
    metas_of,
    render,
    resolve,
    shift_metas,
    telescope,
    unify,
)

# ---------------------------------------------------------------------------
# typeAst constructors, in the corpus's shape
# ---------------------------------------------------------------------------


def ty(term: Dict[str, Any]) -> Dict[str, Any]:
    return {"tag": "Type", "sort": {"tag": "Inf"}, "term": term}


def pi(name: Any, hiding: str, dom: Dict[str, Any], cod: Dict[str, Any]) -> Dict[str, Any]:
    return {"tag": "Pi", "binder": {"hiding": hiding, "nameHint": name}, "dom": ty(dom), "cod": ty(cod)}


def app(term: Dict[str, Any], hiding: str = "explicit") -> Dict[str, Any]:
    return {"tag": "Apply", "hiding": hiding, "term": term}


def var(ix: int, *elims: Dict[str, Any]) -> Dict[str, Any]:
    return {"tag": "Var", "ix": ix, "elims": list(elims)}


def df(qname: str, *elims: Dict[str, Any]) -> Dict[str, Any]:
    return {"tag": "Def", "qname": qname, "elims": list(elims)}


ALG = df("Setoid.Algebras.Basic.Algebra")
LE = "Setoid.Subalgebras.Basic._._≤_"


def le(a: Dict[str, Any], b: Dict[str, Any]) -> Dict[str, Any]:
    return df(LE, app({"tag": "Other", "ctor": "Level (Max 0 [])"}, "implicit"), app(a), app(b))


# ≤-trans : {𝑨 𝑩 𝑪 : Algebra} → 𝑨 ≤ 𝑩 → 𝑩 ≤ 𝑪 → 𝑨 ≤ 𝑪, as the corpus writes it:
# the two premises are NoAbs, so the conclusion sees only the three algebras.
LE_TRANS = ty(pi("𝑨", "implicit", ALG,
              pi("𝑩", "implicit", ALG,
              pi("𝑪", "implicit", ALG,
              pi(None, "explicit", le(var(2), var(1)),
              pi(None, "explicit", le(var(1), var(0)),
                 le(var(2), var(0))))))))


def m(k: int) -> tuple:
    return ("meta", k, ())


# ---------------------------------------------------------------------------
# Conversion
# ---------------------------------------------------------------------------


def test_a_non_dependent_arrow_opens_no_binder() -> None:
    binders, concl = telescope(LE_TRANS)
    assert [(h, n) for h, n, _ in binders] == [
        ("implicit", "𝑨"), ("implicit", "𝑩"), ("implicit", "𝑪"), ("explicit", "_"), ("explicit", "_")]
    # The premises name 𝑨 𝑩 and 𝑩 𝑪, the conclusion 𝑨 𝑪, by telescope position.
    assert metas_of(binders[3][2]) == frozenset({0, 1})
    assert metas_of(binders[4][2]) == frozenset({1, 2})
    assert metas_of(concl) == frozenset({0, 2})
    assert head(concl) == LE


def test_a_dependent_binder_inside_a_type_is_local() -> None:
    # (P : Algebra) → ((x : Algebra) → x ≤ P) → P ≤ P
    t = ty(pi("P", "explicit", ALG,
           pi(None, "explicit", {"tag": "Pi", "binder": {"hiding": "explicit", "nameHint": "x"},
                                 "dom": ty(ALG), "cod": ty(le(var(0), var(1)))},
              le(var(0), var(0)))))
    binders, concl = telescope(t)
    inner = binders[1][2]
    assert inner[0] == "pi"
    # Inside the inner pi, index 0 is its own x (local) and index 1 is P.
    assert inner[3][2][1][2] == ("bv", 0, ())
    assert inner[3][2][2][2] == m(0)
    assert concl[2][1][2] == m(0) and concl[2][2][2] == m(0)
    assert not has_free_bv(inner)


# ---------------------------------------------------------------------------
# Unification
# ---------------------------------------------------------------------------


def test_unify_binds_metas_and_respects_rigid_ones() -> None:
    _, concl = telescope(LE_TRANS)
    goal = ("def", LE, (("app", "implicit", ("lvl",)), ("app", "explicit", m(10)), ("app", "explicit", m(11))))
    s = unify(concl, goal, {})
    assert s is not None and resolve(m(0), s) == m(10) and resolve(m(2), s) == m(11)
    # With the goal's metas rigid, the lemma's metas still bind to them...
    s = unify(concl, goal, {}, rigid=frozenset({10, 11}))
    assert s is not None and resolve(m(0), s) == m(10)
    # ...but two different rigid metas never unify with each other.
    assert unify(m(10), m(11), {}, rigid=frozenset({10, 11})) is None


def test_unify_refuses_a_cyclic_solution_and_lets_levels_through() -> None:
    f_of_x = ("def", "F", (("app", "explicit", m(0)),))
    assert unify(m(0), f_of_x, {}) is None
    assert unify(("lvl",), ("def", "anything", ()), {}) == {}
    assert unify(("sort",), ("sort",), {}) == {}
    assert unify(("def", "A", ()), ("def", "B", ()), {}) is None


def test_an_applied_meta_absorbs_a_spine_prefix() -> None:
    # ?S ._≈_ x y  against  𝑨 .Domain ._≈_ x y  binds ?S := 𝑨 .Domain.
    eq = ("proj", "Relation.Binary.Bundles.Setoid._≈_")
    x, y = ("app", "explicit", m(20)), ("app", "explicit", m(21))
    flex = ("meta", 0, (eq, x, y))
    rigid = ("meta", 5, (("proj", "Setoid.Algebras.Basic.Algebra.Domain"), eq, x, y))
    s = unify(flex, rigid, {}, rigid=frozenset({5, 20, 21}))
    assert s is not None
    assert resolve(m(0), s) == ("meta", 5, (("proj", "Setoid.Algebras.Basic.Algebra.Domain"),))


def test_an_unapplied_meta_binds_before_the_spine_rule_is_tried() -> None:
    # `r .algebra` (a record projection) against an unapplied `?𝑨`: bind ?𝑨,
    # in either order.  The spine rule alone would fail here (found on the
    # mined `≤-trans (issubalgebra _) (mon→≤ h1)`).
    projected = ("meta", 7, (("proj", "Setoid.Subalgebras.Basic.SubalgebraOf.algebra"),))
    s = unify(projected, m(9), {}, rigid=frozenset({7}))
    assert s is not None and resolve(m(9), s) == projected
    s = unify(m(9), projected, {})
    assert s is not None and resolve(m(9), s) == projected


def test_shifting_renames_a_telescope_apart() -> None:
    _, concl = telescope(LE_TRANS)
    assert metas_of(shift_metas(concl, 100)) == frozenset({100, 102})


# ---------------------------------------------------------------------------
# Reduction and rendering
# ---------------------------------------------------------------------------


def test_a_lambda_applied_to_an_argument_reduces() -> None:
    lam = ("lam", "explicit", ("def", "G", (("app", "explicit", ("bv", 0, ())),)))
    assert apply_elims(lam, (("app", "explicit", m(3)),)) == ("def", "G", (("app", "explicit", m(3)),))


def test_rendering_places_mixfix_operators_and_drops_hidden_arguments() -> None:
    binders, concl = telescope(LE_TRANS)
    names = {i: n for i, (_, n, _) in enumerate(binders)}
    assert render(concl, names) == "𝑨 ≤ 𝑪"
    assert render(binders[3][2], names) == "𝑨 ≤ 𝑩"
    proj = ("meta", 0, (("proj", "Agda.Builtin.Sigma.Σ.fst"),))
    assert render(proj, {0: "h"}) == "h.fst"
    assert heads_of(concl) == frozenset({LE})
