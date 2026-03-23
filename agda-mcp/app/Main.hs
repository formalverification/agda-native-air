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
--   agda-mcp [--agda-bin PATH] [--agda-flags "FLAG1 FLAG2 ..."]
--            [--corpus PATH]   [--timeout N] [--verbose]
--
-- M1-3 additions:
--   --corpus PATH   Load agda-strux JSONL corpus for search tools.
--                   Without this flag, search tools are not registered.

{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Monad (when)
import System.Environment (getArgs)
import System.Exit (exitFailure, exitSuccess)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

import AgdaMCP.Agda (AgdaConfig (..), defaultConfig)
import AgdaMCP.Corpus (loadCorpus)
import AgdaMCP.Server (ServerConfig (..), runServer)

-- | Parsed CLI options.  Separates Agda config from corpus path since
-- corpus loading happens before the server loop starts.
data CliOpts = CliOpts
  { cliAgdaConfig :: AgdaConfig
  , cliCorpusPath :: Maybe FilePath
  } deriving (Show)

defaultCliOpts :: CliOpts
defaultCliOpts = CliOpts
  { cliAgdaConfig = defaultConfig
  , cliCorpusPath = Nothing
  }


main :: IO ()
main = do
  args <- getArgs
  when ("--help" `elem` args) $ do
    putStrLn usage
    exitSuccess
  let opts = parseArgs args defaultCliOpts
      cfg  = cliAgdaConfig opts

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

  let serverCfg = ServerConfig
        { scAgdaConfig  = cfg
        , scServerName  = "agda-mcp"
        , scVersion     = "0.2.0"
        , scCorpusIndex = corpusIdx
        }

  hPutStrLn stderr $ "agda-mcp v0.2.0 starting (agda-bin: " <> agdaBin cfg <> ")"
  hPutStrLn stderr $ "  flags: " <> unwords (agdaFlags cfg)
  hPutStrLn stderr $ "  corpus: " <> maybe "(none)" id (cliCorpusPath opts)
  hPutStrLn stderr   "  transport: stdio"
  hPutStrLn stderr   "  Waiting for MCP client..."
  runServer serverCfg


-- | Minimal CLI argument parser.
--
-- Supports:
--   --agda-bin PATH       Override the agda binary path (default: "agda").
--   --agda-flags "..."    Space-separated Agda flags.
--   --corpus PATH         Load agda-strux JSONL corpus for search tools.
--   --timeout N           Timeout in seconds (default: 30).
--   --verbose             Emit debug output to stderr.
--   --help                Print usage and exit.
parseArgs :: [String] -> CliOpts -> CliOpts
parseArgs [] opts = opts
parseArgs ("--agda-bin" : path : rest) opts =
  parseArgs rest opts { cliAgdaConfig = (cliAgdaConfig opts) { agdaBin = path } }
parseArgs ("--agda-flags" : flags : rest) opts =
  parseArgs rest opts { cliAgdaConfig = (cliAgdaConfig opts) { agdaFlags = words flags } }
parseArgs ("--corpus" : path : rest) opts =
  parseArgs rest opts { cliCorpusPath = Just path }
parseArgs ("--timeout" : n : rest) opts = case readMaybe n of
  Just secs -> parseArgs rest opts { cliAgdaConfig = (cliAgdaConfig opts) { agdaTimeout = Just secs } }
  Nothing   -> parseArgs rest opts
parseArgs ("--verbose" : rest) opts =
  parseArgs rest opts { cliAgdaConfig = (cliAgdaConfig opts) { agdaVerbose = True } }
parseArgs ("--help" : _) _ = error usage
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
  , "  --agda-bin PATH       Path to the agda binary (default: agda)"
  , "  --agda-flags \"...\"    Space-separated Agda flags"
  , "  --corpus PATH         Load agda-strux JSONL corpus for search tools"
  , "  --timeout N           Typecheck timeout in seconds (default: 30)"
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
