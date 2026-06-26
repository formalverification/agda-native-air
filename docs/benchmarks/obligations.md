# Benchmark Obligations (M1-5)

**Status:** stdlib obligations COMMITTED and verified; `agda-algebras` obligations DEFERRED  
**Agda:** 2.8.0  |  **standard-library:** 2.3 (pinned by `flake.lock`)

The committed v0 suite — 22 `agda-stdlib` obligations, every gold solution
type-checking under the pinned toolchain — is the source of truth in
`../../data/benchmarks/benchmark-index.jsonl`.  This document is the broader
design catalog and diverges from the committed set in a few places:

+  Committed, beyond the original list below: `*-distribʳ-+`, `*-distribˡ-+`,
   `*-assoc`, `*-identityʳ`, and `++-assoc` (rounding out the arithmetic and
   list families).
+  Proposed below but deferred — more setup or version-drift risk:
   `reverse-involutive`, `deMorgan₁` over `BooleanAlgebra`, `lookup-replicate`
   over `Vec`, and all `agda-algebras` obligations (21–30), which require a
   local `agda-algebras` checkout.

---

## stdlib Obligations (20 proposed)

### Tier 1 — Routine (7 obligations)

These are solvable by local syntactic strategies: `refl`, assumption matching,
or single-step computation.

| # | ID | Module | Definition | Type | Gold Term | Strategy | Domain |
|---|---|---|---|---|---|---|---|
| 1 | `stdlib-nat-plus-identity-l` | `Data.Nat.Properties` | `+-identityˡ` | `∀ n → 0 + n ≡ n` | `refl` | refl | arithmetic |
| 2 | `stdlib-bool-not-involutive` | `Data.Bool.Properties` | `not-involutive` | `∀ b → not (not b) ≡ b` | pattern match: `true → refl; false → refl` | case-split | logic |
| 3 | `stdlib-unit-trivial` | (standalone) | `trivial` | `⊤` | `tt` | constructor | logic |
| 4 | `stdlib-prod-constructor` | (standalone) | `mk-pair` | `{A B : Set} → A → B → A × B` | `λ a b → a , b` | constructor | logic |
| 5 | `stdlib-maybe-map-nothing` | `Data.Maybe.Properties` | `map-nothing` | `∀ {f} → map f nothing ≡ nothing` | `refl` | refl | maybe |
| 6 | `stdlib-list-length-nil` | (standalone) | `length-[]` | `length {A = A} [] ≡ 0` | `refl` | refl | list |
| 7 | `stdlib-nat-zero-less-suc` | `Data.Nat.Properties` | `0<1+n` | `∀ {n} → 0 < suc n` | `s≤s z≤n` | constructor | arithmetic |

### Tier 2 — Compositional (8 obligations)

These require composing 2–5 known lemmas, typically via induction or short
equational chains.

| # | ID | Module | Definition | Type | Gold Term (sketch) | Strategy | Domain |
|---|---|---|---|---|---|---|---|
| 8 | `stdlib-nat-plus-identity-r` | `Data.Nat.Properties` | `+-identityʳ` | `∀ n → n + 0 ≡ n` | Induction on `n`: base `refl`, step `cong suc IH` | induction | arithmetic |
| 9 | `stdlib-nat-plus-suc` | `Data.Nat.Properties` | `+-suc` | `∀ m n → m + suc n ≡ suc (m + n)` | Induction on `m`: base `refl`, step `cong suc IH` | induction | arithmetic |
| 10 | `stdlib-nat-plus-comm` | `Data.Nat.Properties` | `+-comm` | `∀ m n → m + n ≡ n + m` | Induction on `m` using `+-identityʳ` and `+-suc` | induction | arithmetic |
| 11 | `stdlib-nat-plus-assoc` | `Data.Nat.Properties` | `+-assoc` | `∀ m n p → (m + n) + p ≡ m + (n + p)` | Induction on `m`: base `refl`, step `cong suc IH` | induction | arithmetic |
| 12 | `stdlib-list-map-compose` | `Data.List.Properties` | `map-compose` | `map (f ∘ g) xs ≡ map f (map g xs)` | Induction on `xs`: base `refl`, step `cong (f(g x) ∷_) IH` | induction | list |
| 13 | `stdlib-list-length-append` | `Data.List.Properties` | `length-++` | `length (xs ++ ys) ≡ length xs + length ys` | Induction on `xs`: base `refl`, step `cong suc IH` | induction | list |
| 14 | `stdlib-list-map-id` | `Data.List.Properties` | `map-id` | `map id xs ≡ xs` | Induction on `xs`: base `refl`, step `cong (x ∷_) IH` | induction | list |
| 15 | `stdlib-nat-mul-zero-r` | `Data.Nat.Properties` | `*-zeroʳ` | `∀ n → n * 0 ≡ 0` | Induction on `n`: base `refl`, step `+-identityʳ _ ⟨ trans ⟩ IH` or just `IH` depending on reduction | induction | arithmetic |

