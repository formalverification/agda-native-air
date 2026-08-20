-- | LiveQueries.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Tools/LiveQueries.hs
--
-- Description:
--   The interaction-lane tools: type_of, normalize, resolve_name, definition_of,
--   and exports_of.  Each answers a read-only question about a file's scope from
--   the persistent @agda --interaction-json@ child that AgdaMCP.Interaction runs
--   per resolved project root.  There's no edit to the file, no cold subprocess
--   per question, and no build verdict anywhere in the response; interaction mode
--   is tolerant by design, so verdicts stay with the batch tools (the two
--   interface lanes described in docs/agda-mcp-interaction-lane.md § 1).
--
--   Every handler shares one spine ('withLiveFile'): resolve and read the
--   requested path, resolve its library context and refuse a wrong-checkout call,
--   take the root's lane, and make sure the file is loaded (re-loading only on
--   evidence: first sight, switch, changed stamp or flags, failed previous load).
--   The handlers then differ only in which IOTCM command they send and how they
--   shape its response.
--
--   Failure taxonomy, deliberately three-way:
--
--   * A lane-process failure (spawn failure, timeout kill, crash) is a
--     'AgdaMCP.Types.InteractionFailure', an @isError@ tool result carrying the
--     root, wire lines sent, and the child's last words (never an opaque -32603).
--   * An Agda-level negative (the file does not load, the expression does not
--     typecheck, the module is not in scope) is an in-band 'AgdaMCP.Types.LiveError'
--     inside a success-shaped response, because for a "check a term without
--     committing to it" tool the negative answer is a product, exactly as
--     fill_hole's @type_error@ status is.
--   * A path or project refusal is the same structured failure the batch
--     tools raise, from the same 'withSourceFile' / 'withProject' seams.
--
--   Scope selection: an optional @line@ argument names the goal whose range
--   contains it, and the query runs goal-scoped there, which is what makes local
--   variables visible, and on a hole-free file is the difference between seeing
--   opened names and not (the § 2.6 degradation).  With no line, or a line inside
--   no goal, the query runs against the file's top-level scope, and the-response's
--   @scope@ field says which happened.
--
--   resolve_name additionally runs the § 2.6 recovery when WhyInScope says
--   "not in scope": an inference of the bare name whose AmbiguousName error lists
--   every candidate with its binding site, or whose did-you-mean suggestions are
--   each re-resolved for their full provenance chains.  The response's
--   @recovered@ field names the route taken, so a client can tell a first-class
--   answer from a reconstructed one.

{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module AgdaMCP.Tools.LiveQueries
  ( handleTypeOf
  , handleNormalize
  , handleResolveName
  , handleDefinitionOf
  , handleExportsOf
    -- * Shared with the lane-sourced get_goal (issue #108)
  , interactionFailure
  , laneCommandEcho
  , laneEchoFrom
    -- * Exposed for testing
  , candidateFrom
  , defSiteFrom
  ) where

import Control.Exception (IOException, catch)
import Data.Aeson (Value (..))
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Vector as V
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word64)
import GHC.Clock (getMonotonicTimeNSec)
import System.Directory (getCurrentDirectory)

import AgdaMCP.Agda (AgdaConfig (..))
import AgdaMCP.Interaction
import AgdaMCP.Path (withSourceFile)
import AgdaMCP.Project
  ( fileDirIncludeFlags, projectExtraFlags, resolveProject, withEffectiveFlags )
import AgdaMCP.Types

-- ---------------------------------------------------------------------------
-- The shared spine
-- ---------------------------------------------------------------------------

-- | LiveCtx: everything a handler body needs once the file is loaded (or its
-- load has failed, which the body reports in band).
data LiveCtx = LiveCtx
  { lcHandle  :: LaneHandle
  , lcAbsPath :: FilePath
  , lcLoad    :: LoadReport
  , lcProject :: ProjectContext
  , lcConfig  :: AgdaConfig
  , lcStartNs :: Word64
  }

-- | withLiveFile: the spine shared by all five handlers.  Mirrors the batch
-- tools' 'AgdaMCP.Tools.ProofState.withProject' flag assembly exactly (the
-- server's flags, plus what resolution implies, plus the file's own directory
-- when nothing else reaches it) so a lane load resolves against the same
-- tree as a batch check of the same file, by construction.
withLiveFile
  :: InteractionLanes
  -> AgdaConfig
  -> FilePath
  -> Bool       -- ^ @reload@: force a fresh load (a changed dependency).
  -> (LiveCtx -> IO (Either ToolFailure a))
  -> IO (Either ToolFailure a)
