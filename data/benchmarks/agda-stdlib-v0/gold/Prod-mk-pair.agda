-- Prod-mk-pair.agda (gold solution)
--
-- File: data/benchmarks/agda-stdlib-v0/gold/Prod-mk-pair.agda
--
-- Gold solution for benchmark obligation: stdlib-prod-mk-pair
--
module Prod-mk-pair where

open import AgdaDojang.Debug

open import Data.Product.Base using ( _×_ ; _,_ )

mk-pair : {A B : Set} → A → B → A × B
mk-pair a b = a , b
