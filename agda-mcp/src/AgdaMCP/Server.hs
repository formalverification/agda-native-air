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
    -- * Exposed for testing
  , toolDefinitions
  ) where

import Control.Exception (SomeException, try, throwIO, fromException, AsyncException)
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
import AgdaMCP.Types (CorpusIndex, ToolFailure (..))

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

-- | ServerConfig: server-level configuration.
--
-- M1-4: the server loop is now crash-proof — uncaught exceptions in tool
-- handlers are caught and returned as JSON-RPC error responses.
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
    -- The hole model shared by all four tool descriptions (issues #71/#73):
    -- every Agda hole syntax is enumerated, comments and prose never count,
    -- and positions/indices are coordinates in the file as written.
    holeModel =
      "FILE FLAVOURS AND HOLES: plain .agda plus every literate flavour Agda \
      \2.8 supports (.lagda, .lagda.tex, .lagda.md, .lagda.typ, .lagda.rst, \
      \.lagda.org, .lagda.tree), recognized by extension and scanned in their \
      \code regions only, with positions reported in literate-file \
      \coordinates. Holes are enumerated in source order across every Agda \
      \hole syntax ({!!}, {! ... !} with nesting, and standalone ?); tokens \
      \inside comments, string literals, or literate prose are never holes."

    proofStateTools =
      [ toolDef "get_goal"
          ("Inspect the goal type and local context at a hole. Injects a \
           \reporting macro over the addressed hole, typechecks the patched \
           \file in place, reads the goal back from the macro's output, and \
           \restores the file byte for byte. "
           <> holeAddressing
           <> " "
           <> verdictNote
           <> " For this tool verdict.exitCode is normally NON-ZERO even when \
              \the goal is correct, because the injected macro leaves an \
              \interaction point behind: it is evidence about the introspection \
              \run, not a judgement on your file — use check_file for that."
           <> " Returns elapsedMs and checkedFromSource; " <> latencyNote
           <> " On timeout this returns an error whose text is a JSON object —"
           <> " {error, timedOut: true, elapsedMs, checkedFromSource?, verdict,"
           <> " command, project} — naming the bound, since no goal was reported. "
           <> holeModel)
          [ prop "filePath"  "string"  "Path to the Agda file (absolute or relative to cwd)."
          , prop "line"      "integer" lineDoc
          , prop "column"    "integer" columnDoc
          , prop "col"       "integer" colDoc
          , prop "holeIndex" "integer" holeIndexDoc
          ]
          ["filePath"]

      , toolDef "fill_hole"
          ("Substitute a candidate term into a hole (replacing the hole's \
           \actual span), typecheck the patched file in place, and restore it \
           \byte for byte. "
           <> holeAddressing
           <> " "
           <> verdictNote
           <> " status is \"ok\" if and only if that command exits 0, or fails \
              \with nothing but [UnsolvedInteractionMetas] — holes still open \
              \in the file, including any new sub-hole inside the candidate, \
              \which is a successful refinement. EVERY other failure is \
              \\"type_error\", including [UnsolvedMetaVariables] and \
              \[UnsolvedConstraints]: a candidate that leaves a meta unsolved \
              \does not pass the build and is not ok here either. A run killed \
              \by --timeout is \"timeout\" (the candidate was never judged, and \
              \the file is still restored); an agda binary that could not be \
              \started is \"crash\"."
           <> " EVERY response carries holes: the full hole list of the file AS \
              \THIS CANDIDATE LEAVES IT — [{index, line, col, goal}], one entry \
              \per remaining hole, remainingHoles being its length — so you \
              \re-anchor on the next hole's position without a second call. \
              \Because the file on disk is restored, those coordinates are the \
              \ones you get once you write the candidate back; until you do, \
              \the file still has the holes it started with. The hole address, \
              \holes, and remainingHoles all cover every hole syntax."
           <> " Returns elapsedMs and checkedFromSource; " <> latencyNote
           <> " "
           <> holeModel)
          [ prop "filePath"  "string"  "Path to the Agda file (absolute or relative to cwd)."
          , prop "line"      "integer" lineDoc
          , prop "column"    "integer" columnDoc
          , prop "col"       "integer" colDoc
          , prop "holeIndex" "integer" holeIndexDoc
          , prop "candidate" "string"  "The candidate proof term to try."
          ]
          ["filePath", "candidate"]

      , toolDef "check_file"
          ("Typecheck one Agda file and return all diagnostics. "
           <> verdictNote
           <> " " <> batchNote
           <> " " <> diagnosticModel
           <> " holes lists every open hole as {index, line, col, goal} \
              \(holesCount is its length); (line, col) is the stable handle to \
              \pass back to get_goal and fill_hole."
           <> " Returns elapsedMs and checkedFromSource; " <> latencyNote
           <> " On timeout it returns success:false with timedOut:true and an \"agda timed out after Ns\" error diagnostic. "
           <> holeModel)
          [ prop "filePath" "string" "Path to the Agda file (absolute or relative to cwd)."
          , prop "maxDiagnostics" "integer" maxDiagnosticsDoc
          ]
          ["filePath"]

      , toolDef "get_diagnostics"
          ("Typecheck one Agda file and return a summary: error/warning counts, \
           \the diagnostics behind them, and each open hole's index and \
           \(line, col) position — that (line, col) being the stable handle to \
           \pass back to get_goal and fill_hole. "
           <> verdictNote
           <> " " <> batchNote
           <> " success and verdict are the same fields check_file returns, with \
              \the same meaning; the two tools differ in what they summarize, \
              \never in what green means. The counts come from parsing Agda's \
              \prose and can drift with its message format, which is precisely \
              \why success is not read from them."
           <> " " <> diagnosticModel
           <> " The errors and warnings counts are over every diagnostic found, \
              \not over the (capped) diagnostics list."
           <> " Returns elapsedMs and checkedFromSource; " <> latencyNote
           <> " On timeout it returns success:false with timedOut:true and an \"agda timed out after Ns\" error diagnostic. "
           <> holeModel)
          [ prop "filePath" "string" "Path to the Agda file (absolute or relative to cwd)."
          , prop "maxDiagnostics" "integer" maxDiagnosticsDoc
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

-- | holeAddressing: how to name the hole you mean, in the two tools that take
-- one (issue #79).
--
-- The description is where the contract lives (the § 6 meta-suggestion of the
-- feedback document), and the contract worth stating here is not "two
-- parameters are available" but "one of them is stable and the other is not".
-- An agent that reads only this must come away addressing holes by position;
-- § 3.8 records what the other habit costs, and verification found it costs
-- more than stated, since a miscounted decoy could put "the first hole" inside
-- a comment.
holeAddressing :: Text
holeAddressing =
  "ADDRESSING A HOLE: pass EITHER (line, column) — 1-based coordinates in the \
  \file as written, literate-file coordinates for a literate source, exactly \
  \what get_diagnostics.holes, check_file.holes, and every fill_hole response's \
  \holes list report — OR holeIndex. PREFER THE POSITION. It names the hole \
  \itself, so it still names it after any other hole is filled, whereas \
  \holeIndex is a 0-based index into the source-order hole list and every index \
  \after a filled hole shifts down by one: an index cached across calls \
  \silently addresses a different hole. A position addresses the hole whose \
  \span contains it (a position at its first character counts); a position \
  \inside no hole is an error listing the file's nearest holes, never a guess. \
  \Give one spelling or the other — a request carrying both is rejected, \
  \because the two can disagree. col is accepted as a synonym for column, so a \
  \hole entry can be passed straight back."

-- | lineDoc / columnDoc / colDoc / holeIndexDoc: the same contract at the input
-- properties, where a client decides what to send.
--
-- @col@ is declared as a property of its own rather than merely mentioned in
-- @columnDoc@, because a client that validates its arguments against the schema
-- sees only what the schema declares: an accepted key the schema omits is one a
-- careful client will refuse to send (a Copilot review catch on PR #99).
lineDoc :: Text
lineDoc =
  "1-based line of the hole, in the file as written (literate-file coordinates \
  \for literate sources). Requires column (or its synonym col). The stable way \
  \to address a hole: unlike holeIndex, it survives a fill elsewhere in the file."

columnDoc :: Text
columnDoc =
  "1-based column of the hole, in the file as written. Requires line. The key \
  \col is accepted as a synonym; sending both spellings is fine only if they \
  \agree."

colDoc :: Text
colDoc =
  "Synonym for column, accepted because that is the key the hole listings spell \
  \it with — so a hole entry from get_diagnostics, check_file, or a fill_hole \
  \response can be passed back without renaming anything. Requires line; if \
  \column is given too, the two must agree."

holeIndexDoc :: Text
holeIndexDoc =
  "0-based index of the hole, in source order (any hole syntax). Accepted for \
  \backward compatibility and SHIFT-PRONE: filling a hole renumbers every hole \
  \after it, so an index from an earlier call may now name a different hole. \
  \Prefer (line, column). Give one or the other, never both."

-- | diagnosticModel: the shape of a diagnostic, stated where the client reads
-- it (issue #74).
--
-- An agent decides whether to parse prose or branch on a field by reading the
-- tool's description and nothing else — the § 6 meta-suggestion of the feedback
-- document — so a @code@ and a @range@ the description does not mention may as
-- well not exist.
diagnosticModel :: Text
diagnosticModel =
  "Each diagnostic is structured: severity, code (Agda's own name, e.g. \
  \NotInScope / AmbiguousName / UnsolvedMetaVariables — branch on this rather \
  \than matching prose), file, range {startLine, startCol, endLine, endCol} in \
  \1-based coordinates of the file as written, the bounded full message body, \
  \and involved {expected?, actual?, candidates?, metaTypes?} naming what the \
  \message is about (the mismatched types, the \"did you mean\" or ambiguity \
  \candidates, the missing exports, the origin of a clashing definition, or one \
  \entry per unsolved meta or constraint). line and col are kept as aliases of \
  \the range start. Diagnostics are ordered most-likely-root-cause first — \
  \unresolvable-file errors, then scope warnings that precede a hard error \
  \(e.g. ModuleDoesntExport before the NotInScope it causes), then scope \
  \errors, type errors, and unsolved metas — and identical repeats are \
  \collapsed."

-- | maxDiagnosticsDoc: the cap's contract, in the input schema where a client
-- decides what to pass.
maxDiagnosticsDoc :: Text
maxDiagnosticsDoc =
  "Maximum diagnostics to return (default 10; 0 means no limit). \
  \diagnosticsTotal always reports how many were found before the cap, so a \
  \truncated list is never mistaken for a short one."

-- | verdictNote: the response-echo contract, stated in every proof-state tool
-- description (issues #72 and #76).
--
-- The § 6 meta-suggestion of the field report is that an agent picks a tool by
-- reading its description and nothing else, and that the shipped descriptions
-- did not say the one thing that decides whether the tool is worth calling:
-- whether a green result means the build passes.  These three sentences say it,
-- and say where in the response to check it.
verdictNote :: Text
verdictNote =
  "EVERY response carries the echo: verdict {equivalentTo, meaning, exitCode} —"
  <> " the exact agda command this call is equivalent to, what its verdict field"
  <> " means, and agda's own exit code, which the verdict is derived from and"
  <> " never from parsing Agda's message text; command {binary, args, cwd} — the"
  <> " resolved command line; and project {rootSource, root, library,"
  <> " librariesFile, registeredLibraries, selectedLibraries, includePaths} — the"
  <> " tree that was actually checked, with selectedLibraries and includePaths as"
  <> " agda finally received them, so project and command.args never disagree."
  <> " rootSource is \"nearest-agda-lib\" when the"
  <> " requested file's own *.agda-lib decided the context and \"server-config\""
  <> " when the flags fixed at server start did. If the file belongs to a"
  <> " different checkout of a library this server has registered elsewhere, the"
  <> " call FAILS with a rootMismatch object naming both roots rather than"
  <> " quietly checking the other tree — with one limit worth knowing: that"
  <> " detection compares against the libraries registry, so if the configured"
  <> " one is missing there is nothing to compare against and no mismatch can be"
  <> " found. The response says so as project.librariesFileMissing."

-- | batchNote: what success means for the two whole-file tools.
--
-- Stated once, verbatim from 'AgdaMCP.Tools.ProofState.batchVerdictMeaning' in
-- substance: this server shells out to batch @agda@ per call, and its verdict is
-- that command's verdict.
batchNote :: Text
batchNote =
  "success is true if and only if that agda command exits 0, so it means exactly"
  <> " what green means in a batch build: unsolved metavariables, unsolved"
  <> " constraints, and open holes all make agda exit non-zero and so make"
  <> " success false. There is no interaction mode anywhere in this server, and"
  <> " no --safe-style leniency to opt into: the default already is the strict"
  <> " gate."

-- | latencyNote: the shared latency/timeout sentence appended to every
-- proof-state tool description.
--
-- Agents plan around a tool's advertised cost, so the cold-subprocess model has
-- to be stated where they will read it: each call is a fresh @agda@ process, and
-- the only warmth available comes from Agda's own @.agdai@ interface files, not
-- from any caching in this server.  @checkedFromSource@ in the response says
-- which of the two happened on that call.
latencyNote :: Text
latencyNote =
  "each call spawns a cold agda subprocess (no warm session), so a first check of a"
  <> " large library builds its .agdai interfaces and can take minutes, while later"
  <> " calls that reuse those interfaces are far faster."
  <> " Calls are bounded by the server's --timeout (default 300s)."
  <> " checkedFromSource is omitted when the run died before producing evidence"
  <> " either way (e.g. a startup failure, or a timeout before any output)."

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
-- All request handling is wrapped in 'try' so that no exception can kill the loop.
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
                result <- try (handleRequest cfg req)
                case result of
                  Left (e :: SomeException) ->
                    case fromException e of
                      Just ae -> throwIO (ae :: AsyncException)
                      Nothing -> do
                        hPutStrLn stderr $
                          "agda-mcp: uncaught exception handling "
                          <> T.unpack (rpcMethod req) <> ": " <> show e
                        sendResponse $ mkError (rpcId req) (-32603)
                          "Internal error"
                  Right (Just r)  -> sendResponse r
                  Right Nothing   -> pure ()
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
    Aeson.Success p -> failureToMcp <$> handleGetGoal (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg "fill_hole" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp <$> handleFillHole (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg "check_file" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp <$> handleCheckFile (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg "get_diagnostics" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp <$> handleGetDiagnostics (scAgdaConfig cfg) p
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
eitherToMcp = either toolError okToMcp

-- | As 'eitherToMcp', for handlers whose failures are structured 'ToolFailure's
-- — which, since issue #76, is all four proof-state tools.
--
-- A 'FailMessage' renders exactly as it always did — prose with @isError@ —
-- while 'FailTimeout' and 'FailProject' serialize their payload as the error
-- text.  That is what lets a timed-out call still deliver its timing and cache
-- metadata (issue #77), and a wrong-tree refusal still deliver both roots as
-- data rather than as a sentence the client would have to parse (issue #76).
failureToMcp :: ToJSON a => Either ToolFailure a -> Value
failureToMcp = either render okToMcp
  where
    render (FailMessage msg) = toolError msg
    render (FailTimeout tf)  = structuredError (toJSON tf)
    render (FailProject pm)  = structuredError (toJSON pm)

    structuredError payload = object
      [ "content" .= [ object [ "type" .= ("text" :: Text)
                               , "text" .= decodeUtf8 (LBS.toStrict (encode payload))
                               ] ]
      , "isError" .= True
      ]

-- | The success shape shared by every tool: one text content item holding the
-- result's JSON.
okToMcp :: ToJSON a => a -> Value
okToMcp a = object
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
