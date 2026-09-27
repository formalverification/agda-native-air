-- Group-squares-commute.agda
--
-- File: data/benchmarks/agda-stdlib-hard-v0/obligations/Group-squares-commute.agda
--
-- Benchmark obligation: hard-group-squares-commute
-- Difficulty: non-obvious
-- Source: exam genre, group theory qualifying exams (Algebra.Bundles.Group)
-- Import stratum: novel
-- Strategy: cancellation twice on the hypothesis at (x ∙ y) ∙ (x ∙ y)
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
  squares-commute sq x y = sym y∙x≈x∙y
    where
    cancelˡ : ∀ a b c → a ∙ b ≈ a ∙ c → b ≈ c
    cancelˡ a b c eq =
      trans (sym (identityˡ b))
      (trans (∙-congʳ (sym (inverseˡ a)))
      (trans (assoc (a ⁻¹) a b)
      (trans (∙-congˡ eq)
      (trans (sym (assoc (a ⁻¹) a c))
      (trans (∙-congʳ (inverseˡ a)) (identityˡ c))))))

    cancelʳ : ∀ a b c → b ∙ a ≈ c ∙ a → b ≈ c
    cancelʳ a b c eq =
      trans (sym (identityʳ b))
      (trans (∙-congˡ (sym (inverseʳ a)))
      (trans (sym (assoc b a (a ⁻¹)))
      (trans (∙-congʳ eq)
      (trans (assoc c a (a ⁻¹))
      (trans (∙-congˡ (inverseʳ a)) (identityʳ c))))))

    step : y ∙ (x ∙ y) ≈ x ∙ (y ∙ y)
    step = cancelˡ x (y ∙ (x ∙ y)) (x ∙ (y ∙ y))
             (trans (sym (assoc x y (x ∙ y)))
             (trans (sq x y) (assoc x x (y ∙ y))))

    y∙x≈x∙y : y ∙ x ≈ x ∙ y
    y∙x≈x∙y = cancelʳ y (y ∙ x) (x ∙ y)
                (trans (assoc y x y)
                (trans step (sym (assoc x y y))))
