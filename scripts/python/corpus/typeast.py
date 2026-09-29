"""
File: scripts/python/corpus/typeast.py

Description: The `typeAst` of an agda-strux corpus row as a first-order term
  language: conversion, substitution, unification, and printing.

  Every corpus row carries `typeAst` (schema `0.3-v0`), Agda's elaborated
  internal type serialized node by node: `Pi` telescopes, `Def`/`Con`/`Var`
  heads with their eliminations (`Apply` with a hiding, `Proj`), `Lam`,
  sorts, levels, and literals.  This module turns one into terms a program
  can match against each other, which is what the composition miner of
  issue #160 (`mine_compositions.py`) needs: to ask whether one lemma's
  conclusion fits another lemma's premise, and whether any lemma of the
  corpus closes a statement in one step.

  Everything here is a pure function over immutable tuples.  The term
  grammar, with `elims` a tuple of `("app", hiding, term)` or
  `("proj", qname)`:

    ("meta", k, elims)            the k-th binder of a telescope (a lemma's
                                  parameter), applied to eliminations
    ("bv", i, elims)              a variable bound INSIDE the term, by a
                                  dependent pi or a lambda; de Bruijn index i
    ("def", qname, elims)         a defined name, and ("con", qname, elims)
    ("pi", hiding, dom, cod)      a dependent function type: cod sits under
                                  one more binder
    ("arrow", hiding, dom, cod)   a non-dependent one: cod does not
    ("lam", hiding, body)         a lambda: body under one more binder
    ("lam0", hiding, body)        a constant lambda: body under none
    ("sort",) ("lvl",)            any sort, any level (both unify with their
                                  kind: universe levels are left to Agda)
    ("lit", text) ("other", text) a literal, and anything else

Design notes:

  The serializer writes Agda's `NoAbs` binders (a non-dependent arrow
  `A → B`, a lambda that ignores its argument) with `nameHint: null` and
  WITHOUT a de Bruijn binder: in `𝑨 ≤ 𝑩 → 𝑩 ≤ 𝑪 → 𝑨 ≤ 𝑪` the conclusion's
  `𝑨` has index 2, not 4 (measured on `Setoid.Subalgebras.Properties.≤-trans`
  in the v0.1 corpus).  So a telescope binder is a variable only when its
  name hint is present, and conversion keeps the list of those binders in
  scope.

  Unification is first-order with one extension: an unbound meta applied to
  eliminations may absorb a prefix of the other side's spine
  (`?S .≈ x y` against `𝑨 .Domain .≈ x y` binds `?S := 𝑨 .Domain`), which is
  how a relation stated over a setoid meets one stated over an algebra's
  domain.  It never solves a higher-order pattern in general and it never
  unfolds a definition, so it can miss a match that Agda would find; the
  miner's outputs are candidates that Agda then checks, never verdicts.
  Levels and sorts unify with anything of their kind, since the levels of
  agda-algebras' statements are solved by Agda from the algebras they
  mention.
"""

from __future__ import annotations

from typing import Any, Callable, FrozenSet, Iterator, Mapping, Optional, Sequence, Tuple

Term = Tuple[Any, ...]
Elims = Tuple[Tuple[Any, ...], ...]
Subst = Mapping[int, Term]

LEVEL_QNAME: str = "Agda.Primitive.Level"

# ---------------------------------------------------------------------------
# Conversion from the corpus's typeAst
# ---------------------------------------------------------------------------


def _elims(es: Sequence[Mapping[str, Any]], tele: Tuple[int, ...], local: int) -> Elims:
    return tuple(("app", e["hiding"], convert(e["term"], tele, local)) if e["tag"] == "Apply"
                 else ("proj", e["qname"]) if e["tag"] == "Proj"
                 else ("other-elim", e["tag"])
                 for e in es)


