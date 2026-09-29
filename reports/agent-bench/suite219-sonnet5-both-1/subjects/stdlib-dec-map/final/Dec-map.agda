-- Dec-map.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Dec-map.agda
--
-- Benchmark obligation: stdlib-dec-map
-- Difficulty: non-obvious (Tier 3)
--
module Dec-map where

open import AgdaDojang.Debug

open import Relation.Nullary using ( Dec ; yes ; no )

map′ : {A B : Set} → (A → B) → (B → A) → Dec A → Dec B
map′ A→B B→A (yes a)  = yes (A→B a)
map′ A→B B→A (no ¬a)  = no (λ b → ¬a (B→A b))
