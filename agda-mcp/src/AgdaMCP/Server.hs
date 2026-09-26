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
--
-- Issue #17 addition (M2-3, phase 1):
--   * search_in_scope, the fourth corpus tool: scope-aware retrieval whose
--     every returned rendering the interaction lane has typed in the queried
--     file's scope.  Registered with the other three behind @--corpus@, and
--     the one corpus tool that also takes the lanes.
--
-- Issue #78 addition:
--   * check_project — the whole-project gate.  Always registered, and the one
--     tool that reads 'scGateConfig' as well as 'scAgdaConfig'.  Its call
--     blocks for the duration of the gate: this transport is a synchronous line
--     loop with no progress-notification plumbing, so streaming progress is
--     follow-on scope rather than something the framing already supports.
--
-- Issue #184 addition:
--   * Lean answers by default.  Every successful answer is written out through
--     'okToMcp' at the call's verbosity ('AgdaMCP.Types.answerAt'): without the
--     @command@ block and without the parts of @verdict@, @project@, and @lane@
--     that every answer repeated, unless the call passes @verbose: true@.  The
--     eleven tools whose answers carry an echo declare @verbose@ in their input
--     schemas, and their descriptions say what the lean answer keeps and what
--     the full echo adds.
--   * exports_of answers one page of a module's surface: @limit@, @offset@,
--     and @pattern@ in its schema, @total@ / @truncated@ / @nextOffset@ /
--     @remaining@ in its answer.
--
-- Issue #191 additions:
--   * A smaller tool surface.  What every tool shares is stated once, as the
--     @instructions@ of the @initialize@ answer ('serverInstructions'), and
--     each description carries only its own tool's contract, under the 2,048
--     characters at which Claude Code cuts a description (and instructions).
--   * @--expose NAME,...@ ('scExpose'): present only the named tools.
--     tools/list lists those alone, the instructions name those alone, and a
--     call to a registered tool that was not exposed is refused by name.

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Server
  ( runServer
  , ServerConfig (..)
    -- * Exposed for testing
  , toolDefinitions
  , registeredToolNames
  , serverInstructions
  , forceResponse
  ) where

import Control.Exception
  (AsyncException, SomeException, bracket, evaluate, fromException, throwIO, try)
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
import AgdaMCP.Gate (GateConfig)
import AgdaMCP.Interaction
  (InteractionLanes, newInteractionLanes, shutdownLanes)
import AgdaMCP.Tools.CheckProject (handleCheckProject)
import AgdaMCP.Tools.LiveQueries
import AgdaMCP.Tools.ProofState
import AgdaMCP.Tools.Search
import AgdaMCP.Tools.SearchInScope (handleSearchInScope)
import AgdaMCP.Types
  (CorpusIndex, ToolFailure (..), Verbosity (..), answerAt, defaultExportsLimit)

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

