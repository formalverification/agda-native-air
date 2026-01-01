{-# LANGUAGE OverloadedStrings #-}

-- | Run.hs
--
-- File: agda-backend-jsonl/src/AgdaJsonl/Run.hs
--
-- Description:
--   CLI + Agda "boot glue"
--
--   This module has two jobs:
--
--   (1) Parse CLI arguments and open the output file handle.
--   (2) Enter Agda's typechecking monad (TCM) in a way that:
--       - sets include paths
--       - respects Agda library settings (from nix shell's libraries file)
--       - then runs a TCM action that does parse+typecheck+extract
--
--   The important part is: we run `typeCheckMain` ourselves, and then extract
--   from the returned `CheckResult` (which works whether Agda typechecks from
--   scratch OR loads a cached .agdai interface).
--
--   IMPORTANT NOTE ABOUT CACHES / .agdai:
--
--     Agda exposes an interactive driver API:
--
--       runAgdaWithOptions :: Interactor a -> String -> CommandLineOptions -> TCM a
--
--   where the Interactor is given two callbacks: `setup` and `check`.
--   The `check` callback returns a CheckResult and is primarily intended for
--   the interactive protocol.
--
--   Empirically (and consistent with Agda's own docs), relying on `check` does
--   NOT reliably leave the TCM state populated the way we need for extraction
--   (especially when interfaces are cached). Agda's own `interactionInteractor`
--   ignores `check` and calls `typeCheckMain` directly. So we do the same.

module AgdaJsonl.Run
  ( main
  ) where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.List (nub)
import System.Directory (doesFileExist, makeAbsolute)
import System.Environment (getArgs)
import System.Exit (die)
import System.FilePath (takeDirectory)
import System.IO
  ( BufferMode(LineBuffering)
  , Handle
  , IOMode(WriteMode)
  , hPutStrLn
  , hSetBuffering
  , stderr
  , withFile
  )

import qualified AgdaJsonl.Extract as Extract

-- Agda imports (2.8.0)
import Agda.Interaction.Imports (parseSource, typeCheckMain, Mode(..))
import Agda.Interaction.Options (CommandLineOptions(..), defaultOptions)
import Agda.Main (runAgdaWithOptions, runTCMPrettyErrors)
import Agda.TypeChecking.Monad (TCM)
import Agda.TypeChecking.Monad.Base (srcFromPath)
import Agda.Utils.FileName (mkAbsolute, AbsolutePath)

--------------------------------------------------------------------------------
-- CLI
--------------------------------------------------------------------------------

data Cli = Cli
  { cliInput   :: FilePath
  , cliOutput  :: FilePath
  , cliInclude :: [FilePath]
  }

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

parseCli :: [String] -> Either String Cli
parseCli xs =
  let go acc [] = Right acc
      go acc ("--include":d:rest) = go (acc { cliInclude = cliInclude acc <> [d] }) rest
      go acc ("--input":f:rest)   = go (acc { cliInput   = f }) rest
      go acc ("--output":o:rest)  = go (acc { cliOutput  = o }) rest
      go _   bad                  = Left ("Unrecognized args: " <> show bad)
      seed = Cli "" "" []
  in do
    c <- go seed xs
    when (null (cliInput c))  (Left "Missing --input")
    when (null (cliOutput c)) (Left "Missing --output")
    pure c

--------------------------------------------------------------------------------
-- Entry
--------------------------------------------------------------------------------

main :: IO ()
main = do
  args <- getArgs
  cli  <- either (\e -> die (e <> "\n\n" <> usage)) pure (parseCli args)

  ok <- doesFileExist (cliInput cli)
  when (not ok) $
    die ("Input file does not exist: " <> cliInput cli)

  withFile (cliOutput cli) WriteMode $ \h -> do
    hSetBuffering h LineBuffering
    runOnce h cli

--------------------------------------------------------------------------------
-- One run: enter Agda, typecheck, dump JSONL
--------------------------------------------------------------------------------

runOnce :: Handle -> Cli -> IO ()
runOnce h cli = do
  let inputFile   = cliInput cli
      includeDirs = nub (takeDirectory inputFile : cliInclude cli)

  withAgda includeDirs inputFile $ \absInput absIncludes -> do
    -- Parse + typecheck *explicitly* (do not rely on interactive `check`).
    absPath <- mkAbs inputFile
    sf      <- srcFromPath absPath
    src     <- parseSource sf
    -- Dump rows; if zero rows, treat as a hard failure with a helpful message.
    -- IMPORTANT:
    -- typeCheckMain returns a CheckResult containing the Interface even when
    -- Agda uses an existing .agdai cache. The Interface is then extracted
    -- from that CheckResult when writing JSONL.
    cr <- typeCheckMain TypeCheck src
    st  <- Extract.dumpCheckResultAsJsonl h inputFile cr

    -- Hard-fail ONLY if Agda produced an *empty interface signature*.
    -- If dsWrittenDefs == 0, that can be legitimate (e.g. module is just reexports)
    -- especially now that we filter to "main module only".
    when (Extract.dsTotalDefs st == 0) $
      liftIO $ die $
        unlines
          [ "agda-json: typechecking succeeded, but interface signature had 0 definitions."
          , "This is unexpected and usually indicates the TCM signature is empty/unpopulated."
          , "input:       " <> inputFile
          , "absInput:    " <> absInput
          , "absIncludes: " <> show absIncludes
          ]

    when (Extract.dsWrittenDefs st == 0) $
      liftIO $ hPutStrLn stderr $
        unlines
          [ "agda-json WARNING: extracted 0 rows for main module."
          , "  mainModule:  " <> show (Extract.dsMainModule st)
          , "  input:       " <> inputFile
          , "  totalDefs:   " <> show (Extract.dsTotalDefs st)
          , "This can be legitimate (re-export-only module), but we keep it visible."
          ]

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

-- | Convert FilePath -> Agda AbsolutePath safely.
--
-- Agda's `mkAbsolute` is *not* like `System.Directory.makeAbsolute`.
-- It assumes the input is already an absolute OS path and will crash
-- (`__IMPOSSIBLE__`) if given a relative path.
mkAbs :: FilePath -> TCM AbsolutePath
mkAbs fp = do
  absFp <- liftIO (makeAbsolute fp)
  pure (mkAbsolute absFp)

--------------------------------------------------------------------------------
-- Agda boot glue
--------------------------------------------------------------------------------

-- | Enter Agda's TCM with include paths configured, then run the provided TCM action.
--
-- We run only `setup`  (to finalize options) from Agda’s interactor framework (from
-- `runAgdaWithOptions`) because it performs internal option normalization (notably
-- absolute include paths) and then immediately run our TCM action.
--
-- We deliberately DO NOT call the interactive `check` callback:
-- Agda's own docs show that `interactionInteractor` ignores `check` and calls
-- `typeCheckMain` directly instead.
withAgda :: [FilePath] -> FilePath -> (FilePath -> [FilePath] -> TCM ()) -> IO ()
withAgda includeDirs inputFile tcmAction = do
  absInput    <- makeAbsolute inputFile
  absIncludes <- mapM makeAbsolute includeDirs

  let opts = defaultOptions
        { optProgramName   = "agda-json"
        , optInputFile     = Just absInput
        , optIncludePaths  = absIncludes
        -- We *do not* rely on optIgnoreInterfaces here; extraction works for
        -- both cached and non-cached runs because we extract from CheckResult.
        --
        -- The two options below are intentionally kept commented out as a
        -- reference for debugging / development:
        --
        --   * optIgnoreInterfaces    = True
        --       Force Agda to ignore existing interface files and re-check
        --       modules from source.
        --   * optIgnoreAllInterfaces = True
        --       Stronger variant that disables all interface reuse.
        --
        -- Enabling these may be useful when diagnosing cache-related issues
        -- or forcing a clean recheck, but they should remain disabled in
        -- normal runs so that interface caching works as intended.
        --, optIgnoreInterfaces     = True
        --, optIgnoreAllInterfaces  = True
        }

      interactor setup _check = do
        _ <- setup
        tcmAction absInput absIncludes

      tcmProgram :: TCM ()
      tcmProgram = runAgdaWithOptions interactor "agda-json" opts

  runTCMPrettyErrors tcmProgram
