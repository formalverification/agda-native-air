-- | Main.hs
--
-- File: agda-native-air/agda-mcp/app/Main.hs
--
-- Description:
--   Entry point for the agda-mcp MCP server.
--   Parses command-line options and starts the MCP server on stdio transport.
--
--   The server reads JSON-RPC requests from stdin and writes responses to stdout.
--   Configure it as an MCP server in Claude Code (or Cursor, etc.) by pointing
--   the MCP client at this binary.
--
--   Example claude_desktop_config.json:
--     {
--       "mcpServers": {
--         "agda": {
--           "command": "agda-mcp",
--           "args": ["--agda-flags", "...", "--corpus", "data/agda-algebras.jsonl"]
--         }
--       }
--     }
--
-- Usage:
--   agda-mcp [--cwd DIR]      [--agda-bin PATH] [--agda-flags "FLAG1 FLAG2 ..."]
--            [--corpus PATH]  [--timeout N] [--verbose]
--            [--check-command "CMD ARGS ..."] [--check-timeout N]
--
-- M1-3 additions:
--   --corpus PATH   Load agda-strux JSONL corpus for search tools.
--                   Without this flag, search tools are not registered.

{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Exception (IOException, try)
import Control.Monad (when)
import System.Directory (getCurrentDirectory, setCurrentDirectory)
import System.Environment (getArgs)
import System.Exit (exitFailure, exitSuccess)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

import AgdaMCP.Agda (AgdaConfig (..), defaultConfig, defaultTimeoutSeconds)
import AgdaMCP.Corpus (loadCorpus)
import AgdaMCP.Gate
  (GateConfig (..), defaultCheckTimeoutSeconds, defaultGateConfig)
import AgdaMCP.Server (ServerConfig (..), runServer)

-- | Parsed CLI options.  Separates Agda config from corpus path since
-- corpus loading happens before the server loop starts.
data CliOpts = CliOpts
  { cliAgdaConfig :: AgdaConfig
  , cliGateConfig :: GateConfig
  , cliCorpusPath :: Maybe FilePath
  , cliCwd        :: Maybe FilePath
  } deriving (Show)

defaultCliOpts :: CliOpts
defaultCliOpts = CliOpts
  { cliAgdaConfig = defaultConfig
  , cliGateConfig = defaultGateConfig
  , cliCorpusPath = Nothing
  , cliCwd        = Nothing
  }


main :: IO ()
main = do
  args <- getArgs
  when ("--help" `elem` args) $ do
    putStrLn usage
    exitSuccess
  let opts = parseArgs args defaultCliOpts
      cfg  = cliAgdaConfig opts

  -- Enter --cwd before anything else touches a path: the corpus below, every
  -- relative client path (they resolve against this directory — AgdaMCP.Path's
  -- published rule), the gate discovery, and Agda itself, whose own project
  -- discovery (the nearest *.agda-lib) anchors to the directory it is spawned
  -- in.  That last one is what the flag exists for: a server checking a client
  -- project with the client's own agda must run that agda inside the client's
  -- checkout, or Agda resolves the file against no project at all (issue #103).
  -- A directory we cannot enter is a fatal configuration error, reported by
  -- name rather than discovered one bewildering tool failure at a time.
  case cliCwd opts of
    Nothing  -> pure ()
    Just dir -> do
      entered <- try (setCurrentDirectory dir) :: IO (Either IOException ())
      case entered of
        Left err -> do
          hPutStrLn stderr $ "agda-mcp: cannot enter --cwd " <> dir <> ": " <> show err
          exitFailure
        Right () -> pure ()

  -- Load corpus if --corpus was provided.
  corpusIdx <- case cliCorpusPath opts of
    Nothing   -> do
      hPutStrLn stderr "agda-mcp: no --corpus flag; search tools disabled."
      pure Nothing
    Just path -> do
      result <- loadCorpus path
      case result of
        Left err -> do
          hPutStrLn stderr $ "agda-mcp: ERROR loading corpus: " <> show err
          exitFailure
        Right idx -> pure (Just idx)

  let gateCfg = cliGateConfig opts
      serverCfg = ServerConfig
        { scAgdaConfig  = cfg
        , scGateConfig  = gateCfg
        , scServerName  = "agda-mcp"
        , scVersion     = "0.2.0"
        , scCorpusIndex = corpusIdx
        }

  cwdNow <- getCurrentDirectory
  hPutStrLn stderr $ "agda-mcp v0.2.0 starting (agda-bin: " <> agdaBin cfg <> ")"
  hPutStrLn stderr $ "  cwd: " <> cwdNow
  hPutStrLn stderr $ "  flags: " <> unwords (agdaFlags cfg)
  hPutStrLn stderr $ "  timeout: " <> case agdaTimeout cfg of
    Just n | n > 0 -> show n <> "s per agda call"
    _              -> "(none)"
  hPutStrLn stderr $ "  project gate: " <> case gcCommand gateCfg of
    Just cmd@(_ : _) -> unwords cmd
    _                -> "(discovered: nearest Makefile 'check' target, else Everything module)"
  hPutStrLn stderr $ "  check timeout: " <> case gcTimeout gateCfg of
    Just n | n > 0 -> show n <> "s per project check"
    _              -> "(none)"
  hPutStrLn stderr $ "  corpus: " <> maybe "(none)" id (cliCorpusPath opts)
  hPutStrLn stderr   "  transport: stdio"
  hPutStrLn stderr   "  Waiting for MCP client..."
  runServer serverCfg


-- | Minimal CLI argument parser.
--
-- Supports:
--   --cwd DIR             Working directory to enter before anything else.
--   --agda-bin PATH       Override the agda binary path (default: "agda").
--   --agda-flags "..."    Space-separated Agda flags.
--   --corpus PATH         Load agda-strux JSONL corpus for search tools.
--   --timeout N           Per-typecheck timeout in seconds (default: 300; 0 = none).
--   --check-command "..." The project gate check_project runs (no shell).
--   --check-timeout N     Per-project-check timeout in seconds (default: 1800; 0 = none).
--   --verbose             Emit debug output to stderr.
--   --help                Print usage and exit.
parseArgs :: [String] -> CliOpts -> CliOpts
parseArgs [] opts = opts
parseArgs ("--cwd" : dir : rest) opts =
  parseArgs rest opts { cliCwd = Just dir }
parseArgs ("--agda-bin" : path : rest) opts =
  parseArgs rest opts { cliAgdaConfig = (cliAgdaConfig opts) { agdaBin = path } }
parseArgs ("--agda-flags" : flags : rest) opts =
  parseArgs rest opts { cliAgdaConfig = (cliAgdaConfig opts) { agdaFlags = words flags } }
parseArgs ("--corpus" : path : rest) opts =
  parseArgs rest opts { cliCorpusPath = Just path }
parseArgs ("--timeout" : n : rest) opts = case readMaybe n of
  Just secs -> parseArgs rest opts { cliAgdaConfig = (cliAgdaConfig opts) { agdaTimeout = Just secs } }
  Nothing   -> parseArgs rest opts
-- The project gate (issue #78).  The command is split on whitespace and run
-- directly, with no shell: a gate this server puts a wrapper around is a gate
-- whose exit code this server could mask, which is the one thing check_project
-- exists not to do.
parseArgs ("--check-command" : cmd : rest) opts =
  parseArgs rest opts { cliGateConfig = (cliGateConfig opts) { gcCommand = Just (words cmd) } }
parseArgs ("--check-timeout" : n : rest) opts = case readMaybe n of
  Just secs -> parseArgs rest opts { cliGateConfig = (cliGateConfig opts) { gcTimeout = Just secs } }
  Nothing   -> parseArgs rest opts
parseArgs ("--verbose" : rest) opts =
  parseArgs rest opts { cliAgdaConfig = (cliAgdaConfig opts) { agdaVerbose = True } }
parseArgs (_ : rest) opts = parseArgs rest opts
  -- -- Skip unknown flags with a warning (lenient for forward-compat).
  -- where _ = hPutStrLn stderr $ "agda-mcp: ignoring unknown flag: " <> unknown
  -- --        ^ NOTE: this is a dead binding inside a pure function; it compiles but the
  -- --        warning is never emitted (it's a thunk bound to `_`, never forced).
  -- --        Copilot's suggestion of just silently skipping is fine for v0. A cleaner
  -- --        approach would be to return `IO AgdaConfig`, but that's more refactoring
  -- --        than we need right now.

usage :: String
usage = unlines
  [ "agda-mcp — MCP server for AI-assisted Agda proof development"
  , ""
  , "Usage: agda-mcp [OPTIONS]"
  , ""
  , "Options:"
  , "  --cwd DIR             Working directory to enter before anything else."
  , "                        Every later relative path — --corpus, client file"
  , "                        paths, gate discovery — resolves inside it, and the"
  , "                        checking agda runs there, so Agda's own project"
  , "                        discovery (the nearest *.agda-lib) anchors to it."
  , "                        Set it to the client project's checkout root when"
  , "                        this server checks a project it is not started in."
  , "  --agda-bin PATH       Path to the agda binary (default: agda)"
  , "  --agda-flags \"...\"    Space-separated Agda flags"
  , "  --corpus PATH         Load agda-strux JSONL corpus for search tools"
  , "  --timeout N           Per-typecheck timeout in seconds (default: "
                             <> show defaultTimeoutSeconds <> "; 0 = no limit)"
  , "                        Each tool call is a cold agda subprocess, so the"
  , "                        first check of a large library builds its .agdai"
  , "                        interfaces and can take minutes — size this for that"
  , "                        cold build, not for the warm steady state."
  , "  --check-command \"...\" The project's acceptance gate, for check_project."
  , "                        Split on whitespace and run DIRECTLY, with no shell"
  , "                        — so it cannot contain a pipeline or a redirect, and"
  , "                        nothing this server puts around your gate can mask"
  , "                        its exit code.  Without it, check_project discovers"
  , "                        the nearest Makefile's 'check' target, else the"
  , "                        project's Everything module."
  , "  --check-timeout N     Timeout for one check_project run, in seconds"
  , "                        (default: " <> show defaultCheckTimeoutSeconds
                             <> "; 0 = no limit).  Separate from --timeout,"
  , "                        because a whole-project gate legitimately runs for"
  , "                        tens of minutes."
  , "  --verbose             Emit debug output to stderr"
  , "  --help                Show this help"
  , ""
  , "The server reads JSON-RPC (MCP) from stdin and writes to stdout."
  , ""
  , "When --corpus is provided, three additional tools are registered:"
  , "  search_by_name      Find definitions by name pattern"
  , "  search_by_type      Find definitions by type signature pattern"
  , "  get_dependencies    Retrieve the dependency neighborhood of a definition"
  ]
