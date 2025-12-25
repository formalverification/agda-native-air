-- | src/AgdaJsonl/Run.hs
--
-- File: agda-backend-jsonl/src/AgdaJsonl/Run.hs
--
-- Description:
--   CLI + Agda "boot glue"
--
--   This module has two jobs:
--
--   (1) Parse CLI arguments and open the output file handle.
--   (2) Enter Agda’s typechecking monad (TCM) in a way that:
--       - sets include paths
--       - respects Agda library settings (from your nix shell’s libraries file)
--       - then runs a TCM action that does parse+typecheck+extract
--
--   The rest of the project should treat this as "the executable boundary":
--   everything below `withAgda` is regular Agda API usage, not ad-hoc IO hacks.

{-# LANGUAGE OverloadedStrings #-}

module AgdaJsonl.Run
  ( main
  ) where

import Control.Monad (void, when)
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
  , hSetBuffering
  , withFile
  )

import qualified AgdaJsonl.Extract as Extract

-- Agda imports (2.8.0)
import Agda.Interaction.Imports (parseSource, typeCheckMain, Mode(..))
import Agda.Interaction.Options (CommandLineOptions(..), defaultOptions)
import Agda.Main (runAgdaWithOptions, runTCMPrettyErrors)
import Agda.TypeChecking.Monad (TCM)
import Agda.TypeChecking.Monad.Base (srcFromPath)
import Agda.Utils.FileName (mkAbsolute, AbsolutePath, absolute)

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
  , "  agda-json --input proof-parser/src/test/resources/agda-example.agda \\"
  , "           --output /tmp/out.jsonl \\"
  , "           --include proof-parser/src/test/resources"
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

-- | Run Agda parse+typecheck, then dump JSONL.
--
-- We automatically include the input file’s directory in the include path,
-- because many Agda projects rely on relative imports rooted there.
runOnce :: Handle -> Cli -> IO ()
runOnce h cli = do
  let inputFile   = cliInput cli
      includeDirs = nub (takeDirectory inputFile : cliInclude cli)

  withAgda includeDirs inputFile $ do
    absPath <- mkAbs inputFile          -- AbsolutePath
    sf      <- srcFromPath absPath      -- SourceFile
    src     <- parseSource sf
    _cr     <- typeCheckMain TypeCheck src
    Extract.dumpSignatureAsJsonl h inputFile

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

-- | Enter Agda’s TCM with include paths configured, then run the provided TCM action.
--
-- Implementation strategy:
--
--   * Build `CommandLineOptions` starting from `defaultOptions`.
--   * Use `runAgdaWithOptions` to initialize Agda and run an “interactor”.
--   * Our interactor ignores the interactive machinery and simply runs `tcmAction`.
--   * Wrap the whole thing in `runTCMPrettyErrors` so errors are rendered nicely.
--
-- Note: `runTCMPrettyErrors` runs a `TCM ()` in `IO ()`, so this function is
-- intentionally `IO ()`. That’s totally fine for our backend: the “result” is the
-- JSONL we stream to the output handle.
withAgda :: [FilePath] -> FilePath -> TCM () -> IO ()
withAgda includeDirs inputFile tcmAction = do
  -- Agda is picky about invariants on option paths; keep them absolute.
  absInput    <- makeAbsolute inputFile
  absIncludes <- mapM makeAbsolute includeDirs

  let opts =
        defaultOptions
          { optProgramName  = "agda-json"
          , optInputFile    = Just absInput
          , optIncludePaths = absIncludes
          }

      -- IMPORTANT: run the setup that fills optAbsoluteIncludePaths,
      -- and (typically) check/typecheck the input file once.
      interactor setup check = do
        setup
        inputAbs <- liftIO (absolute absInput)
        void (check inputAbs)
        tcmAction

      tcmProgram :: TCM ()
      tcmProgram = runAgdaWithOptions interactor "agda-json" opts

  runTCMPrettyErrors tcmProgram