### Tier 3 — Non-Obvious (5 obligations)

These require non-local lemma selection, non-trivial proof architecture, or
domain-specific insight.

| # | ID | Module | Definition | Type | Gold Term (sketch) | Strategy | Domain |
|---|---|---|---|---|---|---|---|
| 16 | `stdlib-nat-distrib-l` | `Data.Nat.Properties` | `*-distribˡ-+` | `∀ m n p → m * (n + p) ≡ m * n + m * p` | Induction on `m` + equational chain using `+-assoc`, `+-comm` | eq-chain | arithmetic |
| 17 | `stdlib-list-reverse-involutive` | `Data.List.Properties` | `reverse-involutive` | `reverse (reverse xs) ≡ xs` | Requires `reverse-++-commute` as key lemma | non-local | list |
| 18 | `stdlib-boolalg-demorgan1` | `Algebra.Lattice.Properties.BooleanAlgebra` | `deMorgan₁` | `∀ x y → ¬ (x ∧ y) ≈ ¬ x ∨ ¬ y` | Equational chain via distributivity + complements (cf. `FixtureStdlibBooleanAlgebra`) | eq-chain | algebra |
| 19 | `stdlib-decidable-map` | `Relation.Nullary.Decidable` | `map′` | `(A → B) → (B → A) → Dec A → Dec B` | Pattern match + application; requires understanding `Dec` structure | case-split | logic |
| 20 | `stdlib-vec-lookup-replicate` | `Data.Vec.Properties` | `lookup-replicate` | `∀ i → lookup (replicate n x) i ≡ x` | Induction on `i` and `n` simultaneously; structurally tricky | induction | vec |

---

## agda-algebras Obligations (10 proposed)

These draw from the HSP theorem proof path and related infrastructure.  They
require `AGDA_ALGEBRAS_SRC` to be set.

### Tier 1 — Routine (2 obligations)

| # | ID | Module | Definition | Type (sketch) | Gold Term | Strategy | Domain |
|---|---|---|---|---|---|---|---|
| 21 | `alg-func-id-comp` | `Base.Functions.Inverses` (or `Overture`) | identity-composition | `(f ∘ id) x ≡ f x` | `refl` | refl | algebra |
| 22 | `alg-nullary-compat` | `Setoid.Homomorphisms.Basic` | nullary compatibility | compatibility for 0-ary operations | `refl` (after unfolding) | refl | algebra |

### Tier 2 — Compositional (5 obligations)

