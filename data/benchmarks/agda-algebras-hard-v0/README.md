# The agda-algebras hard tier (v0)

File: `data/benchmarks/agda-algebras-hard-v0/README.md`

This directory is the hard tier of issue [#189]: eighteen statements in group
theory and universal algebra, posed by William DeMeo on the issue in two
comments ("Statements" and "Statements, part two"), chosen so that no proof of
them would be on disk and a subject's solve would be construction rather than
a copy.  Nine are posed in the standard library's `Algebra.Bundles.Group`
vocabulary (the qualifying-exam genre); nine in agda-algebras' vocabulary
(`Classical.Structures.Group`, and for row 18 `Setoid.Homomorphisms`), among
them problem 2 of the 2000 Nov 10 exam and the lemmas that follow it.  The
obligation files are the issue's, byte for byte.

The novelty check below did not find every statement absent: three are proved
in agda-algebras' own vocabulary, one follows from a theorem on disk, and four
are partly on disk.  The check reports them and drops nothing; which rows the
tier keeps is William's decision, made while he writes the golds.

## The rows

| #  | id                                          | difficulty    | novelty               | gold   |
|----|---------------------------------------------|---------------|-----------------------|--------|
| 1  | `hard-group-squares-commute`                | non-obvious   | absent                | wanted |
| 2  | `hard-group-involutive-commute`             | compositional | absent                | wanted |
| 3  | `hard-group-inverse-homo-commute`           | compositional | absent                | wanted |
| 4  | `hard-group-unique-involution-central`      | non-obvious   | absent                | wanted |
| 5  | `hard-group-conjugation-automorphism`       | compositional | on disk, other vocab. | wanted |
| 6  | `hard-group-inversion-homo-iff-commutative` | non-obvious   | partly on disk        | wanted |
| 7  | `hard-group-surjective-image-commutative`   | compositional | generalization        | wanted |
| 8  | `hard-group-injective-iff-trivial-kernel`   | non-obvious   | on disk, other vocab. | wanted |
| 9  | `hard-group-centralizer-closed`             | compositional | on disk, other vocab. | wanted |
| 10 | `hard-group-intersection-normal-in-subgroup`| compositional | absent                | wanted |
| 11 | `hard-group-second-iso-cosets-agree`        | non-obvious   | absent                | wanted |
| 12 | `hard-group-second-iso-cosets-onto`         | non-obvious   | absent                | wanted |
| 13 | `hard-group-normal-product-is-join`         | non-obvious   | partly on disk        | wanted |
| 14 | `hard-group-kernel-normal-subgroup`         | non-obvious   | partly on disk        | wanted |
| 15 | `hard-group-commutator-subgroup`            | non-obvious   | absent                | wanted |
| 16 | `hard-group-third-iso-cosets-descend`       | compositional | partly on disk        | wanted |
| 17 | `hard-group-correspondence-over-N`          | compositional | absent                | wanted |
| 18 | `hard-algebra-kernel-of-injective-composite`| compositional | absent                | wanted |

The difficulty is the one the issue gives; the novelty verdicts are defined in
"The novelty check" below.

## Conventions

+  **Fixtures**.  One module per obligation under `obligations/`, its name the
   file stem, `open import AgdaDojang.Debug` first, exactly one `{!!}`.  Each
   checks to exactly one `UnsolvedInteractionMetas` and no other error or
   warning under the judge's own `agda` invocation (the gold verifier's, with
   `--library agda-algebras`), with and without `--safe`.  Each directory has
   its own `.agda-lib`, as in `agda-algebras-v0`, since the twin modules share
   names.
