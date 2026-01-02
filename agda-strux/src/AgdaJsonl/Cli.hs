{-# LANGUAGE OverloadedStrings #-}

-- | Cli.hs
--
-- File: agda-backend-jsonl/src/AgdaJsonl/Cli.hs
--
-- Description: Pure CLI parsing for agda-json.
--
-- Why a separate module?
--   + Tests can exercise argument parsing without spawning processes.
--   + 'AgdaJsonl.Run' stays focused on “boot Agda + run extraction”.
--
-- Note:
--   We keep this intentionally minimal. If/when we add flags,
--   we can extend 'parseCli' in a referentially transparent way.

module AgdaJsonl.Cli
  ( Cli(..)
  , usage
  , parseCli
  ) where

import Control.Monad (when)
import Data.List (nub)

data Cli = Cli
  { cliInput   :: FilePath
  , cliOutput  :: FilePath
  , cliInclude :: [FilePath]
  }
  deriving (Eq, Show)

usage :: String
usage = unlines
  [ "Usage:"
  , "  agda-json --input PATH --output OUT.jsonl [--include DIR]..."
  , ""
  , "Example:"
  , "  agda-json --input test/resources/Example.agda \\"
  , "           --output /tmp/out.jsonl \\"
  , "           --include test/resources"
  ]

-- | Total CLI parser: never throws; returns an error message on failure.
parseCli :: [String] -> Either String Cli
parseCli xs =
  let step :: Cli -> [String] -> Either String Cli
      step acc = \ys ->
        case ys of
          [] -> Right acc
          ("--include" : d : rest) -> step (acc { cliInclude = cliInclude acc <> [d] }) rest
          ("--input"   : f : rest) -> step (acc { cliInput   = f }) rest
          ("--output"  : o : rest) -> step (acc { cliOutput  = o }) rest
          bad -> Left ("Unrecognized args: " <> show bad)

      seed = Cli "" "" []

  in do
    c0 <- step seed xs
    let c = c0 { cliInclude = nub (cliInclude c0) }
    when (null (cliInput c))  (Left "Missing --input")
    when (null (cliOutput c)) (Left "Missing --output")
    pure c
