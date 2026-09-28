"""
File: scripts/python/corpus/mine_compositions.py

Description: Mine candidate rows for the benchmark's composition tier (issue
  #160) from an agda-strux library corpus: statements whose proof strings
  several corpus lemmas together, none of which proves the statement alone.

  A composition row poses a statement the library does not state and whose
  gold applies k >= 2 corpus lemmas (the needles).  This script finds such
  statements by chaining the corpus's own types, so the tier grows by mining
  rather than by posing each row by hand.  It works on the `typeAst` of every
  row (`typeast.py` turns one into first-order terms) and does four things.

  1.  Connectives.  A lemma whose premises share an implicit variable its
      conclusion does not fix is a transitivity step: `≤-trans : 𝑨 ≤ 𝑩 → 𝑩 ≤
      𝑪 → 𝑨 ≤ 𝑪` has the middle point 𝑩.  The proof-search loop cannot commit
      such a lemma with holes for its premises, because `fill_hole` refuses a
      candidate that leaves the middle point unsolved (checked on the real
      server: `(≤-trans {!!} {!!})` comes back `type_error`,
      `[UnsolvedMetaVariables]`).  An explicit middle binder does not count,
      since the refinement form gives it a hole of its own, and neither does a
      binder Agda solves through the type of one the goal fixes (a family's
      index type).  The connective's conclusion must be a relation the library
      defines: `≡` and `Relation.Unary`'s `⊆` are polymorphic in their carrier,
      and their middle points chained unrelated corners of the library.  Every
      candidate's gold has a connective at its root.
  2.  Compositions.  Each premise of the connective is either a hypothesis of
      the statement or the conclusion of another corpus lemma (a feeder),
      whose own premises then become hypotheses.  Unification fixes the
      middle point from the feeders; a composite whose variables do not all
      end up either fixed or quantified by the statement is dropped.
      `--deepen` feeds a kept composite's hypothesis in turn (k + 1).
  3.  Checks, each against the whole corpus, in the loop's own vocabulary:
      +  novel: no corpus lemma closes the statement in one step, with every
         premise filled by a hypothesis (the loop's saturated and `_` forms);
      +  out of the loop's reach: no search that uses only the loop's moves
         (an assumption, a lemma applied to hypotheses, or a lemma whose
         implicit variables the goal fixes, refined with holes that are
         closed the same way) proves the statement, to a bounded depth; this
         is the construction behind the tier's first gate (the loop sweeps
         solve 0 of n);
      +  every needle necessary: for each lemma of the gold, no other corpus
         lemma does its step from the same inputs (the statement's
         hypotheses and the step's own premises), no step concludes what a
         hypothesis already says, and among the composites for one statement
         the one with the fewest needles is kept, so the gold's k is the
         statement's k;
      +  nameable: every needle and every definition the statement mentions
         is a top-level, non-private definition of the library's source (a
         `where` helper cannot be named from a fixture).
  4.  Ranking and output: one JSON record per distinct statement, with the
      gold as a sketch, the needles, the checks, and a score for review.

  Usage, from the repository root (the library source is the one the
  corpus was extracted from; inside the dev shell it is the `include:`
  directory of agda-algebras in `$AGDA_DIR/libraries`):

    python3 scripts/python/corpus/mine_compositions.py \\
      --corpus data/corpora/agda-algebras/v0.1/corpus.jsonl \\
      --library-src /nix/store/<hash>-agda-algebras-.../src \\
      --out data/benchmarks/reports/compositions/candidates.jsonl

  `make mine-compositions` runs exactly this.  Candidates that pass every
  check are written in rank order; `--all` writes every composite with its
  verdicts.  A summary goes to stderr.

Design notes:

  The checks are syntactic: unification never unfolds a definition, so a
  lemma stated through an unfolded form (a Σ where the statement says `≤`)
  is invisible to them.  They are therefore a filter, not a proof: a mined
  row still gets the novelty check of the benchmark README (the server's
  search tools, a conjunctive search, and `grep` over the sources), its gold
  is checked by Agda, and the loop sweeps are run over the tier to confirm
  the first gate.  Two dependent-type facts shape the checks: universe levels
  are left to Agda (they unify with any level), and a composite whose middle
  point is fixed only through a level is never produced, since a middle
  point is never a level.

  The loop-reachability search is exponential in its depth; the default of
  four covers a determined chain of three refinements closed by
  applications, which is past what the loop's 60-probe budget explores.
"""

from __future__ import annotations

import argparse
import functools
import hashlib
import itertools
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import (Any, Callable, Dict, FrozenSet, Iterator, List, Mapping, Optional, Sequence, Tuple)

