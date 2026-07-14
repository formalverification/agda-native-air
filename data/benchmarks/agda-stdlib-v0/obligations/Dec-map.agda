-- Dec-map.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Dec-map.agda
--
-- Benchmark obligation: stdlib-dec-map
-- Difficulty: non-obvious (Tier 3)
-- Source: Relation.Nullary.Decidable.Core
-- Strategy: case split on the decision; transport the witness / refutation
--
-- Note: requires understanding the Dec structure (yes / no pattern synonyms)
-- and constructing a refutation of B from a refutation of A.
--
module Dec-map where

open import AgdaDojang.Debug

open import Relation.Nullary using ( Dec ; yes ; no )

map′ : {A B : Set} → (A → B) → (B → A) → Dec A → Dec B
map′ A→B B→A d = {!!}