withLiveFile lanes cfg0 requested reload body =
  withSourceFile requested $ \absPath _bytes _src -> do
    resolved <- resolveProject cfg0 absPath
    case resolved of
      Left mismatch -> pure (Left (FailProject mismatch))
      Right pc0     -> do
        let baseFlags = agdaFlags cfg0 <> projectExtraFlags pc0
        dirFlags <- fileDirIncludeFlags baseFlags pc0 absPath
        let effFlags = baseFlags <> dirFlags
            pc  = withEffectiveFlags effFlags pc0
            cfg = cfg0 { agdaFlags = effFlags }
        startNs <- getMonotonicTimeNSec
        outcome <- withLane lanes cfg (pcRoot pc) $ \lh -> do
          loaded <- ensureLoaded lh reload absPath effFlags
          case loaded of
            Left lf -> Left . FailInteraction
                         <$> interactionFailure pc cfg startNs lf
            Right lr ->
              body (LiveCtx lh absPath lr pc cfg startNs)
        case outcome of
          Left lf      -> Left . FailInteraction
                            <$> interactionFailure pc cfg startNs lf
          Right result -> pure result

-- | interactionFailure: shape a lane-level failure, wherever in the request it
-- struck.  The telemetry is real on every path: 'lfSent' carries the wire lines
-- the failing request attempted ('doomWith' records them for mid-request fails,
-- the spawn path for its startup flush) and elapsed time runs from the request's
-- own start.  Empty lines mean the child could not even be created, or the
-- registry refused the request at shutdown; there was genuinely nothing to echo.
interactionFailure
  :: ProjectContext -> AgdaConfig -> Word64 -> LaneFailure
  -> IO InteractionFailure
interactionFailure pc cfg startNs lf = do
  echo  <- laneCommandEcho cfg
  endNs <- getMonotonicTimeNSec
  pure InteractionFailure
    { xfEvent      = eventText (lfEvent lf)
    , xfMessage    = lfMessage lf
    , xfStderrTail = lfStderrTail lf
    , xfElapsedMs  = fromIntegral ((endNs - startNs) `div` 1_000_000)
    , xfRoot       = pcRoot pc
    , xfIotcm      = lfSent lf
    , xfCommand    = echo
    , xfProject    = pc
    }

eventText :: LaneEvent -> Text
eventText LaneSpawnFailure = "spawn-failure"
eventText LaneTimeout      = "timeout"
eventText LaneCrash        = "crash"
eventText LaneShutdown     = "shutdown"

-- | laneCommandEcho: the child's invocation.  The per-file flags ride each
-- Cmd_load rather than the process argv (design document § 3), which is why
-- this echo is short and the @lane.iotcm@ lines carry the flags.  The child
-- inherits the server's working directory (batch parity, so relative server
-- flags resolve identically in both lanes) and that is the cwd echoed.
laneCommandEcho :: AgdaConfig -> IO CommandEcho
laneCommandEcho cfg = do
  cwd <- getCurrentDirectory `catch` \(_ :: IOException) -> pure "."
  pure CommandEcho
    { ceBinary = agdaBin cfg
    , ceArgs   = ["--interaction-json"]
    , ceCwd    = cwd
    }