-- | ServerConfig: server-level configuration.
--
-- M1-4: the server loop is now crash-proof — uncaught exceptions in tool
-- handlers are caught and returned as JSON-RPC error responses.
data ServerConfig = ServerConfig
  { scAgdaConfig  :: AgdaConfig
  , scGateConfig  :: GateConfig
    -- ^ The whole-project gate: an optional configured command and its own
    --   timeout (@--check-command@, @--check-timeout@).  Used by check_project
    --   only; the per-file tools never see it (issue #78).
  , scServerName  :: Text
  , scVersion     :: Text
  , scCorpusIndex :: Maybe CorpusIndex
    -- ^ In-memory corpus index, loaded at startup via @--corpus@.
    --   When 'Nothing', search tools are not registered.
  , scExpose      :: Maybe [Text]
    -- ^ The tools to present (@--expose@, issue #191); 'Nothing' presents
    --   every registered tool.  Main refuses a name this configuration does
    --   not register, so every name here is one 'registeredToolNames' lists.
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

-- | The tool definitions a client receives: the tools this configuration
-- registers ('registeredTools'), narrowed to the ones @--expose@ names (issue
-- #191), in registration order.
toolDefinitions :: ServerConfig -> Value
toolDefinitions cfg = toJSON (map snd (exposedTools cfg))

-- | The names this configuration registers, exposed or not: what @--expose@
-- may name.  The corpus tools are among them only when a corpus is loaded.
registeredToolNames :: ServerConfig -> [Text]
registeredToolNames = map fst . registeredTools

-- | The registered tools a client is shown and may call.
exposedTools :: ServerConfig -> [(Text, Value)]
exposedTools cfg = filter (isExposed cfg . fst) (registeredTools cfg)

-- | isExposed: whether this server presents (and answers) the named tool.
-- Without @--expose@ every registered tool is exposed.
isExposed :: ServerConfig -> Text -> Bool
isExposed cfg name = maybe True (name `elem`) (scExpose cfg)

-- | Every tool this configuration registers, as (name, definition).
--
-- Proof-state and live-query tools are always registered; the corpus tools
-- only when a corpus is loaded.
--
-- How the text is laid out (issue #191).  A client puts every tool's
-- description and schema in its model's context on EVERY turn, so a sentence
-- repeated on six tools is paid for six times a turn; and Claude Code (from
-- 2.1.282 at the latest, measured) cuts each description, and the server's
-- instructions, at 2,048 characters, so a sentence past that point is never
-- read at all.  Hence three rules.  What every tool shares is stated once, in
-- 'serverInstructions', which a client places in its system prompt.  Each
-- description states its own tool's contract and nothing else, and stays well
-- under the cap (the suite asserts it).  Mechanism a model does not need in
-- order to use a tool correctly (the rendering ladder, the rank formula, the
-- lane's re-load vocabulary) lives in the README, for people.  The PR for
-- issue #191 lists which sentence went where.
registeredTools :: ServerConfig -> [(Text, Value)]
registeredTools cfg = proofStateTools <> liveQueryTools <> searchTools
  where
    proofStateTools =
      [ toolDefWith "get_goal"
          ("The goal type and local context at a hole. " <> holeAddressing
           <> " source says which of two mechanisms answered. \
              \'interaction-lane' (preferred): Agda's own goal display from \
              \the live lane, with no file edit; the answer carries lane \
              \{load, loadElapsedMs?} and NO verdict, and its context entries \
              \are {name, type}, shadowed outer names primed. \
              \'injected-macro' (the fallback, when the lane cannot serve the \
              \file): injects a reporting macro over the hole, typechecks the \
              \patched file in place with batch agda, and restores it byte for \
              \byte; the one path whose context entries carry visibility \
              \(visible/hidden), with verdict {exitCode} and no lane block. Its \
              \exitCode is normally NON-ZERO even when the goal is right, because the macro leaves an interaction \
              \point behind: it judges the introspection run, not your file \
              \(use check_file for that). A lane timeout is reported as the \
              \lane's failure, never re-run on the fallback path, which would \
              \double the bound; a fallback timeout is an isError whose text \
              \is a JSON object naming the bound.")
          [ prop "filePath"  "string"  filePathDoc
          , prop "line"      "integer" lineDoc
          , prop "column"    "integer" columnDoc
          , prop "col"       "integer" colDoc
          , prop "holeIndex" "integer" holeIndexDoc
          , prop "reload"    "boolean" liveReloadDoc
          , prop "verbose"   "boolean" verboseDoc
          ]
          ["filePath"]
          [addressAlternatives]

      , toolDefWith "fill_hole"
          ("Try a candidate term in a hole: splice it over the hole's span, \
           \typecheck the patched file in place with batch agda, and restore \
           \the file byte for byte, so a candidate you keep you write back \
           \yourself. " <> holeAddressing
           <> " status is \"ok\" if and only if agda exits 0, or fails with \
              \nothing but [UnsolvedInteractionMetas]: holes still open in the \
              \file, including a new sub-hole inside the candidate, which is a \
              \successful refinement. EVERY other failure is \"type_error\", \
              \including [UnsolvedMetaVariables] and [UnsolvedConstraints]: a \
              \candidate that leaves a meta unsolved does not pass the build \
              \and is not ok here either. \"timeout\" means the candidate was \
              \never judged (the file is still restored); \"crash\" means agda \
              \could not start. verdict {exitCode} is agda's own. EVERY answer \
              \carries holes [{index, line, col, goal}] and remainingHoles: \
              \the file's holes AS THIS CANDIDATE LEAVES IT, so once you write \
              \the candidate back you re-anchor on the next hole without a \
              \second call; until you do, the file keeps the holes it had.")
          [ prop "filePath"  "string"  filePathDoc
          , prop "line"      "integer" lineDoc
          , prop "column"    "integer" columnDoc
          , prop "col"       "integer" colDoc
          , prop "holeIndex" "integer" holeIndexDoc
          , prop "candidate" "string"  "The candidate proof term to try."
          , prop "verbose"   "boolean" verboseDoc
          ]
          ["filePath", "candidate"]
          [addressAlternatives]

      , toolDef "check_file"
          ("Typecheck one Agda file with batch agda and return its \
           \diagnostics. " <> batchNote <> " " <> diagnosticModel
           <> " holes lists every open hole as {index, line, col, goal} \
              \(holesCount is its length): (line, col) is the address to pass \
              \to get_goal and fill_hole, and goal is the hole's type when the \
              \root's live lane already holds a load of this exact file state \
              \(a free peek, never a lane call), '?' otherwise. A timeout \
              \answers success:false, timedOut:true, and a timeout \
              \diagnostic.")
          [ prop "filePath" "string" filePathDoc
          , prop "maxDiagnostics" "integer" maxDiagnosticsDoc
          , prop "verbose"        "boolean" verboseDoc
          ]
          ["filePath"]

      , toolDef "get_diagnostics"
          "check_file's check, summarized: errors and warnings counts, the \
          \diagnostics behind them (check_file's shape, root cause first, \
          \capped by maxDiagnostics), and the open holes as check_file lists \
          \them. success and verdict are check_file's fields with the same \
          \meaning: the two tools differ in what they summarize, never in what \
          \green means. The counts cover every diagnostic found, not only the \
          \capped list, and are parsed from Agda's prose, so they can drift \
          \with its format; that is why success is never read from them. A \
          \timeout answers as check_file's does."
          [ prop "filePath" "string" filePathDoc
          , prop "maxDiagnostics" "integer" maxDiagnosticsDoc
          , prop "verbose"        "boolean" verboseDoc
          ]
          ["filePath"]

      , toolDef "check_project"
          ("Run the WHOLE PROJECT's own acceptance gate, the check a human \
           \runs before calling the work done, and report its verdict; use \
           \this instead of running the gate from a shell. " <> gateModel
           <> " " <> projectHonestyNote <> " " <> projectPayloadNote
           <> " With verbose:true, a make or command gate's selectedLibraries \
              \and includePaths are this server's configuration, not the flags \
              \the gate passed agda.")
          [ prop "target" "string"
              "A make target to run instead of check, from the nearest \
              \Makefile above the anchor that declares it; naming one selects \
              \the Makefile gate even over --check-command. If no Makefile \
              \declares it, the call fails rather than running something else."
          , prop "projectPath" "string"
              "A file or directory inside the project (default: this server's \
              \working directory; a file anchors its own directory). PASS AN \
              \ABSOLUTE PATH: a relative one resolves against THIS SERVER'S \
              \working directory, not yours."
          , prop "maxDiagnostics" "integer" maxDiagnosticsDoc
          , prop "verbose"        "boolean" verboseDoc
          ]
          []
      ]

    -- The live queries (issue #75).  What they share (the lane, its
    -- latency, that they inform and never decide, reload) is stated once in
    -- 'serverInstructions'; each description says what its tool answers.
    liveQueryTools =
      [ toolDef "type_of"
          "Infer the type of an Agda expression IN A FILE'S SCOPE, without \
          \editing the file; the expression need not occur in it (Agda's \
          \C-c C-d). Answers {expr, scope, type}, or {expr, scope, error: \
          \{stage, code?, message}} when it does not typecheck there, which is \
          \an answer, not a tool failure."
          (liveProps "The Agda expression to type, sent verbatim (any syntax \
                     \a hole would accept).")
          ["filePath", "expr"]

      , toolDef "normalize"
          "Evaluate an Agda expression to normal form IN A FILE'S SCOPE, \
          \without editing the file (Agda's C-c C-n). Answers {expr, scope, \
          \normalForm}, or an in-band error object when it does not typecheck \
          \there."
          (liveProps "The Agda expression to evaluate, sent verbatim.")
          ["filePath", "expr"]

      , toolDef "resolve_name"
          "What does this name resolve to here, and why? Answers every \
          \candidate with its provenance chain, {description, qualified, \
          \provenance: [{step, site?}], definition?}, through re-exports and \
          \module applications that grep cannot see; an AmbiguousName situation \
          \returns EVERY candidate. inScope is Agda's verdict on the name as \
          \written; when it is false the tool still recovers candidates where \
          \it can (recovered says how: 'ambiguous-name-error', the name is in \
          \scope ambiguously or invisible to the completed top-level scope, or \
          \'did-you-mean', Agda's own suggestions, each re-resolved). An empty \
          \candidates list with inScope:false means the name really is unknown \
          \there."
          (nameProps "The name to resolve, qualified or not, exactly as it \
                     \would appear in the file.")
          ["filePath", "name"]

      , toolDef "definition_of"
          "Where is this name defined? Answers {definitions: [{qualified, file, \
          \line, col, endLine, endCol}]}, the defining file and position of \
          \every candidate the name resolves to, chased through re-exports and \
          \barrel modules to the original definition. unlocated lists \
          \candidates whose site Agda's answer did not carry, so a partial \
          \answer is never mistaken for a total one."
          (nameProps "The name to locate, qualified or not.")
          ["filePath", "name"]

      , toolDef "exports_of"
          ("The public surface of a module: exports [{name, type}], the value \
           \members (a parameterized module's types carry its binders), and \
           \modules [name], the exported nested modules (a datatype or record \
           \induces one), so a barrel omission of either kind shows before you \
           \compile against it. Name the module as filePath's scope can write \
           \it (imported directly or through re-exports); \"\" names the \
           \file's own top-level module; a module the scope cannot name \
           \answers an in-band NotInScope error. PAGED: exports holds at most \
           \limit members with their types (default "
           <> T.pack (show defaultExportsLimit)
           <> ", from offset, in Agda's order); total counts the matching \
              \members and truncated says whether more lie beyond, when \
              \nextOffset continues and remaining NAMES them, so the first \
              \answer names the whole surface; to read one of them, pass its \
              \name as pattern. pattern keeps the members whose name contains \
              \it, ignoring case; modules is never paged.")
          [ prop "filePath" "string"  liveFilePathDoc
          , prop "module"   "string"  "The module, as nameable in filePath's \
              \scope; \"\" for the file's own top-level module."
          , prop "limit"    "integer" exportsLimitDoc
          , prop "offset"   "integer" exportsOffsetDoc
          , prop "pattern"  "string"  exportsPatternDoc
          , prop "reload"   "boolean" liveReloadDoc
          , prop "verbose"  "boolean" verboseDoc
          ]
          ["filePath", "module"]
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

          -- The scope-aware retrieval tool (issue #17, phase 1).  Every
          -- argument the handler accepts is a declared property, since a
          -- client that validates its arguments sees only what the schema
          -- declares.
          , toolDef "search_in_scope"
              searchInScopeNote
              [ prop "filePath" "string"  liveFilePathDoc
              , prop "line"     "integer" searchLineDoc
              , prop "column"   "integer" liveColumnDoc
              , prop "col"      "integer" liveColDoc
              , propObject "query" searchQueryDoc
                  [ prop "name"   "string" "A case-insensitive substring of the \
                      \definition's qualified or unqualified name."
                  , propArray "tokens" "string" "Type tokens as a goal display \
                      \spells them (+, ≡, Commutative, hom); names on both sides \
                      \are reduced to bare ones, so _+_ and Agda.Builtin.Nat._+_ \
                      \meet +."
                  ]
              , prop "limit"     "integer" searchLimitDoc
              , prop "maxProbes" "integer" searchMaxProbesDoc
              , propObject "exclude" searchExcludeDoc
                  [ propArray "names" "string" "Bare (unqualified) names to set aside."
                  , prop "statement" "string" "A type; rows whose type \
                      \normalizes to it are set aside."
                  ]
              , prop "reload"    "boolean" liveReloadDoc
              , prop "verbose"   "boolean" verboseDoc
              ]
              ["filePath"]
          ]
      | otherwise = []

    -- The four properties every scope query takes, around its one question
    -- property: an expression (type_of, normalize) or a name (resolve_name,
    -- definition_of).
    liveProps exprDoc = scopeProps ("expr", exprDoc)
    nameProps nameDoc = scopeProps ("name", nameDoc)
    scopeProps (key, doc) =
      [ prop "filePath" "string"  liveFilePathDoc
      , prop key        "string"  doc
      , prop "line"     "integer" liveLineDoc
      , prop "column"   "integer" liveColumnDoc
      , prop "col"      "integer" liveColDoc
      , prop "reload"   "boolean" liveReloadDoc
      , prop "verbose"  "boolean" verboseDoc
      ]

-- | serverInstructions: what every tool shares, stated once (issue #191).
--
-- Sent as @instructions@ in the @initialize@ answer, which a client places in
-- its model's system prompt once rather than once per tool.  It names only the
-- tools this server exposes, so a server started with @--expose@ never points
-- a model at a tool it cannot call, and a paragraph whose tools are all hidden
-- is left out.  Claude Code cuts instructions at 2,048 characters, as it cuts
-- descriptions, and the suite asserts that the whole text fits.
--
-- What it carries, each item moved here from the descriptions that repeated
-- it: the two-lane rule and each lane's cost (from 'batchNote',
-- 'latencyNote', and 'liveLaneNote' as they stood before #191), the path rule
-- ('filePathDoc'), the echo and the wrong-tree refusal ('verdictNote'),
-- @verbose@ ('verboseDoc'), @reload@ ('liveReloadDoc'), and the hole
-- coordinates ('holeModel').
serverInstructions :: ServerConfig -> Text
serverInstructions cfg = T.unwords (filter (not . T.null) paragraphs)
  where
    shown       = map fst (exposedTools cfg)
    among names = filter (`elem` shown) names
    listed      = T.intercalate ", " . among
    batch       = among ["check_file", "get_diagnostics", "fill_hole", "get_goal"]
    lane        = among ["type_of", "normalize", "resolve_name", "definition_of", "exports_of", "search_in_scope", "get_goal"]
    fileTools   = filter (`notElem` ["search_by_name", "search_by_type", "get_dependencies"]) shown
    holeTools   = among ["check_file", "get_diagnostics", "fill_hole", "get_goal"]
    listers     = among ["check_file", "get_diagnostics", "fill_hole"]
    -- get_goal runs batch agda only on its fallback path, and says so.
    batchRunners = filter (/= "get_goal") batch <> ["get_goal's fallback" | "get_goal" `elem` batch]
    one xs       = length xs == 1
    unless' c t = if c then t else ""
    paragraphs =
      -- The exit-code rule and the cold-agda cost belong to the file-level
      -- tools alone: check_project runs make or a configured command, and its
      -- output's failure evidence can turn a green exit red (maskedFailure),
      -- so it is named apart, pointing at its own description (a Copilot
      -- catch on PR #193).
      [ unless' (not (null batch) || "check_project" `elem` shown) $
          "VERDICTS come from a batch process run per call"
          <> unless' (not (null batch))
               (": " <> T.intercalate ", " batchRunners
                <> (if one batchRunners then " runs" else " run")
                <> " a cold agda on the file (a large library's first check \
                   \builds .agdai interfaces and can take minutes) and"
                <> (if one batchRunners then " judges" else " judge")
                <> " by its exit code alone, never its message text")
          <> unless' ("check_project" `elem` shown)
               "; check_project runs the project's own gate, which failure \
               \evidence in its output can also turn red"
          <> "."
      , unless' (not (null lane)) $
          "KNOWLEDGE comes from one persistent agda --interaction-json process \
          \per project root (" <> listed lane <> "): a first question about a \
          \file costs one load (seconds); further questions about the \
          \unchanged file take milliseconds; another file \
          \re-loads (lane.load says why). These answers inform and NEVER \
          \decide a verdict, so they carry no success field, and an \
          \Agda-level negative is an in-band error {stage, code?, message} \
          \(stage 'load': the file does not load). Pass reload:true after \
          \editing a DEPENDENCY of the file, which the lane cannot see."
      , unless' (not (null fileTools)) $
          "A path naming nothing readable is refused, naming the path as \
          \resolved against this server's working directory. EVERY answer \
          \names the tree it used, project {root, rootSource}; a file in \
          \another checkout of a library registered elsewhere is refused with \
          \a rootMismatch naming both roots (unless the registry is missing: \
          \project.librariesFileMissing:true). \
          \verbose:true adds the full echo (command, registry, lane process \
          \and wire lines); leave it off unless checking what ran. A failed \
          \call (isError) always carries it; a process failure or lane timeout \
          \(--timeout) is one whose text is a JSON object. \
          \checkedFromSource says whether a call re-typechecked its file \
          \(absent: unknown, never a guess)."
      , unless' (not (null holeTools)) $
          "HOLES: every Agda hole syntax ({!!}, {! e !}, ?) in .agda and every \
          \literate flavour Agda 2.8 supports, never inside comments, strings, \
          \or literate prose; positions are 1-based (line, col) in the file as \
          \written"
          <> unless' (not (null listers))
               ("; " <> T.intercalate ", " listers
                <> (if one listers then " lists" else " list")
                <> " them, and the next address comes from the latest list")
          <> "."
      ]

-- | holeAddressing: how to name the hole you mean, in the two tools that take
-- one (issue #79).
--
-- The contract worth stating is not "two parameters are available" but which
-- one to hold across calls, and how long it stays good: a position moves only
-- when the text before it moves, whereas an index is renumbered by any fill at
-- all (the § 3.8 cost the field report records; the stability sentence stays
-- deliberately narrow, a Copilot catch on PR #99).  Since issue #191 the
-- detail of which listings report positions, and the literate-coordinate
-- rule, are said once in 'serverInstructions'.
holeAddressing :: Text
holeAddressing =
  "ADDRESSING: pass EITHER (line, column), from the latest hole list, OR \
  \holeIndex, never both (the schema's oneOf gives the three legal shapes). \
  \PREFER THE POSITION: it moves only if a fill before it changes the text's \
  \length or line count, while holeIndex (0-based, source order) is \
  \renumbered by every fill. A position inside no hole is an error listing \
  \the nearest holes, never a guess."

-- | filePathDoc: the resolution rule, at the property that carries the path.
--
-- The #83 field test measured what an unstated rule costs: an agent sent the
-- relative path natural in its own project, the server resolved it against
-- its own checkout, and the client never called it again (issue #101).  The
-- property keeps the rule's two load-bearing words because a client decides
-- what to send by reading it; the refusal's shape is said once in
-- 'serverInstructions' (issue #191).
filePathDoc :: Text
filePathDoc =
  "ABSOLUTE path to the Agda file (a relative one resolves against this \
  \server's working directory, not yours)."

-- | lineDoc / columnDoc / colDoc / holeIndexDoc: the address at the input
-- properties, where a client decides what to send.
--
-- @col@ is declared as a property of its own because a client that validates
-- its arguments against the schema sees only what the schema declares (a
-- Copilot review catch on PR #99).
lineDoc :: Text
lineDoc = "1-based line of the hole; needs column (or col). Preferred over holeIndex."

columnDoc :: Text
columnDoc = "1-based column of the hole; needs line; not with col."

colDoc :: Text
colDoc =
  "column, spelled as the hole lists spell it, so a hole entry passes back \
  \as it is (its index and goal are ignored)."

holeIndexDoc :: Text
holeIndexDoc =
  "0-based, in source order; SHIFT-PRONE: every fill renumbers the holes \
  \after it."

-- | diagnosticModel: the shape of a diagnostic, stated where the client reads
-- it (issue #74), once, on check_file (issue #191); get_diagnostics and
-- check_project refer to it.  The root-cause ordering in full is in the
-- README.
diagnosticModel :: Text
diagnosticModel =
  "Each diagnostic has severity, code (Agda's own name, e.g. NotInScope, \
  \AmbiguousName, UnsolvedMetaVariables: branch on it, not on the prose), \
  \file, range {startLine, startCol, endLine, endCol} (1-based, as written; \
  \line and col alias the start), the bounded message, and involved \
  \{expected?, actual?, candidates?, metaTypes?, metas?}, where metas (each \
  \unsolved meta's name, type, and range) comes only from a warm lane already \
  \holding this file's load. Ordered most-likely root cause first, repeats \
  \collapsed, and capped by maxDiagnostics, with diagnosticsTotal counting \
  \all."

-- | gateModel: which command @check_project@ runs, and how it decided (issue
-- #78).  An agent that cannot predict what the tool will run has to run the
-- gate itself to be sure, the whole failure this tool exists to end.
gateModel :: Text
gateModel =
  "THE GATE, in order: the make target named by target (the nearest Makefile \
  \above the anchor that declares it, run in its directory); else this \
  \server's --check-command (run directly, no shell); else the nearest \
  \Makefile's check target; else agda on the project's Everything module. The \
  \search stops at the repository boundary; finding none, the call FAILS, \
  \naming what it searched, and never reports a check that did not happen. \
  \gate {source, target?, makefile?, entry?, searchedFrom} says which ran."

-- | projectHonestyNote: the one thing the tool exists for, said where a
-- client reads it.
projectHonestyNote :: Text
projectHonestyNote =
  "success is true if and only if the gate exited 0, finished inside the \
  \bound, AND its output carried no failure evidence (an Agda error, or \
  \make's own failure line); one that exits 0 with such evidence is \
  \success:false with maskedFailure:true. verdict.exitCode is the gate's own \
  \status, never reinterpreted (-1 when it had none: not started, or killed \
  \at the bound, which timedOut tells apart). Read success; you need not grep \
  \the log. The recognizers are a list, not a theory, so outputTail, the \
  \bounded tail of the gate's output, comes back whatever the verdict."

-- | projectPayloadNote: what a project answer carries beyond the verdict,
-- and the call's cost (issue #78).
projectPayloadNote :: Text
projectPayloadNote =
  "firstError is the first error diagnostic (check_file's shape); \
  \failingModule and failingFile name where a failed gate stopped; \
  \modulesChecked counts modules re-typechecked from source (absent when \
  \--trace-imports=0 silences it; best effort for a make or command gate). \
  \The call BLOCKS for the whole gate (10-20 minutes is ordinary) up to \
  \--check-timeout (default 1800s, apart from --timeout); on expiry the \
  \gate's process group is killed and the answer is success:false, \
  \timedOut:true, still with elapsedMs, modulesChecked, and failingModule; \
  \timeoutSeconds echoes the bound."

-- | maxDiagnosticsDoc: the cap's contract, in the input schema where a client
-- decides what to pass.
maxDiagnosticsDoc :: Text
maxDiagnosticsDoc =
  "Default 10; 0 means no limit. diagnosticsTotal counts every one found."

-- | batchNote: what success means for the two whole-file tools (issue #72),
-- stated on check_file; get_diagnostics names it as check_file's.
batchNote :: Text
batchNote =
  "success is true if and only if agda exits 0, which is exactly what green \
  \means in a batch build: unsolved metavariables, unsolved constraints, and \
  \open holes all make it false, and there is no leniency to opt into. \
  \verdict {exitCode} is agda's own; the live lane never takes part in the \
  \verdict and only fills informational fields."

-- | liveFilePathDoc: the path rule for the live queries, plus what the file
-- means to a scope query.
liveFilePathDoc :: Text
liveFilePathDoc =
  "ABSOLUTE path to the Agda file whose scope answers (a relative one \
  \resolves against this server's working directory, not yours)."

-- | liveLineDoc: the @line@ property's contract, which is also where the scope
-- rule is stated (issue #191 folded 'liveLineNote' into it).
liveLineDoc :: Text
liveLineDoc =
  "Optional 1-based line: inside a hole, that goal's scope (locals and \
  \file-local opens visible, which a hole-free file's top-level scope \
  \loses); else the top-level scope. scope says which."

-- | liveColumnDoc / liveColDoc: the optional column that sharpens @line@ into
-- a position, deciding between goals that share a line.
liveColumnDoc :: Text
liveColumnDoc =
  "Optional 1-based column: picks the hole when two share the line (else the \
  \earliest). Needs line; not with col."

liveColDoc :: Text
liveColDoc = "column, spelled as the hole lists spell it."

-- | verboseDoc: the @verbose@ property (issue #184), declared on every tool
-- whose answer carries an echo, since a client that validates its arguments
-- sends only what the schema declares.  What the lean answer keeps, and when
-- to ask for more, is said once in 'serverInstructions'.
verboseDoc :: Text
verboseDoc = "Default false; true adds the full echo."

-- | exportsLimitDoc / exportsOffsetDoc / exportsPatternDoc: the @exports_of@
-- page (issue #184).
exportsLimitDoc :: Text
exportsLimitDoc =
  "Default " <> T.pack (show defaultExportsLimit) <> ": how many members to \
  \return with their types; remaining names the rest. 0 or less returns every \
  \matching member typed."

exportsOffsetDoc :: Text
exportsOffsetDoc =
  "Default 0: where the page starts among the matching members; pass the \
  \previous answer's nextOffset to continue."

exportsPatternDoc :: Text
exportsPatternDoc =
  "Keep only members whose name contains this, ignoring case, in exports and \
  \modules alike; total and remaining then count and name only those."

-- | liveReloadDoc: the @reload@ property.  Why it exists (a changed
-- dependency, which no stamp on the queried file can see) is said once in
-- 'serverInstructions'.
liveReloadDoc :: Text
liveReloadDoc = "Default false; true re-loads the file first (lane.load: 'forced')."

-- | searchInScopeNote: the contract of search_in_scope (issue #17), stated
-- where the client reads it and cut to what a caller needs (issue #191): the
-- question; that it informs and never decides; that every rendering was
-- typed by Agda here; the query; that scope is derived, and what that costs;
-- the two bounds; that exclusion is the caller's policy; the ledger and what
-- an empty answer means; the in-band errors.  The rendering ladder, the rank
-- formula, and the exclusion's two statement checks are in the README.
searchInScopeNote :: Text
searchInScopeNote =
  "Corpus rows that filePath can actually name, and what Agda says each one's \
  \type is: results [{prettyQname, rendering, type, via {module, rung}, \
  \module, defKind, hasBody, corpusType, score}] in rank order, where EVERY \
  \rendering was typed by this server through the live lane in filePath's \
  \scope (the hole's scope when line/column addresses one), and checked to \
  \denote its row, and type is Agda's printing, not the corpus's. THIS TOOL \
  \INFORMS AND NEVER DECIDES: a rendering that types says nothing about \
  \whether it fills a hole (fill_hole judges that). query {name?, tokens?} \
  \matches case-insensitive substrings of names and of type tokens as a goal \
  \display spells them (both, when both are given); omit it at a hole to take \
  \the tokens from the goal's type (query.source says 'given' or 'goal'). \
  \SCOPE is DERIVED from source text, the file's import lines, so a row \
  \re-exported from outside them can be reported out of scope though \
  \nameable: it costs recall, never a name the file cannot write. Only \
  \function rows are ranked, by type-token overlap with the query; limit \
  \counts ACCEPTED rows, cut after validation, and maxProbes bounds the rows \
  \sent to the lane. EXCLUSION is your policy: exclude {names?, statement?}, \
  \every exclusion named in ledger.excluded with its reason. EVERY answer \
  \carries ledger {hits (corpus-wide, before scope), inScope, outOfScope, \
  \excluded, nonFunction, ranked, probed, laneCalls, laneRejected \
  \[{prettyQname, tried}], accepted, truncated, stoppedBy}, so an empty \
  \result states its bounds: hits > 0 with inScope 0 means the file does not \
  \import the module; accepted 0 with laneRejected naming rows means the \
  \corpus and the library disagree. timing {poolMs, laneMs}. In-band errors: \
  \error.stage 'load' (the file does not load) or 'query' (no usable query)."

-- | searchLineDoc: the anchor's contract for search_in_scope.
searchLineDoc :: Text
searchLineDoc =
  "Optional 1-based line. Inside a hole: renderings are typed in that goal's \
  \scope, and with no query the goal's type supplies the tokens. Elsewhere or \
  \omitted: the top-level scope, and a query is required."

searchQueryDoc :: Text
searchQueryDoc =
  "{name?, tokens?}; optional when line/column addresses a hole, required \
  \otherwise."

searchLimitDoc :: Text
searchLimitDoc =
  "Maximum ACCEPTED rows (default 8; a non-positive value means 1); \
  \ledger.truncated says whether ranked rows remained."

searchMaxProbesDoc :: Text
searchMaxProbesDoc =
  "Maximum ranked rows sent to the lane before giving up on filling limit \
  \(default 4 x limit, never below limit)."

searchExcludeDoc :: Text
searchExcludeDoc =
  "Rows to set aside, and only these: typically the name and stated type of \
  \the definition you are proving, so the answer cannot be the definition \
  \itself."

-- | Build a tool definition (MCP tools/list schema), paired with its name.
toolDef :: Text -> Text -> [(Text, Value)] -> [Text] -> (Text, Value)
toolDef name desc props required = toolDefWith name desc props required []

-- | As 'toolDef', with extra JSON Schema keywords merged into the input schema.
--
-- Exists for one keyword — the @oneOf@ that says a hole must be addressed
-- somehow ('addressAlternatives').  @required@ alone cannot express it: the
-- address is mandatory but its spelling is a choice, so listing any one
-- spelling would be wrong and listing none advertises that a bare @filePath@ is
-- a complete call, which the wire parser rejects (a Copilot review catch on PR
-- #99).  A client that ignores @oneOf@ is no worse off than before; one that
-- honours it now agrees with the parser about what a legal request is.
toolDefWith :: Text -> Text -> [(Text, Value)] -> [Text] -> [(Text, Value)] -> (Text, Value)
toolDefWith name desc props required extra = (,) name $ object
  [ "name"        .= name
  , "description" .= desc
  , "inputSchema" .= object
      ( [ "type"       .= ("object" :: Text)
        , "properties" .= object [ Key.fromText k .= v | (k, v) <- props ]
        , "required"   .= required
        ]
        <> [ Key.fromText k .= v | (k, v) <- extra ]
      )
  ]

-- | addressAlternatives: the hole address, as JSON Schema.
--
-- These three branches are exactly the shapes 'AgdaMCP.Types.parseHoleRef'
-- accepts, and @oneOf@ (rather than @anyOf@) is what makes the correspondence
-- exact: a request naming two of them — an index /and/ a position, or both
-- spellings of the column — matches two branches and is therefore invalid here,
-- which is precisely the parser's answer too.  The one rule the schema cannot
-- carry is that a position must be inside a hole; that needs the file.
addressAlternatives :: (Text, Value)
addressAlternatives =
  ( "oneOf"
  , toJSON
      [ requiring ["holeIndex"]
      , requiring ["line", "column"]
      , requiring ["line", "col"]
      ]
  )
  where
    requiring ks = object ["required" .= (ks :: [Text])]

-- | Build a property definition for the input schema.
prop :: Text -> Text -> Text -> (Text, Value)
prop name typ desc = (name, object ["type" .= typ, "description" .= desc])

-- | propObject: an object-valued property with its own declared properties
-- (search_in_scope's @query@ and @exclude@, issue #17).  Declared in full so
-- a client that validates its arguments sees every key the handler accepts.
propObject :: Text -> Text -> [(Text, Value)] -> (Text, Value)
propObject name desc props =
  ( name
  , object
      [ "type"        .= ("object" :: Text)
      , "description" .= desc
      , "properties"  .= object [ Key.fromText k .= v | (k, v) <- props ]
      ]
  )

-- | propArray: an array-valued property whose items share one type.
propArray :: Text -> Text -> Text -> (Text, Value)
propArray name itemType desc =
  ( name
  , object
      [ "type"        .= ("array" :: Text)
      , "description" .= desc
      , "items"       .= object [ "type" .= itemType ]
      ]
  )


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
  -- The interaction lanes (issue #75) are runtime state, not configuration:
  -- acquired with 'bracket' so no exit path — and no cancellation landing
  -- between construction and cleanup installation — can leak the registry's
  -- reaper thread or an agda child (bracket's acquire runs masked, which is
  -- what closes the construction gap a 'finally' after the fact cannot).
  bracket newInteractionLanes shutdownLanes loop
  where
    loop lanes = do
      eof <- isEOF
      if eof
        then hPutStrLn stderr "agda-mcp: stdin closed, shutting down."
        else do
          line <- LBS.fromStrict <$> BS8.hGetLine stdin
          when (not $ LBS.null line) $
            case decode line of
              Nothing -> sendResponse $ mkError Nothing (-32700) "Parse error"
              Just req -> do
                result <- try (handleRequest cfg lanes req)
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
          loop lanes

sendResponse :: Value -> IO ()
sendResponse v = do
  LBS8.putStrLn (encode v)
  hFlush stdout


-- | handleRequest: dispatcher
handleRequest
  :: ServerConfig -> InteractionLanes -> JsonRpcRequest -> IO (Maybe Value)

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
handleRequest cfg _lanes req | rpcMethod req == "initialize" = do
  let result = object
        [ "protocolVersion" .= ("2024-11-05" :: Text)
        , "capabilities"    .= object
            [ "tools" .= object []
            ]
        , "serverInfo" .= object
            [ "name"    .= scServerName cfg
            , "version" .= scVersion cfg
            ]
          -- What every tool shares, once (issue #191): a client puts it in
          -- its model's system prompt rather than repeating it per tool.
        , "instructions" .= serverInstructions cfg
        ]
  pure . Just $ mkResult (rpcId req) result

-- MCP notification: initialized (no response)
handleRequest _ _lanes req | rpcMethod req == "notifications/initialized" =
  pure Nothing

-- MCP: tools/list
handleRequest cfg _lanes req | rpcMethod req == "tools/list" = do
  let result = object ["tools" .= toolDefinitions cfg]
  pure . Just $ mkResult (rpcId req) result

-- MCP: tools/call
handleRequest cfg lanes req | rpcMethod req == "tools/call" = do
  let params = fromMaybe (Object mempty) (rpcParams req)
  case params of
    Object o -> do
      let toolName = case KM.lookup "name" o of
            Just (String n) -> n
            _               -> ""
          args = case KM.lookup "arguments" o of
            Just v  -> v
            Nothing -> Object mempty
      result <- dispatchToolGuarded cfg lanes toolName args
      pure . Just $ mkResult (rpcId req) result
    _ ->
      pure . Just $ mkError (rpcId req) (-32602) "Invalid params"

-- Unrecognised method
handleRequest _ _lanes req =
  pure . Just $ mkError (rpcId req) (-32601) ("Method not found: " <> rpcMethod req)


-- ---------------------------------------------------------------------------
-- Tool dispatch
-- ---------------------------------------------------------------------------

-- | dispatchToolGuarded: the last line of defence.  A tool that throws answers
-- with a tool error, never with a JSON-RPC one.
--
-- The handlers return their failures as data ('AgdaMCP.Types.ToolFailure'), so
-- reaching this is a bug.  It still matters which /kind/ of answer a bug
-- produces.  A JSON-RPC error is a transport fault: Claude Code renders it as
-- @MCP error -32603: Internal error@, with no path, no tool, and no rule, and
-- the #83 field test recorded an agent reading exactly that as "the MCP agda
-- server crashed" and never calling the server again (issue #101).  An
-- @isError@ tool result is content the client hands its model, naming the tool
-- and what actually went wrong — which at worst tells the agent that this call
-- failed rather than that this server is dead.
--
-- The guard covers the value as well as the action, which is why
-- 'forceResponse' is inside the 'try' rather than after it.  A handler can
-- return successfully and hand back a 'Value' whose thunks have not been
-- evaluated yet; those are forced later, by @encode@ in 'sendResponse', which
-- runs outside every 'try' in this module.  A bottom reachable from a tool
-- result would then kill the loop instead of becoming a tool error — a worse
-- outcome than the @-32603@ this exists to prevent, since the client sees the
-- transport close rather than an answer (Copilot's review of PR 102).
--
-- Asynchronous exceptions are re-thrown rather than reported: a cancelled
-- server is not a failed tool call, and the loop above is what shuts it down.
dispatchToolGuarded
  :: ServerConfig -> InteractionLanes -> Text -> Value -> IO Value
dispatchToolGuarded cfg lanes name args = do
  outcome <- try (dispatch >>= forceResponse)
  case outcome of
    Right value -> pure value
    Left (e :: SomeException) -> case fromException e of
      Just ae -> throwIO (ae :: AsyncException)
      Nothing -> do
        hPutStrLn stderr $ "agda-mcp: uncaught exception in tool "
          <> T.unpack name <> ": " <> show e
        -- Deliberately silent about what the call did or did not do.  An earlier
        -- version promised "the call ran nothing you need to undo", which is not
        -- something this point can know: check_project may already have run the
        -- operator's gate, and a proof-state tool may already have run agda and
        -- written interface files, since the exception can be raised after either
        -- (Copilot's review of PR 102).  The one effect that /is/ guaranteed
        -- undone is get_goal's and fill_hole's in-place patch, which is restored
        -- under a bracket whatever happens; that is stated in their own contracts
        -- rather than promised here for tools it is not true of.
        pure . toolError $
          "agda-mcp: the " <> name <> " tool failed with an unexpected internal \
          \error. This is a bug in the server, not a problem with your request. \
          \Treat what the call had already done as unknown: it may have run agda, \
          \or a project gate, before failing. What went wrong: "
          <> T.pack (show e)
  where
    -- A registered tool that @--expose@ left out is refused here, before its
    -- handler can run, so a subset server answers exactly the tools it
    -- presents (issue #191).  The @verbose@ argument is read here too, once
    -- for every tool (issue #184).
    dispatch
      | name `elem` registeredToolNames cfg && not (isExposed cfg name) =
          pure . toolError $
            "agda-mcp: the " <> name <> " tool is not exposed by this server, \
            \which was started with --expose " <> maybe "" (T.intercalate ",") (scExpose cfg)
            <> " and presents only those tools."
      | otherwise = case verbosityOf args of
          Left msg        -> pure $ toolError ("Invalid arguments: " <> msg)
          Right verbosity -> dispatchTool cfg lanes verbosity name args

-- | verbosityOf: a call's @verbose@ argument (issue #184), read here once for
-- every tool rather than by each tool's parameter parser, because what it
-- selects is how the answer is written out and not what the tool does.
--
-- Absent, null, or false is 'Lean', and true is 'Verbose'.  Anything else is
-- refused by name: a client that sent the string @"true"@ asked for the full
-- echo, and handing it the lean answer would leave it wondering where the echo
-- went.
verbosityOf :: Value -> Either Text Verbosity
verbosityOf (Object o) = case KM.lookup "verbose" o of
  Nothing           -> Right Lean
  Just Null         -> Right Lean
  Just (Bool False) -> Right Lean
  Just (Bool True)  -> Right Verbose
  Just other        -> Left $
    "verbose must be true or false, not " <> decodeUtf8 (LBS.toStrict (encode other))
verbosityOf _ = Right Lean

-- | forceResponse: force a response value's JSON encoding, and hand the value
-- back once nothing lazy is left in it.
--
-- The point is /where/ the exception surfaces, not the bytes: 'encode' traverses
-- the whole structure, so evaluating its length raises any bottom inside the
-- value here, in the caller's guarded region, rather than in the writer.
-- Thunks are updated in place once forced, so the encode 'sendResponse' does
-- afterwards cannot raise what this one did not.
--
-- The cost is one extra traversal per tool call, which is nothing beside
-- spawning @agda@, and every response is bounded — diagnostics are capped and
-- message bodies truncated — so there is no large payload to pay for twice.
forceResponse :: Value -> IO Value
forceResponse value = do
  _ <- evaluate (LBS.length (encode value))
  pure value

-- | dispatchTool: route a tool call to the appropriate handler.
--
-- Proof-state tools delegate to AgdaMCP.Tools.ProofState (IO, calls Agda).
-- Search tools delegate to AgdaMCP.Tools.Search (pure, uses CorpusIndex).
dispatchTool
  :: ServerConfig -> InteractionLanes -> Verbosity -> Text -> Value -> IO Value

-- Proof-state tools (existing M1-2)
dispatchTool cfg lanes v "get_goal" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp v <$> handleGetGoal lanes (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg _lanes v "fill_hole" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp v <$> handleFillHole (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg lanes v "check_file" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp v <$> handleCheckFile lanes (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg lanes v "get_diagnostics" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp v <$> handleGetDiagnostics lanes (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

-- Whole-project gate (M1-5, issue #78).  The one tool that takes the gate
-- configuration as well as the Agda one.
dispatchTool cfg _lanes v "check_project" args =
  case Aeson.fromJSON args of
    Aeson.Success p ->
      failureToMcp v <$> handleCheckProject (scAgdaConfig cfg) (scGateConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

-- Search tools (new M1-3)
dispatchTool cfg _lanes v "search_by_name" args =
  case scCorpusIndex cfg of
    Nothing  -> pure $ toolError "No corpus loaded.  Start the server with --corpus <path.jsonl>."
    Just idx ->
      case Aeson.fromJSON args of
        Aeson.Success p -> pure . eitherToMcp v $ handleSearchByName idx p
        Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg _lanes v "search_by_type" args =
  case scCorpusIndex cfg of
    Nothing  -> pure $ toolError "No corpus loaded.  Start the server with --corpus <path.jsonl>."
    Just idx ->
      case Aeson.fromJSON args of
        Aeson.Success p -> pure . eitherToMcp v $ handleSearchByType idx p
        Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg _lanes v "get_dependencies" args =
  case scCorpusIndex cfg of
    Nothing  -> pure $ toolError "No corpus loaded.  Start the server with --corpus <path.jsonl>."
    Just idx ->
      case Aeson.fromJSON args of
        Aeson.Success p -> pure . eitherToMcp v $ handleGetDependencies idx p
        Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

-- Scope-aware retrieval (issue #17): the one corpus tool that also takes the
-- lanes, since every rendering it returns is typed there.
dispatchTool cfg lanes v "search_in_scope" args =
  case scCorpusIndex cfg of
    Nothing  -> pure $ toolError "No corpus loaded.  Start the server with --corpus <path.jsonl>."
    Just idx ->
      case Aeson.fromJSON args of
        Aeson.Success p ->
          failureToMcp v <$> handleSearchInScope lanes (scAgdaConfig cfg) idx p
        Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

-- Live-query tools (issue #75): the interaction lane.
dispatchTool cfg lanes v "type_of" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp v <$> handleTypeOf lanes (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg lanes v "normalize" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp v <$> handleNormalize lanes (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg lanes v "resolve_name" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp v <$> handleResolveName lanes (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg lanes v "definition_of" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp v <$> handleDefinitionOf lanes (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg lanes v "exports_of" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp v <$> handleExportsOf lanes (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

-- Unknown tool
dispatchTool _ _ _ name _ =
  pure $ toolError ("Unknown tool: " <> name)


-- ---------------------------------------------------------------------------
-- MCP response helpers
-- ---------------------------------------------------------------------------

-- | Wrap an IO-based tool handler result (Either Text a) as an MCP content response.
eitherToMcp :: ToJSON a => Verbosity -> Either Text a -> Value
eitherToMcp v = either toolError (okToMcp v)

-- | As 'eitherToMcp', for handlers whose failures are structured 'ToolFailure's
-- — which, since issue #76, is all four proof-state tools.
--
-- A 'FailMessage' renders exactly as it always did — prose with @isError@ —
-- while 'FailTimeout', 'FailProject', and 'FailPath' serialize their payload as
-- the error text.  That is what lets a timed-out call still deliver its timing
-- and cache metadata (issue #77), a wrong-tree refusal still deliver both roots
-- as data rather than as a sentence the client would have to parse (issue #76),
-- and a path that named no readable file deliver what it resolved to and the
-- directory it was resolved against (issue #101).
--
-- All of them arrive as @isError@ /tool results/ rather than as JSON-RPC
-- errors, which is the distinction issue #101 turns on: a tool result is
-- content the client shows its model, while a JSON-RPC error is a transport
-- fault, and @-32603 Internal error@ is what an agent reasonably reads as
-- "this server is broken".
--
-- The verbosity (issue #184) reaches the success shape only.  A failure's
-- payload keeps its whole echo whatever was asked: it is rare, and there the
-- echo (the command that timed out, the two roots that disagree, the wire
-- lines a crashed lane was sent) is the diagnosis.
failureToMcp :: ToJSON a => Verbosity -> Either ToolFailure a -> Value
failureToMcp v = either render (okToMcp v)
  where
    render (FailMessage msg)     = toolError msg
    render (FailTimeout tf)      = structuredError (toJSON tf)
    render (FailProject pm)      = structuredError (toJSON pm)
    render (FailPath pf)         = structuredError (toJSON pf)
    render (FailInteraction xf)  = structuredError (toJSON xf)

    structuredError payload = object
      [ "content" .= [ object [ "type" .= ("text" :: Text)
                               , "text" .= decodeUtf8 (LBS.toStrict (encode payload))
                               ] ]
      , "isError" .= True
      ]

-- | The success shape shared by every tool: one text content item holding the
-- result's JSON, at the call's verbosity ('AgdaMCP.Types.answerAt', issue
-- #184).  This is the one place a successful answer is written out, which is
-- what lets one rule decide the lean shape of every tool's answer.
okToMcp :: ToJSON a => Verbosity -> a -> Value
okToMcp v a = object
  [ "content" .= [ object [ "type" .= ("text" :: Text)
                           , "text" .= decodeUtf8 (LBS.toStrict (encode (answerAt v (toJSON a))))
                           ] ]
  ]

toolError :: Text -> Value
toolError msg = object
  [ "content" .= [ object [ "type" .= ("text" :: Text)
                           , "text" .= msg
                           ] ]
  , "isError" .= True
  ]
