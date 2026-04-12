# Benchmark Difficulty Taxonomy (M1-5)

**Document**: Difficulty classification for the `agda-native-air` baseline benchmark.  
**Version**: draft-v0.1  
**Date**: 2026-04-12

---

## Design Principles

The taxonomy classifies proof obligations by **what the agent must do**, not merely
by proof-term size.  A 40-character proof that requires selecting an obscure lemma
from a large namespace is harder than a 200-character proof whose structure is
dictated by the goal type.  The tiers are defined so that:

1. **Tier 1** obligations are solvable by local, syntactic strategies — the kind a
   deterministic heuristic policy (like the existing `policy_fixture.py`) can handle.
2. **Tier 2** obligations require composing known lemmas or following a standard
   proof pattern, but the specific composition isn't syntactically determined by the
   goal alone.  A frontier LLM with access to the goal, local context, and a modest
   amount of library context should succeed.
3. **Tier 3** obligations require non-obvious lemma selection, domain-specific
   reasoning, or structural creativity.  These test the upper bound of the current
   system and are expected to have low solve rates initially — they exist to measure
   progress over time.

The target distribution is approximately **30% / 45% / 25%** across Tiers 1/2/3.
This ensures the benchmark isn't trivially saturated by a good policy but still
contains enough solvable obligations to produce meaningful statistics.

---

## Tier 1 — Routine (tag: `routine`)

### Characterization

The proof term is **determined (up to minor variation) by the goal type and the
immediately visible context**.  A correct strategy can be selected without consulting
definitions outside the local scope.

### Proof Patterns

- **Reflexivity**: goal is `x ≡ x` (possibly after normalization/unfolding); solved
  by `refl`.
- **Assumption matching**: goal type appears verbatim as a hypothesis in the context;
  solved by naming the hypothesis.
- **Constructor application**: goal is a product, record, or sum type; solved by
  applying the evident constructor and recursing on subgoals that are themselves
  routine.
- **Trivial inhabitants**: `tt : ⊤`, `refl : x ≡ x`, `Level.lift tt`, identity
  functions, etc.
- **Direct unfolding**: goal reduces to a known form after `with`-free pattern
  matching on a single argument; the recursive structure mirrors the datatype.

### Agda-stdlib Examples (illustrative)

| Candidate obligation | Module | Why Tier 1 |
|---|---|---|
| `+-identityˡ : ∀ n → 0 + n ≡ n` | `Data.Nat.Properties` | Holds by `refl` (computation). |
| `∷-injective` (second component) | `Data.List.Properties` | Immediate from `refl` after `cong`. |
| `lookup-replicate : lookup (replicate n x) i ≡ x` | `Data.Vec.Properties` | Structural induction; each case is `refl` or a single recursive call. |
| `⊤-isMonoid` (identity proof components) | `Algebra.Structures` | `tt` or `refl`. |

### Agda-algebras Examples (illustrative)

| Candidate obligation | Module | Why Tier 1 |
|---|---|---|
| Identity law for `Func` composition | `Base.Functions.Inverses` | Definitional; `refl` or `≡.refl`. |
| Trivial homomorphism preservation on nullary ops | various `Homomorphisms.*` | Unfolds to `refl`. |

### Selection Criteria

- Proof term ≤ ~30 tokens.
- ≤ 1 lemma application from outside the local module.
- Solvable by `policy_fixture.py`-class heuristics (or close to it).

---

## Tier 2 — Compositional (tag: `compositional`)

### Characterization

The proof requires **composing 2–5 known lemmas or standard proof steps**, but the
composition follows a recognizable pattern (equational chain, congruence + recursion,
map-functoriality, etc.).  The agent must know *which* lemmas to apply and in what
order, but the overall proof architecture is standard for the domain.

### Proof Patterns

- **Short equational chains**: `begin x ≡⟨ p ⟩ y ≡⟨ q ⟩ z ∎` with 2–4 steps,
  where each justification `p`, `q` is a named lemma from the same module or a
  direct import.
- **Congruence + known lemma**: `cong f p` or `cong₂ _+_ p q` where `p` and `q`
  are obtained by recursive calls or known results.
- **Standard inductive proofs**: the proof proceeds by pattern matching on one
  argument, with the inductive case requiring an appeal to a previously proved
  lemma (e.g., commutativity of `_+_` using the successor case and `+-suc`).