-- | liveMeta: the echo block of a completed call.
liveMeta :: LiveCtx -> IO LiveMeta
liveMeta ctx = do
  echo  <- laneCommandEcho (lcConfig ctx)
  lane  <- laneEchoFrom (pcRoot (lcProject ctx)) (lcHandle ctx) (lcLoad ctx)
  endNs <- getMonotonicTimeNSec
  pure LiveMeta
    { lmElapsedMs         =
        fromIntegral ((endNs - lcStartNs ctx) `div` 1_000_000)
    , lmCheckedFromSource = lrCheckedFromSource (lcLoad ctx)
    , lmLane    = lane
    , lmCommand = echo
    , lmProject = lcProject ctx
    }

-- | laneEchoFrom: the lane block of a completed request — shared by the five
-- live-query tools and the lane-sourced @get_goal@ (issue #108).
laneEchoFrom :: FilePath -> LaneHandle -> LoadReport -> IO LaneEcho
laneEchoFrom root lh lr = do
  sent <- laneSentLines lh
  ver  <- laneAgdaVersion lh
  pid  <- lanePidOf lh
  pure LaneEcho
    { lchRoot          = root
    , lchPid           = pid
    , lchSpawned       = laneWasSpawned lh
    , lchLoad          = loadActionText (lrAction lr)
    , lchLoadElapsedMs = case lrAction lr of
        LoadReused -> Nothing
        _          -> Just (lrElapsedMs lr)
    , lchAgdaVersion   = ver
    , lchIotcm         = sent
    }

loadActionText :: LoadAction -> Text
loadActionText LoadReused  = "reused"
loadActionText LoadFirst   = "first"
loadActionText LoadSwitch  = "switch"
loadActionText LoadChanged = "changed"
loadActionText LoadRetry   = "retry"
loadActionText LoadForced  = "forced"

-- | loadError: the in-band error for a file whose load failed.  The query
-- was not run; saying so, with Agda's message, is the whole answer.
loadError :: Text -> LiveError
loadError msg = LiveError
  { lveStage   = "load"
  , lveCode    = errorCodeOf msg
  , lveMessage = msg
  }

-- | QueryScope: where a query runs, plus the text the response reports.
data QueryScope = AtGoal Int | Toplevel

scopeFor :: Maybe Int -> Maybe Int -> LoadReport -> (QueryScope, Text)
scopeFor mLine mCol lr = case (mLine, lrOutcome lr) of
  (Just ln, Right li)
    | Just p <- pointContaining ln mCol (liPoints li) ->
        ( AtGoal (ipId p)
        , "goal " <> T.pack (show (ipId p)) <> " (line " <> T.pack (show ln)
          <> maybe "" ((", column " <>) . T.pack . show) mCol <> ")"
        )
    | otherwise ->
        ( Toplevel
        , "toplevel (line " <> T.pack (show ln)
          <> maybe "" ((", column " <>) . T.pack . show) mCol
          <> " is inside no goal)"
        )
  _ -> (Toplevel, "toplevel")

-- | runShaped: send one query and shape its responses, converting a lane
-- failure with full context.
runShaped
  :: LiveCtx -> Text
  -> ([IResponse] -> IO (Either ToolFailure a))
  -> IO (Either ToolFailure a)
runShaped ctx cmd shape = do
  rs <- runQuery (lcHandle ctx) (lcAbsPath ctx) cmd
  case rs of
    Left lf -> Left . FailInteraction
                 <$> interactionFailure (lcProject ctx) (lcConfig ctx)
                                        (lcStartNs ctx) lf
    Right resps -> shape resps


-- ---------------------------------------------------------------------------
-- Response extraction
-- ---------------------------------------------------------------------------

-- | answerOf: the expression answer of the given kind (@InferredType@ or
-- @NormalForm@, whose @expr@ field carries it) accepted from either wire
-- position: a toplevel @DisplayInfo@ of that kind, or the same payload
-- wrapped in a goal-scoped @GoalSpecific.goalInfo@.
answerOf :: Text -> [IResponse] -> Maybe Text
answerOf kind rs = listToMaybe $
  [ t | IDisplayInfo k (Object io) <- rs
      , k == kind
      , Just t <- [textOf "expr" io] ]
  <> [ t | r <- rs
         , Just (Object gi) <- [goalInfoOf r]
         , textOf "kind" gi == Just kind
         , Just t <- [textOf "expr" gi] ]

inferredTypeOf :: [IResponse] -> Maybe Text
inferredTypeOf = answerOf "InferredType"

normalFormOf :: [IResponse] -> Maybe Text
normalFormOf = answerOf "NormalForm"

-- | whyInScopeMessageOf: the provenance prose of a @WhyInScope@ answer.
whyInScopeMessageOf :: [IResponse] -> Maybe Text
whyInScopeMessageOf rs = listToMaybe
  [ m | IDisplayInfo "WhyInScope" (Object io) <- rs
      , Just m <- [textOf "message" io] ]

-- | moduleSurfaceOf: the full surface of a @ModuleContents@ answer; the
-- value members (@contents@), the exported nested modules (@names@ probed:
-- a nested @module@ appears there and nowhere in @contents@), and the
-- @telescope@ passed through verbatim when nonempty (never observed under
-- 2.8.0, where a parameterized module's binders arrive folded into each
-- member's type; carried so a future shape is not silently dropped).
moduleSurfaceOf :: [IResponse] -> Maybe ([ExportEntry], [Text], Maybe Value)
moduleSurfaceOf rs = listToMaybe
  [ ( maybe [] entriesFrom (KM.lookup "contents" io)
    , maybe [] namesFrom   (KM.lookup "names" io)
    , case KM.lookup "telescope" io of
        Just v@(Array a) | not (V.null a) -> Just v
        _                                 -> Nothing
    )
  | IDisplayInfo "ModuleContents" (Object io) <- rs
  ]
  where
    entriesFrom (Array a) = mapMaybe entryFrom (V.toList a)
    entriesFrom _         = []
    entryFrom (Object e)  =
      ExportEntry <$> textOf "name" e <*> textOf "term" e
    entryFrom _ = Nothing
    namesFrom (Array a) = [n | String n <- V.toList a]
    namesFrom _         = []

-- | queryError: the first Agda error among the responses, shaped in band.
queryError :: Text -> [IResponse] -> Maybe LiveError
queryError stage rs = case mapMaybe errorMessageOf rs of
  (msg : _) -> Just (LiveError stage (errorCodeOf msg) msg)
  []        -> Nothing

textOf :: Text -> KM.KeyMap Value -> Maybe Text
textOf k o = case KM.lookup (Key.fromText k) o of
  Just (String t) -> Just t
  _               -> Nothing


-- ---------------------------------------------------------------------------
-- Candidate shaping
-- ---------------------------------------------------------------------------

-- | defSiteFrom: a parsed source location as the wire's 'DefSite'.
defSiteFrom :: Maybe Text -> SrcLoc -> DefSite
defSiteFrom qual loc = DefSite
  { dsQualified = qual
  , dsFile      = slFile loc
  , dsLine      = slLine loc
  , dsCol       = slCol loc
  , dsEndLine   = slEndLine loc
  , dsEndCol    = slEndCol loc
  }

-- | candidateFrom: one WhyInScope bullet as the wire's 'NameCandidate'.
candidateFrom :: ScopeCandidate -> NameCandidate
candidateFrom sc = NameCandidate
  { ncDescription = scDescription sc
  , ncQualified   = scQualified sc
  , ncProvenance  =
      [ ProvenanceEcho (psStep st) (defSiteFrom Nothing <$> psLocation st)
      | st <- scChain sc ]
  , ncDefinition  = defSiteFrom (scQualified sc) <$> scDefinition sc
  }


-- ---------------------------------------------------------------------------
-- type_of
-- ---------------------------------------------------------------------------

-- | handleTypeOf: Agda's @C-c C-d@ on an expression that need not be in the
-- file.  Goal-scoped when the (line, column) position addresses a goal,
-- else toplevel.
handleTypeOf
  :: InteractionLanes -> AgdaConfig -> TypeOfParams
  -> IO (Either ToolFailure TypeOfResult)
handleTypeOf lanes cfg0 p =
  withLiveFile lanes cfg0 (topFilePath p) (topReload p) $ \ctx ->
    case lrOutcome (lcLoad ctx) of
      Left loadMsg -> do
        meta <- liveMeta ctx
        pure . Right $ TypeOfResult (topExpr p) "toplevel"
          Nothing (Just (loadError loadMsg)) meta
      Right _ -> do
        let (scope, scopeTxt) = scopeFor (topLine p) (topColumn p) (lcLoad ctx)
            cmd = case scope of
              AtGoal g -> cmdInferAtGoal g (topExpr p)
              Toplevel -> cmdInferToplevel (topExpr p)
        runShaped ctx cmd $ \resps -> do
          meta <- liveMeta ctx
          pure . Right $ TypeOfResult
            { torExpr  = topExpr p
            , torScope = scopeTxt
            , torType  = inferredTypeOf resps
            , torError = case inferredTypeOf resps of
                Just _  -> Nothing
                Nothing -> Just (fromMaybe (opaqueAnswer "expression" resps)
                                           (queryError "expression" resps))
            , torMeta  = meta
            }

-- | opaqueAnswer: the fallback error when Agda answered with neither the
-- expected payload nor an error; this is named as such rather than guessed at,
-- with the stage supplied by the caller to match its 'queryError'.
opaqueAnswer :: Text -> [IResponse] -> LiveError
opaqueAnswer stage rs = LiveError
  { lveStage   = stage
  , lveCode    = Nothing
  , lveMessage = "agda answered with neither a result nor an error; kinds seen: "
      <> T.intercalate ", " (map kindOf rs)
  }
  where
    kindOf r = case r of
      IDisplayInfo k _    -> "DisplayInfo/" <> k
      IInteractionPoints _ -> "InteractionPoints"
      IRunningInfo _      -> "RunningInfo"
      IOther k _          -> k
      IUnreadable _       -> "unreadable"


-- ---------------------------------------------------------------------------
-- normalize
-- ---------------------------------------------------------------------------

-- | handleNormalize: Agda's @C-c C-n@ (evaluate an expression to normal form
-- in the file's scope).
handleNormalize
  :: InteractionLanes -> AgdaConfig -> NormalizeParams
  -> IO (Either ToolFailure NormalizeResult)
handleNormalize lanes cfg0 p =
  withLiveFile lanes cfg0 (nomFilePath p) (nomReload p) $ \ctx ->
    case lrOutcome (lcLoad ctx) of
      Left loadMsg -> do
        meta <- liveMeta ctx
        pure . Right $ NormalizeResult (nomExpr p) "toplevel"
          Nothing (Just (loadError loadMsg)) meta
      Right _ -> do
        let (scope, scopeTxt) = scopeFor (nomLine p) (nomColumn p) (lcLoad ctx)
            cmd = case scope of
              AtGoal g -> cmdComputeAtGoal g (nomExpr p)
              Toplevel -> cmdComputeToplevel (nomExpr p)
        runShaped ctx cmd $ \resps -> do
          meta <- liveMeta ctx
          pure . Right $ NormalizeResult
            { nrExpr       = nomExpr p
            , nrScope      = scopeTxt
            , nrNormalForm = normalFormOf resps
            , nrError      = case normalFormOf resps of
                Just _  -> Nothing
                Nothing -> Just (fromMaybe (opaqueAnswer "expression" resps)
                                           (queryError "expression" resps))
            , nrMeta       = meta
            }


-- ---------------------------------------------------------------------------
-- resolve_name / definition_of
-- ---------------------------------------------------------------------------

-- | Resolution: what the shared resolve machinery found, before the two
-- tools shape it differently.
data Resolution = Resolution
  { resScopeTxt   :: Text
  , resInScope    :: Bool
  , resCandidates :: [NameCandidate]
  , resRecovered  :: Maybe Text
  , resError      :: Maybe LiveError
  }

-- | resolveMachinery: WhyInScope first; on "not in scope" (the § 2.6 recovery)
-- this is an inference of the bare name whose AmbiguousName error carries
-- every candidate's binding site, or whose did-you-mean suggestions are each
-- re-resolved for their chains.
resolveMachinery
  :: LiveCtx -> Text -> Maybe Int -> Maybe Int
  -> IO (Either ToolFailure Resolution)
resolveMachinery ctx name mLine mCol = do
  let (scope, scopeTxt) = scopeFor mLine mCol (lcLoad ctx)
      whyCmd n = case scope of
        AtGoal g -> cmdWhyInScopeAtGoal g n
        Toplevel -> cmdWhyInScopeToplevel n
      inferCmd = case scope of
        AtGoal g -> cmdInferAtGoal g name
        Toplevel -> cmdInferToplevel name
  runShaped ctx (whyCmd name) $ \resps ->
    case whyInScopeMessageOf resps of
      Nothing -> pure . Right $ Resolution scopeTxt False []
        Nothing (Just (fromMaybe (opaqueAnswer "name" resps)
                                 (queryError "name" resps)))
      Just msg -> case parseWhyInScope msg of
        Just cands@(_ : _) -> pure . Right $
          Resolution scopeTxt True (map candidateFrom cands) Nothing Nothing
        Just [] -> pure . Right $ Resolution scopeTxt True [] Nothing Nothing
        Nothing ->
          -- Not in scope as written: recover through the name's own errors.
          -- Both routes below resolve each recovered qualified spelling with
          -- its own WhyInScope, so recovered candidates carry provenance
          -- chains like first-class ones (§ 2.6 of the design document:
          -- qualified names resolve even in the completed toplevel scope).
          runShaped ctx inferCmd $ \inferResps ->
            case mapMaybe errorMessageOf inferResps of
              (errMsg : _)
                -- No input under the pinned 2.8.0 is known to reach this
                -- branch: the shapes probed for the design document route to
                -- did-you-mean (completed toplevel scope) or to an in-scope
                -- WhyInScope answer (goal scope, or a holed file's toplevel).
                -- It exists because [AmbiguousName] is documented output of
                -- Cmd_infer, and if it ever fires the recovery must not lose
                -- it; the binding site from the error is the fallback when
                -- the qualified lookup answers nothing.
                | ambs@(_ : _) <- parseAmbiguousName errMsg ->
                    resolveEach scopeTxt whyCmd "ambiguous-name-error"
                      [ (q, Just (bindingSiteCandidate q mLoc))
                      | (q, mLoc) <- ambs ]
                | suggs@(_ : _) <- parseDidYouMean errMsg ->
                    resolveEach scopeTxt whyCmd "did-you-mean"
                      [ (sugg, Nothing) | sugg <- suggs ]
              _ -> pure . Right $
                Resolution scopeTxt False [] Nothing Nothing
  where
    -- resolveEach: the shared engine of both recovery routes — one
    -- WhyInScope per recovered qualified spelling, its parsed candidates
    -- taken whole, the per-item fallback (a binding-site-only candidate, or
    -- nothing) used when the lookup answers nothing.
    resolveEach scopeTxt whyCmd tag items = go items []
      where
        go [] acc = pure . Right $
          Resolution scopeTxt False (reverse acc) (Just tag) Nothing
        go ((q, mFallback) : rest) acc =
          runShaped ctx (whyCmd q) $ \resps ->
            case parseWhyInScope =<< whyInScopeMessageOf resps of
              Just cands@(_ : _) ->
                go rest (reverse (map candidateFrom cands) <> acc)
              _ -> go rest (maybe acc (: acc) mFallback)

    bindingSiteCandidate q mLoc = NameCandidate
      { ncDescription = "bound as " <> q
      , ncQualified   = Just q
      , ncProvenance  = []
      , ncDefinition  = defSiteFrom (Just q) <$> mLoc
      }

-- | handleResolveName: the AmbiguousName moment (candidates with their
-- provenance chains).
handleResolveName
  :: InteractionLanes -> AgdaConfig -> ResolveNameParams
  -> IO (Either ToolFailure ResolveNameResult)
handleResolveName lanes cfg0 p =
  withLiveFile lanes cfg0 (rnpFilePath p) (rnpReload p) $ \ctx ->
    case lrOutcome (lcLoad ctx) of
      Left loadMsg -> do
        meta <- liveMeta ctx
        pure . Right $ ResolveNameResult (rnpName p) "toplevel" False []
          Nothing (Just (loadError loadMsg)) meta
      Right _ -> do
        resolved <- resolveMachinery ctx (rnpName p) (rnpLine p) (rnpColumn p)
        case resolved of
          Left tf  -> pure (Left tf)
          Right res -> do
            meta <- liveMeta ctx
            pure . Right $ ResolveNameResult
              { rnrName       = rnpName p
              , rnrScope      = resScopeTxt res
              , rnrInScope    = resInScope res
              , rnrCandidates = resCandidates res
              , rnrRecovered  = resRecovered res
              , rnrError      = resError res
              , rnrMeta       = meta
              }

-- | handleDefinitionOf: the single most common grep an agent runs, answered
-- by the type-checker, through re-exports and module applications, which
-- grep cannot see.
handleDefinitionOf
  :: InteractionLanes -> AgdaConfig -> DefinitionOfParams
  -> IO (Either ToolFailure DefinitionOfResult)
handleDefinitionOf lanes cfg0 p =
  withLiveFile lanes cfg0 (dopFilePath p) (dopReload p) $ \ctx ->
    case lrOutcome (lcLoad ctx) of
      Left loadMsg -> do
        meta <- liveMeta ctx
        pure . Right $ DefinitionOfResult (dopName p) "toplevel" [] []
          Nothing (Just (loadError loadMsg)) meta
      Right _ -> do
        resolved <- resolveMachinery ctx (dopName p) (dopLine p) (dopColumn p)
        case resolved of
          Left tf  -> pure (Left tf)
          Right res -> do
            meta <- liveMeta ctx
            let located   = mapMaybe ncDefinition (resCandidates res)
                unlocated = [ ncDescription c
                            | c <- resCandidates res
                            , Nothing <- [ncDefinition c] ]
            pure . Right $ DefinitionOfResult
              { dorName        = dopName p
              , dorScope       = resScopeTxt res
              , dorDefinitions = located
              , dorUnlocated   = unlocated
              , dorRecovered   = resRecovered res
              , dorError       = case (located, unlocated, resError res) of
                  ([], [], Nothing)
                    | not (resInScope res) -> Just LiveError
                        { lveStage   = "name"
                        , lveCode    = Nothing
                        , lveMessage = dopName p <> " is not in scope in "
                            <> T.pack (lcAbsPath ctx)
                        }
                  _ -> resError res
              , dorMeta        = meta
              }


-- ---------------------------------------------------------------------------
-- exports_of
-- ---------------------------------------------------------------------------

-- | handleExportsOf: a module's public surface, from a file whose scope can
-- name it (probed: the module must be in scope there; the empty string names
-- the file's own top-level module).
handleExportsOf
  :: InteractionLanes -> AgdaConfig -> ExportsOfParams
  -> IO (Either ToolFailure ExportsOfResult)
handleExportsOf lanes cfg0 p =
  withLiveFile lanes cfg0 (eopFilePath p) (eopReload p) $ \ctx ->
    case lrOutcome (lcLoad ctx) of
      Left loadMsg -> do
        meta <- liveMeta ctx
        pure . Right $ ExportsOfResult (eopModule p)
          Nothing Nothing Nothing (Just (loadError loadMsg)) meta
      Right _ ->
        runShaped ctx (cmdModuleContentsToplevel (eopModule p)) $ \resps -> do
          meta <- liveMeta ctx
          let surface = moduleSurfaceOf resps
          pure . Right $ ExportsOfResult
            { exrModule    = eopModule p
            , exrExports   = (\(es, _, _) -> es) <$> surface
            , exrModules   = (\(_, ms, _) -> ms) <$> surface
            , exrTelescope = (\(_, _, tv) -> tv) =<< surface
            , exrError     = case surface of
                Just _  -> Nothing
                Nothing -> Just . fromMaybe (opaqueAnswer "module" resps) $
                  queryError "module" resps
            , exrMeta      = meta
            }
