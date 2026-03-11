-- | app/Main.hs
--
-- File: agda-backend-jsonl/app/Main.hs
--
-- Description:
--   Minimal entrypoint.
--
--   We keep Main extremely small: all real logic lives in AgdaJsonl.Run
--   so that future refactors (CLI flags, running Agda, etc.) don't
--   involve shuffling the executable wiring.

{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import qualified AgdaJsonl.Run as Run

main :: IO ()
main = Run.main
