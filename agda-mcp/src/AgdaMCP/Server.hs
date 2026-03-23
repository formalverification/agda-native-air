-- | Server.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Server.hs
--
-- Description:
--   Minimal MCP stdio transport for agda-mcp; implements the subset of the Model
--   Context Protocol (MCP 2024-11-05) needed for tool-based interaction:
--
--   * @initialize@ / @initialized@ handshake
--   * @tools/list@ — enumerate available tools with JSON Schema parameters
--   * @tools/call@ — dispatch a tool invocation to the appropriate handler
--
--   Communication is line-delimited JSON-RPC 2.0 over stdin/stdout.
--
-- Design note:
--   We implement this by hand (~200 lines) rather than using the @mcp-server@
--   Hackage library because that library requires base >= 4.20 (GHC 9.10+),
--   and the project pins GHC 9.8.2 for Agda compatibility.  This module can
--   be replaced by @mcp-server@ once GHC versions converge.
--
-- M1-3 additions:
--   * Optional 'CorpusIndex' in 'ServerConfig' (loaded via @--corpus@ flag).
--   * Three search tools: search_by_name, search_by_type, get_dependencies.
--   * Search tools appear in tools/list only when a corpus is loaded.

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Server
  ( runServer
  , ServerConfig (..)
  ) where

import Control.Monad (when)
import Data.Aeson
  ( FromJSON (..), ToJSON (..), Value (..), (.:), (.:?), (.=)
  , decode, encode, object, withObject
  )
import qualified Data.Aeson as Aeson

import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8)
import qualified Data.Text as T
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Lazy.Char8 as LBS8

import System.IO (hFlush, hPutStrLn, hSetBuffering, stdin, stdout, stderr, BufferMode (..), isEOF)

import AgdaMCP.Agda (AgdaConfig)
import AgdaMCP.Tools.ProofState
import AgdaMCP.Tools.Search
import AgdaMCP.Types (CorpusIndex)

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

-- | ServerConfig: server-level configuration.
data ServerConfig = ServerConfig
  { scAgdaConfig  :: AgdaConfig
  , scServerName  :: Text
  , scVersion     :: Text
  , scCorpusIndex :: Maybe CorpusIndex
    -- ^ In-memory corpus index, loaded at startup via @--corpus@.
    --   When 'Nothing', search tools are not registered.
  } deriving (Show)


-- ---------------------------------------------------------------------------
-- JSON-RPC types (minimal, internal)
-- ---------------------------------------------------------------------------

data JsonRpcRequest = JsonRpcRequest
  { rpcId     :: Maybe Value    -- ^ May be absent for notifications.
  , rpcMethod :: Text
  , rpcParams :: Maybe Value
  } deriving (Show)

instance FromJSON JsonRpcRequest where
  parseJSON = withObject "JsonRpcRequest" $ \o ->
    JsonRpcRequest
      <$> o .:? "id"
      <*> o .:  "method"
      <*> o .:? "params"

mkResult :: Maybe Value -> Value -> Value
mkResult reqId result = object
  [ "jsonrpc" .= ("2.0" :: Text)
  , "id"      .= fromMaybe Null reqId
  , "result"  .= result
  ]

mkError :: Maybe Value -> Int -> Text -> Value
mkError reqId code msg = object
  [ "jsonrpc" .= ("2.0" :: Text)
  , "id"      .= fromMaybe Null reqId
  , "error"   .= object
      [ "code"    .= code
      , "message" .= msg
      ]
  ]


-- ---------------------------------------------------------------------------
-- Tool definitions (JSON Schema for tools/list)
-- ---------------------------------------------------------------------------