+  **Module telescopes**.  Every statement is posed under `module _ … where`
   (`(G : Group c ℓ)` with `open Group G`, or agda-algebras' `(𝒢 : Group α ρ)`
   with its subgroups and their proofs), because that is the readable way to
   write them.  The definition's elaborated type includes the telescope, which
   is what the judge compares.  Goal-anchored `get_goal` and `type_of` answer
   inside it (checked on row 1: the lane's goal display, and `sq`, `assoc`,
   `inverseˡ` typed in the goal's scope); a `type_of` without a line sees the
   top-level scope, where the telescope's opens are not in scope, which is
   issue [#139].
+  **Definitions the statement names**.  Rows 11, 12, 14, and 15 define
   predicates and abbreviations before the hole (`H∩K` and its subgroup proof,
   `Ker`, `Commutators`, `Derived`, and the private `𝑮`, `G`, `h`), and every
   row opens modules inside its telescope.  The judge compares the
   definition's type by the names it mentions, so a file could keep that type
   and change what `Commutators` means.  Since issue [#189] the judge freezes
   these lines as text, as it freezes the module line and the imports: every
   line outside the definition with the hole must survive, each declaration's
   lines as one run that nothing continues, in the obligation's order, while
   lines may be added between declarations (`Gates.scope` in
   `strux-driver/.../agentbench/Judge.scala`, pinned in `JudgeSpec`).  The
   mined tiers' obligations have no such lines, so their verdicts cannot move.
+  **Index rows**.  `source: "agda-algebras"` and the tag `stratum:novel`, so
   every report counts the tier as `agda-algebras/novel`.  No row carries a
   `restates:` or `target:` tag, since no row has an original, and no
   definition in either corpus or either library's sources carries any of the
   eighteen hole names, so the restatement rule cannot fire.  `module` names
   the library module the fixture's `Source:` line names first, the vocabulary
   the statement is posed in (nothing is proved there); `goldTerm` is the
   fixture's `Strategy:` line, a sketch, until a gold replaces it; `type` is
   the signature as the fixture writes it, as on every other tier, because
   Agda prints these types with every definition unfolded (past a thousand
   characters on rows 10 to 18).
+  **Corpus**.  `source` chooses the corpus a subject is given, so rows 1 to 9,
   posed in the standard library's vocabulary, give their subjects the
   agda-algebras corpus, whose search tools do not index the standard-library
   lemmas those proofs use.

## The golds

Every row's gold is wanted.  Its twin under `gold/` is the obligation with
the hole still in it and a `-- GOLD WANTED` line under the header (and the
header's `File:` line naming the gold's own path), so it checks exactly as the
obligation does and the finished gold's diff is the proof alone.  Until the
golds are in, the following hold:

+  the CI slice `make eval-benchmark-smoke` selects rows by a fixed id list
   (`BENCHMARK_SMOKE_IDS` in the `Makefile`) that names none of these rows, so
   it stays green (verified 2026-09-26: 9/9, deterministic);
+  the full `make eval-benchmark`, which is not a CI lane, reports 55 of 73
   golds passing, the eighteen failures being exactly these rows;
+  the judge cannot judge these rows, since its statement gate reads the
   statement from the gold's elaborated type and `agda-json` cannot extract a
   holed file: it stops on an internal error of Agda's
   (`src/full/Agda/TypeChecking/Rules/LHS.hs:751`) on 72 of the 73 committed
   obligations, every one whose hole stays open (the exception is
   `Unit-trivial`, whose hole of type `⊤` Agda fills by eta).  So the
   gold-less path, reading the statement from the obligation, is not available
   with the extractor as it stands, and a row without a gold waits for one.

## The novelty check

A statement belongs in this tier only if no proof of it is on disk: in the
agda-algebras library (the flake's store copy, at the commit of the corpus),
in the standard library 2.3, or in either corpus.  Each row was checked four
ways, as follows:

+  `search_by_type` through the agda-mcp server (built from this branch) over
   the agda-algebras corpus v0.1 (SHA-256 `af864432`), and for rows 1 to 9 also
   over the standard-library corpus v0 (`14e0d47e`), with a limit of 2,000.
   The tool is a case-insensitive substring match over each definition's
   printed type, which is fully qualified and broken across lines, so a whole
   statement never matches; each row records its statement's most distinctive
   fragments and its conclusion's head, in the corpus's own spelling
   (`Group-Op.∙`, `Coset.∼`, `Algebra.Definitions.Commutative`).
+  `search_by_name` with the natural names, the same way.
+  A conjunctive search over the same corpus rows, every fragment in one row's
   type, which the server's tools cannot do.
+  `grep` over both libraries' sources for the conclusion's head symbols
   together: the files containing all of them, then the lines.

agda-algebras states many things twice, in `Legacy.Base` and in `Setoid`;
`Legacy` has no group theory, so the twin applies only to row 18, which neither
side has.  Rows 10 to 18 are posed in agda-algebras' vocabulary, and the
standard library has no subgroup, coset, kernel, centralizer, or conjugation
name at all (its corpus, searched by name), so for them the standard library
was checked by name only.

The verdicts are defined as follows:

+  **absent**: nothing on disk proves the statement; the nearest lemma is a
   different statement;
+  **on disk, other vocabulary**: agda-algebras proves the statement's content
   in its own group vocabulary, as lemmas a subject can read and translate;
+  **generalization**: a theorem on disk implies the statement;
+  **partly on disk**: some conjuncts are one or two library lemmas away, and
   the rest are absent.

| #  | verdict | nearest on disk, and why it is not the statement |
|----|---------|---------------------------------------------------|
| 1  | absent | `Algebra.Properties.Group.\\≗flip-//⇒comm` concludes commutativity from `x \\ y ≈ y // x`, a different hypothesis; the nearest in agda-algebras is `Wreath.WreathProduct.CoreFreeness.inv-conj→comm` (a group with an inner inversion is abelian). |
| 2  | absent | The same two lemmas; `Examples.Classical.Groups.KleinFourGroup.·-comm` is one group of exponent 2, decided by computation. |
| 3  | absent | `Algebra.Properties.AbelianGroup.⁻¹-∙-comm` is the converse, and `Algebra.Properties.Group.⁻¹-anti-homo-∙` is the step the proof turns on. |
| 4  | absent | No lemma on disk concerns an element of order two; `Conjugation.conj-∙-hom` and `conj-ε` make a conjugate of an involution an involution, the first step, and `CoreFreeness.conj-fix→comm` turns the conclusion into commutation. |
| 5  | on disk, other vocab. | `Classical.Structures.Group.Conjugation` proves that `conj g x = g ∙ x ∙ g ⁻¹`, this row's map, preserves `∙`, `ε`, `⁻¹` and is inverted by conjugation by `g ⁻¹` (`conj-∙-hom`, `conj-ε`, `conj-⁻¹`, `conj-cong`, `conj-conj⁻¹`, `conj⁻¹-conj`): the content of every field of `IsGroupIsomorphism`, for agda-algebras' groups. |
| 6  | partly on disk | The second half's homomorphism law is `Algebra.Properties.AbelianGroup.⁻¹-∙-comm` (for an `AbelianGroup` bundle) with `ε⁻¹≈ε` and `⁻¹-cong`; the first half is row 3. |
| 7  | generalization | `Setoid.Varieties.Preservation.H-id1`: an identity true in a class holds in its homomorphic images, and commutativity is an identity; stated for agda-algebras' algebras and terms.  The standard library has only the dual, `Algebra.Morphism.MagmaMonomorphism.comm`, pulled back along an injective homomorphism. |
| 8  | on disk, other vocab. | `Classical.Structures.Group.Congruences.GroupCongruences.con-below-trivial→below-diagonal` and `con-below-diagonal→below-trivial` (a group congruence is below the diagonal exactly when its identity class is trivial) are this statement for the kernel congruence, since `BelowDiagonal (kercon g)` is `IsInjective g` by definition (`Setoid.Subalgebras.Subdirect.Irreducible.injective↔0kernel` records it, by `refl`, for a subdirect product's coordinates). |
| 9  | on disk, other vocab. | `Classical.Structures.Group.Centralizer.C-isSubgroup` makes the centralizer of any set a subgroup; its where-lemmas `∙-c` and `⁻¹-c` at the set `{a}` are this row's two conjuncts, each equation's sides swapped. |
| 10 | absent | `MinimalNormal.∩-isNormalSubgroup` is two normal subgroups' intersection, normal in `G`; here `H` is not normal and normality is relative to `H`.  By the definition of `IsNormal`, the second conjunct is the hypothesis `K-normal h x∈K` itself. |
| 11 | absent | No lemma relates the cosets of two subgroups; the nearest are the coset relation's laws (`Cosets.Coset`) and Dedekind's rule (`Dedekind.dedekindˡ`). |
| 12 | absent | The nearest is the step `anti` in `Complements.Factors-sym` (from `x ⁻¹ ≈ p ∙ q`, `x ≈ q ⁻¹ ∙ p ⁻¹`), a piece of the computation. |
| 13 | partly on disk | The containments are `Complements.mem-∙ᶜˡ` and `mem-∙ᶜʳ`; leastness is `Complexes.∙ᶜ-mono` then `subgroup-∙ᶜ-idem`, the body of `Complements.Factors-least`; normality of `N ∙ᶜ M` is absent.  `NormalSubgroupLattice` does have a join, `_∨ⁿ_`, but it is the congruence join carried across, not the complex product, and its leastness ranges over normal subgroups only. |
| 14 | partly on disk | The subgroup and normality conjuncts are `GroupCongruences.ConNormal.IdentityClass-isSubgroup` and `IdentityClass-normal` at the kernel congruence `kercon`, once `Ker` is identified with the identity class through `h ε ≈ εᴴ`; the coset conjunct is absent. |
| 15 | absent | `Commutator` has element-level lemmas only, and `NormalClosure` closes one element of a finite group; nothing generates a subgroup from commutators or proves one normal. |
| 16 | partly on disk | The first conjunct is the inclusion `N⊆M` itself (the coset relation is `x ⁻¹ ∙ y ∈ N`), as `FLRP.Bridge`'s `reflx` shows for `H ⊆ K` at level zero; the second is `Coset.∼-sym` and `∼-trans` around it. |
| 17 | absent | `FLRP.Bridge.H⊆Kθ` has the step `ε ∼ h` from `h ∈ H` that the second half turns on; nothing states the correspondence. |
| 18 | absent | No lemma on disk concerns the kernel of a composite; the pieces are `Setoid.Congruences.Lattice.⊆-antisym` and the definition of `kercon`, and the nearest statement about kernels and injectivity is `Subdirect.Irreducible.injective↔0kernel`. |

Summary: ten rows are absent (1, 2, 3, 4, 10, 11, 12, 15, 17, 18); three are on
disk in agda-algebras' vocabulary (5, 8, 9); one is a generalization's
instance (7); four are partly on disk (6, 13, 14, 16).  Of the absent rows, 10
and 18 are a line or two given the library, which bears on their difficulty
label rather than on their novelty.

## The searches, row by row

Counts are hits, from the runs of 2026-09-26.

### 1. `hard-group-squares-commute`

+  agda-algebras corpus: `search_by_type` on the statement, `Group-Op.∙ x) y)`
   18, `Commutative` 209; on the conclusion, `Commutative` 209, `IsAbelian` 3,
   `AbelianGroup` 63; `search_by_name`, `squares` 0, `square` 0, `sq-comm` 0,
   `abelian` 95, `commut` 266; conjunctive, `Group-Op.∙` with `Commutative` 0;
   `Group-Op.∙ x) x)` with `Group-Op.∙ y) y)` 0.
+  standard-library corpus: `search_by_type` on the statement,
   `Algebra.Definitions.Commutative` 611; on the conclusion,
   `Algebra.Definitions.Commutative` 611; `search_by_name`, `squares` 0,
   `square` 1, `sq-comm` 0, `abelian` 498; conjunctive, `Algebra.Bundles.Group`
   with `Algebra.Definitions.Commutative` 10; `Algebra.Bundles.Group.∙ x) x)`
   with `Algebra.Bundles.Group.∙ y) y)` 0.
+  `grep` over the standard-library sources for `Commutative`, `Group`, `∙ x) ∙
   (x ∙` together: 0 files.
+  `grep` over the agda-algebras sources for `comm`, `Group`, `(x ∙ y) ∙ (x ∙
   y)` together: 0 files.

### 2. `hard-group-involutive-commute`

+  agda-algebras corpus: `search_by_type` on the statement, `Group-Op.∙ x) x)`
   0, `Group-Op.ε` 389; on the conclusion, `Commutative` 209, `IsAbelian` 3;
   `search_by_name`, `involut` 0, `exponent` 0, `order-two` 0, `order2` 0,
   `elementary` 0, `self-inverse` 0, `boolean` 4; conjunctive, `Group-Op.∙ x)
   x)` with `Group-Op.ε` 0.
+  standard-library corpus: `search_by_type` on the statement,
   `Algebra.Bundles.Group.∙ x) x)` 0; on the conclusion,
   `Algebra.Definitions.Commutative` 611; `search_by_name`, `involut` 57,
   `exponent` 31, `elementary` 0, `self-inverse` 0, `x∙x` 0; conjunctive,
   `Algebra.Bundles.Group.∙ x) x)` with `Algebra.Bundles.Group.ε` 0;
   `Algebra.Bundles.Group` with `Algebra.Definitions.Commutative` 10.
+  `grep` over the standard-library sources for `x ∙ x ≈ ε`, `Commutative`
   together: 0 files.
+  `grep` over the agda-algebras sources for `x ∙ x ≈ ε`, `comm` together: 0
   files.

### 3. `hard-group-inverse-homo-commute`

+  agda-algebras corpus: `search_by_type` on the statement, `Group-Op.⁻¹) ((` 0,
   `Group-Op.⁻¹` 103; on the conclusion, `Commutative` 209, `IsAbelian` 3;
   `search_by_name`, `⁻¹-homo` 0, `inverse-homo` 0, `anti-homo` 0, `⁻¹-∙` 0,
   `inv-hom` 0; conjunctive, `Group-Op.⁻¹` with `Group-Op.∙` with `Commutative`
   0.
+  standard-library corpus: `search_by_type` on the statement,
   `Algebra.Bundles.Group.⁻¹` 84; on the conclusion,
   `Algebra.Definitions.Commutative` 611; `search_by_name`, `⁻¹-homo` 45,
   `inverse-homo` 0, `anti-homo` 18, `⁻¹-∙` 3, `⁻¹-comm` 0; conjunctive,
   `Algebra.Bundles.Group.⁻¹` with `Algebra.Definitions.Commutative` 0.
+  `grep` over the standard-library sources for `⁻¹ ∙ y ⁻¹`, `Commutative`
   together: 0 files.
+  `grep` over the agda-algebras sources for `⁻¹ ∙ y ⁻¹`, `comm` together: 1
   file, `Commutator` (the commutator's definition in prose).

### 4. `hard-group-unique-involution-central`

+  agda-algebras corpus: `search_by_type` on the statement, `⊎` 218,
   `Relation.Nullary.Negation.Core.¬` 828; on the conclusion, `Centre` 0,
   `Center` 80, `Centralizer.C[` 38; `search_by_name`, `involution` 0, `central`
   41, `centre` 0, `center` 19, `unique` 20; conjunctive, `Group-Op.ε` with `⊎`
   with `Group-Op.⁻¹` 0; `¬` with `Group-Op.ε` with `Group-Op.∙` 46.
+  standard-library corpus: `search_by_type` on the statement, `Data.Sum.Base.⊎`
   572, `Relation.Nullary.Negation.Core.¬` 213; on the conclusion,
   `Algebra.Bundles.Group.⁻¹` 84; `search_by_name`, `involution` 0, `central` 0,
   `centre` 0, `center` 1; conjunctive, `Algebra.Bundles.Group.⁻¹` with
   `Data.Sum.Base.⊎` 0; `Algebra.Bundles.Group.ε` with
   `Relation.Nullary.Negation.Core.¬` 0.
+  `grep` over the standard-library sources for `⊎`, `¬`, `⁻¹ ≈` together: 0
   files.
+  `grep` over the agda-algebras sources for `⊎`, `b ∙ b ≈ ε` together: 0 files.

### 5. `hard-group-conjugation-automorphism`

+  agda-algebras corpus: `search_by_type` on the statement, `conj` 150, `IsIso`
   0, `IsGroupIsomorphism` 0; on the conclusion, `IsHom` 84, `IsIso` 0, `≅` 336,
   `Aut` 0; `search_by_name`, `conj` 60, `inner` 1, `automorph` 0, `aut` 0,
   `iso` 355; conjunctive, `Conjugate` with `hom` 0; `Conjugate` with `Iso` 35;
   `Conjugate` with `≅` 0.
+  standard-library corpus: `search_by_type` on the statement,
   `IsGroupIsomorphism` 79; on the conclusion, `IsGroupIsomorphism` 79,
   `IsGroupAutomorphism` 0; `search_by_name`, `conj` 0, `inner` 72, `automorph`
   0; conjunctive, `IsGroupIsomorphism` with `Algebra.Bundles.Group.⁻¹` 0;
   `IsGroupIsomorphism` with `Algebra.Bundles.Group.∙` 0.
+  `grep` over the standard-library sources for `IsGroupIsomorphism`, `⁻¹`
   together: 5 files, the morphism structures, their generic constructions, and
   `Data.Parity.Properties`; no conjugation.
+  `grep` over the agda-algebras sources for `conj`, `Iso` together: 11 files,
   `Congruences` and FLRP modules, where `Iso` is a lattice isomorphism.

### 6. `hard-group-inversion-homo-iff-commutative`

+  agda-algebras corpus: `search_by_type` on the statement,
   `IsGroupHomomorphism` 0, `Group-Op.⁻¹` 103; on the conclusion, `Commutative`
   209, `IsAbelian` 3; `search_by_name`, `⁻¹-hom` 0, `inv-hom` 0, `inversion` 0,
   `⁻¹-isHom` 0, `inverse` 70; conjunctive, `IsHom` with `Group-Op.⁻¹` 0;
   `Commutative` with `hom` 0.
+  standard-library corpus: `search_by_type` on the statement,
   `IsGroupHomomorphism` 92; on the conclusion,
   `Algebra.Definitions.Commutative` 611; `search_by_name`,
   `⁻¹-isGroupHomomorphism` 0, `⁻¹-isMagmaHomomorphism` 0, `⁻¹-homo` 45,
   `inverse-homo` 0, `inversion` 2; conjunctive, `IsGroupHomomorphism` with
   `Algebra.Definitions.Commutative` 0; `IsGroupHomomorphism` with `⁻¹` 14.
+  `grep` over the standard-library sources for `IsGroupHomomorphism`,
   `Commutative` together: 3 files, instances in `Data.Parity.Properties` and
   `Data.Rational.Properties`, and the deprecated `Algebra.Morphism`.
+  `grep` over the agda-algebras sources for `⁻¹`, `IsHom`, `comm` together: 6
   files, homomorphism factorization and variety files; none about inversion.

### 7. `hard-group-surjective-image-commutative`

+  agda-algebras corpus: `search_by_type` on the statement, `IsSurjective` 146,
   `Surjective` 154, `IsEpi` 20, `epi` 90; on the conclusion, `Commutative` 209,
   `⊧` 93, `Mod` 142, `Th` 675; `search_by_name`, `surj` 80, `epi` 98, `image`
   112, `H-id` 7, `H-preserves` 0, `hom-image` 3, `HomImage` 21; conjunctive,
   `IsSurjective` with `⊧` 10; `epi` with `⊧` 0; `IsSurjective` with
   `Commutative` 0.
+  standard-library corpus: `search_by_type` on the statement,
   `Function.Definitions.Surjective` 155; on the conclusion,
   `Algebra.Definitions.Commutative` 611; `search_by_name`, `surj` 389, `epi` 1,
   `image` 11, `homomorphic` 51; conjunctive, `Function.Definitions.Surjective`
   with `Algebra.Definitions.Commutative` 0; `Surjective` with `Commutative` 0;
   `Surjective` with `IsMagmaHomomorphism` 0.
+  `grep` over the standard-library sources for `Surjective`, `Commutative`,
   `Homomorphism` together: 2 files, concrete isomorphisms in
   `Data.Nat.Binary.Properties` and `Data.Parity.Properties`.
+  `grep` over the agda-algebras sources for `IsSurjective`, `⊧`, `comm`
   together: 2 files, the HSP development (`Examples.Demos.HSP`,
   `Legacy.Base.Varieties.FreeAlgebras`).

### 8. `hard-group-injective-iff-trivial-kernel`

+  agda-algebras corpus: `search_by_type` on the statement, `IsInjective` 63,
   `kercon` 39, `kerel` 0; on the conclusion, `IsInjective` 63, `0[` 9, `Δ` 47;
   `search_by_name`, `kernel` 76, `ker` 122, `injective` 41, `mono` 421,
   `trivial` 73; conjunctive, `IsInjective` with `kercon` 8; `IsInjective` with
   `kerel` 0; `IsInjective` with `ker` 17; `kercon` with `0[` 0.
+  standard-library corpus: `search_by_type` on the statement,
   `Function.Definitions.Injective` 229; on the conclusion,
   `Function.Definitions.Injective` 229; `search_by_name`, `kernel` 0, `ker` 3,
   `trivial` 30, `injective` 438; conjunctive, `Function.Definitions.Injective`
   with `IsGroupHomomorphism` 7; `Function.Definitions.Injective` with
   `Algebra.Bundles.Group.ε` 0; `Injective` with `IsGroupMonomorphism` 14.
+  `grep` over the standard-library sources for `Injective`,
   `IsGroupHomomorphism`, `ε` together: 4 files, the morphism structures and
   concrete instances; no kernel.
+  `grep` over the agda-algebras sources for `IsInjective`, `kercon` together: 5
   files, `Setoid.Subalgebras.Subdirect.Irreducible` (`injective↔0kernel`) and
   `Legacy` first-isomorphism files.

### 9. `hard-group-centralizer-closed`

+  agda-algebras corpus: `search_by_type` on the statement, `Centralizer` 52,
   `C[` 38, `Group-Op.∙ a) x)` 0; on the conclusion, `IsSubgroup` 1169,
   `Centralizer.C[` 38; `search_by_name`, `centraliz` 39, `centralis` 0,
   `centre` 0, `center` 19, `commut` 266, `C-is` 6, `C[` 3; conjunctive,
   `Centralizer.C[` with `IsSubgroup` 28; `Group-Op.∙ a) x)` with `Group-Op.∙ x)
   a)` 0.
+  standard-library corpus: `search_by_type` on the statement,
   `Algebra.Bundles.Group.∙ a) x)` 0; on the conclusion,
   `Algebra.Bundles.Group.⁻¹` 84; `search_by_name`, `centraliz` 0, `centralis`
   0, `centre` 0, `center` 1, `Centre` 0; conjunctive,
   `Algebra.Bundles.Group.⁻¹` with `Algebra.Bundles.Group.∙` with
   `Data.Product.Base.×` 0.
+  `grep` over the standard-library sources for `a ∙ x ≈ x ∙ a`, `⁻¹` together:
   0 files.
+  `grep` over the agda-algebras sources for `C-isSubgroup`, `⁻¹-c` together: 2
   files, `Classical.Structures.Group.Centralizer` and its use in
   `FLRP.Parachute.Basic`.

### 10. `hard-group-intersection-normal-in-subgroup`

+  agda-algebras corpus: `search_by_type` on the statement, `Conjugate.IsNormal`
   113, `∩` 39; on the conclusion, `IsNormal` 193, `∩` 39; `search_by_name`, `∩`
   6, `meet` 336, `intersect` 6, `inter` 515, `normal-in` 6, `rel-normal` 0,
   `relative` 0; conjunctive, `IsNormal` with `∩` 18; `IsNormal` with
   `IsSubgroup` with `Relation.Unary.∩` 13; `IsNormal` with `IsSubgroup` with
   `×` 1.
+  `grep` over the agda-algebras sources for `IsNormal`, `∩`, `IsSubgroup`
   together: 5 files, `MinimalNormal` (`∩-isNormalSubgroup`),
   `MinimalNormalDescent`, `Complements`, `NormalSubgroupLattice`,
   `FLRP.Parachute.Basic`.

### 11. `hard-group-second-iso-cosets-agree`

+  agda-algebras corpus: `search_by_type` on the statement, `Coset.∼` 25,
   `Complex.∙ᶜ` 32; on the conclusion, `Coset.∼` 25; `search_by_name`, `second`
   0, `2nd` 0, `iso` 355, `diamond` 0, `cosets` 24, `∼` 78; conjunctive,
   `Coset.∼` with `∩` 0; `Coset.∼` with `×` 0; `Coset.∼` with `Coset.∼` 26.
+  `grep` over the agda-algebras sources for `Coset`, `∩`, `∙ᶜ` together: 0
   files.

### 12. `hard-group-second-iso-cosets-onto`

+  agda-algebras corpus: `search_by_type` on the statement, `Complex.∙ᶜ` 32,
   `Coset.∼` 25; on the conclusion, `Coset.∼` 25, `Σ` 2000; `search_by_name`,
   `second` 0, `onto` 18, `surj` 80, `∙ᶜ` 13, `coset` 66, `complex` 66;
   conjunctive, `Complex.∙ᶜ` with `Coset.∼` 0; `Complex.∙ᶜ` with `Σ` 2.
+  `grep` over the agda-algebras sources for `∙ᶜ`, `Coset`, `Σ` together: 0
   files.

### 13. `hard-group-normal-product-is-join`

+  agda-algebras corpus: `search_by_type` on the statement, `Complex.∙ᶜ` 32,
   `Conjugate.IsNormal` 113; on the conclusion, `IsNormal` 193, `⊆` 1007;
   `search_by_name`, `join` 400, `sup` 14, `∨` 298, `lub` 0, `normal-∙ᶜ` 2,
   `∙ᶜ-is` 2, `product` 292; conjunctive, `Complex.∙ᶜ` with `IsNormal` 5;
   `Complex.∙ᶜ` with `⊆` with `IsSubgroup` 25.
+  `grep` over the agda-algebras sources for `∙ᶜ`, `IsNormal`, `⊆` together: 2
   files, `Complements` and `FLRP.Parachute.Basic`.

### 14. `hard-group-kernel-normal-subgroup`

+  agda-algebras corpus: `search_by_type` on the statement, `hom` 1022,
   `Conjugate.IsNormal` 113; on the conclusion, `IsNormal` 193, `IsSubgroup`
   1169; `search_by_name`, `ker` 122, `kernel` 76, `NormalCon` 19, `ConNormal`
   15, `fiber` 1, `fibre` 0; conjunctive, `hom` with `IsNormal` 0; `kercon` with
   `IsNormal` 0; `hom` with `IsSubgroup` 3; `Group-Op.ε` with `hom` 1.
+  `grep` over the agda-algebras sources for `IsNormal`, `hom`, `ker` together:
   0 files.

### 15. `hard-group-commutator-subgroup`

+  agda-algebras corpus: `search_by_type` on the statement, `Commutator.[` 7,
   `Sg` 931; on the conclusion, `IsNormal` 193, `Sg` 931; `search_by_name`,
   `derived` 6, `commutator` 12, `abelianiz` 0, `abelianis` 0, `G′` 0, `G'` 1,
   `NormalClosure` 32; conjunctive, `Commutator.[` with `Sg` 0; `Commutator.[`
   with `IsNormal` 0; `Sg` with `IsNormal` 0.
+  `grep` over the agda-algebras sources for `[_⸴_]`, `Sg` together: 0 files.
+  `grep` over the agda-algebras sources for `Sg`, `IsNormal` together: 0 files.

### 16. `hard-group-third-iso-cosets-descend`

+  agda-algebras corpus: `search_by_type` on the statement, `Coset.∼` 25, `⊆`
   1007; on the conclusion, `Coset.∼` 25; `search_by_name`, `third` 0, `3rd` 0,
   `descend` 3, `quot` 73, `∼-resp` 2, `∼-cong` 1; conjunctive, `Coset.∼` with
   `⊆` 0; `Coset.∼` with `IsNormal` with `⊆` 0.
+  `grep` over the agda-algebras sources for `Coset`, `⊆`, `IsNormal` together:
   1 file, `Congruences`.

### 17. `hard-group-correspondence-over-N`

+  agda-algebras corpus: `search_by_type` on the statement, `Respects` 177,
   `Coset.∼` 25; on the conclusion, `Respects` 177, `⊆` 1007; `search_by_name`,
   `correspond` 0, `respects` 40, `Respects` 40, `lift` 223, `over` 323;
   conjunctive, `Respects` with `Coset.∼` 1; `Respects` with `IsSubgroup` 38;
   `Respects` with `IsNormal` 1.
+  `grep` over the agda-algebras sources for `Respects`, `Coset`, `⊆` together:
   3 files, `Congruences`, `FLRP.Bridge`, `FLRP.KurzweilNetter.Interval`.

### 18. `hard-algebra-kernel-of-injective-composite`

+  agda-algebras corpus: `search_by_type` on the statement, `kercon` 39,
   `Lattice._≑_` 6, `⊙-hom` 1; on the conclusion, `Lattice._≑_` 6, `kercon` 39;
   `search_by_name`, `kercon` 7, `ker-` 9, `-ker` 9, `⊙` 9, `≑` 299, `comp` 506,
   `inj` 187; conjunctive, `kercon` with `⊙-hom` 0; `kercon` with `IsInjective`
   8; `Lattice._≑_` with `kercon` 0; `kercon` with `≑` 0.
+  `grep` over the agda-algebras sources for `kercon`, `⊙-hom` together: 1 file,
   `Setoid.Homomorphisms.Properties` (`Cg⊆ker`, not a composite).
+  `grep` over the agda-algebras sources for `kercon`, `IsInjective`, `≑`
   together: 1 file, `Setoid.Subalgebras.Subdirect.Irreducible`.

[#139]: https://github.com/formalverification/agda-native-air/issues/139
[#189]: https://github.com/formalverification/agda-native-air/issues/189
