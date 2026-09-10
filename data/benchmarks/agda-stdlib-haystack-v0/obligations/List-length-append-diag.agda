-- List-length-append-diag.agda
--
-- File: data/benchmarks/agda-stdlib-haystack-v0/obligations/List-length-append-diag.agda
--
-- Benchmark obligation: haystack-list-length-append-diag
-- Difficulty: routine (Tier 1)
-- Haystack: Data.List.Properties
-- Needle: Data.List.Properties.length-++
-- Strategy: one saturated application of the needle over the goal's context
--
-- Note: the diagonal instance of length-++; its implicit ys is solved by unification.
--
-- Haystack tier (issue #129): the Properties module is opened with a
-- deliberately narrow `using` list of decoys that cannot close the goal, so
-- the needle is import-reachable only by its qualified name.  A gold that
-- names it qualified is the same text the retrieval ladder renders.
--
module List-length-append-diag where

open import AgdaDojang.Debug

open import Data.List.Base using ( List ; _++_ ; length )
open import Data.Nat.Base using ( _+_ )
open import Relation.Binary.PropositionalEquality using ( _≡_ )

-- The haystack: reachable qualified; the `using` list holds decoys only.
open import Data.List.Properties using ( ++-assoc )

length-++-diag : ∀ {A : Set} (xs : List A) → length (xs ++ xs) ≡ length xs + length xs
length-++-diag xs = {!!}