from scripts.python.corpus.typeast import (
    LEVEL_QNAME, Subst, Term, head, heads_of, metas_of, render, resolve, shift_metas, short,
    telescope, unify, walk,
)
from scripts.python.utils.file_ops import read_text, write_text
from scripts.python.utils.pipeline_types import ErrorType, PipelineError, Result

# The namespaces whose lemmas may be needles or connectives: the library's own
# mathematics, not its examples, exercises, or legacy twin (all of which stay
# in every check, since a subject can read them).
DEFAULT_NAMESPACES: Tuple[str, ...] = ("Setoid", "Classical", "Overture", "Order")

# Conclusion heads that name data rather than a property: a lemma concluding
# one of these builds an object and is not a proof step.
DATA_HEADS: FrozenSet[str] = frozenset({
    "Setoid.Algebras.Basic.𝕌[_]", "Setoid.Algebras.Basic.Algebra", LEVEL_QNAME,
    "Relation.Binary.Bundles.Setoid", "Data.Vec.Base.Vec", "Data.Fin.Base.Fin",
    "Agda.Builtin.List.List", "Agda.Builtin.Nat.Nat", "Agda.Builtin.Bool.Bool",
    "Relation.Unary.Pred", "Relation.Binary.Core.Rel", "Overture.Terms._.Term",
    "Overture.Terms.Basic.Term", "Function.Bundles._.Func",
    "Overture.Signatures.OperationSymbolsOf", "Overture.Signatures.ArityOf",
    "Overture.Signatures.Signature",
})

# ---------------------------------------------------------------------------
# Lemmas
# ---------------------------------------------------------------------------


@dataclass(frozen=True, eq=False)
class Lemma:
    """A corpus row as a rule: its binders, its conclusion, and, computed once,
    its premise slots and the binders that are universe levels.  Compared and
    hashed by identity (`eq=False`): one object per corpus row, so the
    renamed-apart copies of its types memoize cheaply (`_shifted`)."""

    qname: str
    name: str
    module: str
    file: str
    binders: Tuple[Tuple[str, str, Term], ...]
    concl: Term
    slots: Tuple[int, ...]
    levels: FrozenSet[int]
    from_goal: FrozenSet[int]
    from_all: FrozenSet[int]

    @property
    def arity(self) -> int:
        return len(self.binders)

    @property
    def conclusion_head(self) -> Optional[str]:
        return head(self.concl)


def _slots(binders: Tuple[Tuple[str, str, Term], ...], concl: Term) -> Tuple[int, ...]:
    """The premises: explicit (or instance) binders that no later binder type
    and not the conclusion mentions.  Every other binder is solved by
    unification or quantified by a statement."""
    later: List[FrozenSet[int]] = []
    acc = metas_of(concl)
    for _, _, t in reversed(binders):
        later.append(acc)
        acc = acc | metas_of(t)
    later.reverse()
    return tuple(i for i, (hiding, _, _) in enumerate(binders) if hiding != "implicit" and i not in later[i])


def _is_level(t: Term) -> bool:
    return t[0] == "lvl" or t == ("def", LEVEL_QNAME, ())


def _type_closure(binders: Tuple[Tuple[str, str, Term], ...], seed: FrozenSet[int]) -> FrozenSet[int]:
    """The binders Agda solves once `seed` is solved: those in seed, and every
    binder the type of one of them mentions, transitively (Agda unifies the
    types of what it solves; the syntactic unifier here does not, so this
    closure stands in for it: `coord-iso`'s index type I is solved from the
    type of the family it concludes about)."""
    grown = seed.union(*(metas_of(binders[k][2]) for k in seed)) if seed else seed
    return seed if grown == seed else _type_closure(binders, grown)


def lemma_of(row: Mapping[str, Any]) -> Lemma:
    """A corpus row's lemma, from its `typeAst`."""
    binders, concl = telescope(row["typeAst"])
    slots = _slots(binders, concl)
    goal_metas = metas_of(concl)
    return Lemma(
        qname=str(row["prettyQname"]), name=str(row.get("prettyName", "")), module=str(row.get("prettyModule", "")),
        file=str(row.get("file", "")), binders=binders, concl=concl, slots=slots,
        levels=frozenset(i for i, (_, _, t) in enumerate(binders) if _is_level(t)),
        from_goal=_type_closure(binders, goal_metas),
        from_all=_type_closure(binders, goal_metas.union(*(metas_of(binders[i][2]) for i in slots))))


