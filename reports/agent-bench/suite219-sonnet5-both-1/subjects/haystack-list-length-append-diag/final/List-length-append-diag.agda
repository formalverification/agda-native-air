-- List-length-append-diag.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/List-length-append-diag.agda
--
-- Benchmark obligation: haystack-list-length-append-diag
-- Difficulty: routine (Tier 1)
--
module List-length-append-diag where

open import AgdaDojang.Debug

open import Data.List.Base using ( List ; _++_ ; length )
open import Data.Nat.Base using ( _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.List.Properties using ( ++-assoc )
open import Data.List.Properties using ( length-++ )

length-++-diag : ∀ {A : Set} (xs : List A) → length (xs ++ xs) ≡ length xs + length xs
length-++-diag xs = length-++ xs