| # | ID | Module | Definition | Type (sketch) | Gold Term (sketch) | Strategy | Domain |
|---|---|---|---|---|---|---|---|
| 23 | `alg-hom-compose` | `Setoid.Homomorphisms.Properties` | `⊙-is-hom` | `IsHom 𝑨 𝑩 g → IsHom 𝑩 𝑪 h → IsHom 𝑨 𝑪 (h ⊙ g)` | `trans (cong h (compatible ghom)) (compatible hhom)` | eq-chain | algebra |
| 24 | `alg-epi-compose` | `Setoid.Homomorphisms.Properties` | `⊙-is-epi` | composition of epis is epi | Record assembly using `⊙-is-hom` + `⊙-IsSurjective` | record-assembly | algebra |
| 25 | `alg-hom-kernel-reflexive` | `Setoid.Homomorphisms.Kernels` (or similar) | kernel reflexivity | reflexivity of hom kernel | Uses `cong h refl` or similar | eq-chain | algebra |
| 26 | `alg-free-hom` | `Setoid.Varieties.FreeAlgebras` | `hom𝔽[_]` | `hom (𝑻 X) 𝔽[ X ]` | `epi→hom (𝑻 X) 𝔽[ X ] epi𝔽[ X ]` | application | algebra |
| 27 | `alg-subalg-product` | `Setoid.Varieties.Preservation` | `PS⊆SP` component | subalgebra-of-product closure | Composition of closure operators | eq-chain | algebra |

### Tier 3 — Non-Obvious (3 obligations)

| # | ID | Module | Definition | Type (sketch) | Gold Term (sketch) | Strategy | Domain |
|---|---|---|---|---|---|---|---|
| 28 | `alg-ker-free-subset-ker-prod` | `Setoid.Varieties.HSP` | `ker𝔽⊆kerℭ` | kernel inclusion via free-lift-interp | Navigates between free-lift, kernel, and environment layers | non-local | algebra |
| 29 | `alg-birkhoff-sp-free` | `Setoid.Varieties.HSP` | `SP𝔽` | `𝔽[ X ] ∈ S ι (P ℓ ι 𝒦)` | Composes `S-idem`, `PS⊆SP`, and the product construction | non-local | algebra |
| 30 | `alg-birkhoff` | `Setoid.Varieties.HSP` | `Birkhoff` | `𝑨 ∈ Mod (Th (V ℓ ι 𝒦)) → 𝑨 ∈ V ℓ ι 𝒦` | Assembles `SP𝔽`, `𝔽-ModTh-epi-lift`, `epi→ontohom`, `V-≅-lc` | assembly | algebra |

---

## Distribution Summary

| Tier | stdlib | agda-algebras | Total |
|---|---|---|---|
| Routine | 7 | 2 | 9 |
| Compositional | 8 | 5 | 13 |
| Non-Obvious | 5 | 3 | 8 |
| **Total** | **20** | **10** | **30** |

---

## Notes for Review

1. **stdlib obligations 1–15** are high-confidence: these lemmas exist in Agda 2.8.0 stdlib and the proof strategies are standard.  Need to verify exact names and module paths against the Nix-pinned version.

2. **stdlib obligations 16–20** need more careful verification.  In particular:
   - `reverse-involutive` exists but the proof might be refactored in newer stdlib.
   - The `BooleanAlgebra` de Morgan proof is modeled on the existing `FixtureStdlibBooleanAlgebra.agda` fixture and should translate directly.
   - `map′` for `Dec` is simple structurally but the agent needs to know the `Dec` type.

3. **agda-algebras obligations 21–30** are best-effort guesses based on recollection of what's in the HSP proof and supporting lemmas; module paths may need adjusting; the `Setoid.*` hierarchy is the target (not `Base.*`), since the HSP
   theorem is proved in the setoid setting.

4. **Standalone obligations** (3, 4, 6) don't reprove an existing stdlib lemma; they define a fresh goal in a self-contained module; this avoids import complexity while still testing the same proof skill.

5. Several obligations (8–11, 12–15) form **dependency chains**: `+-comm` depends on `+-identityʳ` and `+-suc`.  The benchmark should include all members of the chain so the evaluation captures whether the agent can find prerequisites.

6. **Potential additions** if we want to reach 40: `*-comm`, `*-assoc`, `filter-++`, `++-assoc`, `map-++-commute`, more `Vec` lemmas, and additional agda-algebras obligations from `Setoid.Subalgebras` and `Setoid.Terms`.