def middle(lemma: Lemma) -> FrozenSet[int]:
    """The implicit binders a premise mentions and the conclusion does not,
    levels aside: what makes a lemma a transitivity step the loop cannot
    take.  Only an IMPLICIT middle point blocks the loop: `fill_hole` refuses
    `(≤-trans {!!} {!!})` because the middle algebra is an unsolved meta,
    but an explicit middle binder gets a hole of its own in the refinement
    form, which the loop can fill later with a context name."""
    in_premises = frozenset().union(*(metas_of(lemma.binders[i][2]) for i in lemma.slots)) if lemma.slots else frozenset()
    return frozenset(k for k in in_premises - lemma.from_goal
                     if k not in lemma.levels and lemma.binders[k][0] != "explicit")


def is_connective(lemma: Lemma, namespaces: Sequence[str]) -> bool:
    """A transitivity law of one of the library's own relations: two or more
    premises, a middle point, and a conclusion whose head the library defines.
    The last condition leaves out `≡` and `Relation.Unary`'s `∈` and `⊆`,
    which are polymorphic in their carrier, so their middle point chains
    lemmas from unrelated corners of the library through whatever term
    unifies (mined: `f (Inv f q) ≡ i`, from `InvIsInverseʳ` and `act-invʳ`)."""
    h = lemma.conclusion_head
    return (len(lemma.slots) >= 2 and bool(middle(lemma)) and h is not None
            and h.split(".", 1)[0] in namespaces)


# ---------------------------------------------------------------------------
# The corpus index and the one-step closure the loop can make
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Index:
    """Every lemma of the corpus, by the head of its conclusion."""

    by_head: Mapping[str, Tuple[Lemma, ...]]

    @staticmethod
    def of(lemmas: Sequence[Lemma]) -> "Index":
        grouped: Dict[str, List[Lemma]] = {}
        for lem in lemmas:
            h = lem.conclusion_head
            if h is not None:
                grouped.setdefault(h, []).append(lem)
        return Index({h: tuple(ls) for h, ls in grouped.items()})

    def concluding(self, goal: Term) -> Tuple[Lemma, ...]:
        h = head(goal)
        return self.by_head.get(h, ()) if h is not None else ()


@functools.lru_cache(maxsize=400_000)
def _shifted(lemma: Lemma, offset: int) -> Tuple[Tuple[Term, ...], Term]:
    """A lemma's binder types and conclusion with every meta moved by `offset`."""
    return (tuple(shift_metas(t, offset) for _, _, t in lemma.binders), shift_metas(lemma.concl, offset))


@dataclass(frozen=True)
class Inst:
    """A lemma with its binders renamed apart: binder i is meta `offset + i`."""

    lemma: Lemma
    offset: int

    def ty(self, i: int) -> Term:
        return _shifted(self.lemma, self.offset)[0][i]

    @property
    def concl(self) -> Term:
        return _shifted(self.lemma, self.offset)[1]

    def unsolved(self, s: Subst, filled: bool = True) -> bool:
        """Is any binder left unsolved that Agda could not solve either?  A
        premise, a level, and a binder in the type closure of what is solved
        (`from_all` once every premise is filled, `from_goal` when only the
        conclusion is) do not count.  With `filled` off (the loop's
        refinement form, premises left as holes) an explicit binder does not
        count either: the refinement gives it a hole of its own."""
        lem = self.lemma
        skip = set(lem.slots) | lem.levels | (lem.from_all if filled else lem.from_goal)
        return any(walk(("meta", self.offset + i, ()), s) == ("meta", self.offset + i, ())
                   for i in range(lem.arity)
                   if i not in skip and (filled or lem.binders[i][0] != "explicit"))


def _fill(inst: Inst, todo: Tuple[int, ...], facts: Sequence[Term], s: Subst,
          rigid: FrozenSet[int]) -> Optional[Subst]:
    """Fill the premises `todo` from the facts, backtracking over choices."""
    if not todo:
        return None if inst.unsolved(s) else s
    for f in facts:
        s2 = unify(inst.ty(todo[0]), f, s, rigid)
        found = _fill(inst, todo[1:], facts, s2, rigid) if s2 is not None else None
        if found is not None:
            return found
    return None


_FAR = 10 ** 7  # an offset no composite's metas reach


def closes(lemma: Lemma, goal: Term, facts: Sequence[Term], rigid: FrozenSet[int]) -> bool:
    """Does `lemma` close `goal` in one step, each premise a fact and every other
    binder solved by unification?  The loop's `_` and saturated forms."""
    inst = Inst(lemma, _FAR)
    s = unify(inst.concl, goal, {}, rigid)
    return s is not None and _fill(inst, inst.lemma.slots, facts, s, rigid) is not None


