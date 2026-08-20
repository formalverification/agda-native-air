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
-- Issue #78 addition:
--   * check_project — the whole-project gate.  Always registered, and the one
--     tool that reads 'scGateConfig' as well as 'scAgdaConfig'.  Its call
--     blocks for the duration of the gate: this transport is a synchronous line
--     loop with no progress-notification plumbing, so streaming progress is
--     follow-on scope rather than something the framing already supports.

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Server
  ( runServer
  , ServerConfig (..)
    -- * Exposed for testing
  , toolDefinitions
  , forceResponse
  ) where

import Control.Exception
  (AsyncException, SomeException, evaluate, finally, fromException, throwIO, try)
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
  , scGateConfig  :: GateConfig
    -- ^ The whole-project gate: an optional configured command and its own
    --   timeout (@--check-command@, @--check-timeout@).  Used by check_project
    --   only; the per-file tools never see it (issue #78).
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
-- Proof-state and live-query tools are always available.
-- Search tools are only registered when a corpus is loaded.
toolDefinitions :: ServerConfig -> Value
toolDefinitions cfg = toJSON $ proofStateTools <> liveQueryTools <> searchTools
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
      [ toolDefWith "get_goal"
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
          [ prop "filePath"  "string"  filePathDoc
          , prop "line"      "integer" lineDoc
          , prop "column"    "integer" columnDoc
          , prop "col"       "integer" colDoc
          , prop "holeIndex" "integer" holeIndexDoc
          ]
          ["filePath"]
          [addressAlternatives]

      , toolDefWith "fill_hole"
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
          [ prop "filePath"  "string"  filePathDoc
          , prop "line"      "integer" lineDoc
          , prop "column"    "integer" columnDoc
          , prop "col"       "integer" colDoc
          , prop "holeIndex" "integer" holeIndexDoc
          , prop "candidate" "string"  "The candidate proof term to try."
          ]
          ["filePath", "candidate"]
          [addressAlternatives]

      , toolDef "check_file"
          ("Typecheck one Agda file and return all diagnostics. "
           <> verdictNote
           <> " " <> batchNote
           <> " " <> diagnosticModel
           <> " holes lists every open hole as {index, line, col, goal} \
              \(holesCount is its length); (line, col) is the address to pass \
              \back to get_goal and fill_hole, and this is the listing to take \
              \it from."
           <> " Returns elapsedMs and checkedFromSource; " <> latencyNote
           <> " On timeout it returns success:false with timedOut:true and an \"agda timed out after Ns\" error diagnostic. "
           <> holeModel)
          [ prop "filePath" "string" filePathDoc
          , prop "maxDiagnostics" "integer" maxDiagnosticsDoc
          ]
          ["filePath"]

      , toolDef "get_diagnostics"
          ("Typecheck one Agda file and return a summary: error/warning counts, \
           \the diagnostics behind them, and each open hole's index and \
           \(line, col) position — that (line, col) being the address to pass \
           \back to get_goal and fill_hole. "
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
          [ prop "filePath" "string" filePathDoc
          , prop "maxDiagnostics" "integer" maxDiagnosticsDoc
          ]
          ["filePath"]

      , toolDef "check_project"
          ("Run the WHOLE PROJECT's own acceptance gate — the check a human runs \
           \before calling the work done — and report its verdict. Use this \
           \instead of running the gate from a shell. "
           <> gateModel
           <> " " <> projectHonestyNote
           <> " " <> projectPayloadNote
           <> " " <> diagnosticModel
           <> " " <> projectTimingNote
           <> " " <> projectEchoNote)
          [ prop "target" "string"
              "A make target to run instead of the default 'check'. It is \
              \resolved against the nearest Makefile up from the anchor that \
              \declares it; naming one selects the Makefile gate even when the \
              \server has a --check-command configured. If no Makefile declares \
              \it, the call fails rather than running something else."
          , prop "projectPath" "string"
              "A file or directory inside the project to check (default: the \
              \server's working directory). A file anchors its own directory. \
              \PASS AN ABSOLUTE PATH: a relative one is resolved against THIS \
              \SERVER'S working directory, not yours. A path that does not exist \
              \is an error naming the path as resolved and that working \
              \directory."
          , prop "maxDiagnostics" "integer" maxDiagnosticsDoc
          ]
          []
       ]
    -- The interaction-lane tools (issue #75).  Their descriptions carry the
    -- two-lane boundary — these inform and never decide a build verdict —
    -- because an agent picks a tool by reading its description and nothing
    -- else (the § 6 meta-suggestion of the feedback document).
    liveQueryTools =
      [ toolDef "type_of"
          ("Infer the type of an Agda expression IN A FILE'S SCOPE, without \
           \editing the file — the expression need not appear in it (Agda's \
           \C-c C-d). Answers {expr, scope, type} on success and {expr, \
           \scope, error: {stage, code?, message}} when the expression does \
           \not typecheck there — that negative is an answer, not a tool \
           \failure. "
           <> liveLineNote <> " " <> liveLaneNote)
          [ prop "filePath" "string"  liveFilePathDoc
          , prop "expr"     "string"  "The Agda expression to type. It is sent \
              \verbatim (any syntax a hole would accept); it does not have to \
              \occur in the file."
          , prop "line"     "integer" liveLineDoc
          , prop "reload"   "boolean" liveReloadDoc
          ]
          ["filePath", "expr"]

      , toolDef "normalize"
          ("Evaluate an Agda expression to normal form IN A FILE'S SCOPE, \
           \without editing the file (Agda's C-c C-n). Answers {expr, scope, \
           \normalForm} on success and an in-band error object when the \
           \expression does not typecheck there. "
           <> liveLineNote <> " " <> liveLaneNote)
          [ prop "filePath" "string"  liveFilePathDoc
          , prop "expr"     "string"  "The Agda expression to evaluate, sent \
              \verbatim; it does not have to occur in the file."
          , prop "line"     "integer" liveLineDoc
          , prop "reload"   "boolean" liveReloadDoc
          ]
          ["filePath", "expr"]

      , toolDef "resolve_name"
          ("What does this name resolve to here, and why? Answers every \
           \candidate with its provenance chain — {description, qualified, \
           \provenance: [{step, site?}], definition?} — resolving re-exports \
           \and module applications that grep cannot see; an AmbiguousName \
           \situation returns EVERY candidate. inScope is Agda's verdict on \
           \the name as written; when it is false the tool still recovers \
           \candidates where it can (recovered says how: \
           \'ambiguous-name-error' — the name is in scope ambiguously or \
           \invisible to the completed top-level scope — or 'did-you-mean', \
           \Agda's own suggestions, each re-resolved for its chain). An empty \
           \candidates list with inScope:false means the name really is \
           \unknown there. "
           <> liveLineNote <> " " <> liveLaneNote)
          [ prop "filePath" "string"  liveFilePathDoc
          , prop "name"     "string"  "The name to resolve, qualified or not, \
              \exactly as it would appear in the file."
          , prop "line"     "integer" liveLineDoc
          , prop "reload"   "boolean" liveReloadDoc
          ]
          ["filePath", "name"]

      , toolDef "definition_of"
          ("Where is this name defined? Answers {definitions: [{qualified, \
           \file, line, col, endLine, endCol}]} — the defining file and \
           \position of every candidate the name resolves to, chased through \
           \re-exports and barrel modules to the original definition (the \
           \single most common grep, answered by the type-checker instead). \
           \unlocated lists candidates whose site Agda's answer did not \
           \carry, so a partial answer is never mistaken for a total one. "
           <> liveLineNote <> " " <> liveLaneNote)
          [ prop "filePath" "string"  liveFilePathDoc
          , prop "name"     "string"  "The name to locate, qualified or not."
          , prop "line"     "integer" liveLineDoc
          , prop "reload"   "boolean" liveReloadDoc
          ]
          ["filePath", "name"]

      , toolDef "exports_of"
          ("The public surface of a module: every exported name with its \
           \type, as {exports: [{name, type}]} — so a barrel omission is \
           \caught before compiling against it. The module is named FROM A \
           \FILE'S SCOPE: pass the module name as that file can write it \
           \(imported directly or through re-exports); a module the file's \
           \scope cannot name answers with an in-band NotInScope error. The \
           \empty string names the file's own top-level module and lists its \
           \definitions. "
           <> liveLaneNote)
          [ prop "filePath" "string"  liveFilePathDoc
          , prop "module"   "string"  "The module whose exports to list, as \
              \nameable in filePath's scope; \"\" for the file's own \
              \top-level module."
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
          ]
      | otherwise = []

-- | holeAddressing: how to name the hole you mean, in the two tools that take
-- one (issue #79).
--
-- The description is where the contract lives (the § 6 meta-suggestion of the
-- feedback document), and the contract worth stating here is not "two
-- parameters are available" but which one to hold across calls, and how long it
-- stays good.  An agent that reads only this must come away addressing holes by
-- position and re-anchoring from each response; § 3.8 records what the other
-- habit costs, and verification found it costs more than stated, since a
-- miscounted decoy could put "the first hole" inside a comment.
--
-- The stability sentence is deliberately narrow.  A position is not stable under
-- arbitrary edits — a candidate that differs in length or line count from the
-- hole it replaced moves everything after it — and promising otherwise would
-- hand a client the same wrong-hole answer by a different route (a Copilot
-- review catch on PR #99).  What is true, and enough, is that a position moves
-- only when the text before it moves, whereas an index is renumbered by any
-- fill at all.
holeAddressing :: Text
holeAddressing =
  "ADDRESSING A HOLE: pass EITHER (line, column) — 1-based coordinates in the \
  \file as written, literate-file coordinates for a literate source, exactly \
  \what get_diagnostics.holes, check_file.holes, and every fill_hole response's \
  \holes list report — OR holeIndex. PREFER THE POSITION, AND RE-ANCHOR IT FROM \
  \EACH RESPONSE. A position names the hole where it sits, so a fill later in \
  \the file never disturbs it, and a fill earlier in the file disturbs it only \
  \if the candidate differs in length or line count from the hole token it \
  \replaced. holeIndex is a 0-based index into the source-order hole list, so \
  \EVERY hole after a filled one is renumbered whether or not any text moved. \
  \Neither survives an arbitrary edit: after a fill you keep, take the next \
  \address from that response's holes list rather than reusing coordinates from \
  \before it. A position addresses the hole whose span contains it (a position \
  \at its first character counts); a position inside no hole is an error \
  \listing the file's nearest holes, never a guess. Give one spelling or the \
  \other — a request carrying both is rejected, because the two can disagree — \
  \and see the schema's oneOf for the three shapes a legal request has."

-- | filePathDoc: the resolution rule, at the property that carries the path.
--
-- The four file-taking tools used to say "absolute or relative to cwd" without
-- saying /whose/ cwd, and for any client outside this repository the honest
-- answer — the server's own working directory — was never the one meant.  The
-- #83 field test measured the cost: an agent sent the relative path natural in
-- its own project, the server resolved it against its own checkout, the file
-- was not there, and the client never called the server again (issue #101).
-- Saying it plainly here is half the repair; the other half is that a path
-- resolving to nothing now fails by name rather than silently or opaquely.
filePathDoc :: Text
filePathDoc =
  "Path to the Agda file. PASS AN ABSOLUTE PATH. A relative path is resolved \
  \against THIS SERVER'S working directory — the server is a separate process, \
  \normally started in its own checkout rather than in your project, so a path \
  \relative to your project does not name your file here. A path that resolves \
  \to no readable file is refused with an error naming the path AS RESOLVED and \
  \this server's working directory; it is never quietly checked somewhere else, \
  \and it is never an opaque internal error."

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
  \for literate sources). Requires column (or col). The address to prefer: it \
  \moves only when a fill above it moves the text, whereas holeIndex is \
  \renumbered by any fill at all. Re-anchor it from each response's holes list."

columnDoc :: Text
columnDoc =
  "1-based column of the hole, in the file as written. Requires line. Give this \
  \or col, not both."

colDoc :: Text
colDoc =
  "The same thing as column, accepted because that is how the hole listings \
  \spell it — so a hole entry from get_diagnostics, check_file, or a fill_hole \
  \response can be passed back without renaming anything (its other keys, index \
  \and goal, are ignored). Requires line. Give this or column, not both."

holeIndexDoc :: Text
holeIndexDoc =
  "0-based index of the hole, in source order (any hole syntax). Accepted for \
  \backward compatibility and SHIFT-PRONE: filling any hole renumbers every \
  \hole after it — even a fill that moves no text — so an index from an earlier \
  \call may now name a different hole. Prefer (line, column). Give one or the \
  \other, never both."

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

-- | gateModel: which command @check_project@ runs, and how it decided (issue
-- #78).
--
-- An agent that cannot predict what the tool will run has to run the gate
-- itself to be sure — the whole failure this tool exists to end — so the
-- resolution order belongs in the description, not only in the response.
gateModel :: Text
gateModel =
  "THE GATE: chosen in this order — the make target named by `target` (the \
  \nearest Makefile above the anchor that declares it, run in that Makefile's \
  \own directory); else this server's --check-command, if the operator \
  \configured one (run directly, never through a shell); else the nearest \
  \Makefile's `check` target; else agda on the project's Everything module \
  \(Everything.agda or a literate flavour). The upward search stops at the \
  \repository boundary. If none of those exists the call FAILS, naming every \
  \directory it searched and what to configure — it never reports a check that \
  \did not happen. gate {source, target?, makefile?, entry?, searchedFrom} in \
  \the response says which one ran and on what evidence, and command echoes the \
  \exact argument vector and working directory."

-- | projectHonestyNote: the one thing the tool exists for, said where a client
-- reads it.
projectHonestyNote :: Text
projectHonestyNote =
  "success is true if and only if the gate exited 0, finished inside the bound, \
  \AND its output carried no failure evidence — an Agda error diagnostic, or the \
  \gate's own failure line (make reporting a recipe that died). exitCode is the \
  \gate's own status whenever the gate produced one, echoed verbatim and never \
  \reinterpreted, so a failing gate can never be reported green; the two runs \
  \with no status of their own — a gate that could not be started, and one \
  \killed at the bound — report -1, and timedOut tells them apart. The reverse \
  \is deliberate: a gate that exits 0 \
  \with such evidence in its output is reported as success:false with \
  \maskedFailure:true — a wrapper script whose last command is an echo exits 0 \
  \whatever make did, which is the trap that forces agents to grep build logs \
  \for 'error:'. Read success; you do not have to grep the log. Those two \
  \recognizers are a list, not a theory of failure: a mask that prints neither \
  \is reported as a pass, which is why outputTail comes back whatever the \
  \verdict — the response never claims a pass while withholding the output that \
  \could contradict it."

-- | projectPayloadNote: what a project response carries beyond the diagnostics
-- list, and what each field is for.
projectPayloadNote :: Text
projectPayloadNote =
  "firstError is the first error-severity diagnostic, lifted out so you need \
  \not scan the (capped) diagnostics list. failingModule and failingFile name \
  \the module the gate stopped in, and appear only on a check that did not \
  \pass: the one carrying that error, or — when the gate failed without a \
  \located error, a timeout included — the last module agda started. \
  \modulesChecked counts the distinct \
  \modules agda re-typechecked from source, so it says how much of the project \
  \was actually rebuilt and, on a timeout, how far the run got. outputTail is \
  \the bounded tail of the gate's stdout and stderr, returned whatever the \
  \verdict and absent only when the gate printed nothing, because a gate can \
  \fail for reasons agda never printed (no such target, a missing tool, a killed \
  \build) and an unrecognized mask is reported as a pass."

-- | projectTimingNote: the cost model of a whole-project check, including the
-- fact that this call blocks.
projectTimingNote :: Text
projectTimingNote =
  "COST: this call BLOCKS for the whole gate and does not stream progress; a \
  \large library's gate running for 10-20 minutes is ordinary, and elapsedMs \
  \reports the wall-clock time at the end. It is bounded by the server's \
  \--check-timeout (default 1800s), which is a SEPARATE bound from the per-file \
  \--timeout; timeoutSeconds echoes the bound that was in effect. On expiry the \
  \gate's whole process group is killed — make and every agda under it — and the \
  \response is success:false with timedOut:true and a timeout error diagnostic, \
  \still carrying elapsedMs, modulesChecked, and failingModule so you can see \
  \where it reached."

-- | projectEchoNote: the response echo, in the vocabulary of a gate rather than
-- of one agda call (issues #72, #76).
projectEchoNote :: Text
projectEchoNote =
  "EVERY response carries the echo: verdict {equivalentTo, meaning, exitCode} — \
  \the exact command this call is equivalent to, including the directory it runs \
  \in, what success means, and the gate's own exit code; command {binary, args, \
  \cwd}; and project {rootSource, root, library, librariesFile, \
  \registeredLibraries, selectedLibraries, includePaths} — the tree the gate ran \
  \in, resolved from the anchor exactly as check_file resolves it from a file. \
  \One difference worth knowing: for a make or --check-command gate, \
  \selectedLibraries and includePaths are this server's own configuration and \
  \not a claim about the flags the gate passed agda, since the gate chooses \
  \those itself; for the Everything gate they are what agda finally received. If \
  \the anchor belongs to a different checkout of a library this server has \
  \registered elsewhere, the call FAILS with a rootMismatch object naming both \
  \roots rather than running a gate against the other tree."

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

-- | liveLaneNote: the interaction-lane contract, stated in every live-query
-- tool description (issue #75): the process model and its latency, the
-- verdict boundary, the in-band error model, and the response echo.
liveLaneNote :: Text
liveLaneNote =
  "LIVE QUERY (interaction lane): answered by a persistent agda \
  \--interaction-json process this server keeps per project root. The file \
  \is loaded once and re-loaded only when it changes on disk or its flags \
  \change (lane.load in the response says what happened: reused, first, \
  \switch, changed, or retry), so the FIRST question about a file costs one \
  \load — seconds, comparable to one check_file — and every further question \
  \about the unchanged file is milliseconds. Editing a dependency is picked \
  \up when this file itself is next re-loaded. THIS TOOL INFORMS AND NEVER \
  \DECIDES A BUILD VERDICT: interaction-mode agda is tolerant (it loads \
  \files with open holes), so there is no success or verdict field here; \
  \check_file, check_project, and fill_hole remain the only verdict sources. \
  \A file that does not load answers with error.stage='load' carrying Agda's \
  \message, and the query is not run. A process-level failure — timeout \
  \(the same --timeout bound as the batch tools; the child is killed and \
  \respawned on next use), crash, or could-not-start — is an isError result \
  \whose text is a JSON object naming the event, the root, the exact IOTCM \
  \lines sent, and agda's last stderr lines. EVERY response echoes: lane \
  \{root, pid, spawned, load, loadElapsedMs?, agdaVersion, iotcm}, command \
  \{binary, args, cwd} (the persistent child; per-file flags ride the \
  \Cmd_load line visible in lane.iotcm), project {the same block the batch \
  \tools report}, elapsedMs, and checkedFromSource (whether this call \
  \re-typechecked the file from source). Pass reload:true to force a fresh \
  \load first — the escape hatch for a changed DEPENDENCY, which no stamp \
  \on the queried file can see; the response echoes lane.load='forced'."

-- | liveLineNote: what the optional @line@ argument selects, and why it
-- matters for scope questions (the probed § 2.6 degradation).
liveLineNote :: Text
liveLineNote =
  "SCOPE: if line falls inside a hole, the query runs in that goal's scope — \
  \local variables become visible, and names opened from file-local modules \
  \resolve that the completed top-level scope of a hole-free file loses. \
  \Otherwise it runs against the file's top-level scope. The response's \
  \scope field says which happened."

-- | liveFilePathDoc: the path rule for live-query tools — the batch tools'
-- resolution rule (issue #101), plus what the file means to a scope query.
liveFilePathDoc :: Text
liveFilePathDoc =
  "The Agda file whose scope answers the question. PASS AN ABSOLUTE PATH; a \
  \relative one is resolved against THIS SERVER'S working directory, and a \
  \path naming no readable file is refused with an error naming the path as \
  \resolved. Every literate flavour Agda 2.8 supports is accepted, with all \
  \positions in literate-file coordinates."

-- | liveLineDoc: the @line@ property's contract.
liveLineDoc :: Text
liveLineDoc =
  "Optional 1-based line in the file as written. Inside a hole: the query \
  \runs in that goal's scope (locals visible). Elsewhere or omitted: the \
  \file's top-level scope."

-- | liveReloadDoc: the @reload@ property's contract.
liveReloadDoc :: Text
liveReloadDoc =
  "Optional; default false. Force a fresh Cmd_load before answering, even \
  \though this file's stamp is unchanged — the escape hatch after editing a \
  \DEPENDENCY of this file, which the lane's own change detection cannot \
  \see. Agda re-examines the dependencies on that load and re-checks what \
  \changed; checkedFromSource reports whether this file itself was \
  \re-typechecked. The response echoes lane.load='forced'."

-- | Build a tool definition object (MCP tools/list schema).
toolDef :: Text -> Text -> [(Text, Value)] -> [Text] -> Value
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
toolDefWith :: Text -> Text -> [(Text, Value)] -> [Text] -> [(Text, Value)] -> Value
toolDefWith name desc props required extra = object
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
  -- created here, threaded to dispatch, and shut down on EVERY exit path —
  -- the asynchronous exceptions the dispatch deliberately re-throws escape
  -- 'loop', and an embedding that cancels 'runServer' must not leave agda
  -- children behind (a Copilot review catch on PR 107; in the shipped binary
  -- the children would EOF-exit when the process dies anyway, but the
  -- 'finally' is what makes the cleanup hold for any embedding).
  lanes <- newInteractionLanes
  loop lanes `finally` shutdownLanes lanes
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
  outcome <- try (dispatchTool cfg lanes name args >>= forceResponse)
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
dispatchTool :: ServerConfig -> InteractionLanes -> Text -> Value -> IO Value

-- Proof-state tools (existing M1-2)
dispatchTool cfg _lanes "get_goal" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp <$> handleGetGoal (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg _lanes "fill_hole" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp <$> handleFillHole (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg _lanes "check_file" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp <$> handleCheckFile (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg _lanes "get_diagnostics" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp <$> handleGetDiagnostics (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

-- Whole-project gate (M1-5, issue #78).  The one tool that takes the gate
-- configuration as well as the Agda one.
dispatchTool cfg _lanes "check_project" args =
  case Aeson.fromJSON args of
    Aeson.Success p ->
      failureToMcp <$> handleCheckProject (scAgdaConfig cfg) (scGateConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

-- Search tools (new M1-3)
dispatchTool cfg _lanes "search_by_name" args =
  case scCorpusIndex cfg of
    Nothing  -> pure $ toolError "No corpus loaded.  Start the server with --corpus <path.jsonl>."
    Just idx ->
      case Aeson.fromJSON args of
        Aeson.Success p -> pure . eitherToMcp $ handleSearchByName idx p
        Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg _lanes "search_by_type" args =
  case scCorpusIndex cfg of
    Nothing  -> pure $ toolError "No corpus loaded.  Start the server with --corpus <path.jsonl>."
    Just idx ->
      case Aeson.fromJSON args of
        Aeson.Success p -> pure . eitherToMcp $ handleSearchByType idx p
        Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg _lanes "get_dependencies" args =
  case scCorpusIndex cfg of
    Nothing  -> pure $ toolError "No corpus loaded.  Start the server with --corpus <path.jsonl>."
    Just idx ->
      case Aeson.fromJSON args of
        Aeson.Success p -> pure . eitherToMcp $ handleGetDependencies idx p
        Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

-- Live-query tools (issue #75): the interaction lane.
dispatchTool cfg lanes "type_of" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp <$> handleTypeOf lanes (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg lanes "normalize" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp <$> handleNormalize lanes (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg lanes "resolve_name" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp <$> handleResolveName lanes (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg lanes "definition_of" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp <$> handleDefinitionOf lanes (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

dispatchTool cfg lanes "exports_of" args =
  case Aeson.fromJSON args of
    Aeson.Success p -> failureToMcp <$> handleExportsOf lanes (scAgdaConfig cfg) p
    Aeson.Error e   -> pure $ toolError ("Invalid arguments: " <> T.pack e)

-- Unknown tool
dispatchTool _ _ name _ =
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
failureToMcp :: ToJSON a => Either ToolFailure a -> Value
failureToMcp = either render okToMcp
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