def convert(node: Mapping[str, Any], tele: Tuple[int, ...] = (), local: int = 0) -> Term:
    """One typeAst node as a term.  `tele` lists the telescope positions of the
    dependent binders in scope, outermost first; `local` counts the dependent
    binders crossed inside the term itself."""
    tag = node["tag"]
    if tag == "Type":
        return convert(node["term"], tele, local)
    if tag == "Var":
        ix = node["ix"]
        es = _elims(node["elims"], tele, local)
        return ("bv", ix, es) if ix < local else ("meta", tele[len(tele) - 1 - (ix - local)], es)
    if tag in ("Def", "Con"):
        return (tag.lower(), node["qname"], _elims(node["elims"], tele, local))
    if tag == "Pi":
        hiding = node["binder"]["hiding"]
        dependent = node["binder"]["nameHint"] is not None
        return (("pi", hiding, convert(node["dom"], tele, local), convert(node["cod"], tele, local + 1))
                if dependent else
                ("arrow", hiding, convert(node["dom"], tele, local), convert(node["cod"], tele, local)))
    if tag == "Lam":
        return (("lam0", node["hiding"], convert(node["body"], tele, local))
                if node.get("nameHint") is None else
                ("lam", node["hiding"], convert(node["body"], tele, local + 1)))
    if tag in ("Sort", "Set", "Inf", "OtherSort"):
        return ("sort",)
    if tag == "Level":
        return ("lvl",)
    if tag == "Other":
        # Agda prints a level used as a term argument as `Level (Max …)`.
        return ("lvl",) if str(node.get("ctor", "")).startswith("Level") else ("other", node.get("ctor"))
    if tag == "Lit":
        return ("lit", node["lit"])
    return ("other", tag)


def telescope(type_ast: Mapping[str, Any]) -> Tuple[Tuple[Tuple[str, str, Term], ...], Term]:
    """Split a row's type into its binders `(hiding, name, type)`, outermost
    first, and its conclusion; binder k of the telescope is `("meta", k, ())`."""
    def go(t: Mapping[str, Any], j: int, tele: Tuple[int, ...],
           acc: Tuple[Tuple[str, str, Term], ...]) -> Tuple[Tuple[Tuple[str, str, Term], ...], Term]:
        term = t["term"] if t.get("tag") == "Type" else t
        if term["tag"] != "Pi":
            return acc, convert(term, tele, 0)
        hint = term["binder"]["nameHint"]
        binder = (term["binder"]["hiding"], hint if hint is not None else "_", convert(term["dom"], tele, 0))
        return go(term["cod"], j + 1, tele + ((j,) if hint is not None else ()), acc + (binder,))
    return go(type_ast, 0, (), ())


# ---------------------------------------------------------------------------
# Traversal
# ---------------------------------------------------------------------------


def tmap(t: Term, on_meta: Callable[[Term, int], Term], on_bv: Callable[[Term, int], Term],
         depth: int = 0) -> Term:
    """Rebuild a term bottom-up; `on_meta`/`on_bv` rebuild the variables (their
    eliminations already mapped), given the number of binders crossed."""
    tag = t[0]
    if tag in ("meta", "bv", "def", "con"):
        es = tuple(("app", e[1], tmap(e[2], on_meta, on_bv, depth)) if e[0] == "app" else e for e in t[2])
        node = (tag, t[1], es)
        return on_meta(node, depth) if tag == "meta" else on_bv(node, depth) if tag == "bv" else node
    if tag == "pi":
        return ("pi", t[1], tmap(t[2], on_meta, on_bv, depth), tmap(t[3], on_meta, on_bv, depth + 1))
    if tag == "arrow":
        return ("arrow", t[1], tmap(t[2], on_meta, on_bv, depth), tmap(t[3], on_meta, on_bv, depth))
    if tag == "lam":
        return ("lam", t[1], tmap(t[2], on_meta, on_bv, depth + 1))
    if tag == "lam0":
        return ("lam0", t[1], tmap(t[2], on_meta, on_bv, depth))
    return t


def subterms(t: Term, depth: int = 0) -> Iterator[Tuple[Term, int]]:
    """Every subterm with the number of binders above it, preorder.  A
    generator, so a search (`has_free_bv`) stops at its first witness."""
    yield (t, depth)
    tag = t[0]
    if tag in ("meta", "bv", "def", "con"):
        for e in t[2]:
            if e[0] == "app":
                yield from subterms(e[2], depth)
    elif tag in ("pi", "arrow"):
        yield from subterms(t[2], depth)
        yield from subterms(t[3], depth + 1 if tag == "pi" else depth)
    elif tag in ("lam", "lam0"):
        yield from subterms(t[2], depth + 1 if tag == "lam" else depth)


def metas_of(t: Term) -> FrozenSet[int]:
    return frozenset(s[1] for s, _ in subterms(t) if s[0] == "meta")


def heads_of(t: Term) -> FrozenSet[str]:
    return frozenset(s[1] for s, _ in subterms(t) if s[0] in ("def", "con"))


def has_free_bv(t: Term) -> bool:
    """Does `t` mention a variable bound outside it?"""
    return any(s[0] == "bv" and s[1] >= d for s, d in subterms(t))