-- | Build the tool definitions list.
--
-- Proof-state tools are always available.
-- Search tools are only registered when a corpus is loaded.
toolDefinitions :: ServerConfig -> Value
toolDefinitions cfg = toJSON $ proofStateTools <> searchTools
  where
    proofStateTools =
      [ toolDef "get_goal"
          "Inspect the goal type and local context at a hole."
          [ prop "filePath"  "string" "Path to the Agda file (absolute or relative to cwd)."
          , prop "holeIndex" "integer" "0-based index of the {!!} hole."
          ]
          ["filePath", "holeIndex"]

      , toolDef "fill_hole"
          "Substitute a candidate term into a hole and typecheck."
          [ prop "filePath"  "string" "Path to the Agda file (absolute or relative to cwd)."
          , prop "holeIndex" "integer" "0-based index of the {!!} hole."
          , prop "candidate" "string" "The candidate proof term to try."
          ]
          ["filePath", "holeIndex", "candidate"]

      , toolDef "check_file"
          "Load/reload an Agda file and return all diagnostics."
          [ prop "filePath" "string" "Path to the Agda file (absolute or relative to cwd)."
          ]
          ["filePath"]

      , toolDef "get_diagnostics"
          "Retrieve diagnostic summary: error/warning counts, open holes."
          [ prop "filePath" "string" "Path to the Agda file (absolute or relative to cwd)."
          ]
          ["filePath"]
       ]
    searchTools
      | isJust (scCorpusIndex cfg) =
          [ toolDef "search_by_name"
              "Find definitions matching a name pattern (case-insensitive substring on qualified/unqualified name)."
              [ prop "pattern" "string" "Substring to search for in definition names."
              , prop "limit"   "integer" "Maximum number of results (default: 20)."
              ]
              ["pattern"]

          , toolDef "search_by_type"
              "Find definitions whose type signature contains the given pattern (case-insensitive substring match)."
              [ prop "pattern" "string" "Substring to search for in type signatures."
              , prop "limit"   "integer" "Maximum number of results (default: 20)."
              ]
              ["pattern"]

          , toolDef "get_dependencies"
              "Retrieve the dependency neighborhood of a definition. Returns dependency tokens and optionally expands them to full entries."
              [ prop "name"   "string"  "The prettyQname of the definition to look up."
              , prop "expand" "boolean" "If true, also return corpus entries for each dependency (1-hop neighborhood)."
              ]
              ["name"]
          ]
      | otherwise = []

-- | Build a tool definition object (MCP tools/list schema).
toolDef :: Text -> Text -> [(Text, Value)] -> [Text] -> Value
toolDef name desc props required = object
  [ "name"        .= name
  , "description" .= desc
  , "inputSchema" .= object
      [ "type"       .= ("object" :: Text)
      , "properties" .= object [ Key.fromText k .= v | (k, v) <- props ]
      , "required"   .= required
      ]
  ]

-- | Build a property definition for the input schema.
prop :: Text -> Text -> Text -> (Text, Value)
prop name typ desc = (name, object ["type" .= typ, "description" .= desc])


-- ---------------------------------------------------------------------------
-- Main server loop
-- ---------------------------------------------------------------------------

-- | runServer: run the MCP server on stdio.
--
-- Reads JSON-RPC requests from stdin and writes responses to stdout.
runServer :: ServerConfig -> IO ()
runServer cfg = do
  -- Ensure line buffering for correct MCP framing.
  hSetBuffering stdin  LineBuffering
  hSetBuffering stdout LineBuffering
  loop
  where
    loop = do
      eof <- isEOF
      if eof
        then hPutStrLn stderr "agda-mcp: stdin closed, shutting down."
        else do
          line <- LBS.fromStrict <$> BS8.hGetLine stdin
          when (not $ LBS.null line) $
            case decode line of
              Nothing -> sendResponse $ mkError Nothing (-32700) "Parse error"
              Just req -> do
                resp <- handleRequest cfg req
                case resp of
                  Just r  -> sendResponse r
                  Nothing -> pure ()
          loop

sendResponse :: Value -> IO ()
sendResponse v = do
  LBS8.putStrLn (encode v)
  hFlush stdout


-- | handleRequest: dispatcher
handleRequest :: ServerConfig -> JsonRpcRequest -> IO (Maybe Value)

-- Copilot suggested, "JSON-RPC notifications (requests without an id) must not
-- receive a response. Currently handleRequest will still return Just ... for methods
-- like tools/list / tools/call even when rpcId is Nothing, which can break strict
-- MCP clients. Consider returning Nothing whenever rpcId is Nothing (except the
-- parse-error case where id must be null)."
-- SEE: https://github.com/formalverification/agda-native-air/pull/38#discussion_r2969684715
--
-- Copilot is technically right that per JSON-RPC spec, notifications (no `id`)
-- should not get responses. In practice, MCP clients (Claude Code, Cursor) only send
-- notifications for `notifications/initialized` (which we already handle correctly
-- by returning `Nothing`). The risk of a client sending `tools/call` without an `id`
-- is essentially zero — that would be a client bug. The suggested refactor adds a
-- lot of boilerplate for no practical gain right now.