def closers(index: Index, goal: Term, facts: Sequence[Term], rigid: FrozenSet[int],
            exclude: FrozenSet[str] = frozenset(), limit: int = 4) -> Tuple[str, ...]:
    """The corpus lemmas (up to `limit`) that close `goal` in one step from `facts`."""
    hits = (lem.qname for lem in index.concluding(goal) if lem.qname not in exclude and closes(lem, goal, facts, rigid))
    return tuple(itertools.islice(hits, limit))


def loop_reachable(index: Index, goal: Term, facts: Sequence[Term], rigid: FrozenSet[int], depth: int) -> bool:
    """Can the loop's moves prove `goal` from `facts`: an assumption, a lemma
    applied to facts, or a lemma the goal determines, refined with holes that
    are each closed the same way, at most `depth` steps deep?"""
    facts_t = tuple(facts)

    @functools.lru_cache(maxsize=None)
    def reach(g: Term, d: int) -> bool:
        if any(unify(g, f, {}, rigid) is not None for f in facts_t):
            return True
        if d == 0:
            return False
        return any(_step(lem, g, d) for lem in index.concluding(g))

    def _step(lem: Lemma, g: Term, d: int) -> bool:
        inst = Inst(lem, _FAR + d * 100_000)
        s = unify(inst.concl, g, {}, rigid)
        if s is None:
            return False
        if _fill(inst, lem.slots, facts_t, s, rigid) is not None:
            return True
        # Refined with holes: only an unsolved IMPLICIT binder makes fill_hole
        # refuse.  An unsolved explicit binder is a hole the loop may fill
        # later, so it stays a flexible meta in the premises, and each premise
        # may bind it independently: an over-approximation of the loop's
        # reach, which is the safe direction for a filter that keeps only
        # what the loop cannot prove.
        return (d > 1 and bool(lem.slots) and not inst.unsolved(s, filled=False)
                and all(reach(resolve(inst.ty(i), s), d - 1) for i in lem.slots))

    return reach(goal, depth)


# ---------------------------------------------------------------------------
# Compositions
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Node:
    """One lemma in a composition, and what fills each of its premises: a
    hypothesis of the statement (None) or another node."""

    inst: Inst
    kids: Tuple[Tuple[int, Optional["Node"]], ...]

    def nodes(self) -> Iterator["Node"]:
        yield self
        for _, kid in self.kids:
            if kid is not None:
                yield from kid.nodes()

    def leaves(self) -> Iterator[Tuple["Node", int]]:
        for i, kid in self.kids:
            if kid is None:
                yield (self, i)
            else:
                yield from kid.leaves()


@dataclass(frozen=True)
class Composite:
    """A composition under its unifier, and the statement it proves."""

    root: Node
    subst: Subst
    params: Tuple[int, ...]
    hyps: Tuple[Tuple[Tuple[int, int], Term], ...]  # ((node offset, premise), type)
    concl: Term

    @property
    def needles(self) -> Tuple[str, ...]:
        return tuple(n.inst.lemma.qname for n in self.root.nodes())


def assemble(root: Node, s: Subst) -> Optional[Composite]:
    """The statement a composition proves, or None when a binder floats: neither
    solved nor mentioned by a hypothesis or the conclusion."""
    hyps = tuple(((n.inst.offset, i), resolve(n.inst.ty(i), s)) for n, i in root.leaves())
    concl = resolve(root.inst.concl, s)
    # Every binder of every node, with its type under the unifier: the
    # statement quantifies over what its hypotheses and conclusion mention and
    # over what the types of those mention in turn (a family's index type).
    types = {n.inst.offset + i: resolve(n.inst.ty(i), s) for n in root.nodes() for i in range(n.inst.lemma.arity)}

    def close(ks: FrozenSet[int]) -> FrozenSet[int]:
        grown = ks.union(*(metas_of(types[k]) for k in ks if k in types))
        return ks if grown == ks else close(grown)

    free = close(metas_of(concl).union(*(metas_of(t) for _, t in hyps)))
    floating = any(
        resolve(("meta", n.inst.offset + i, ()), s) == ("meta", n.inst.offset + i, ()) and n.inst.offset + i not in free
        for n in root.nodes() for i in range(n.inst.lemma.arity)
        if i not in n.inst.lemma.slots and i not in n.inst.lemma.levels)
    return None if floating else Composite(root, s, tuple(sorted(free)), hyps, concl)


