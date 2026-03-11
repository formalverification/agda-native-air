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
  , OutputFormat(..)
  , usage
  , parseCli
  ) where

import Control.Monad (when)
import Data.List (nub)
import Data.Char (toLower)

data OutputFormat = Full | Human
  deriving (Eq, Show)

data Cli = Cli
  { cliInput   :: FilePath
  , cliOutput  :: FilePath
  , cliInclude :: [FilePath]
  , cliFormat  :: OutputFormat
  }
  deriving (Eq, Show)

usage :: String
usage = unlines
  [ "Usage:"
  , " |   agda-json --input PATH --output OUT.jsonl [--include DIR]... [--format full|human | --human]"
  , " | "
  , "Example:"
  , " |   agda-json --input ../data/agda/Example.agda \\"
  , " |             --output /tmp/out.jsonl \\"
  , " |             --include test/resources"
  , " | "
  , "Human output:"
  , " |   agda-json --input X.agda --output /tmp/out.jsonl --human"
  , " | "
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
          ("--human"         : rest) -> step (acc { cliFormat = Human }) rest
          ("--format" : v : rest) ->
            case map toLower v of
              "full"  -> step (acc { cliFormat = Full })  rest
              "human" -> step (acc { cliFormat = Human }) rest
              _       -> Left ("Bad --format: " <> v <> " (use full|human)")
          bad -> Left ("Unrecognized args: " <> show bad)

      seed = Cli "" "" [] Full

  in do
    c0 <- step seed xs
    let c = c0 { cliInclude = nub (cliInclude c0) }
    when (null (cliInput c))  (Left "Missing --input")
    when (null (cliOutput c)) (Left "Missing --output")
    pure c