- **Algebraic simplification**: a chain of rewrites using associativity,
  commutativity, identity, or inverse laws — each step individually obvious, but
  the agent must select the right sequence.
- **Transport / substitution**: `subst P eq x` where `P`, `eq`, and `x` are all
  in scope or one step away, but the combination isn't syntactically immediate.

### Agda-stdlib Examples (illustrative)

| Candidate obligation | Module | Why Tier 2 |
|---|---|---|
| `+-comm : ∀ m n → m + n ≡ n + m` | `Data.Nat.Properties` | Induction on `m`; base uses `+-identityʳ`, step uses `+-suc` + `cong suc`. |
| `*-distribˡ-+ : ∀ m n p → m * (n + p) ≡ m * n + m * p` | `Data.Nat.Properties` | Induction + 3-step equational chain with `+-assoc` and `*-comm`. |
| `map-compose : map (f ∘ g) ≡ map f ∘ map g` | `Data.List.Properties` | Structural induction; step is `cong (f (g x) ∷_)` + IH. |
| `reverse-involutive` | `Data.List.Properties` | Requires `reverse-++-commute` as a lemma; non-trivial composition. |
| `filter-++ : filter p (xs ++ ys) ≡ filter p xs ++ filter p ys` | `Data.List.Properties` | Induction + case split on `p x`; each branch is a short chain. |

### Agda-algebras Examples (illustrative)

| Candidate obligation | Module | Why Tier 2 |
|---|---|---|
| Composition of homomorphisms is a homomorphism | `Homomorphisms.Compose` | The `compatible` proof composes two `compatible` witnesses; 3–5 steps of equational reasoning. |
| Kernel of a homomorphism is a congruence | `Homomorphisms.Kernels` | Requires showing reflexivity, symmetry, transitivity, and compatibility — each individually straightforward but must be assembled. |
| Image of a subalgebra under a homomorphism is a subalgebra | `Subalgebras.Images` | Functorial argument; requires composing the closure property with the homomorphism condition. |

### Selection Criteria

- Proof term ~30–120 tokens.
- Requires 2–5 lemma applications from the local module or its direct imports.
- The "right" proof strategy is standard for the domain (a working mathematician
  would describe it as "straightforward" or "routine" — but an AI agent still needs
  to find and compose the pieces).
- Should be solvable by a frontier LLM with goal + context + ~500 tokens of
  relevant library context.

---

## Tier 3 — Non-Obvious (tag: `non-obvious`)

### Characterization

The proof requires **selecting lemmas from outside the immediate context**, or
involves a proof architecture that isn't determined by the goal type alone.  There
may be multiple plausible proof strategies, and the agent must either search a large
space or apply domain-specific insight.

### Proof Patterns

- **Non-local lemma selection**: the key lemma lives in a different module or
  subpackage, and its relevance isn't syntactically signaled by the goal type.  The
  agent must know (or discover via search) that, e.g., `Algebra.Solver.Ring` can
  close a polynomial identity, or that `IsLattice.∧-comm` is the right entry point
  for a lattice-theoretic goal.
- **Auxiliary definitions**: the proof requires introducing a helper function or an
  intermediate lemma (via `where` clause) that doesn't appear in the goal or context.
- **Universe-polymorphic reasoning**: the obligation involves manipulating universe
  levels explicitly, or requires `Level.lift` / `Level.lower` in non-obvious places.
- **Setoid / heterogeneous reasoning**: proofs over quotient types, setoid morphisms,
  or heterogeneous equality where the "obvious" `refl` path doesn't apply and the
  agent must construct an explicit transport or coherence argument.
- **Decision procedures and reflection**: obligations that are best solved by
  invoking a decision procedure or a reflection-based solver, rather than by direct
  term construction.
- **Creative induction schemes**: proofs requiring well-founded induction, strong
  induction, induction on a non-obvious measure, or simultaneous induction on
  multiple arguments.

### Agda-stdlib Examples (illustrative)

| Candidate obligation | Module | Why Tier 3 |
|---|---|---|
| `+-*-isCommutativeSemiring` (assembled from parts) | `Data.Nat.Properties` | Requires assembling ~8 previously proved properties into a record; the agent must know which fields to fill and with what. |
| `¬¬-excluded-middle → excluded-middle` (or similar classical↔intuitionistic results) | `Relation.Nullary.Decidable` | Requires a non-obvious CPS-like argument; proof structure not determined by the types. |
| Correctness of a sort (e.g., `sort-perm` or `sort-sorted`) | `Data.List.Sort` | Requires intricate induction with multiple auxiliary lemmas about permutations and ordering. |
| `Algebra.Solver.Ring` applications | `Algebra.Solver.*` | Knowing to invoke the solver is the hard part; the proof term itself may be short. |

