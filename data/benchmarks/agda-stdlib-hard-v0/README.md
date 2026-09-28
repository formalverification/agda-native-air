# The agda-stdlib hard tier (v0)

File: `data/benchmarks/agda-stdlib-hard-v0/README.md`

This directory is half of the hard tier of issue [#189]: six statements in
group theory, posed by William DeMeo on the issue (rows 1 to 9 of the
"Statements" comment, less the three dropped below) in the standard library's
`Algebra.Bundles.Group` vocabulary, the equational and homomorphism problems of
the qualifying-exam genre.  The other eight, posed in agda-algebras'
vocabulary, are in `../agda-algebras-hard-v0/`.  The two halves share their
conventions, the rules for their golds, and the method of their novelty check;
`../README.md` records those under "Hard tiers: conventions, golds, and the
novelty check", and this file holds what is particular to these rows.  Row
numbers are the issue's.

## The rows

| #  | id                                          | difficulty    | novelty               | gold   |
|----|---------------------------------------------|---------------|-----------------------|--------|
| 1  | `hard-group-squares-commute`                | non-obvious   | absent                | in     |
| 2  | `hard-group-involutive-commute`             | compositional | absent                | in     |
| 3  | `hard-group-inverse-homo-commute`           | compositional | absent                | in     |
| 4  | `hard-group-unique-involution-central`      | non-obvious   | absent                | in     |
| 6  | `hard-group-inversion-homo-iff-commutative` | non-obvious   | partly on disk        | in     |
| 7  | `hard-group-surjective-image-commutative`   | compositional | generalization        | in     |

The rows carry `source: "agda-stdlib"` and the tag `stratum:novel`, so every
report counts them as `agda-stdlib/novel`, and a subject is given the
standard-library corpus, which indexes the lemmas these proofs use.  The
obligations import only the standard library and `AgdaDojang.Debug`.  The
judge's batch `agda` (`EvalBenchmark.agdaCommand`, the command the shell arms'
prompts quote) adds `--library agda-algebras` only for `agda-algebras` rows,
so it checks these without it; the server a run starts, which answers the
subjects' and the judge's `check_file`, takes one set of flags for every row,
and those name agda-algebras, which changes nothing for a file that imports
none of it.  Like the other standard-library tiers, the directories carry no
`.agda-lib`; outside the dev shell an editor finds `agda-dojang` through the
registry's defaults, with `AGDA_DIR` set to the checkout's `agda/`.

## The golds

Every row's gold is in: each checks under the judge's invocation with
`--safe`, and its definition elaborates to the obligation's statement.  Row
3's gold is William DeMeo's own, as is row 2's alternative; the others were
written by Claude on 2026-09-27 and await his review.  The proofs, in brief, are
as follows:

+  **1**.  Two cancellations around the chain `x(xy)y ≈ x²y² ≈ (xy)² ≈
   x(yx)y`, regrouped by the standard library's `uv∙wx≈u[vw∙x]`; the file also
   keeps `squares-commute-by-assoc`, the same chain regrouped by associativity
   alone.
+  **2**.  Each element is its own inverse (`inverseˡ-unique`), so `xy ≈
   (xy)⁻¹ ≈ y⁻¹x⁻¹ ≈ yx`; the file also keeps `involutive-commute-by-axioms`, a
   nine-step chain from the group axioms alone.
+  **3**.  `xy ≈ (x⁻¹)⁻¹(y⁻¹)⁻¹ ≈ (y⁻¹x⁻¹)⁻¹ ≈ ((yx)⁻¹)⁻¹ ≈ yx`, by
   `⁻¹-involutive`, `⁻¹-anti-homo-∙`, and the hypothesis at `y` and `x`.
+  **4**.  The conjugate `aᵇ = (ba)b⁻¹` is an involution, so the hypothesis
   makes it `ε` or `a`; it is not `ε`, since cancelling `b` would make `a` so.
+  **6**.  If inversion is a homomorphism, `(xy)⁻¹ ≈ y⁻¹x⁻¹ ≈ (yx)⁻¹`, and
   `⁻¹-injective` finishes; conversely, commutativity turns
   `⁻¹-anti-homo-∙` into the homomorphism law, and `ε⁻¹≈ε` and `⁻¹-cong`
   fill the other fields of `IsGroupHomomorphism`.
