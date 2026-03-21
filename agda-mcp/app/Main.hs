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
--           "args": ["--agda-flags", "-i agda --library-file=agda/libraries -l agda-dojang -l standard-library"]
--         }
--       }
--     }
--
-- Usage:
--   agda-mcp [--agda-bin PATH] [--agda-flags "FLAG1 FLAG2 ..."]
--

{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Monad (when)
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (getArgs)
import System.Exit (exitSuccess)
import System.IO (hPutStrLn, stderr)

import AgdaMCP.Agda (AgdaConfig (..), defaultConfig)
import AgdaMCP.Server (ServerConfig (..), runServer)


main :: IO ()
main = do
  args <- getArgs
  when ("--help" `elem` args) $ do
    putStrLn usage
    exitSuccess
  let cfg = parseArgs args defaultConfig
      serverCfg = ServerConfig
        { scAgdaConfig = cfg
        , scServerName = "agda-mcp"
        , scVersion    = "0.1.0"
        }
  hPutStrLn stderr $ "agda-mcp v0.1.0 starting (agda-bin: " <> agdaBin cfg <> ")"
  hPutStrLn stderr $ "  flags: " <> unwords (agdaFlags cfg)
  hPutStrLn stderr   "  transport: stdio"
  hPutStrLn stderr   "  Waiting for MCP client..."
  runServer serverCfg


-- | Minimal CLI argument parser.
--
-- Supports:
--   --agda-bin PATH       Override the agda binary path (default: "agda").
--   --agda-flags "..."    Space-separated Agda flags.
--   --timeout N           Timeout in seconds (default: 30).
--   --help                Print usage and exit.
parseArgs :: [String] -> AgdaConfig -> AgdaConfig
parseArgs [] cfg = cfg
parseArgs ("--agda-bin" : path : rest) cfg =
  parseArgs rest cfg { agdaBin = path }
parseArgs ("--agda-flags" : flags : rest) cfg =
  parseArgs rest cfg { agdaFlags = words flags }
parseArgs ("--timeout" : n : rest) cfg =
  parseArgs rest cfg { agdaTimeout = Just (read n) }
parseArgs (unknown : rest) cfg =
  -- do
  parseArgs rest cfg
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
  , "  --timeout N           Typecheck timeout in seconds (default: 30)"
  , "  --help                Show this help"
  , ""
  , "The server reads JSON-RPC (MCP) from stdin and writes to stdout."
  ]
