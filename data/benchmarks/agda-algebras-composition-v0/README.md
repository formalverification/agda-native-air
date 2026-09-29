# The agda-algebras composition tier (v0)

File: `data/benchmarks/agda-algebras-composition-v0/README.md`

This directory is the composition tier of issue [#160]: twelve statements in
agda-algebras' vocabulary whose proofs string two to four library lemmas
together, none of which proves the statement alone.  Every statement was found
by a program, `scripts/python/corpus/mine_compositions.py`, that chains the
corpus's own types; every row was then read, posed as a fixture, given a gold
that Agda checks, and put through the novelty check of the hard tiers.  What
the tier shares with the other tiers (the fixture convention, the judge, the
index schema) is in `../README.md`; this file holds what is particular to it.

## The rows

The needles are the lemmas each gold applies, qualified as the corpus names
them; `k` counts them.

| #  | id                                          | k | needles                                                          | difficulty    |
|----|---------------------------------------------|---|------------------------------------------------------------------|---------------|
| 1  | `comp-variety-subalgebra-of-model`          | 3 | `⊧-S-invar`, `Soundness.sound`, `mon→≤`                          | non-obvious   |
| 2  | `comp-variety-image-of-product`             | 3 | `⊧-H-invar`, `⊧-P-invar`, `HomImage-≅`                           | non-obvious   |
| 3  | `comp-congruence-monolith-below-member`     | 3 | `⊆-trans`, `IsMonolith.mono-least`, `⋂-lower`                    | non-obvious   |
| 4  | `comp-subalgebra-subdirect-into-product`    | 3 | `≤-trans`, `subdirect→≤`, `⨅-≤`                                  | compositional |
| 5  | `comp-lattice-below-join-bound`             | 2 | `Lattice-Order.≤-trans`, `Lattice-Order.∨-least`                 | compositional |
| 6  | `comp-group-normal-of-equivalent-congruence`| 4 | `≈ⁿ-trans`, `normalOf-cong`, `≑-trans`, `normalOf∘congruenceOf`  | non-obvious   |
| 7  | `comp-congruence-meet-below-join`           | 3 | `⊆-trans`, `∧-lowerˡ`, `⋁-upper`                                 | compositional |
| 8  | `comp-homomorphism-isomorph-is-image`       | 2 | `HomImage-≅'`, `IdHomImage`                                      | compositional |
| 9  | `comp-congruence-simple-equivalent-total`   | 3 | `≑-trans`, `≑-sym`, `simple⇒total`                               | compositional |
| 10 | `comp-group-normal-of-smaller-congruence`   | 2 | `≤ⁿ-trans`, `normalOf-mono`                                      | compositional |
| 11 | `comp-variety-subdirect-product-models`     | 3 | `⊧-S-invar`, `⊧-P-invar`, `subdirect→≤`                          | non-obvious   |
| 12 | `comp-homomorphism-epi-through-kernel`      | 2 | `⊙-epi`, `πker`                                                  | compositional |

The statements, in words, are as follows:

+  **1**.  An algebra that embeds in a model of `E` satisfies every identity
   derivable from `E`.
+  **2**.  An identity true in every factor holds in every isomorphic copy of
   a homomorphic image of the product.
+  **3**.  The monolith lies below every member of a family of congruences
   whose meet is nonzero.
+  **4**.  An algebra subdirectly embedded in a product of subalgebras of the
   `𝒜 i` is a subalgebra of the product of the `𝒜 i`.
+  **5**.  In a lattice, anything below a join lies below every common upper
   bound of the joinands.
+  **6**.  The normal subgroup of a congruence equivalent (through a third) to
   the congruence of a normal subgroup `𝑵` is `𝑵`.
+  **7**.  The meet of a family member with any congruence lies below the join
   of the family.
+  **8**.  An algebra isomorphic to `𝑩` is a homomorphic image of `𝑩`.
+  **9**.  In a simple algebra, a congruence equivalent to one that relates two
   distinct points is the total congruence.
+  **10**.  If `θ ⊆ φ` and the normal subgroup of `φ` lies in `𝑵`, so does the
   normal subgroup of `θ`.
+  **11**.  An identity true in every factor holds in any algebra subdirectly
   embedded in their product.
+  **12**.  An epimorphism out of the kernel quotient of `h` gives an
   epimorphism out of the domain of `h`.

The rows carry `source: "agda-algebras"`, the tag `stratum:composition`, and one
`needle:<prettyQname>` tag per needle, so every report counts them as
`agda-algebras/composition` and a subject is given the agda-algebras corpus.
The directory has its own `.agda-lib` per side, as in `agda-algebras-v0`, since
the twin modules share names.  Every statement is posed under a module
telescope (`module _ {…} where`), as the hard tiers are, and the judge freezes
the telescope's lines as text (`Gates.scope`).

## How the rows were found

The miner reads each corpus row's `typeAst` (`scripts/python/corpus/typeast.py`
turns it into first-order terms) and builds statements from the library's own
lemmas.  Its design follows from what the tier must measure.

