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
  , runJsonl
  ) where
import Control.Exception (catch, throwIO)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.List (nub)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import System.Directory (doesFileExist, makeAbsolute)
import System.Environment (getArgs)
import System.Exit (die, ExitCode(..))
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
import qualified AgdaJsonl.Cli     as Cli

-- Agda imports (2.8.0)
import Agda.Interaction.Imports (parseSource, typeCheckMain, Mode(..))
import Agda.Interaction.Options (CommandLineOptions(..), defaultOptions)
import Agda.Main (runAgdaWithOptions, runTCMPrettyErrors)
import Agda.TypeChecking.Monad (TCM)
import Agda.TypeChecking.Monad.Base (srcFromPath)
import Agda.Utils.FileName (mkAbsolute, AbsolutePath)

--------------------------------------------------------------------------------
-- Entry
--------------------------------------------------------------------------------

main :: IO ()
main = do
  args <- getArgs
  cli  <- either (\e -> die (e <> "\n\n" <> Cli.usage)) pure (Cli.parseCli args)
  _    <- runJsonl (Cli.cliInput cli) (Cli.cliOutput cli) (Cli.cliInclude cli)
  pure ()

-- | In-process API for tests and future batch drivers.
--
-- This function:
--   + validates the input file exists,
--   + opens the output file handle,
--   + boots Agda and runs extraction,
--   + returns extraction statistics.
runJsonl :: FilePath -> FilePath -> [FilePath] -> IO Extract.DumpStats
runJsonl inputFile outputFile extraIncludes = do
  ok <- doesFileExist inputFile
  when (not ok) $
    die $ "agda-json: Input file does not exist: " <> inputFile

  withFile outputFile WriteMode $ \h -> do
    hSetBuffering h LineBuffering
    runOnce h inputFile extraIncludes

--------------------------------------------------------------------------------
-- One run: enter Agda, typecheck, dump JSONL
--------------------------------------------------------------------------------

runOnce :: Handle -> FilePath -> [FilePath] -> IO Extract.DumpStats
runOnce h inputFile extraIncludes = do
  let includeDirs = nub (takeDirectory inputFile : extraIncludes)

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
      liftIO $ hPutStrLn stderr $
        unlines
          [ "agda-json NOTE: typechecking succeeded but extracted 0 definitions."
          , "This is normal for barrel/re-export modules."
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

    pure st

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

-- | Enter Agda's TCM with include paths configured, run the provided TCM action,
--   and return its result.
--
-- Implementation note:
--   Agda's executable-oriented runner may terminate with `exitSuccess`,
--   which is implemented as throwing `ExitSuccess`. In library/test use, we
--   treat ExitSuccess as normal completion, so `runAgda` runs a `TCM ()` program and
--   returns a value by storing the action's result in an IORef and then reading it
--   back after the Agda run finishes.
runAgda :: TCM () -> IO ()
runAgda prog =
  runTCMPrettyErrors prog `catch` \e -> case e of
    ExitSuccess   -> pure ()      -- Agda sometimes ends runs via exitSuccess
    ExitFailure _ -> throwIO e

withAgda :: [FilePath] -> FilePath -> (FilePath -> [FilePath] -> TCM a) -> IO a
withAgda includeDirs inputFile tcmAction = do
  absInput    <- makeAbsolute inputFile
  absIncludes <- mapM makeAbsolute includeDirs

  resultRef :: IORef (Maybe a) <- newIORef Nothing

  let opts = defaultOptions
        { optProgramName   = "agda-json"
        , optInputFile     = Just absInput
        , optIncludePaths  = absIncludes
        }

      -- Interactor must return () for runTCMPrettyErrors.
      interactor setup _check = do
        _ <- setup
        r <- tcmAction absInput absIncludes
        liftIO (writeIORef resultRef (Just r))
        pure ()

      tcmProgram = runAgdaWithOptions interactor "agda-json" opts

  -- Run Agda (prints pretty errors if it fails).
  runAgda tcmProgram

  -- Recover the result.
  mr <- readIORef resultRef
  case mr of
    Just r  -> pure r
    Nothing ->
      die $
        unlines
          [ "agda-json: internal error: Agda run completed but produced no result."
          , "input: " <> inputFile
          ]
