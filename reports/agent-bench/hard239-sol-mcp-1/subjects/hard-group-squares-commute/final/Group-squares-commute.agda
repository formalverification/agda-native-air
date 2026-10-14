-- Group-squares-commute.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/obligations/Group-squares-commute.agda
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
  squares-commute sq x y = sym (cancel-right y (y ∙ x) (x ∙ y)
    (cancel-left x ((y ∙ x) ∙ y) ((x ∙ y) ∙ y) middle))
    where
    undo-left : ∀ a b → (a ⁻¹) ∙ (a ∙ b) ≈ b
    undo-left a b = trans (sym (assoc (a ⁻¹) a b))
      (trans (∙-cong (inverseˡ a) refl) (identityˡ b))

    cancel-left : ∀ a b d → a ∙ b ≈ a ∙ d → b ≈ d
    cancel-left a b d p = trans (sym (undo-left a b))
      (trans (∙-cong refl p) (undo-left a d))

    undo-right : ∀ a b → (b ∙ a) ∙ (a ⁻¹) ≈ b
    undo-right a b = trans (assoc b a (a ⁻¹))
      (trans (∙-cong refl (inverseʳ a)) (identityʳ b))

    cancel-right : ∀ a b d → b ∙ a ≈ d ∙ a → b ≈ d
    cancel-right a b d p = trans (sym (undo-right a b))
      (trans (∙-cong p refl) (undo-right a d))

    middle : x ∙ ((y ∙ x) ∙ y) ≈ x ∙ ((x ∙ y) ∙ y)
    middle = trans (∙-cong refl (assoc y x y))
      (trans (sym (assoc x y (x ∙ y)))
      (trans (sq x y)
      (trans (assoc x x (y ∙ y))
        (∙-cong refl (sym (assoc x y y))))))