+  **The loop must not be able to prove a row**.  The proof-search loop is a
   beam search whose moves apply one lemma: to hypotheses (its saturated and
   `_` forms), or with a hole for each explicit argument (its refinement
   form), and a refined hole is closed the same way.  So a chain of steps
   each fixed by its goal, like `A (B x)`, is within its reach.  What is not
   is a lemma with an implicit *middle point*, a variable its premises share
   and its conclusion does not mention: `fill_hole` refuses
   `(≤-trans {!!} {!!})` with `[UnsolvedMetaVariables]` (checked on the real
   server).  Every gold here has such a connective at its root.
+  **Compositions**.  Each premise of a connective is either a hypothesis of
   the statement or the conclusion of another corpus lemma (a feeder);
   unification fixes the middle point, and a composite in which some variable
   is neither fixed nor quantified by the statement is dropped.  An explicit
   middle binder does not count, since the refinement form gives it a hole of
   its own, and neither does one Agda solves through a type (`coord-iso`'s
   index type).  The connective's conclusion must be a relation the library
   defines: `≡` and `Relation.Unary`'s `⊆` are polymorphic in their carrier,
   and their middle points chained unrelated corners of the library.
+  **Four checks, each against the whole corpus**.  *Novel*: no corpus lemma
   closes the statement in one step, its premises filled from the
   hypotheses.  *Out of the loop's reach*: a bounded search using only the
   loop's moves (an assumption, a lemma applied to hypotheses, a lemma the
   goal determines refined with holes closed the same way, four levels deep)
   fails.  *Every needle necessary*: no other corpus lemma does a needle's
   step from the same inputs, and no step concludes what a hypothesis already
   says.  *Nameable*: every needle, and every definition the statement names,
   is a top-level, non-private definition of the library's source, since a
   `where` helper cannot be named from a fixture.
+  **Deeper compositions**.  With `--deepen`, a kept composite's hypothesis
   is fed in turn by another lemma, which is how row 6 reaches k = 4 with a
   natural statement.

Over the agda-algebras corpus v0.1 (SHA-256 `af864432`: 11,865 distinct names,
1,787 of them nameable lemmas of the library's own namespaces that can serve as
needles) the miner finds 93 connectives and builds 8,367 distinct statements
from them, of which 4,443 pass every check (704 with k = 2, 2,746 with k = 3,
993 with k = 4).  The rest fall as follows: 1,038 are within the loop's reach,
904 have a needle with an alternative, 713 name a helper no fixture can name,
661 are closed by one corpus lemma, 393 run past 200 characters, 196 repeat a
needle, and 19 have a step that does no work.  Deepening the families the tier
draws on adds 8,629 statements, of which 7,332 pass (1,109 with k = 3, 6,223
with k = 4); row 6 is one.  The checks are syntactic (they never unfold a
definition), so each chosen row was then read against the library's source,
and three candidates fell there (see "Dropped candidates").  The run is `make
mine-compositions`; its candidates land in
`data/benchmarks/reports/compositions/candidates.jsonl`, ranked for review, and
`COMPOSITIONS_ARGS=--all` writes the rejected ones too, each with its verdicts.

## The golds

Every gold checks under the judge's invocation with `--safe`, and its
definition elaborates to the obligation's statement (`verify-gold.sh`: agda
exit 0, statement equal).  Each gold is the mined composition, with what
Agda cannot infer written out:

+  **1**, **2**, **11**.  The identity's terms are implicit in `⊧-S-invar`,
   `⊧-H-invar`, and `⊧-P-invar` and sit under the non-injective
   interpretation `⟦_⟧`, so the golds pass `{p = p} {q = q}`; without them
   Agda reports unsolved constraints.
+  **3**, **7**, **9**.  `_⊆_` and `_≑_` on congruences are defined relations,
   not injective type formers, so `⊆-trans` and `≑-trans` need their three
   congruences given (`{θ = μ} {φ = ⋂ 𝑨 θ} {ψ = θ i}`); the library's own
   source says so beside `≑-refl`.
+  **6**, **10**.  The same holds for `≤ⁿ-trans` and `≈ⁿ-trans` on normal
   subgroups (the library's comment above `≤ⁿ-refl`).
+  **2**.  `HomImage-≅` wants the image and the product at one universe level,
   so `𝑨` is posed at `⨅ 𝒜`'s levels, `α ⊔ ι` and `ρᵃ ⊔ ι`.
+  **4**, **5**, **8**, **12**.  The composition as mined, with each needle
   named in full.

A subject that finds every needle still has to supply these; that is part of
what the tier measures.

The proofs, in words, are as follows:

+  **1**.  Soundness makes the model satisfy the identity; the monomorphism
   makes `𝑨` a subalgebra of it; identities pass to subalgebras.
+  **2**.  The product models the identity; an isomorphic copy of a
   homomorphic image of the product is a homomorphic image of it; identities
   pass to homomorphic images.
+  **3**.  The monolith lies below the nonzero meet, and the meet below each
   member.
+  **4**.  A subdirect embedding makes `𝑩` a subalgebra of the product of the
   `ℬ i`, which is a subalgebra of the product of the `𝒜 i`; compose the two.
+  **5**.  `y ∨ z ≤ w` since both joinands are, and `x ≤ y ∨ z`; compose.
+  **6**.  `θ ≑ congruenceOf 𝑵`, so
   `normalOf θ ≈ⁿ normalOf (congruenceOf 𝑵) ≈ⁿ 𝑵`.
+  **7**.  `f i ∧ φ` lies below `f i`, which lies below the join of the family.
+  **8**.  `𝑨` is a homomorphic image of itself, and `𝑨 ≅ 𝑩` carries the
   source of that image across to `𝑩`.
+  **9**.  `θ` relates a distinct pair, so `θ` is total in a simple algebra;
   `φ` is equivalent to `θ`.
+  **10**.  `normalOf` is monotone, so `normalOf θ ≤ⁿ normalOf φ ≤ⁿ 𝑵`.
+  **11**.  The product of the factors models the identity; `𝑩` is a
   subalgebra of the product; identities pass to subalgebras.
+  **12**.  The canonical epimorphism onto the kernel quotient, followed by
   the given epimorphism.

## Needles and the ground truth

A `needle:` tag names one lemma of the gold, by the corpus's `prettyQname`,
and every needle is a function row of the corpus.  Needles are kept apart
from the mined tiers' `target:` tags: the recall instrument
(`RetrievalRecall.scala`) ranks a needle in the pool with exclusion as
configured, exactly as it ranks a target, and reports needle recall and
"every needle in the top k" per stratum only where a row carries a needle, so
the other strata's reports are unchanged byte for byte.  The loop's exclusion
policy keys on the hole's name and the statement (`TargetExclusion`), which no
needle matches.  Only the root goal is replayed: a needle that closes an
intermediate goal is ranked against the root goal's display, the only goal
the loop records.

Each fixture opens every needle's defining module with a single-line
`open import M using ( … )` (the form the loop's scope reader parses), listing
the statement's vocabulary and at most a decoy, never a needle.  The gold
names each needle qualified.

A subject's work file is a byte-for-byte copy of the obligation
(`Scaffold.stage`), comments included, so this tier's headers carry no
`Source:` or `Strategy:` line, the two hint lines of the suite's original
fixture template, which issue [#219] removes everywhere.  Here the first
would name every needle and the second would sketch the chain, middle point
included (row 3's read "the monolith lies below the nonzero meet, and the
meet below each member").  The loop reads only a fixture's
`open import` lines, so the gates above were unaffected by the change.  The
needles are in the index and in the table above, and the proofs, in words,
are under "The golds".

## Dropped candidates

Three mined candidates were read and dropped, and one gold was replaced:

+  **Every group is congruence permutable** (`MaltsevTerm⇒CP` with
   `maltsev-≼-group`, k = 2).  `maltsev⇒CP` in the same module concludes
   `CongruencePermutableVariety ℰ`, which unfolds to the same statement, so the
   connective has a twin and is not a necessary needle.  The syntactic check
   cannot see through the definition; the source read did.
+  **Congruence distributivity from Jónsson terms**
   (`jonsson⇒CongruenceDistributive` with `CD⇒jonsson`).
   `CongruenceDistributiveVariety ℰ` is defined as
   "every model of `ℰ` is congruence distributive", so the statement is that
   hypothesis applied to the model (k = 0 by unfolding).
+  **A coset across an equality** (`Coset.∼-trans` with `Coset.≈⇒∼`: `x ≈ y
   → y ∼ z → x ∼ z`).  The twin coset relation in
   `Classical.Structures.Group.Congruences` (`SubgroupRel`) has `∼-resp`,
   whose proof contains this composition verbatim, on a relation with the same
   definition: a near miss a subject could read and translate.
+  **Row 8's first gold** was `HomImage-≅ IdHomImage (≅-sym A≅B)`, k = 3.  The
   miner, which keeps the composite with the fewest needles per statement,
   found `HomImage-≅' IdHomImage A≅B`: `≅-sym` was not a necessary needle.

## The gates

Every row passed four gates before any agent saw it, as follows:

+  **Gate 1: the loop solves no row**.  Three sweeps of the proof-search
   loop at k = 1 over the twelve rows, at the published knobs (beam 4, depth
   6, 60 probes, script dedup, the peek on), run serially and detached from a
   frozen class snapshot on 2026-09-28: the fixed space (`comp160-fixed-1`),
   and retrieval from the agda-algebras corpus v0.1 with 8 lemmas per goal,
   exclusion on and dependency expansion off, under the published scorer,
   token overlap (`comp160-retrieval-1`), and under idf-unfold
   (`comp160-retrieval-idf-1`).  No sweep solves a row or records an
   anomaly, and no retrieval outcome excluded a lemma, so the exclusion
   policy, which keys on the hole's name and the statement, touched no
   needle.

   | run                       | proposer                 | solved | exhausted | budget exceeded | anomalies | probes | wall     |
   |---------------------------|--------------------------|--------|-----------|-----------------|-----------|--------|----------|
   | `comp160-fixed-1`         | fixed space              | 0/12   | 12        | 0               | 0         | 29     | 4.6 min  |
   | `comp160-retrieval-1`     | retrieval, token overlap | 0/12   | 5         | 7               | 0         | 433    | 37.0 min |
   | `comp160-retrieval-idf-1` | retrieval, idf-unfold    | 0/12   | 12        | 0               | 0         | 57     | 6.7 min  |

   Under token overlap the proposer never offered a needle, at any goal.
   Under idf-unfold it offered one on nine rows, and the loop probed a
   needle on five of them, as follows:

   +  **The root lemma**, refused in both of the loop's forms (`_` and
      `{!!}` for each explicit argument) with unsolved metas or constraints,
      which is the implicit middle point at work: row 5's
      `Lattice-Order.≤-trans`, row 8's `HomImage-≅'`, and row 12's `⊙-epi`.
   +  **A feeder, refused the same way**: row 9's `simple⇒total`.
   +  **A feeder, accepted as a refinement of the root goal**: row 4's
      `subdirect→≤ {!!} {!!}`, whose family hole the loop filled with `𝒜`,
      leaving a subdirect embedding into the `𝒜 i` that no hypothesis gives
      (the hypothesis embeds into the `ℬ i`).

   On rows 1, 2, 7, and 11 the offered needles were never probed.  Of the
   519 probes in the three sweeps, 10 name a needle, all under idf-unfold,
   and none names two.

+  **Gate 2: every gold checks**.  `make eval-benchmark` passes all 81 rows,
   and `verify-gold.sh` gives each of the twelve golds `--safe` exit 0 and
   the obligation's statement.
+  **Gate 3: needle recall at the root goal**.  The recall instrument
   (`RetrievalRecall`) replays each row's root goal as the loop recorded it
   and ranks the lemmas in scope under both scorers, exclusion on.  Every
   needle is in its row's pool (33 of 33: import-reachable, though no
   `using` list names it).

   | scorer                    | needles @8 | needles @32 | MRR   | rows, every needle @8 | rows, every needle @32 |
   |---------------------------|------------|-------------|-------|-----------------------|------------------------|
   | token overlap (published) | 0/33       | 0/33        | 0.006 | 0/12                  | 0/12                   |
   | idf-unfold                | 14/33      | 21/33       | 0.236 | 2/12                  | 7/12                   |

   The published scorer puts no needle in the top 32 of any pool, and the
   token-overlap sweep never proposed one at any goal.  The goal the loop
   records is normalized (row 1's `⊧` and row 3's `⊆` appear unfolded),
   while the needles' types keep the defined names.  idf-unfold, which
   unfolds a candidate's defined names through the corpus bodies (three
   steps) and matches the hypotheses against its premises, ranks 14 of the
   33 needles in the top 8, and every needle of rows 2 and 8; rows 6 and 10,
   in the group-congruence vocabulary, rank their best needles at 103 and
   99.  The instrument flags every row `CONTEXT-MISMATCH`, which is
   expected: the recorded context holds the module telescope's variables
   (and, on rows 3, 7, and 10, the implicit binders Agda introduces at the
   hole), which the fallback reconstruction from the clause lacks; the
   ranking uses the recorded context.

   Each needle's rank in its row's pool, token overlap / idf-unfold
   (`comp160-recall-1`, replaying `comp160-retrieval-1`'s goals), is as
   follows:

   | #  | pool | ranks                                                                          |
   |----|------|--------------------------------------------------------------------------------|
   | 1  | 396  | `⊧-S-invar` 376/4, `Soundness.sound` 396/1, `mon→≤` 328/31                      |
   | 2  | 440  | `⊧-H-invar` 371/1, `⊧-P-invar` 372/3, `HomImage-≅` 366/5                        |
   | 3  | 324  | `⊆-trans` 251/33, `IsMonolith.mono-least` 258/17, `⋂-lower` 285/58              |
   | 4  | 324  | `≤-trans` 303/12, `subdirect→≤` 227/1, `⨅-≤` 80/2                               |
   | 5  | 129  | `Lattice-Order.≤-trans` 37/6, `Lattice-Order.∨-least` 61/23                     |
   | 6  | 237  | `≈ⁿ-trans` 151/103, `normalOf-cong` 120/161, `≑-trans` 177/209, `normalOf∘congruenceOf` 57/142 |
   | 7  | 319  | `⊆-trans` 256/35, `∧-lowerˡ` 261/77, `⋁-upper` 285/14                           |
   | 8  | 346  | `HomImage-≅'` 293/2, `IdHomImage` 180/3                                         |
   | 9  | 304  | `≑-trans` 245/48, `≑-sym` 234/43, `simple⇒total` 289/6                          |
   | 10 | 237  | `≤ⁿ-trans` 149/99, `normalOf-mono` 114/162                                      |
   | 11 | 354  | `⊧-S-invar` 327/2, `⊧-P-invar` 309/1, `subdirect→≤` 307/17                      |
   | 12 | 333  | `⊙-epi` 268/4, `πker` 284/14                                                    |

+  **Gate 4: novelty**.  All twelve absent; see "The novelty check" below.

## The agents on the tier

Stage two of [#160] ran Opus 5 and Sonnet 5 on the twelve rows, each in the
`shell`, `mcp`, and `both` arms, on these header-free fixtures (runs
`comp-*-1`; the numbers and their reading are § 4.7 of
`docs/reading-the-results.md`).  Every one of the 72 final files type-checks
with its statement kept, so the tier sits at both models' ceiling.  Two of
its findings are about the rows, and a revision of the tier would start from
them:

+  **A needle can be bypassed by unfolding its relation**.  `_⊆_`, `_≑_`,
   `_≤ⁿ_`, and `_IsHomImageOf_` are defined as functions and pairs, so a
   proof can compose pointwise instead of through the needles: Opus proved
   row 10 as `λ p → φ≤N (θ⊆φ p)`, row 8 as `from A≅B , fromIsSurjective
   A≅B`, and row 9 by pattern matching on the equivalence's two halves, and
   used only one of row 3's and row 7's three needles.  The miner's
   necessity check compares a needle with the corpus's other lemmas, not
   with a term built from the definitions.
+  **Row 2 has a second route through its own decoy**.  All six arms proved
   it with `⊧-I-invar`, which the fixture's `using` list offers, in place of
   `HomImage-≅`: the identity is taken to the homomorphic image first and
   then carried across the isomorphism.  A route that takes the steps in
   another order escapes the miner's same-inputs comparison.

Sonnet also lost 19 of its 36 rows to the preservation gate by appending a
needle to one of these `using` lists instead of adding an import line; the
rows' shape invites that edit, and the prompt forbids it.

## The novelty check

As on the hard tiers (`../README.md`, "The novelty check"): `search_by_type`
and `search_by_name` through the agda-mcp server over the agda-algebras corpus
v0.1 with a limit of 2,000, a conjunctive search over the same rows, and
`grep` over the library's sources for the needles together.  The miner's own
one-step check over every corpus row is a fifth, and it found no closer for
any row.  The standard library has none of this vocabulary.

| #  | verdict | nearest on disk, and why it is not the statement |
|----|---------|---------------------------------------------------|
| 1  | absent | No lemma combines `⊨`, `mon`, and `⊧`; the conjunctive searches are empty. |
| 2  | absent | No lemma combines `IsHomImageOf` with `⨅` or `≅` in a `⊧` conclusion. |
| 3  | absent | The `where` helper `μ⊆θ` of `monolith⇒cmi` concludes `μ ⊆ θ i` from every member nonzero; here only the meet is, and the helper cannot be named. |
| 4  | absent | `subdirect→≤` and `⨅-≤` are the only rows naming a subdirect embedding with `≤`; no source file uses both. |
| 5  | absent | The conjunctive hits are the order laws themselves (`∨-least`, `∨-upper`, the connecting lemmas). |
| 6  | absent | `normalOf-cong` and `normalOf∘congruenceOf` are the only conjunctive hits; no file uses them with `≑-trans`. |
| 7  | absent | No row mentions `∧` and `⋁` together. |
| 8  | absent | The conjunctive hits are the needle `HomImage-≅'` and its sibling `HomImage-≅`. |
| 9  | absent | The one conjunctive hit is the needle `simple⇒total`, for θ itself. |
| 10 | absent | The one conjunctive hit is the needle `normalOf-mono`. |
| 11 | absent | No row mentions `SubdirectEmbedding` in a `⊧` conclusion. |
| 12 | absent | The one conjunctive hit is the needle `πker`; no file uses `πker` with `⊙-epi`. |

## The searches, row by row

Counts are hits, from the run of 2026-09-28.

### 1. `comp-variety-subalgebra-of-model`

+  agda-algebras corpus: `search_by_type` on the statement,
   `Setoid.Homomorphisms.Basic.mon` 4, `SoundAndComplete.⊨` 4; on the
   conclusion, `SoundAndComplete.⊧` 28; `search_by_name`, `S-invar` 12, `sound`
   130, `mon→` 9, `embed` 16, `model` 6; conjunctive, `SoundAndComplete.⊨` with
   `Setoid.Homomorphisms.Basic.mon` with `SoundAndComplete.⊧` 0;
   `SoundAndComplete.⊢` with `Setoid.Homomorphisms.Basic.mon` 0;
   `SoundAndComplete.⊢` with `Subalgebras.Basic._.≤` with
   `SoundAndComplete.⊧` 0.
+  `grep` over the agda-algebras sources for `mon`, `⊧`, `⊨` together: 11 files,
   Examples.Demos.HSP, Classical.Structures.CommutativeSemigroup,
   Classical.Structures.Monoid, Classical.Structures.Ring,
   Classical.Structures.CommutativeRing, Classical.Structures.CommutativeMonoid,
   Classical.Structures.Semigroup, Classical.Structures.Lattice.Basic,
   Classical.Structures.Group.Basic, Classical.Structures.Group.AbelianGroup,
   Classical.Categories.Forgetful (the pattern `mon` also matches `monoid`); for
   the needles `⊧-S-invar` and `mon→≤` together, 1 file, Examples.Demos.HSP,
   which defines its own copies of both and uses them apart (`S-id1`, `F≤C`).

### 2. `comp-variety-image-of-product`

+  agda-algebras corpus: `search_by_type` on the statement, `IsHomImageOf` 25,
   `Setoid.Algebras.Products.⨅` 87; on the conclusion, `SoundAndComplete.⊧` 28;
   `search_by_name`, `H-invar` 4, `P-invar` 4, `HP` 60, `image` 112;
   conjunctive, `IsHomImageOf` with `Products.⨅` with `SoundAndComplete.⊧` 0;
   `IsHomImageOf` with `Isomorphisms._.≅` with `SoundAndComplete.⊧` 0.
+  `grep` over the agda-algebras sources for `IsHomImageOf`, `⨅`, `⊧` together:
   3 files, Setoid.Varieties.Properties, Setoid.Varieties.Reducts,
   Examples.Demos.HSP.

### 3. `comp-congruence-monolith-below-member`

+  agda-algebras corpus: `search_by_type` on the statement,
   `Monolith.IsMonolith` 11, `Monolith.⋂` 5; on the conclusion,
   `Congruences.Lattice._.⊆` 267; `search_by_name`, `mono-` 5, `monolith` 45,
   `⋂` 11; conjunctive, `Monolith.IsMonolith` with `Monolith.⋂` 3;
   `Monolith.IsMonolith` with `Monolith.Nonzero` with
   `Congruences.Lattice._.⊆` 6.
+  `grep` over the agda-algebras sources for `IsMonolith`, `⋂`, `Nonzero`
   together: 2 files, Setoid.Congruences.Monolith,
   Setoid.Subalgebras.Subdirect.Irreducible.

### 4. `comp-subalgebra-subdirect-into-product`

+  agda-algebras corpus: `search_by_type` on the statement, `SubdirectEmbedding`
   18, `Products.⨅` 163; on the conclusion, `Subalgebras.Basic._.≤` 49;
   `search_by_name`, `subdirect` 110, `⨅-≤` 1, `product` 292; conjunctive,
   `SubdirectEmbedding` with `Subalgebras.Basic._.≤` 1; `Subalgebras.Basic._.≤`
   with `Setoid.Algebras.Products.⨅` with `(i : I)` 5.
+  `grep` over the agda-algebras sources for `SubdirectEmbedding`, `⨅-≤`
   together: 0 files.

### 5. `comp-lattice-below-join-bound`

+  agda-algebras corpus: `search_by_type` on the statement, `Lattice-Order.≤`
   75, `Lattice-Op.∨` 84; on the conclusion, `Lattice-Order.≤` 75;
   `search_by_name`, `∨-least` 3, `join` 400, `upper` 63, `bound` 33;
   conjunctive, `Lattice-Order.≤` with `Lattice-Op.∨` 5.
+  `grep` over the agda-algebras sources for `∨-least`, `≤-trans` together: 5
   files, Setoid.Varieties.Maltsev.Modularity, FLRP.Parachute.Representation,
   Classical.Properties.Lattice, Classical.Structures.Lattice.Parachute,
   Classical.Structures.Lattice.FilterIdeal.

### 6. `comp-group-normal-of-equivalent-congruence`

+  agda-algebras corpus: `search_by_type` on the statement,
   `GroupCongruences.normalOf` 23, `GroupCongruences.congruenceOf` 16; on the
   conclusion, `GroupCongruences.≈ⁿ` 10; `search_by_name`, `normalOf` 10,
   `congruenceOf` 12; conjunctive, `GroupCongruences.normalOf` with
   `GroupCongruences.congruenceOf` with `GroupCongruences.≈ⁿ` 1;
   `Congruences.Lattice._.≑` with `GroupCongruences.normalOf` with
   `GroupCongruences.≈ⁿ` 1.
+  `grep` over the agda-algebras sources for `normalOf`, `congruenceOf`,
   `≑-trans` together: 0 files.

### 7. `comp-congruence-meet-below-join`

+  agda-algebras corpus: `search_by_type` on the statement, `CompleteLattice.⋁`
   5, `Congruences.Lattice._.∧` 17; on the conclusion, `Congruences.Lattice._.⊆`
   267; `search_by_name`, `⋁` 12, `join` 400, `meet` 336; conjunctive,
   `Congruences.Lattice._.∧` with `CompleteLattice.⋁` 0.
+  `grep` over the agda-algebras sources for `⋁`, `∧-lower` together: 1 file,
   Classical.Structures.Lattice.Parachute.

### 8. `comp-homomorphism-isomorph-is-image`

+  agda-algebras corpus: `search_by_type` on the statement, `Isomorphisms._.≅`
   92; on the conclusion, `IsHomImageOf` 25; `search_by_name`, `iso` 355,
   `HomImage` 21, `image` 112, `≅→` 2; conjunctive, `Isomorphisms._.≅` with
   `IsHomImageOf` 2.
+  `grep` over the agda-algebras sources for `HomImage-≅'`, `IdHomImage`
   together: 1 file, Setoid.Homomorphisms.HomomorphicImages.

### 9. `comp-congruence-simple-equivalent-total`

+  agda-algebras corpus: `search_by_type` on the statement,
   `Congruences.Simple.IsSimple` 11, `RelatesDistinctPoints` 3; on the
   conclusion, `Congruences.Lattice._.≑` 415; `search_by_name`, `simple` 60,
   `total` 2, `𝟙` 22; conjunctive, `Congruences.Simple.IsSimple` with
   `Congruences.Lattice._.≑` 1; `RelatesDistinctPoints` with
   `Congruences.Lattice._.≑` with `𝟙[` 1.
+  `grep` over the agda-algebras sources for `simple⇒total`, `≑-trans` together:
   0 files.

### 10. `comp-group-normal-of-smaller-congruence`

+  agda-algebras corpus: `search_by_type` on the statement,
   `GroupCongruences.normalOf` 23, `GroupCongruences.≤ⁿ` 13; on the conclusion,
   `GroupCongruences.≤ⁿ` 13; `search_by_name`, `normalOf-mono` 1, `≤ⁿ` 6;
   conjunctive, `Congruences.Lattice._.⊆` with `GroupCongruences.normalOf` with
   `GroupCongruences.≤ⁿ` 1.
+  `grep` over the agda-algebras sources for `normalOf-mono`, `≤ⁿ-trans`
   together: 2 files, Classical.Structures.Group.NormalClosure,
   Classical.Structures.Group.Congruences.

### 11. `comp-variety-subdirect-product-models`

+  agda-algebras corpus: `search_by_type` on the statement, `SubdirectEmbedding`
   18; on the conclusion, `SoundAndComplete.⊧` 28; `search_by_name`, `subdirect`
   110, `P-invar` 4, `S-invar` 12; conjunctive, `SubdirectEmbedding` with
   `SoundAndComplete.⊧` 0.
+  `grep` over the agda-algebras sources for `SubdirectEmbedding`, `⊧` together:
   0 files.

### 12. `comp-homomorphism-epi-through-kernel`

+  agda-algebras corpus: `search_by_type` on the statement, `Kernels.ker[` 25,
   `Setoid.Homomorphisms.Basic.epi` 15; on the conclusion,
   `Setoid.Homomorphisms.Basic.epi` 15; `search_by_name`, `πker` 5, `⊙-epi` 1,
   `ker` 122; conjunctive, `Kernels.ker[` with
   `Setoid.Homomorphisms.Basic.epi` 1.
+  `grep` over the agda-algebras sources for `πker`, `⊙-epi` together: 0 files.

[#160]: https://github.com/formalverification/agda-native-air/issues/160
[#219]: https://github.com/formalverification/agda-native-air/issues/219
