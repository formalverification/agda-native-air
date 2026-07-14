-- Prod-mk-pair.agda
--
-- File: data/benchmarks/agda-stdlib-v0/obligations/Prod-mk-pair.agda
--
-- Benchmark obligation: stdlib-prod-mk-pair
-- Difficulty: routine (Tier 1)
-- Source: standalone
-- Strategy: apply the product constructor
--
module Prod-mk-pair where

open import AgdaDojang.Debug

open import Data.Product.Base using ( _×_ ; _,_ )

mk-pair : {A B : Set} → A → B → A × B
mk-pair a b = {!!}