def compositions(connective: Lemma, feeders: Mapping[str, Tuple[Lemma, ...]],
                 max_hypotheses: int) -> Iterator[Composite]:
    """Every depth-one composition rooted at `connective`: each premise a
    hypothesis or a feeder's conclusion, at least one fed, at most
    `max_hypotheses` hypotheses in all."""
    root = Inst(connective, 0)
    offsets = itertools.count(1_000, 1_000)

    def options(i: int) -> Tuple[Optional[Inst], ...]:
        premise = root.ty(i)
        h = head(premise)
        fed = (Inst(f, next(offsets)) for f in (feeders.get(h, ()) if h is not None else ()) if f.qname != connective.qname)
        return (None,) + tuple(inst for inst in fed if unify(premise, inst.concl, {}) is not None)

    per_slot = tuple((i, options(i)) for i in connective.slots)

    def go(k: int, s: Subst, kids: Tuple[Tuple[int, Optional[Node]], ...], leaves: int, fed: int) -> Iterator[Composite]:
        if leaves > max_hypotheses:
            return
        if k == len(per_slot):
            built = assemble(Node(root, kids), s) if fed else None
            if built is not None:
                yield built
            return
        i, opts = per_slot[k]
        for inst in opts:
            if inst is None:
                yield from go(k + 1, s, kids + ((i, None),), leaves + 1, fed)
                continue
            s2 = unify(root.ty(i), inst.concl, s)
            if s2 is not None:
                kid = Node(inst, tuple((j, None) for j in inst.lemma.slots))
                yield from go(k + 1, s2, kids + ((i, kid),), leaves + len(inst.lemma.slots), fed + 1)

    yield from go(0, {}, (), 0, 0)


def _replace_leaf(node: Node, target: int, slot: int, kid: Node) -> Node:
    """`node` with the hypothesis at (`target` node offset, `slot`) replaced by
    `kid`, rebuilt without touching the original tree."""
    return Node(node.inst, tuple(
        (i, kid if node.inst.offset == target and i == slot and k is None
         else _replace_leaf(k, target, slot, kid) if k is not None else None)
        for i, k in node.kids))


def deepen(c: Composite, feeders: Mapping[str, Tuple[Lemma, ...]], max_hypotheses: int) -> Iterator[Composite]:
    """Every composite one level deeper than `c`: one of its hypotheses becomes
    the conclusion of a further corpus lemma, whose premises become
    hypotheses.  How the tier reaches k = 4 with natural statements: a depth-
    one composite needs a connective with three premises for that."""
    offsets = itertools.count(max(n.inst.offset for n in c.root.nodes()) + 1_000, 1_000)
    used = frozenset(c.needles)
    for node, slot in tuple(c.root.leaves()):
        premise = node.inst.ty(slot)
        h = head(resolve(premise, c.subst))
        for lem in (feeders.get(h, ()) if h is not None else ()):
            if lem.qname in used:
                continue
            inst = Inst(lem, next(offsets))
            s2 = unify(premise, inst.concl, c.subst)
            if s2 is None:
                continue
            root = _replace_leaf(c.root, node.inst.offset, slot, Node(inst, tuple((j, None) for j in lem.slots)))
            if sum(1 for _ in root.leaves()) <= max_hypotheses:
                built = assemble(root, s2)
                if built is not None:
                    yield built


# ---------------------------------------------------------------------------
# Rendering a composite for a reader
# ---------------------------------------------------------------------------


def binder_names(c: Composite) -> Dict[int, str]:
    """A distinct readable name for every statement parameter, from the binder
    names of the lemmas it came from."""
    seen: Dict[str, int] = {}
    names: Dict[int, str] = {}
    for n in c.root.nodes():
        for i, (_, name, _) in enumerate(n.inst.lemma.binders):
            k = n.inst.offset + i
            if k in c.params and k not in names:
                seen[name] = seen.get(name, 0) + 1
                names[k] = name if seen[name] == 1 else f"{name}{seen[name]}"
    return names


def parameter_types(c: Composite) -> Dict[int, Term]:
    """Each statement parameter's type: the type of the binder it came from,
    under the composite's unifier."""
    types: Dict[int, Term] = {}
    for n in c.root.nodes():
        for i in range(n.inst.lemma.arity):
            k = n.inst.offset + i
            if k in c.params and k not in types:
                types[k] = resolve(n.inst.ty(i), c.subst)
    return types


def hypothesis_names(c: Composite) -> Dict[Tuple[int, int], str]:
    return {key: f"h{j + 1}" for j, (key, _) in enumerate(c.hyps)}


