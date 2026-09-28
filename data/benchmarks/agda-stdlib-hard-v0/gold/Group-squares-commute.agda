-- Group-squares-commute.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/gold/Group-squares-commute.agda
--
-- Benchmark obligation: hard-group-squares-commute
-- Difficulty: non-obvious
-- Import stratum: novel
--
-- If (x ∙ y)² ≈ x² ∙ y² for all x and y, the group is commutative.
--
module Group-squares-commute where

open import AgdaDojang.Debug

open import Level                     using ( Level )
open import Algebra.Bundles           using ( Group )
open import Algebra.Definitions       using ( Commutative )

module _ {c ℓ : Level} (G : Group c ℓ) where
  open Group G

  squares-commute : (∀ x y → (x ∙ y) ∙ (x ∙ y) ≈ (x ∙ x) ∙ (y ∙ y)) → Commutative _≈_ _∙_
  squares-commute sq x y = ∙-cancelʳ y _ _ (∙-cancelˡ x _ _ (begin
    x ∙ ((x ∙ y) ∙ y)  ≈⟨ uv∙wx≈u[vw∙x] x x y y ⟨
    (x ∙ x) ∙ (y ∙ y)  ≈⟨ sq x y ⟨
    (x ∙ y) ∙ (x ∙ y)  ≈⟨ uv∙wx≈u[vw∙x] x y x y ⟩
    x ∙ ((y ∙ x) ∙ y)  ∎))
    where
    open import Algebra.Properties.Group G using ( ∙-cancelˡ ; ∙-cancelʳ )
    open import Algebra.Properties.Semigroup semigroup using ( uv∙wx≈u[vw∙x] )
    open import Relation.Binary.Reasoning.Setoid setoid

  -- An alternative proof, by associativity alone (see data/benchmarks/README.md,
  -- "Alternative proofs").
  squares-commute-by-assoc : (∀ x y → (x ∙ y) ∙ (x ∙ y) ≈ (x ∙ x) ∙ (y ∙ y)) → Commutative _≈_ _∙_
  squares-commute-by-assoc sq x y = ∙-cancelʳ y _ _ (∙-cancelˡ x _ _ (begin
    x ∙ ((x ∙ y) ∙ y)  ≈⟨ ∙-congˡ (assoc x y y) ⟩
    x ∙ (x ∙ (y ∙ y))  ≈⟨ assoc x x (y ∙ y) ⟨
    (x ∙ x) ∙ (y ∙ y)  ≈⟨ sq x y ⟨
    (x ∙ y) ∙ (x ∙ y)  ≈⟨ assoc x y (x ∙ y) ⟩
    x ∙ (y ∙ (x ∙ y))  ≈⟨ ∙-congˡ (assoc y x y) ⟨
    x ∙ ((y ∙ x) ∙ y)  ∎))
    where
    open import Algebra.Properties.Group G using ( ∙-cancelˡ ; ∙-cancelʳ )
    open import Relation.Binary.Reasoning.Setoid setoid
