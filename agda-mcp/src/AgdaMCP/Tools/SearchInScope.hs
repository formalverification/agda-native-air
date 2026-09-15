-- | SearchInScope.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Tools/SearchInScope.hs
--
-- Description:
--   The @search_in_scope@ tool (issue #17, phase 1): scope-aware retrieval
--   over the corpus index, with every returned rendering validated by the
--   interaction lane.  It answers one question: of the corpus rows that could
--   help here, which ones can this file actually name, and what does Agda say
--   each one's type is?
--
--   The tool rides both of the server's data sources and neither of its
--   verdict paths.  The corpus index ('AgdaMCP.Corpus') supplies the pool and
--   'AgdaMCP.Retrieval' cuts and ranks it, purely; the file's import surface
--   comes from 'AgdaMCP.Scope', read off the code-only view; and the lane
--   ('AgdaMCP.Interaction', through the live-query spine of
--   'AgdaMCP.Tools.LiveQueries') types each candidate rendering in the file's
--   scope, goal-scoped when the anchor addresses a hole.  So this is a
--   knowledge tool under the two-lane policy (ADR 0002 § 2): it informs and
--   never decides, no response carries @success@ or @verdict@, and a returned
--   rendering typechecks as an expression here, which says nothing about
--   whether it fills any hole.
--
--   The handler owns the lane half of the pipeline and the response:
--
--   * The query.  Given, or derived from the goal at the anchor through one
--     @Cmd_goal_type_context@ (Agda's own normalized display and context, the
--     same call @get_goal@'s lane path makes), so a call with no query at a
--     hole asks "what in scope could help with this goal".
--   * The walk.  Ranked rows are resolved through the rendering ladder one by
--     one until @limit@ rows are ACCEPTED or @maxProbes@ rows have been sent
--     to the lane; the cut is taken after resolution, so a rejected rendering
--     never consumes a slot (the driver's #130 review lesson), and the bound
--     on probes is what keeps a pool of thousands of stale rows from holding
--     the call.  A lane process failure mid-walk aborts the call with the
--     structured failure the live-query tools raise; a rejection is an answer.
--   * The identity check.  That a spelling TYPES does not prove it denotes
--     the corpus row (Copilot's review of PR #161): in goal scope a pattern
--     variable named like a using-listed import shadows it, so the bare
--     spelling types as the local; and a re-exported spelling can resolve to
--     whatever the importing module exports under that name.  So every
--     accepted spelling other than the row's own qualified name is asked
--     @WhyInScope@, and it is kept only if a candidate's defined name is the
--     row's (anonymous-module segments dropped on both sides, as the
--     extractor's @prettyQname@ drops them); a local answers @a variable
--     bound at@ with no defined name and is refused, and the ladder goes on.
--   * The lane-form statement exclusion.  The caller's @exclude.statement@ is
--     applied a second time to Agda's printing of the accepted rendering,
--     because corpus text and lane text agree only in unit tests.
--   * The ledger and the timing.  Every cut is counted and every exclusion
--     and rejection is named, and the pool half and the lane half of the
--     latency are reported apart, so the issue's acceptance figure for the
--     lookup half can be read off a response.
--
-- See also:
--   AgdaMCP.Scope, AgdaMCP.Retrieval: the pure halves.
--   AgdaMCP.Tools.LiveQueries: the spine, the echo, and type_of.
--   docs/adr/0002-agda-mcp.md § 10: the corpus tools and this phase.

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Tools.SearchInScope
  ( handleSearchInScope
    -- * Exposed for testing
  , defaultLimit
  , probeBudget
  ) where

import Control.Exception (evaluate)
import Control.Monad (when)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (partition)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Word (Word64)
import GHC.Clock (getMonotonicTimeNSec)

import AgdaMCP.Agda (AgdaConfig)
import AgdaMCP.Holes (codeOnly, flavourOf)
import AgdaMCP.Interaction
  ( GoalContext (..), GoalCtxEntry (..), IResponse, InteractionLanes, LoadReport (..)
  , ScopeCandidate (..), cmdGoalTypeContext, cmdInferAtGoal, cmdInferToplevel
  , cmdWhyInScopeAtGoal, cmdWhyInScopeToplevel, goalContextOf, parseWhyInScope, runQuery
  )
import AgdaMCP.Retrieval
  ( Pool (..), Ranked (..), buildPool, normalizeStatement, queryTokensOf )
import AgdaMCP.Scope (parseImports, renderings)
import AgdaMCP.Tools.LiveQueries
  ( LiveCtx (..), QueryScope (..), inferredTypeOf, interactionFailure, liveMeta
  , loadError, opaqueAnswer, queryError, scopeFor, whyInScopeMessageOf, withLiveFile
  )
import qualified Data.Text as T
import AgdaMCP.Types


-- | defaultLimit: accepted rows per call when the caller names none.  Eight
-- is the driver's @topK@, and "a handful an agent can triage itself" is the
-- consumer brief's own sizing.
defaultLimit :: Int
defaultLimit = 8

-- | probeBudget: how many ranked rows may be sent to the lane for a given
-- limit when the caller names no @maxProbes@: four times the limit, and
-- never fewer than the limit itself.
probeBudget :: Int -> Maybe Int -> Int
probeBudget lim = maybe (4 * lim) (max lim)

-- | Counters: the lane half of the ledger, accumulated across the walk.
data Counters = Counters
  { cLaneNs    :: IORef Word64
  , cLaneCalls :: IORef Int
  }

-- | handleSearchInScope: the tool.
handleSearchInScope
  :: InteractionLanes -> AgdaConfig -> CorpusIndex -> SearchInScopeParams
  -> IO (Either ToolFailure SearchInScopeResult)
handleSearchInScope lanes cfg0 idx p =
  withLiveFile lanes cfg0 (sipFilePath p) (sipReload p) $ \ctx -> do
    let imports = parseImports (codeOnly (flavourOf (lcAbsPath ctx)) (lcSource ctx))
    counters <- Counters <$> newIORef 0 <*> newIORef 0
    case lrOutcome (lcLoad ctx) of
      -- The file does not load: the query is not run, and saying so with
      -- Agda's message is the whole answer.
      Left loadMsg -> do
        meta <- liveMeta ctx
        pure . Right $ emptyResult Nothing "toplevel" imports (Just (loadError loadMsg)) meta
      Right _ -> do
        let (scope, scopeTxt) = scopeFor (sipLine p) (sipColumn p) (lcLoad ctx)
        queried <- resolveQuery ctx counters (sipQuery p) scope
        case queried of
          Left tf -> pure (Left tf)
          Right (Left err) -> do
            meta <- liveMeta ctx
            pure . Right $ emptyResult Nothing scopeTxt imports (Just err) meta
          Right (Right (q, source)) -> do
            -- The pool half, timed on its own: query, scope, exclusion,
            -- kind, rank, over the whole index.  Forcing the ranked list's
            -- length forces the sort and with it every key.
            poolStart <- getMonotonicTimeNSec
            let pool = buildPool q (sipExclude p) imports idx
            _ <- evaluate (length (poolRanked pool))
            _ <- evaluate (poolHits pool + poolInScope pool + poolNonFunction pool
                           + length (poolExcluded pool))
            poolEnd <- getMonotonicTimeNSec
            -- The lane half: the walk.
            let lim    = maybe defaultLimit (max 1) (sipLimit p)
                budget = probeBudget lim (sipMaxProbes p)
            walked <- walk ctx counters scope lim budget (sipExclude p) (poolRanked pool)
            case walked of
              Left tf -> pure (Left tf)
              Right w -> do
                laneNs    <- readIORef (cLaneNs counters)
                laneCalls <- readIORef (cLaneCalls counters)
                meta      <- liveMeta ctx
                pure . Right $ SearchInScopeResult
                  { sirQuery   = Just (q, source)
                  , sirScope   = scopeTxt
                  , sirImports = imports
                  , sirResults = wAccepted w
                  , sirLedger  = ScopeLedger
                      { slHits         = poolHits pool
                      , slInScope      = poolInScope pool
                      , slOutOfScope   = poolOutOfScope pool
                      , slExcluded     = poolExcluded pool <> wExcluded w
                      , slNonFunction  = poolNonFunction pool
                      , slRanked       = length (poolRanked pool)
                      , slProbed       = wProbed w
                      , slLaneCalls    = laneCalls
                      , slLaneRejected = wRejected w
                      , slAccepted     = length (wAccepted w)
                      , slTruncated    = wTruncated w
                      , slStoppedBy    = wStoppedBy w
                      }
                  , sirTiming  = ScopeTiming
                      { stPoolMs = msOf (poolEnd - poolStart)
                      , stLaneMs = msOf laneNs
                      }
                  , sirError   = Nothing
                  , sirMeta    = meta
                  }

-- | resolveQuery: the caller's query, or one derived from the goal at the
-- anchor, or the in-band error that neither exists.  A lane process failure
-- while reading the goal is the structured failure, as everywhere on the lane.
resolveQuery
  :: LiveCtx -> Counters -> Maybe SearchQuery -> QueryScope
  -> IO (Either ToolFailure (Either LiveError (SearchQuery, Text)))
resolveQuery ctx counters mQuery scope = case (mQuery, scope) of
  (Just q, _) -> pure (Right (Right (q, "given")))
  (Nothing, Toplevel) -> pure . Right . Left $ LiveError
    { lveStage   = "query"
    , lveCode    = Nothing
    , lveMessage = "no query was given and the anchor addresses no goal: pass \
                   \query {name, tokens}, or a (line, column) inside a hole so \
                   \the query can be derived from that goal's type"
    }
  (Nothing, AtGoal g) -> do
    answered <- timedQuery ctx counters GoalRead (cmdGoalTypeContext g)
    case answered of
      Left tf -> pure (Left tf)
      Right resps -> case goalContextOf resps of
        Just gc ->
          let ctxNames = [ geName e | e <- gcEntries gc ]
              toks     = queryTokensOf (gcType gc) ctxNames
          in  if null toks
                -- A goal that is only a context variable (or otherwise
                -- yields no tokens) must not become the match-all query an
                -- empty token list would be (Copilot's review of PR #161).
                then pure . Right . Left $ LiveError
                  { lveStage   = "query"
                  , lveCode    = Nothing
                  , lveMessage = "the goal at the anchor displays as `" <> gcType gc
                      <> "`, which yields no retrieval tokens once context names, \
                         \metas, numerals, and structure are dropped; pass \
                         \query {name, tokens}"
                  }
                else pure . Right . Right $ (SearchQuery Nothing toks, "goal")
        Nothing -> pure . Right . Left $
          fromMaybe (opaqueAnswer "goal" resps) (queryError "goal" resps)

-- | Walked: what the walk produced.
data Walked = Walked
  { wAccepted  :: [ScopeRow]
  , wRejected  :: [ScopeRejection]
  , wExcluded  :: [ScopeExclusion]
  , wProbed    :: Int
  , wTruncated :: Bool
  , wStoppedBy :: Text
  }

-- | walk: resolve ranked rows through the ladder until the limit is filled,
-- the probe budget is spent, or the list is exhausted.
--
-- The rung memo: rows of one module under one import all resolve by the same
-- qualified rung (nested rows by their own qualified name, re-exported rows
-- by the importing module), so once a row of module M has been accepted at
-- rung R, later rows of M try R's rendering first.  Measured on the
-- agda-algebras corpus before the memo, every accepted re-export cost two
-- lane calls (the qualified rung refused, then the importing one accepted);
-- the memo makes it one.  The bare rung is never reordered: it depends on
-- the name, not the module, and it is what dedups against the file's own
-- opens.
walk
  :: LiveCtx -> Counters -> QueryScope -> Int -> Int -> Maybe SearchExclude -> [Ranked]
  -> IO (Either ToolFailure Walked)
walk ctx counters scope lim budget mExclude = go Map.empty 0 [] [] []
  where
    go :: Map.Map Text Rung -> Int -> [ScopeRow] -> [ScopeRejection] -> [ScopeExclusion]
       -> [Ranked] -> IO (Either ToolFailure Walked)
    go memo probed acc rej exc remaining
      | null remaining        = stop probed acc rej exc False "exhausted"
      | length acc >= lim     = stop probed acc rej exc True  "limit"
      | probed >= budget      = stop probed acc rej exc True  "maxProbes"
      | (r : rest) <- remaining = do
          let entry  = rkEntry r
              qname  = cePrettyQname entry
              modul  = cePrettyModule entry
              ladder = preferRung (Map.lookup modul memo) (renderings (rkImports r) qname)
          outcome <- tryLadder ctx counters scope qname ladder
          case outcome of
            Left tf -> pure (Left tf)
            Right Nothing ->
              go memo (probed + 1) acc (ScopeRejection qname (map snd ladder) : rej) exc rest
            Right (Just (rung, rendering, printed))
              | Just stmt <- sxStatement =<< mExclude
              , normalizeStatement printed == normalizeStatement stmt ->
                  go (remember modul rung memo) (probed + 1) acc rej
                     (ScopeExclusion qname "lane-statement" : exc) rest
              | otherwise ->
                  let row = ScopeRow
                        { srowPrettyQname = qname
                        , srowRendering   = rendering
                        , srowType        = printed
                        , srowVia         = case rkImports r of
                            (imp : _) -> siModule imp
                            []        -> cePrettyModule entry
                        , srowRung        = rung
                        , srowModule      = cePrettyModule entry
                        , srowDefKind     = ceDefKind entry
                        , srowHasBody     = ceHasBody entry
                        , srowCorpusType  = ceType entry
                        , srowScore       = rkScore r
                        }
                  in  go (remember modul rung memo) (probed + 1) (row : acc) rej exc rest
      | otherwise = stop probed acc rej exc False "exhausted"

    -- Only the two qualified rungs are worth remembering.
    remember modul rung memo
      | rung == RungBare = memo
      | otherwise        = Map.insert modul rung memo

    -- Move the remembered rung's rendering ahead of the other qualified one;
    -- a bare rendering stays first.
    preferRung Nothing ladder = ladder
    preferRung (Just rung) ladder =
      let (bare, rest) = span ((== RungBare) . fst) ladder
          (hit, miss)  = partition ((== rung) . fst) rest
      in  bare <> hit <> miss

    stop probed acc rej exc truncated why = pure . Right $ Walked
      { wAccepted  = reverse acc
      , wRejected  = reverse rej
      , wExcluded  = reverse exc
      , wProbed    = probed
      , wTruncated = truncated
      , wStoppedBy = why
      }

-- | tryLadder: the first rendering the lane types AND that denotes the row,
-- with its rung and Agda's printed type; @Nothing@ when no rung does.  A lane
-- rejection (an in-band Agda error) or a spelling that denotes something
-- else moves to the next rung; a lane process failure aborts.  The row's own
-- qualified name needs no identity check: typing it is resolving it.
tryLadder
  :: LiveCtx -> Counters -> QueryScope -> Text -> [(Rung, Text)]
  -> IO (Either ToolFailure (Maybe (Rung, Text, Text)))
tryLadder _ _ _ _ [] = pure (Right Nothing)
tryLadder ctx counters scope qname ((rung, rendering) : rest) = do
  let cmd = case scope of
        AtGoal g -> cmdInferAtGoal g rendering
        Toplevel -> cmdInferToplevel rendering
  answered <- timedQuery ctx counters ValidationCall cmd
  case answered of
    Left tf -> pure (Left tf)
    Right resps -> case inferredTypeOf resps of
      Nothing -> next
      Just printed
        | rung == RungQualified -> pure (Right (Just (rung, rendering, printed)))
        | otherwise -> do
            identity <- denotesRow ctx counters scope rendering qname
            case identity of
              Left tf     -> pure (Left tf)
              Right True  -> pure (Right (Just (rung, rendering, printed)))
              Right False -> next
  where
    next = tryLadder ctx counters scope qname rest

-- | denotesRow: does this spelling, in this scope, resolve to the corpus
-- row?  Agda's @WhyInScope@ lists every binding of the spelling, the one
-- that wins AND the ones it shadows (probed at the fixture's @shadow@ hole:
-- @a variable bound at …:32.8-13 shadowing@ first, then @a defined name
-- ScopeSearchLib.twice@).  So the spelling denotes the row iff no candidate
-- is a variable (a local always wins over a defined name) and one
-- candidate's defined name is the row's @prettyQname@ once anonymous-module
-- segments are dropped from Agda's printing (the extractor's own
-- normalization, @normalizeQNameText@ in agda-strux).  An unparseable
-- answer is a refusal; every refusal sends the ladder to its next rung.
denotesRow
  :: LiveCtx -> Counters -> QueryScope -> Text -> Text -> IO (Either ToolFailure Bool)
denotesRow ctx counters scope rendering qname = do
  let cmd = case scope of
        AtGoal g -> cmdWhyInScopeAtGoal g rendering
        Toplevel -> cmdWhyInScopeToplevel rendering
  answered <- timedQuery ctx counters ValidationCall cmd
  pure $ case answered of
    Left tf -> Left tf
    Right resps -> Right $ case parseWhyInScope =<< whyInScopeMessageOf resps of
      Just cands ->
        not (any isVariable cands)
          && any (\c -> (normalizeQName <$> scQualified c) == Just (normalizeQName qname)) cands
      Nothing    -> False
  where
    isVariable c = "a variable" `T.isPrefixOf` scDescription c
    normalizeQName = T.intercalate "." . filter (\s -> not (T.null s) && s /= "_") . T.splitOn "."

-- | LaneUse: what a lane command is for, which decides whether it counts in
-- @ledger.laneCalls@ (the calls spent validating renderings: every
-- @type_of@ and every identity check) or only in @timing.laneMs@ (the goal
-- read of a derived query, which validates nothing).
data LaneUse = ValidationCall | GoalRead
  deriving (Eq)

-- | timedQuery: one lane command, its wall time added to the lane half of the
-- ledger and its count when it is a validation call, its process failure
-- shaped as the live tools shape it.
timedQuery :: LiveCtx -> Counters -> LaneUse -> Text -> IO (Either ToolFailure [IResponse])
timedQuery ctx counters use cmd = do
  t0 <- getMonotonicTimeNSec
  rs <- runQuery (lcHandle ctx) (lcAbsPath ctx) cmd
  t1 <- getMonotonicTimeNSec
  modifyIORef' (cLaneNs counters) (+ (t1 - t0))
  when (use == ValidationCall) $ modifyIORef' (cLaneCalls counters) (+ 1)
  case rs of
    Left lf -> Left . FailInteraction
                 <$> interactionFailure (lcProject ctx) (lcConfig ctx) (lcStartNs ctx) lf
    Right resps -> pure (Right resps)

-- | emptyResult: the shape of a call that ran no walk: a load failure, or
-- nothing to search for.  The ledger is all zeros and says so.
emptyResult
  :: Maybe (SearchQuery, Text) -> Text -> [ScopeImport] -> Maybe LiveError -> LiveMeta
  -> SearchInScopeResult
emptyResult q scopeTxt imports err meta = SearchInScopeResult
  { sirQuery   = q
  , sirScope   = scopeTxt
  , sirImports = imports
  , sirResults = []
  , sirLedger  = ScopeLedger 0 0 0 [] 0 0 0 0 [] 0 False "exhausted"
  , sirTiming  = ScopeTiming 0 0
  , sirError   = err
  , sirMeta    = meta
  }

msOf :: Word64 -> Int
msOf ns = fromIntegral (ns `div` 1_000_000)