def gold(node: Node, hyp: Mapping[Tuple[int, int], str]) -> str:
    """The gold as a sketch: every explicit argument in place, a premise as its
    hypothesis or its sub-proof, anything unification solves as `_`."""
    kid_of = dict(node.kids)

    def arg(i: int) -> str:
        if i in kid_of:
            kid = kid_of[i]
            return hyp[(node.inst.offset, i)] if kid is None else f"({gold(kid, hyp)})"
        return "_"

    explicit = [i for i, (hiding, _, _) in enumerate(node.inst.lemma.binders) if hiding != "implicit"]
    return " ".join([short(node.inst.lemma.qname)] + [arg(i) for i in explicit])


def statement_text(c: Composite) -> str:
    names, hyp = binder_names(c), hypothesis_names(c)
    hs = " ".join(f"({hyp[key]} : {render(t, names)})" for key, t in c.hyps)
    return f"{hs} → {render(c.concl, names)}" if hs else render(c.concl, names)


# ---------------------------------------------------------------------------
# Assessment
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Assessment:
    novel: bool
    closers: Tuple[str, ...]
    reachable: Optional[bool]
    alternatives: Mapping[str, Tuple[str, ...]]
    nameable: bool
    superfluous: Tuple[str, ...] = ()

    @property
    def unique(self) -> bool:
        return (bool(self.alternatives) and all(not v for v in self.alternatives.values())
                and not self.superfluous)

    def keep(self, c: Composite, max_chars: int = 200) -> bool:
        return (self.novel and self.reachable is False and self.unique and self.nameable
                and len(set(c.needles)) == len(c.needles) and len(statement_text(c)) <= max_chars)


def assess(c: Composite, index: Index, nameable: Callable[[str], Optional[bool]], depth: int) -> Assessment:
    """The checks of the file header, cheapest first; a failed check skips the
    ones after it (their fields read as not computed)."""
    rigid = frozenset(c.params)
    facts = tuple(t for _, t in c.hyps)
    # A needle must be found and top-level; a definition the statement names
    # must only not be hidden (the standard library's names are not rows).
    named = (all(nameable(q) is True for q in c.needles)
             and all(nameable(h) is not False for h in heads_of(c.concl).union(*(heads_of(t) for t in facts))))
    found = closers(index, c.concl, facts, rigid, limit=3)
    if found or not named:
        return Assessment(not found, found, None, {}, named)
    if loop_reachable(index, c.concl, facts, rigid, depth):
        return Assessment(True, (), True, {}, named)

    def alternatives(n: Node) -> Tuple[str, ...]:
        step = resolve(n.inst.concl, c.subst)
        inputs = tuple(resolve(n.inst.ty(i), c.subst) for i, _ in n.kids)
        return closers(index, step, inputs + facts, rigid, exclude=frozenset({n.inst.lemma.qname}))

    # A needle whose step concludes what a hypothesis already says does no work
    # (mined: `⊧-H-invar h1 IdHomImage`, from `𝑨 ⊧ e` to `𝑨 ⊧ e`), however
    # unique it is.
    superfluous = tuple(n.inst.lemma.qname for n in c.root.nodes()
                        if any(unify(resolve(n.inst.concl, c.subst), f, {}, rigid) is not None for f in facts))
    return Assessment(True, (), False, {n.inst.lemma.qname: alternatives(n) for n in c.root.nodes()}, named, superfluous)


def score(c: Composite) -> float:
    """Review order: three needles over two or four, needles from several
    modules, fewer hypotheses, a shorter statement, no universe lifting."""
    modules = {q.rsplit(".", 1)[0] for q in c.needles}
    k = len(c.needles)
    text = statement_text(c)
    return (3.0 if k == 3 else 2.0 if k == 4 else 1.5) + len(modules) - 0.3 * len(c.hyps) \
        - len(text) / 200.0 - (2.0 if "Lift" in text else 0.0)


def record(c: Composite, a: Assessment) -> Dict[str, Any]:
    names, hyp = binder_names(c), hypothesis_names(c)
    text = statement_text(c)
    return {
        "id": hashlib.sha256(text.encode("utf-8")).hexdigest()[:12],
        "k": len(c.needles),
        "connective": c.needles[0],
        "needles": list(c.needles),
        "gold": gold(c.root, hyp),
        "statement": text,
        "parameters": [f"{names[k]} : {render(t, names)}" for k, t in parameter_types(c).items()],
        "hypotheses": [render(t, names) for _, t in c.hyps],
        "conclusion": render(c.concl, names),
        "novel": a.novel,
        "closers": list(a.closers),
        "loopReachable": a.reachable,
        "alternatives": {q: list(v) for q, v in a.alternatives.items()},
        "superfluous": list(a.superfluous),
        "unique": a.unique,
        "nameable": a.nameable,
        "keep": a.keep(c),
        "score": round(score(c), 3),
    }


