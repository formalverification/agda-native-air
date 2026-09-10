-- List-map-append-diag.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/List-map-append-diag.agda
--
-- Benchmark obligation: haystack-list-map-append-diag
-- Difficulty: compositional (Tier 2)
-- Haystack: Data.List.Properties
-- Needle: Data.List.Properties.map-++
-- Strategy: one saturated application of the needle over the goal's context
--
-- Note: the diagonal instance of map-++, arity 3 over a two-name context.
--
-- Haystack tier (issue #129): the Properties module is opened with a
-- deliberately narrow `using` list of decoys that cannot close the goal, so
-- the needle is import-reachable only by its qualified name.  A gold that
-- names it qualified is the same text the retrieval ladder renders.
--
module List-map-append-diag where

open import AgdaDojang.Debug

open import Data.List.Base using ( List ; _++_ ; map )
open import Data.Nat.Base using ( ℕ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.List.Properties using ( ++-assoc )

map-++-diag : ∀ (f : ℕ → ℕ) (xs : List ℕ) → map f (xs ++ xs) ≡ map f xs ++ map f xs
map-++-diag f xs = {!!}
