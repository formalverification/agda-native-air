-- List-map-append-diag.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/gold/List-map-append-diag.agda
--
-- Benchmark obligation: haystack-list-map-append-diag
-- Difficulty: compositional (Tier 2)
--
module List-map-append-diag where

open import AgdaDojang.Debug

open import Data.List.Base using ( List ; _++_ ; map )
open import Data.Nat.Base using ( ℕ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.List.Properties using ( ++-assoc )

map-++-diag : ∀ (f : ℕ → ℕ) (xs : List ℕ) → map f (xs ++ xs) ≡ map f xs ++ map f xs
map-++-diag f xs = Data.List.Properties.map-++ f xs xs