+  **7**.  Pull `u` and `v` back along the surjection to `a` and `b`; then
   `uv ≈ f(a)f(b) ≈ f(ab) ≈ f(ba) ≈ f(b)f(a) ≈ vu`.

## Dropped rows

Three of the issue's nine statements were dropped on 2026-09-27: rows 5
(`hard-group-conjugation-automorphism`), 8
(`hard-group-injective-iff-trivial-kernel`), and 9
(`hard-group-centralizer-closed`).  The novelty check below found each one
proved in agda-algebras' vocabulary, and a subject with a shell can read those
proofs, since the read roots are every registered library's directory on every
arm; a solve could then be a translation, not a construction, and the tier
exists to rule that out.  Their files are in the history (added in commit
`10bba55`, moved here in `51ab972`), and their searches stay below as the
record of the check.

## The novelty check

The four searches and the four verdicts are defined in `../README.md`.  These
rows were searched in both corpora, since a statement posed in one library's
vocabulary may be proved in the other's, and three of them were, which dropped
them.

| #  | verdict | nearest on disk, and why it is not the statement |
|----|---------|---------------------------------------------------|
| 1  | absent | `Algebra.Properties.Group.\\≗flip-//⇒comm` concludes commutativity from `x \\ y ≈ y // x`, a different hypothesis; the nearest in agda-algebras is `Wreath.WreathProduct.CoreFreeness.inv-conj→comm` (a group with an inner inversion is abelian). |
| 2  | absent | The same two lemmas; `Examples.Classical.Groups.KleinFourGroup.·-comm` is one group of exponent 2, decided by computation. |
| 3  | absent | `Algebra.Properties.AbelianGroup.⁻¹-∙-comm` is the converse, and `Algebra.Properties.Group.⁻¹-anti-homo-∙` is the step the proof turns on. |
| 4  | absent | No lemma on disk concerns an element of order two; `Conjugation.conj-∙-hom` and `conj-ε` make a conjugate of an involution an involution, the first step, and `CoreFreeness.conj-fix→comm` turns the conclusion into commutation. |
| 5  | on disk, other vocab.; dropped | `Classical.Structures.Group.Conjugation` proves that `conj g x = g ∙ x ∙ g ⁻¹`, this row's map, preserves `∙`, `ε`, `⁻¹` and is inverted by conjugation by `g ⁻¹` (`conj-∙-hom`, `conj-ε`, `conj-⁻¹`, `conj-cong`, `conj-conj⁻¹`, `conj⁻¹-conj`): the content of every field of `IsGroupIsomorphism`, for agda-algebras' groups. |
| 6  | partly on disk | The second half's homomorphism law is `Algebra.Properties.AbelianGroup.⁻¹-∙-comm` (for an `AbelianGroup` bundle) with `ε⁻¹≈ε` and `⁻¹-cong`; the first half is row 3. |
| 7  | generalization | `Setoid.Varieties.Preservation.H-id1`: an identity true in a class holds in its homomorphic images, and commutativity is an identity; stated for agda-algebras' algebras and terms.  The standard library has only the dual, `Algebra.Morphism.MagmaMonomorphism.comm`, pulled back along an injective homomorphism. |
| 8  | on disk, other vocab.; dropped | `Classical.Structures.Group.Congruences.GroupCongruences.con-below-trivial→below-diagonal` and `con-below-diagonal→below-trivial` (a group congruence is below the diagonal exactly when its identity class is trivial) are this statement for the kernel congruence, since `BelowDiagonal (kercon g)` is `IsInjective g` by definition (`Setoid.Subalgebras.Subdirect.Irreducible.injective↔0kernel` records it, by `refl`, for a subdirect product's coordinates). |
| 9  | on disk, other vocab.; dropped | `Classical.Structures.Group.Centralizer.C-isSubgroup` makes the centralizer of any set a subgroup; its where-lemmas `∙-c` and `⁻¹-c` at the set `{a}` are this row's two conjuncts, each equation's sides swapped. |

Summary: rows 1 to 4 are absent; rows 5, 8, and 9 are proved in agda-algebras'
vocabulary, and are dropped; row 7 is an instance of a theorem on disk; row 6
is partly on disk.

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

### 5. `hard-group-conjugation-automorphism` (dropped)

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

### 8. `hard-group-injective-iff-trivial-kernel` (dropped)

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

### 9. `hard-group-centralizer-closed` (dropped)

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

[#189]: https://github.com/formalverification/agda-native-air/issues/189
