# The agda-algebras hard tier (v0)

File: `data/benchmarks/agda-algebras-hard-v0/README.md`

This directory is half of the hard tier of issue [#189]: nine statements in
group theory and universal algebra, posed by William DeMeo on the issue (rows 10
to 18 of the two "Statements" comments) in agda-algebras' vocabulary
(`Classical.Structures.Group`, and for row 18 `Setoid.Homomorphisms`): problem 2
of the 2000 Nov 10 exam and the lemmas that follow it.  The other nine, posed in
the standard library's vocabulary, are in `../agda-stdlib-hard-v0/`.  The two
halves share their conventions, the rules for their golds, and the method of
their novelty check; `../README.md` records those under "Hard tiers:
conventions, golds, and the novelty check", and this file holds what is
particular to these nine rows.  Row numbers are the issue's.

## The rows

| #  | id                                          | difficulty    | novelty               | gold   |
|----|---------------------------------------------|---------------|-----------------------|--------|
| 10 | `hard-group-intersection-normal-in-subgroup`| compositional | absent                | wanted |
| 11 | `hard-group-second-iso-cosets-agree`        | non-obvious   | absent                | wanted |
| 12 | `hard-group-second-iso-cosets-onto`         | non-obvious   | absent                | wanted |
| 13 | `hard-group-normal-product-is-join`         | non-obvious   | partly on disk        | wanted |
| 14 | `hard-group-kernel-normal-subgroup`         | non-obvious   | partly on disk        | wanted |
| 15 | `hard-group-commutator-subgroup`            | non-obvious   | absent                | wanted |
| 16 | `hard-group-third-iso-cosets-descend`       | compositional | partly on disk        | wanted |
| 17 | `hard-group-correspondence-over-N`          | compositional | absent                | wanted |
| 18 | `hard-algebra-kernel-of-injective-composite`| compositional | absent                | wanted |

The rows carry `source: "agda-algebras"` and the tag `stratum:novel`, so every
report counts them as `agda-algebras/novel`, and a subject is given the
agda-algebras corpus.  Each directory has its own `.agda-lib`, as in
`agda-algebras-v0`, since the twin modules share names.  Rows 11, 12, 14, and
15 define predicates and abbreviations before the hole (`H∩K` and its subgroup
proof, `Ker`, `Commutators`, `Derived`, and the private `𝑮`, `G`, `h`), which
the judge freezes as text with the rest of the obligation outside the holed
definition.

## The novelty check

The four searches and the four verdicts are defined in `../README.md`.  These
rows are posed in agda-algebras' vocabulary, and the standard library has no
subgroup, coset, kernel, centralizer, or conjugation name at all (its corpus,
searched by name), so for them the standard library was checked by name only.
agda-algebras states many things twice, in `Legacy.Base` and in `Setoid`;
`Legacy` has no group theory, so the twin applies only to row 18, which neither
side has.

| #  | verdict | nearest on disk, and why it is not the statement |
|----|---------|---------------------------------------------------|
| 10 | absent | `MinimalNormal.∩-isNormalSubgroup` is two normal subgroups' intersection, normal in `G`; here `H` is not normal and normality is relative to `H`.  By the definition of `IsNormal`, the second conjunct is the hypothesis `K-normal h x∈K` itself. |
| 11 | absent | No lemma relates the cosets of two subgroups; the nearest are the coset relation's laws (`Cosets.Coset`) and Dedekind's rule (`Dedekind.dedekindˡ`). |
| 12 | absent | The nearest is the step `anti` in `Complements.Factors-sym` (from `x ⁻¹ ≈ p ∙ q`, `x ≈ q ⁻¹ ∙ p ⁻¹`), a piece of the computation. |
| 13 | partly on disk | The containments are `Complements.mem-∙ᶜˡ` and `mem-∙ᶜʳ`; leastness is `Complexes.∙ᶜ-mono` then `subgroup-∙ᶜ-idem`, the body of `Complements.Factors-least`; normality of `N ∙ᶜ M` is absent.  `NormalSubgroupLattice` does have a join, `_∨ⁿ_`, but it is the congruence join carried across, not the complex product, and its leastness ranges over normal subgroups only. |
| 14 | partly on disk | The subgroup and normality conjuncts are `GroupCongruences.ConNormal.IdentityClass-isSubgroup` and `IdentityClass-normal` at the kernel congruence `kercon`, once `Ker` is identified with the identity class through `h ε ≈ εᴴ`; the coset conjunct is absent. |
| 15 | absent | `Commutator` has element-level lemmas only, and `NormalClosure` closes one element of a finite group; nothing generates a subgroup from commutators or proves one normal. |
| 16 | partly on disk | The first conjunct is the inclusion `N⊆M` itself (the coset relation is `x ⁻¹ ∙ y ∈ N`), as `FLRP.Bridge`'s `reflx` shows for `H ⊆ K` at level zero; the second is `Coset.∼-sym` and `∼-trans` around it. |
| 17 | absent | `FLRP.Bridge.H⊆Kθ` has the step `ε ∼ h` from `h ∈ H` that the second half turns on; nothing states the correspondence. |
| 18 | absent | No lemma on disk concerns the kernel of a composite; the pieces are `Setoid.Congruences.Lattice.⊆-antisym` and the definition of `kercon`, and the nearest statement about kernels and injectivity is `Subdirect.Irreducible.injective↔0kernel`. |

Summary: rows 10, 11, 12, 15, 17, and 18 are absent; rows 13, 14, and 16 are
partly on disk.  Rows 10 and 18 are a line or two given the library, which
bears on their difficulty label rather than on their novelty.

## The searches, row by row

Counts are hits, from the runs of 2026-09-26.

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

[#189]: https://github.com/formalverification/agda-native-air/issues/189
