-- | File: agda-native-air/agda-mcp/src/AgdaMCP/Server.hs
--
-- Minimal MCP stdio transport for agda-mcp.
--
-- Implements the subset of the Model Context Protocol (MCP 2024-11-05)
-- needed for tool-based interaction:
--
--   * @initialize@ / @initialized@ handshake
--   * @tools/list@ — enumerate available tools with JSON Schema parameters
--   * @tools/call@ — dispatch a tool invocation to the appropriate handler
--
-- Communication is line-delimited JSON-RPC 2.0 over stdin/stdout.
--
-- Design note:
--   We implement this by hand (~200 lines) rather than using the @mcp-server@
--   Hackage library because that library requires base >= 4.20 (GHC 9.10+),
--   and the project pins GHC 9.8.2 for Agda compatibility.  This module can
--   be replaced by @mcp-server@ once GHC versions converge.

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Server
  ( runServer
  , ServerConfig (..)
  ) where

import Control.Monad (forever, when)
import Data.Aeson
  ( FromJSON (..), ToJSON (..), Value (..), (.:), (.:?), (.=)
  , decode, encode, object, withObject
  )
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Lazy.Char8 as LBS8
import System.IO (hFlush, hSetBuffering, stdin, stdout, BufferMode (..))

import AgdaMCP.Agda (AgdaConfig)
import AgdaMCP.Types
import AgdaMCP.Tools.ProofState


-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

-- | Server-level configuration.
data ServerConfig = ServerConfig
  { scAgdaConfig :: AgdaConfig
  , scServerName :: Text
  , scVersion    :: Text
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

toolDefinitions :: Value
toolDefinitions = toJSON
  [ toolDef "get_goal"
      "Inspect the goal type and local context at a hole."
      [ prop "filePath"  "string" "Absolute path to the Agda file."
      , prop "holeIndex" "integer" "0-based index of the {!!} hole."
      ]
      ["filePath", "holeIndex"]

  , toolDef "fill_hole"
      "Substitute a candidate term into a hole and typecheck."
      [ prop "filePath"  "string" "Absolute path to the Agda file."
      , prop "holeIndex" "integer" "0-based index of the {!!} hole."
      , prop "candidate" "string" "The candidate proof term to try."
      ]
      ["filePath", "holeIndex", "candidate"]

  , toolDef "check_file"
      "Load/reload an Agda file and return all diagnostics."
      [ prop "filePath" "string" "Absolute path to the Agda file."
      ]
      ["filePath"]

  , toolDef "get_diagnostics"
      "Retrieve diagnostic summary: error/warning counts, open holes."
      [ prop "filePath" "string" "Absolute path to the Agda file."
      ]
      ["filePath"]
  ]

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

-- | Run the MCP server on stdio.  Blocks forever, reading JSON-RPC
-- requests from stdin and writing responses to stdout.
runServer :: ServerConfig -> IO ()
runServer cfg = do
  -- Ensure line buffering for correct MCP framing.
  hSetBuffering stdin  LineBuffering
  hSetBuffering stdout LineBuffering
  forever $ do
    line <- LBS.fromStrict <$> BS8.hGetLine stdin
    when (not $ LBS.null line) $
      case decode line of
        Nothing  -> do
          -- Malformed JSON — send a parse error.
          let resp = mkError Nothing (-32700) "Parse error"
          sendResponse resp
        Just req -> do
          resp <- handleRequest cfg req
          case resp of
            Just r  -> sendResponse r
            Nothing -> pure ()  -- Notification — no response.

sendResponse :: Value -> IO ()
sendResponse v = do
  LBS8.putStrLn (encode v)
  hFlush stdout


-- ---------------------------------------------------------------------------
-- Request dispatch
-- ---------------------------------------------------------------------------

handleRequest :: ServerConfig -> JsonRpcRequest -> IO (Maybe Value)

-- MCP handshake: initialize
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
handleRequest _ req | rpcMethod req == "tools/list" = do
  let result = object ["tools" .= toolDefinitions]
  pure . Just $ mkResult (rpcId req) result

-- MCP: tools/call
handleRequest cfg req | rpcMethod req == "tools/call" = do
  let acfg    = scAgdaConfig cfg
      params  = fromMaybe (Object mempty) (rpcParams req)
  case params of
    Object o -> do
      let toolName = case KM.lookup "name" o of
            Just (String n) -> n
            _               -> ""
          args = case KM.lookup "arguments" o of
            Just v  -> v
            Nothing -> Object mempty
      result <- dispatchTool acfg toolName args
      pure . Just $ mkResult (rpcId req) result
    _ ->
      pure . Just $ mkError (rpcId req) (-32602) "Invalid params"

-- Unrecognised method
handleRequest _ req =
  pure . Just $ mkError (rpcId req) (-32601) ("Method not found: " <> rpcMethod req)


-- ---------------------------------------------------------------------------
-- Tool dispatch
-- ---------------------------------------------------------------------------

dispatchTool :: AgdaConfig -> Text -> Value -> IO Value
dispatchTool cfg "get_goal" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> eitherToMcp <$> handleGetGoal cfg p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg "fill_hole" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> eitherToMcp <$> handleFillHole cfg p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg "check_file" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> eitherToMcp <$> handleCheckFile cfg p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg "get_diagnostics" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> eitherToMcp <$> handleGetDiagnostics cfg p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool _ name _ =
  pure $ toolError ("Unknown tool: " <> name)

-- | Wrap a tool handler result as an MCP tool response.
eitherToMcp :: ToJSON a => Either Text a -> Value
eitherToMcp (Left err) = toolError err
eitherToMcp (Right a)  = object
  [ "content" .= [ object [ "type" .= ("text" :: Text)
                           , "text" .= show (toJSON a)
                           ] ]
  ]

toolError :: Text -> Value
toolError msg = object
  [ "content" .= [ object [ "type" .= ("text" :: Text)
                           , "text" .= msg
                           ] ]
  , "isError" .= True
  ]