### Agda-algebras Examples (illustrative)

| Candidate obligation | Module | Why Tier 3 |
|---|---|---|
| HSP-related closure results | `Varieties.Closure` | Requires composing H, S, P operators and showing closure under each; deep domain knowledge. |
| Free algebra universal property | `Terms.FreeAlgebras` | The proof of the universal mapping property requires constructing a unique homomorphism and proving uniqueness — non-trivial proof architecture. |
| Congruence lattice properties | `Structures.Congruences` | Lattice-theoretic arguments (meet, join, modularity) that require selecting from a large namespace of lattice lemmas. |

### Selection Criteria

- Proof term ≥ ~80 tokens, or shorter but requiring non-local insight.
- Requires lemmas from ≥ 2 modules that aren't directly imported.
- A working mathematician would describe the proof as requiring "a bit of thought"
  or "knowing the right trick."
- Expected to have **low initial solve rate** — these obligations define the
  system's ceiling and measure improvement as retrieval and local models come online
  in M2.

---

## Cross-Cutting Dimensions

Beyond the three tiers, each obligation should be tagged with additional metadata
that enables slicing the benchmark results along interesting axes:

| Tag | Values | Purpose |
|---|---|---|
| `source` | `agda-stdlib`, `agda-algebras` | Library of origin. |
| `domain` | `arithmetic`, `list`, `vec`, `algebra`, `order`, `logic`, `setoid` | Mathematical domain. |
| `proof-strategy` | `refl`, `induction`, `equational-chain`, `congruence`, `record-assembly`, `solver`, `other` | Primary proof technique. |
| `universe-polymorphic` | `true`, `false` | Whether universe levels are non-trivially involved. |
| `uses-with` | `true`, `false` | Whether the gold solution uses `with`-abstraction. |

These tags aren't part of the difficulty classification per se, but they allow
richer analysis in the tool paper (e.g., "the agent struggles with equational
chains but handles induction well").

---

## Distribution Target

For a 30-obligation benchmark:

| Tier | Count | stdlib | agda-algebras |
|---|---|---|---|
| 1 — Routine | ~9 | ~7 | ~2 |
| 2 — Compositional | ~13 | ~8 | ~5 |
| 3 — Non-Obvious | ~8 | ~4 | ~4 |
| **Total** | **~30** | **~19** | **~11** |

For a 40-obligation benchmark, scale proportionally (12 / 18 / 10).

The agda-algebras obligations are weighted toward the harder tiers, reflecting the
strategic narrative: stdlib covers breadth and establishes baseline metrics;
agda-algebras covers depth and demonstrates research utility.

---

## Relationship to Evaluation Metrics

The benchmark runner should report, per tier:

- **Solve rate**: fraction of obligations where the agent produced a typechecking
  term.
- **Iterations**: average number of propose→check rounds per obligation.
- **Wall-clock time**: total time per obligation (including Agda typechecking).
- **Lemma-discovery rate** (Tier 3 only): did the agent find the key non-local
  lemma?

These per-tier metrics tell a much richer story than a single aggregate solve rate.
In the tool paper, the expected narrative is: "Tier 1 is near-saturated (validating
the infrastructure), Tier 2 shows what the frontier model can do with MCP access,
and Tier 3 reveals where retrieval and local models (M2) are needed."

---

## Notes on Gold Solutions

Each benchmark obligation must have a committed gold solution — the proof term that
Agda accepts.  Gold solutions serve three purposes:

1. **Verification**: `make eval-benchmark` can check that the gold solutions still
   typecheck (regression guard against library version drift).
2. **Scoring**: the gold solution defines the "correct" answer for automated
   comparison (exact match or type-equivalent match).
3. **Difficulty calibration**: a gold solution that is 5 tokens of `refl` confirms
   Tier 1; a gold solution that is a 15-line equational chain confirms Tier 2–3.

Gold solutions should be the **simplest correct term** the author can write, not a
minimal-token-count golf.  Readability matters for the paper and for future
difficulty re-calibration.


