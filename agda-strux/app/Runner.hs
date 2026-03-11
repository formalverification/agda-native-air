{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

-- |  Runner.hs
--
-- File: agda-strux/app/Runner.hs
--
-- Description:
--   agda-jsonl runner: run agda-jsonl over a list of top-level
--   Agda modules, producing JSONL outputs and a run manifest.
--
--   Supports parallelism and resuming incomplete runs.
--
--   Usage:
--     agda-json-runner \
--       --project-root <repo-root> \
--       --agda-dir     <repo-root>/agda-dojang/agda \
--       --src-dir      <path-to-library-src> \
--       --modules-file <everything-modules.txt> \
--       --out-dir      <out-dir> \
--       --agda-json    <path-to-agda-json-exe> \
--       [--parallelism N] [--no-resume]
--
--   Example:
--     agda-json-runner \
--       --project-root ~/dev/agda/agda-strux \
--       --agda-dir     ~/dev/agda/agda-dojang/agda \
--       --src-dir      ~/dev/agda/agda-stdlib/src \
--       --modules-file ~/dev/agda/agda-stdlib/everything-modules.txt
--       --out-dir      ~/tmp/agda-jsonl-out \
--       --agda-json    ~/dev/agda/agda-strux/dist-newstyle/build/agda-jsonl/agda-jsonl \
--       --parallelism  16 \
--       --no-resume
--
--   Notes:
--     + The modules file should list top-level Agda modules, one per line.
--       Lines starting with '#' are ignored as comments.
--       Module names should use '.' as separator, e.g. Data.List.
--     + The output directory will contain 'jsonl/' and 'logs/' subdirectories.
--     + The run manifest is written
--       to '<out-dir>/run-manifest.json' upon completion.
--     + If '--no-resume' is not given, existing non-empty JSONL outputs
--       will be skipped.
--     + Parallelism defaults to 8 if not specified.

module Main (main) where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar
import Control.Concurrent.QSem
import Control.Exception (SomeException, try)
import Control.Monad (forM_, when, void)
import Data.Aeson (ToJSON, encode)
import Data.List (isPrefixOf)
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import GHC.Generics (Generic)
import System.Directory (createDirectoryIfMissing, doesFileExist, getFileSize)
import System.Environment (getArgs)
import System.Exit (ExitCode(..))
import System.FilePath ((</>), takeDirectory)
import System.IO (IOMode(..), withFile)
import System.Process (CreateProcess(..), proc, createProcess, waitForProcess, StdStream(..))

data ModuleRun = ModuleRun
  { moduleName    :: String
  , inputFile     :: FilePath
  , outputFile    :: FilePath
  , logFile       :: FilePath
  , skipped       :: Bool
  , ok            :: Bool
  , exitCode      :: Maybe Int
  , seconds       :: Double
  } deriving (Show, Generic)

instance ToJSON ModuleRun

data RunManifest = RunManifest
  { startedAt    :: String
  , finishedAt   :: String
  , projectRoot  :: FilePath
  , agdaDir      :: FilePath
  , srcDir       :: FilePath
  , modulesFile  :: FilePath
  , outDir       :: FilePath
  , agdaJsonBin  :: FilePath
  , parallelism  :: Int
  , resume       :: Bool
  , results      :: [ModuleRun]
  } deriving (Show, Generic)

instance ToJSON RunManifest

data Config = Config
  { cfgProjectRoot :: FilePath
  , cfgAgdaDir     :: FilePath
  , cfgSrcDir      :: FilePath
  , cfgModulesFile :: FilePath
  , cfgOutDir      :: FilePath
  , cfgAgdaJsonBin :: FilePath
  , cfgPar         :: Int
  , cfgResume      :: Bool
  } deriving (Show)

usage :: String
usage = unlines
  [ "Usage:"
  , "  agda-json-runner \\"
  , "    --project-root <repo-root> \\"
  , "    --agda-dir     <repo-root>/agda-dojang/agda \\"
  , "    --src-dir      <path-to-library-src> \\"
  , "    --modules-file <everything-modules.txt> \\"
  , "    --out-dir      <out-dir> \\"
  , "    --agda-json    <path-to-agda-json-exe> \\"
  , "    [--parallelism N] [--no-resume]"
  ]

parseArgs :: [String] -> Either String Config
parseArgs xs = go xs (Config "" "" "" "" "" "" 8 True)
  where
    go [] c = do
      when (null (cfgProjectRoot c)) (Left "Missing --project-root")
      when (null (cfgAgdaDir c))     (Left "Missing --agda-dir")
      when (null (cfgSrcDir c))      (Left "Missing --src-dir")
      when (null (cfgModulesFile c)) (Left "Missing --modules-file")
      when (null (cfgOutDir c))      (Left "Missing --out-dir")
      when (null (cfgAgdaJsonBin c)) (Left "Missing --agda-json")
      pure c

    go ("--no-resume":rest) c = go rest (c { cfgResume = False })
    go ("--project-root":v:rest) c = go rest (c { cfgProjectRoot = v })
    go ("--agda-dir":v:rest) c     = go rest (c { cfgAgdaDir = v })
    go ("--src-dir":v:rest) c      = go rest (c { cfgSrcDir = v })
    go ("--modules-file":v:rest) c = go rest (c { cfgModulesFile = v })
    go ("--out-dir":v:rest) c      = go rest (c { cfgOutDir = v })
    go ("--agda-json":v:rest) c    = go rest (c { cfgAgdaJsonBin = v })
    go ("--parallelism":v:rest) c  =
      case reads v of
        [(n,"")] -> go rest (c { cfgPar = max 1 n })
        _        -> Left ("Bad --parallelism: " <> v)
    go bad _ = Left ("Unrecognized args: " <> show (take 2 bad) <> "\n\n" <> usage)

readTopLevelModules :: FilePath -> IO [String]
readTopLevelModules fp = do
  txt <- readFile fp
  pure $
    [ l
    | l <- map trim (lines txt)
    , not (null l)
    , not ("#" `isPrefixOf` l)
    ]
  where
    trim = reverse . dropWhile (== ' ') . reverse . dropWhile (== ' ')

pathsFor :: Config -> String -> (FilePath, FilePath, FilePath)
pathsFor cfg m =
  ( cfgSrcDir cfg </> (m <> ".agda")
  , cfgOutDir cfg </> "jsonl" </> (m <> ".jsonl")
  , cfgOutDir cfg </> "logs" </> (m <> ".log")
  )

shouldSkip :: Bool -> FilePath -> IO Bool
shouldSkip resume out = do
  if not resume then pure False
  else do
    ex <- doesFileExist out
    if not ex then pure False
    else do
      sz <- getFileSize out
      pure (sz > 0)

runOne :: QSem -> Config -> String -> MVar ModuleRun -> IO ()
runOne sem cfg m outVar = do
  waitQSem sem
  let (inp, out, logp) = pathsFor cfg m
  _ <- try $ createDirectoryIfMissing True (takeDirectory out) :: IO (Either SomeException ())
  _ <- try $ createDirectoryIfMissing True (takeDirectory logp) :: IO (Either SomeException ())
  skip <- shouldSkip (cfgResume cfg) out

  if skip then do
    signalQSem sem
    putMVar outVar (ModuleRun m inp out logp True True Nothing 0.0)
  else do
    t0 <- getCurrentTime
    withFile logp AppendMode $ \hlog -> do
      let p = (proc (cfgAgdaJsonBin cfg)
                [ "--input", inp
                , "--output", out
                , "--include", cfgSrcDir cfg
                ])
                { cwd = Just (cfgProjectRoot cfg)
                , env = Just [ ("AGDA_DIR", cfgAgdaDir cfg) ]
                , std_out = UseHandle hlog
                , std_err = UseHandle hlog
                }
      ecp <- try (do
        (_, _, _, ph) <- createProcess p
        waitForProcess ph) :: IO (Either SomeException ExitCode)

      t1 <- getCurrentTime
      let secs = realToFrac (diffUTCTime t1 t0) :: Double

      let (ok, code) =
            case ecp of
              Right ExitSuccess     -> (True,  Just 0)
              Right (ExitFailure n) -> (False, Just n)
              Left _                -> (False, Nothing)

      signalQSem sem
      putMVar outVar (ModuleRun m inp out logp False ok code secs)

main :: IO ()
main = do
  args <- getArgs
  cfg  <- either (error . (<> "\n\n" <> usage)) pure (parseArgs args)

  createDirectoryIfMissing True (cfgOutDir cfg </> "jsonl")
  createDirectoryIfMissing True (cfgOutDir cfg </> "logs")

  mods <- readTopLevelModules (cfgModulesFile cfg)
  when (null mods) $ error ("No top-level modules found in: " <> cfgModulesFile cfg)

  started <- getCurrentTime
  sem <- newQSem (cfgPar cfg)

  vars <- mapM (const newEmptyMVar) mods
  forM_ (zip mods vars) $ \(m, v) ->
    void (forkIO (runOne sem cfg m v))

  rs <- mapM takeMVar vars

  finished <- getCurrentTime

  let manifest = RunManifest
        { startedAt   = show started
        , finishedAt  = show finished
        , projectRoot = cfgProjectRoot cfg
        , agdaDir     = cfgAgdaDir cfg
        , srcDir      = cfgSrcDir cfg
        , modulesFile = cfgModulesFile cfg
        , outDir      = cfgOutDir cfg
        , agdaJsonBin = cfgAgdaJsonBin cfg
        , parallelism = cfgPar cfg
        , resume      = cfgResume cfg
        , results     = rs
        }

  let outManifest = cfgOutDir cfg </> "run-manifest.json"
  writeFile outManifest (show (encode manifest))
  putStrLn ("[agda-json-runner] manifest: " <> outManifest)

  let bad = length (filter (not . ok) rs)
  if bad == 0 then pure () else error (show bad <> " module(s) failed")