# ---------------------------------------------------------------------------
# Nameability, from the library source's layout
# ---------------------------------------------------------------------------

BLOCK_HEADERS: FrozenSet[str] = frozenset({
    "module", "record", "data", "instance", "mutual", "interleaved", "abstract", "opaque", "postulate", "field",
    "constructor"})


def code_lines(text: str, literate: bool) -> Tuple[str, ...]:
    """The Agda code of a source file: every line of a `.agda`, the fenced
    `agda` blocks of a `.lagda.md` (other lines blanked, to keep numbering)."""
    if not literate:
        return tuple(text.split("\n"))

    def step(state: Tuple[bool, Tuple[str, ...]], line: str) -> Tuple[bool, Tuple[str, ...]]:
        inside, acc = state
        stripped = line.strip()
        if stripped.startswith("```"):
            return ((not inside) and stripped[3:].strip().startswith("agda"), acc + ("",))
        return (inside, acc + ((line if inside else ""),))

    return functools.reduce(step, text.split("\n"), (False, ()))[1]


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def _is_code(line: str) -> bool:
    s = line.strip()
    return bool(s) and not s.startswith("--")


def _parent(lines: Sequence[str], k: int) -> Optional[int]:
    """The nearest code line above k that is indented less."""
    ind = _indent(lines[k])
    return next((j for j in range(k - 1, -1, -1) if _is_code(lines[j]) and _indent(lines[j]) < ind), None)


def _declares(line: str, name: str) -> bool:
    """Does this line start a type signature for `name`: the name first, then
    only more names before a `:` (or before the end of the line, when the
    names continue on the next one, as in agda-algebras' `_≤_   -- alias`
    above `_IsSubalgebraOf_ : …`), and no `=` in between?"""
    tokens = line.split(" --", 1)[0].split()
    if not tokens or tokens[0] != name:
        return False
    names = tokens[:tokens.index(":")] if ":" in tokens else tokens
    return "=" not in names


def layout_nameable(lines: Sequence[str], name: str) -> Optional[bool]:
    """Is `name`'s signature a top-level declaration of its module (possibly
    inside `module`, `record`, `data` blocks), rather than a `where` helper
    or a `private` one?  None when no signature for it is found."""
    start = next((k for k, line in enumerate(lines) if _is_code(line) and _declares(line, name)), None)

    def climb(k: int) -> bool:
        p = _parent(lines, k)
        if p is None:
            return True
        first = lines[p].strip().split()[0]
        if first == "private":
            return False
        if first in BLOCK_HEADERS:
            return climb(p)
        # Indented under anything else (a clause and its `where`, a `let`):
        # a helper, which no fixture can name.
        return False

    return None if start is None else climb(start)


def library_file(corpus_file: str, library_src: Path) -> Path:
    """The source file of a corpus row inside `library_src`: the corpus records
    the path it was extracted from, whose part after `/src/` is stable."""
    cut = corpus_file.find("/src/")
    return library_src / corpus_file[cut + len("/src/"):] if cut >= 0 else Path(corpus_file)


# ---------------------------------------------------------------------------
# The shell
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Options:
    corpus: Path
    library_src: Path
    out: Path
    namespaces: Tuple[str, ...]
    connectives: Optional[str]
    max_hypotheses: int
    depth: int
    everything: bool
    deepen: Optional[str] = None


def parse_options(argv: Sequence[str]) -> Options:
    p = argparse.ArgumentParser(description=(__doc__ or "").split("\n\n")[0])
    p.add_argument("--corpus", type=Path, required=True, help="agda-strux corpus.jsonl")
    p.add_argument("--library-src", type=Path, required=True, help="the library's source root (its include: directory)")
    p.add_argument("--out", type=Path, required=True, help="candidates JSONL to write")
    p.add_argument("--namespaces", default=",".join(DEFAULT_NAMESPACES), help="top-level namespaces needles come from")
    p.add_argument("--connectives", default=None, help="only connectives whose qualified name matches this regex")
    p.add_argument("--max-hypotheses", type=int, default=4)
    p.add_argument("--depth", type=int, default=4, help="the loop-reachability search depth")
    p.add_argument("--all", dest="everything", action="store_true", help="write every composite, not only the kept ones")
    p.add_argument("--deepen", default=None,
                   help="also feed one hypothesis of every kept composite whose connective matches this regex (k + 1)")
    a = p.parse_args(list(argv))
    return Options(a.corpus, a.library_src, a.out, tuple(x.strip() for x in a.namespaces.split(",") if x.strip()),
                   a.connectives, a.max_hypotheses, a.depth, a.everything, a.deepen)