def head(t: Term) -> Optional[str]:
    """The qualified name at the head of a term, if it is a definition or constructor."""
    return t[1] if t[0] in ("def", "con") else None


def shift_metas(t: Term, offset: int) -> Term:
    """Rename every meta k to k + offset (to rename two telescopes apart)."""
    return tmap(t, lambda n, d: ("meta", n[1] + offset, n[2]), lambda n, d: n)


def _shift_bv(t: Term, by: int) -> Term:
    return tmap(t, lambda n, d: n, lambda n, d: ("bv", n[1] + by if n[1] >= d else n[1], n[2]))


def _instantiate(body: Term, arg: Term) -> Term:
    """`body` (under one binder) with that binder replaced by `arg`."""
    def on_bv(n: Term, d: int) -> Term:
        return (apply_elims(_shift_bv(arg, d), n[2]) if n[1] == d
                else ("bv", n[1] - 1 if n[1] > d else n[1], n[2]))
    return tmap(body, lambda n, d: n, on_bv)


def apply_elims(t: Term, es: Elims) -> Term:
    """Apply eliminations to a term, reducing a lambda applied to an argument."""
    if not es:
        return t
    tag = t[0]
    if tag in ("meta", "bv", "def", "con"):
        return (tag, t[1], t[2] + tuple(es))
    if tag == "lam" and es[0][0] == "app":
        return apply_elims(_instantiate(t[2], es[0][2]), es[1:])
    if tag == "lam0" and es[0][0] == "app":
        return apply_elims(t[2], es[1:])
    return ("other", "stuck")


# ---------------------------------------------------------------------------
# Substitution and unification
# ---------------------------------------------------------------------------


def walk(t: Term, s: Subst) -> Term:
    """Resolve a bound meta at the head of `t`, repeatedly."""
    return walk(apply_elims(s[t[1]], t[2]), s) if t[0] == "meta" and t[1] in s else t


def resolve(t: Term, s: Subst) -> Term:
    """Apply the substitution everywhere in `t`."""
    if not s:
        return t
    return tmap(t, lambda n, d: resolve(apply_elims(s[n[1]], n[2]), s) if n[1] in s else n,
                lambda n, d: n)


def bind(k: int, t: Term, s: Subst) -> Optional[Subst]:
    """Extend `s` with k := t, or None when t escapes its binders or contains k."""
    if has_free_bv(t):
        return None
    value = resolve(t, s)
    if value == ("meta", k, ()):
        return s
    if k in metas_of(value):
        return None
    return {**s, k: value}


def unify(a: Term, b: Term, s: Optional[Subst], rigid: FrozenSet[int] = frozenset()) -> Optional[Subst]:
    """The most general extension of `s` making `a` and `b` equal, or None.
    Metas in `rigid` behave as constants (a statement's own parameters)."""
    if s is None:
        return None
    a, b = walk(a, s), walk(b, s)
    ta, tb = a[0], b[0]
    # A level is a wildcard against what a level position can hold: another
    # level expression, a level binder (a meta, left unbound, since `α ⊔ β`
    # and `β ⊔ α` are one level and no syntactic binding is right), a level
    # bound inside a premise (a de Bruijn variable), or a level-valued name.
    # It is not a wildcard against a constructor, a Π, a sort, or a literal,
    # which no level position holds (PR #218 review).  Argument lists are
    # paired positionally under one head, so on the corpus a level meets only
    # a level meta (1,602 of 1,602 times over the `≤-trans` family).
    if ta == "lvl" or tb == "lvl":
        return s if {ta, tb} <= {"lvl", "meta", "bv", "def"} else None
    if ta == "sort" and tb == "sort":
        return s
    if ta == "meta" and tb == "meta" and a[1] == b[1]:
        return _unify_elims(a[2], b[2], s, rigid)
    # An unapplied flexible meta binds outright; only when neither side is one
    # does an applied meta try to absorb a spine prefix (`r .algebra` against
    # an unapplied `?𝑨` must bind `?𝑨`, not fail on the spine rule).
    if ta == "meta" and not a[2] and a[1] not in rigid:
        return bind(a[1], b, s)
    if tb == "meta" and not b[2] and b[1] not in rigid:
        return bind(b[1], a, s)
    if ta == "meta" and a[1] not in rigid:
        return _unify_spine(a, b, s, rigid)
    if tb == "meta" and b[1] not in rigid:
        return _unify_spine(b, a, s, rigid)
    if ta != tb:
        return None
    if ta in ("def", "con", "bv"):
        return _unify_elims(a[2], b[2], s, rigid) if a[1] == b[1] else None
    if ta == "meta":
        return None
    if ta in ("pi", "arrow"):
        return unify(a[3], b[3], unify(a[2], b[2], s, rigid), rigid)
    if ta in ("lam", "lam0"):
        return unify(a[2], b[2], s, rigid)
    return s if a == b else None