-- | MCP handshake: initialize
handleRequest cfg req | rpcMethod req == "initialize" = do
  let result = object
        [ "protocolVersion" .= ("2024-11-05" :: Text)
        , "capabilities"    .= object
            [ "tools" .= object []
            ]
        , "serverInfo" .= object
            [ "name"    .= scServerName cfg
            , "version" .= scVersion cfg
            ]
        ]
  pure . Just $ mkResult (rpcId req) result

-- MCP notification: initialized (no response)
handleRequest _ req | rpcMethod req == "notifications/initialized" =
  pure Nothing

-- MCP: tools/list
handleRequest cfg req | rpcMethod req == "tools/list" = do
  let result = object ["tools" .= toolDefinitions cfg]
  pure . Just $ mkResult (rpcId req) result

-- MCP: tools/call
handleRequest cfg req | rpcMethod req == "tools/call" = do
  let params = fromMaybe (Object mempty) (rpcParams req)
  case params of
    Object o -> do
      let toolName = case KM.lookup "name" o of
            Just (String n) -> n
            _               -> ""
          args = case KM.lookup "arguments" o of
            Just v  -> v
            Nothing -> Object mempty
      result <- dispatchTool cfg toolName args
      pure . Just $ mkResult (rpcId req) result
    _ ->
      pure . Just $ mkError (rpcId req) (-32602) "Invalid params"

-- Unrecognised method
handleRequest _ req =
  pure . Just $ mkError (rpcId req) (-32601) ("Method not found: " <> rpcMethod req)


-- ---------------------------------------------------------------------------
-- Tool dispatch
-- ---------------------------------------------------------------------------

-- | dispatchTool: route a tool call to the appropriate handler.
--
-- Proof-state tools delegate to AgdaMCP.Tools.ProofState (IO, calls Agda).
-- Search tools delegate to AgdaMCP.Tools.Search (pure, uses CorpusIndex).
dispatchTool :: ServerConfig -> Text -> Value -> IO Value

-- Proof-state tools (existing M1-2)
dispatchTool cfg "get_goal" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> eitherToMcp <$> handleGetGoal (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg "fill_hole" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> eitherToMcp <$> handleFillHole (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg "check_file" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> eitherToMcp <$> handleCheckFile (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg "get_diagnostics" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> eitherToMcp <$> handleGetDiagnostics (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

-- Search tools (new M1-3)
dispatchTool cfg "search_by_name" args =
  case scCorpusIndex cfg of
    Nothing  -> pure $ toolError "No corpus loaded.  Start the server with --corpus <path.jsonl>."
    Just idx ->
      case Aeson.fromJSON args of
        Aeson.Success p -> pure . eitherToMcp $ handleSearchByName idx p
        Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg "search_by_type" args =
  case scCorpusIndex cfg of
    Nothing  -> pure $ toolError "No corpus loaded.  Start the server with --corpus <path.jsonl>."
    Just idx ->
      case Aeson.fromJSON args of
        Aeson.Success p -> pure . eitherToMcp $ handleSearchByType idx p
        Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg "get_dependencies" args =
  case scCorpusIndex cfg of
    Nothing  -> pure $ toolError "No corpus loaded.  Start the server with --corpus <path.jsonl>."
    Just idx ->
      case Aeson.fromJSON args of
        Aeson.Success p -> pure . eitherToMcp $ handleGetDependencies idx p
        Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

-- Unknown tool
dispatchTool _ name _ =
  pure $ toolError ("Unknown tool: " <> name)


-- ---------------------------------------------------------------------------
-- MCP response helpers
-- ---------------------------------------------------------------------------

-- | Wrap an IO-based tool handler result (Either Text a) as an MCP content response.
eitherToMcp :: ToJSON a => Either Text a -> Value
eitherToMcp (Left err) = toolError err

eitherToMcp (Right a)  = object
  [ "content" .= [ object [ "type" .= ("text" :: Text)
                           , "text" .= decodeUtf8 (LBS.toStrict (encode (toJSON a)))
                           ] ]
  ]

toolError :: Text -> Value
toolError msg = object
  [ "content" .= [ object [ "type" .= ("text" :: Text)
                           , "text" .= msg
                           ] ]
  , "isError" .= True
  ]