def load_rows(path: Path) -> Result[Tuple[Dict[str, Any], ...], PipelineError]:
    """The corpus rows, the last row per qualified name winning (the server's
    semantics: it indexes the corpus as a map keyed by `prettyQname`)."""
    def parse(text: str) -> Result[Tuple[Dict[str, Any], ...], PipelineError]:
        try:
            rows = [json.loads(line) for line in text.split("\n") if line.strip()]
        except json.JSONDecodeError as e:
            return Result.err(PipelineError(ErrorType.PARSING_ERROR, f"bad corpus row in {path}", cause=e))
        return Result.ok(tuple({r["prettyQname"]: r for r in rows}.values()))
    return read_text(path).and_then(parse)


def nameability(rows: Sequence[Mapping[str, Any]], library_src: Path) -> Callable[[str], Optional[bool]]:
    """Whether a qualified name (pretty or internal) can be named from a
    fixture: True or False from its row's source layout, None when the name
    is not a corpus row (the standard library's) or its signature was not
    found."""
    by_name = {**{r["qname"]: r for r in rows}, **{r["prettyQname"]: r for r in rows}}

    @functools.lru_cache(maxsize=None)
    def lines_of(path: Path) -> Tuple[str, ...]:
        text = read_text(path)
        return code_lines(text.unwrap(), path.suffix == ".md") if text.is_ok else ()

    @functools.lru_cache(maxsize=None)
    def verdict(q: str) -> Optional[bool]:
        row = by_name.get(q)
        if row is None:
            return None
        return layout_nameable(lines_of(library_file(str(row.get("file", "")), library_src)), str(row.get("prettyName", "")))

    return verdict


def mine(rows: Sequence[Mapping[str, Any]], opts: Options, nameable: Callable[[str], Optional[bool]]) -> Tuple[Dict[str, Any], ...]:
    lemmas = tuple(lemma_of(r) for r in rows if r.get("defKind") == "function")
    index = Index.of(lemmas)
    eligible = tuple(lem for lem in lemmas
                     if lem.qname.split(".", 1)[0] in opts.namespaces and lem.conclusion_head is not None
                     and lem.conclusion_head not in DATA_HEADS and nameable(lem.qname) is True)
    feeders = Index.of(eligible).by_head
    pattern = re.compile(opts.connectives) if opts.connectives else None
    roots = tuple(lem for lem in eligible
                  if is_connective(lem, opts.namespaces) and (pattern is None or pattern.search(lem.qname)))
    # One composite per statement: the one with the fewest needles, so a gold
    # padded with a step that does no work never shadows the lean one.
    distinct: Dict[str, Composite] = {}
    for c in (c for r in roots for c in compositions(r, feeders, opts.max_hypotheses)):
        text = statement_text(c)
        if text not in distinct or len(c.needles) < len(distinct[text].needles):
            distinct[text] = c
    assessed = {text: (c, assess(c, index, nameable, opts.depth)) for text, c in distinct.items()}
    deep_pattern = re.compile(opts.deepen) if opts.deepen else None
    deeper: Dict[str, Composite] = {}
    for c, a in assessed.values():
        if deep_pattern is not None and a.keep(c) and deep_pattern.search(c.needles[0]):
            for d in deepen(c, feeders, opts.max_hypotheses):
                text = statement_text(d)
                if text not in assessed and (text not in deeper or len(d.needles) < len(deeper[text].needles)):
                    deeper[text] = d
    everything = list(assessed.values()) + [(d, assess(d, index, nameable, opts.depth)) for d in deeper.values()]
    records = (record(c, a) for c, a in everything)
    kept = (r for r in records if opts.everything or r["keep"])
    return tuple(sorted(kept, key=lambda r: (-r["score"], r["statement"])))


def main(argv: Sequence[str]) -> int:
    opts = parse_options(argv)
    loaded = load_rows(opts.corpus)
    if loaded.is_err:
        sys.stderr.write(f"mine_compositions: {loaded.unwrap_err()}\n")
        return 1
    rows = loaded.unwrap()
    found = mine(rows, opts, nameability(rows, opts.library_src))
    written = write_text(opts.out, "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in found))
    if written.is_err:
        sys.stderr.write(f"mine_compositions: {written.unwrap_err()}\n")
        return 1
    kept = sum(1 for r in found if r["keep"])
    sys.stderr.write(f"mine_compositions: {len(rows)} corpus rows; {len(found)} records written to {opts.out} "
                     f"({kept} pass every check)\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