def _unify_spine(flex: Term, other: Term, s: Subst, rigid: FrozenSet[int]) -> Optional[Subst]:
    """An unbound meta applied to eliminations against a head with a longer
    spine: the meta takes the head and the extra prefix, provided the prefix
    is projections only (`?S` absorbs `𝑨 .Domain`).  An argument in the
    prefix would make the meta a partial application of some other function,
    which nothing here can check is well typed, so that case fails."""
    if other[0] not in ("meta", "def", "con", "bv"):
        return None
    n, m = len(flex[2]), len(other[2])
    if m < n or any(e[0] != "proj" for e in other[2][:m - n]):
        return None
    prefix = (other[0], other[1], other[2][:m - n])
    return _unify_elims(flex[2], other[2][m - n:], bind(flex[1], prefix, s), rigid)


def _unify_elims(xs: Elims, ys: Elims, s: Optional[Subst], rigid: FrozenSet[int]) -> Optional[Subst]:
    if s is None or len(xs) != len(ys):
        return None
    if not xs:
        return s
    x, y = xs[0], ys[0]
    if x[0] != y[0] or x[0] not in ("app", "proj"):
        return None
    step = (s if x[1] == y[1] else None) if x[0] == "proj" else unify(x[2], y[2], s, rigid)
    return _unify_elims(xs[1:], ys[1:], step, rigid)


# ---------------------------------------------------------------------------
# Printing
# ---------------------------------------------------------------------------


def short(qname: str) -> str:
    """The last segment of a qualified name."""
    return qname.rsplit(".", 1)[-1] if "." in qname else qname


def render(t: Term, names: Mapping[int, str], prec: int = 0, bound: Tuple[str, ...] = ()) -> str:
    """A readable rendering: names unqualified, mixfix operators in place,
    hidden arguments dropped.  For reading candidates, not for Agda."""
    tag = t[0]
    if tag in ("def", "con", "meta", "bv"):
        name = (names.get(t[1]) or f"?{t[1]}" if tag == "meta"
                else (bound[t[1]] if t[1] < len(bound) else f"#{t[1]}") if tag == "bv"
                else short(t[1]))
        visible = [render(e[2], names, 2, bound) for e in t[2] if e[0] == "app" and e[1] == "explicit"]
        projections = [short(e[1]) for e in t[2] if e[0] == "proj"]
        holes = name.count("_") if tag in ("def", "con") and name.strip("_") else 0
        if holes and holes <= len(visible):
            parts = name.split("_")
            words = [w for i, p in enumerate(parts) for w in ([p] if p else []) + ([visible[i]] if i < holes else [])]
            text = " ".join(words)
            text = f"({text}) " + " ".join(visible[holes:]) if visible[holes:] else text
            text = "".join([f"({text})" if projections else text] + [f".{p}" for p in projections])
            return f"({text})" if prec >= 1 else text
        text = " ".join([name] + visible)
        text = (f"({text})" if visible and projections else text) + "".join(f".{p}" for p in projections)
        return f"({text})" if visible and prec >= 2 else text
    if tag in ("pi", "arrow"):
        if tag == "pi":
            x = f"x{len(bound)}"
            binder = f"({x} : {render(t[2], names, 0, bound)})" if t[1] == "explicit" else f"{{{x} : {render(t[2], names, 0, bound)}}}"
            text = f"{binder} → {render(t[3], names, 0, (x,) + bound)}"
        else:
            text = f"{render(t[2], names, 1, bound)} → {render(t[3], names, 0, bound)}"
        return f"({text})" if prec >= 1 else text
    if tag in ("lam", "lam0"):
        x = f"y{len(bound)}"
        text = (f"λ {x} → {render(t[2], names, 0, (x,) + bound)}" if tag == "lam"
                else f"λ _ → {render(t[2], names, 0, bound)}")
        return f"({text})" if prec >= 1 else text
    return {"sort": "Set", "lvl": "ℓ"}.get(tag) or (str(t[1]).replace("LitNat ", "") if tag == "lit" else str(t))
