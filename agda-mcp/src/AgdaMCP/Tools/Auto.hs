-- | Auto.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Tools/Auto.hs
--
-- Description:
--   The auto tool (issue #205): Agda's own proof search at one hole, run on
--   the interaction lane, answering the term it found as a candidate.
--
--   Under Agda 2.8.0 and 2.9.0 the search is Mimer, which replaced Agsy in
--   Agda 2.7 (the 2.7.0 release notes); @Cmd_autoOne@ is the command, the
--   one an editor's @C-c C-a@ sends.  It needs no corpus and no model, and on
--   the benchmark it costs milliseconds a hole, so it is the cheapest proposer
--   this repository has.  It is also not a judge, for three measured reasons,
--   which is why the answer is a candidate:
--
--   * Agda gives a found term into the lane's state WithForce, which skips
--     the termination check and the double check (@Agda.Interaction.BasicOps@,
--     'give'), and the search can build recursive calls.
--   * The lane's give answers a different question from a batch check on a
--     partial fill (issue #163's finding, ADR 0002 § 2).
--   * The term is a printed rendering, read back in the hole's scope; what
--     the batch splice reads is that text in the file, not the term Agda
--     built.  Only fill_hole, a batch agda on the file, decides.
--
--   What the handler adds to the protocol layer ('AgdaMCP.Interaction.autoAt'):
--
--   * The options are built from declared fields ('autoOptions'), so no free
--     text reaches Agda's option reader, and the string sent is echoed back.
--   * Each hint is put to Agda's scope query at the hole before the search
--     runs ('checkHints'), and a hint the search could not use (one it would
--     drop without a word, or one it could not read at all) refuses the call
--     by name.
--   * A found term is joined onto one line ('joinRendering').  Agda's printer
--     breaks a long term across lines and starts each continuation at column
--     1, and a batch splice of the text as printed ends the declaration at
--     the first continuation (measured on algebras-inverses-range-to-image,
--     whose term was refused until joined).
--   * A refusal is named: a @NotInScope@ that names one of the call's hints
--     is the hint's fault (stage @hints@); any other @NotInScope@ can only be
--     the found term read back with a name the file cannot write, since the
--     hints are the only other words Agda reads as names, and that is the
--     @out-of-scope@ outcome (stage @term@); every other refusal is stage
--     @auto@, since Agda's message does not say whether the search or the
--     reading of its term refused (a term Agda printed and could not read
--     back as the type it found, @ShouldBePi@, was measured on one
--     composition row).
--   * The search's own time bound (Agda's @-t@, CPU milliseconds, checked
--     between search steps; Agda's default when the call names none) must
--     sit inside the lane's deadline, the server's @--timeout@; a request
--     whose bound reaches that deadline could only end in the lane being
--     killed, so it is refused before anything is sent
--     ('searchBoundProblem').
--
--   The lane is left describing the file after a found term ('runConsuming'
--   re-loads it, the reset a give owes), and an answer says what that cost
--   ('aurResetMs'), counts its re-check in @checkedFromSource@
--   ('withResetEvidence'), and turns into the load's error if the re-load
--   failed ('resetAware').

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Tools.Auto
  ( handleAuto
    -- * Exposed for testing
  , autoOptions
  , joinRendering
  , notInScopeName
  , classifyAuto
  , unusableHint
  , searchBoundProblem
  , autoDefaultTimeoutMs
  , resetAware
  , withResetEvidence
  ) where

import Data.List (nub)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import AgdaMCP.Agda (AgdaConfig (..))
import AgdaMCP.Holes (ResolvedHole (..), flavourOf, resolveHoleRef)
import AgdaMCP.Interaction
import AgdaMCP.Tools.LiveQueries
  ( LiveCtx (..), interactionFailure, liveMeta, loadError, opaqueAnswer
  , pointForHole, queryError, runShaped, whyInScopeMessageOf, withLiveFile )
import AgdaMCP.Types

-- | handleAuto: run the search at the addressed hole and shape the answer.
handleAuto
  :: InteractionLanes -> AgdaConfig -> AutoParams
  -> IO (Either ToolFailure AutoResult)
handleAuto lanes cfg0 p = case searchBoundProblem (agdaTimeout cfg0) (apTimeoutMs p) of
  Just msg -> pure (Left (FailMessage msg))
  Nothing  ->
    withLiveFile lanes cfg0 (apFilePath p) (apReload p) $ \ctx ->
      case resolveHoleRef (lcAbsPath ctx) (flavourOf (lcAbsPath ctx)) (lcSource ctx) (apHole p) of
        Left miss -> pure (Left (FailMessage miss))
        Right rh -> let idx = rhIndex rh; addressed = addressedOf rh in case lrOutcome (lcLoad ctx) of
          Left loadMsg -> do
            meta <- liveMeta ctx
            pure . Right $ AutoResult OutcomeError Nothing Nothing
              (Just (loadError loadMsg)) opts Nothing Nothing addressed meta
          Right li ->
            case pointForHole (flavourOf (lcAbsPath ctx)) (lcSource ctx) idx (liPoints li) of
              Nothing -> pure . Left . FailMessage $
                "the interaction lane's points do not line up with the hole scan \
                \at hole " <> T.pack (show idx) <> " of " <> T.pack (lcAbsPath ctx)
                <> ", so the search was not run rather than run at another hole"
              Just point -> do
                checked <- checkHints ctx (ipId point) (apHints p)
                case checked of
                  Left tf -> pure (Left tf)
                  Right (Just refusal) -> do
                    meta <- liveMeta ctx
                    pure . Right $ AutoResult OutcomeError Nothing Nothing
                      (Just refusal) opts Nothing Nothing addressed meta
                  Right Nothing -> search ctx point addressed
  where
    opts = autoOptions p

    search ctx point addressed = do
      ran <- autoAt (lcHandle ctx) (lcAbsPath ctx)
               (agdaFlags (lcConfig ctx)) (ipId point) opts
      case ran of
        Left lf -> Left . FailInteraction
                     <$> interactionFailure (lcProject ctx) (lcConfig ctx)
                                            (lcStartNs ctx) lf
        Right run -> do
          meta0 <- liveMeta ctx
          let meta = meta0
                { lmCheckedFromSource = withResetEvidence
                    (lmCheckedFromSource meta0) (lrCheckedFromSource <$> auReset run) }
              (outcome, term, message, err) =
                resetAware (auReset run) (classifyAuto (apHints p) (auAnswer run))
          pure . Right $ AutoResult
            { aurOutcome  = outcome
            , aurTerm     = term
            , aurMessage  = message
            , aurError    = err
            , aurOptions  = opts
            , aurSearchMs = Just (auSearchUs run `div` 1000)
            , aurResetMs  = (`div` 1000) <$> auResetUs run
            , aurAddressed = addressed
            , aurMeta     = meta
            }


-- | autoDefaultTimeoutMs: the search's bound when a call names none, Agda's
-- own (@optTimeout@ in @Agda.Mimer.Options@, 1,000 ms of CPU time).
autoDefaultTimeoutMs :: Int
autoDefaultTimeoutMs = 1000

-- | searchBoundProblem: why a search with this bound cannot run under this
-- server's @--timeout@ (seconds), or 'Nothing' when it can.
--
-- The search's bound must end before the lane's own deadline does, or the
-- call could only end in the lane being killed.  The bound is the effective
-- one: a call that names no @timeoutMs@ searches for Agda's default, so a
-- server whose @--timeout@ is 1 s cannot run a default search either (a
-- Copilot catch on PR #230: only a bound the call named was checked).  A
-- missing or non-positive @--timeout@ is no deadline, the batch lane's
-- convention, and leaves nothing to check against.
searchBoundProblem :: Maybe Int -> Maybe Int -> Maybe Text
searchBoundProblem serverSecs asked = case serverSecs of
  Just secs | secs > 0, bound >= secs * 1000 -> Just $
    which <> " reaches this server's --timeout of " <> T.pack (show secs)
    <> " s, which bounds the whole call; a search that long could only end \
       \in the lane being killed. Ask for less than "
    <> T.pack (show (secs * 1000)) <> " ms with timeoutMs."
  _ -> Nothing
  where
    bound = fromMaybe autoDefaultTimeoutMs asked
    which = case asked of
      Just ms -> "timeoutMs " <> T.pack (show ms)
      Nothing -> "Agda's default search bound of " <> T.pack (show autoDefaultTimeoutMs)
                 <> " ms (the call names no timeoutMs)"

-- | checkHints: the first hint the search could not use, asked of the lane
-- at the hole before the search runs; 'Nothing' when every hint is usable.
--
-- Mimer reads each hint as an expression in the hole's scope and keeps it
-- only when it is a defined name, a constructor, or a record field
-- (@hintExprToQName@ in @Agda.Mimer.Options@); it drops any other expression
-- without a word, so a call whose hint was dropped answered as if the hint
-- had been used.  A hint Agda cannot read as a name at all (@λ@, @let@)
-- fails the whole command with an error that does not name it.  Both were
-- measured (a Copilot catch on PR #230).  So each hint is first put to
-- Agda's own scope query at the hole (@Cmd_why_in_scope@, the question
-- resolve_name asks), and the call is refused in band, stage @hints@,
-- naming the first hint that the query cannot read as a name (Agda's error,
-- with its code), or that 'unusableHint' finds the search cannot use.
--
-- A hint not in scope at all is left to the search, whose own @NotInScope@
-- names it with Agda's suggestions ('classifyAuto').  An ambiguous name is
-- left to Agda too, whose rules for overloaded constructors and fields the
-- query does not restate.  Each query is one lane round trip and changes
-- no state.
checkHints :: LiveCtx -> Int -> [Text] -> IO (Either ToolFailure (Maybe LiveError))
checkHints _ _ [] = pure (Right Nothing)
checkHints ctx gid (h : hs) =
  runShaped ctx (cmdWhyInScopeAtGoal gid h) $ \resps ->
    case whyInScopeMessageOf resps of
      Just msg -> case unusableHint h msg of
        Just why -> pure (Right (Just (LiveError "hints" Nothing why)))
        Nothing  -> checkHints ctx gid hs
      Nothing -> pure . Right . Just $ case queryError "hints" resps of
        Just err -> err { lveMessage = "hint `" <> h <> "` is not a name Agda \
                                       \can read in this hole's scope. Agda: "
                                       <> lveMessage err }
        Nothing  -> opaqueAnswer "hints" resps

-- | unusableHint: why a hint Agda's scope query found is one the search
-- cannot use, from the query's answer; 'Nothing' when the search can use
-- it, and when the answer says the hint is not in scope (the search names
-- that itself).
--
-- A variable of the hole's context is read before any definition of the
-- same name, so a hint naming one is a variable, which the search drops
-- (it searches the context already).  Otherwise the hint is usable when
-- one of its candidates is a kind Mimer keeps: a defined name of any sort
-- (Agda's kinds @defined name@, @data type@, @record type@, @postulate@,
-- @primitive function@), a constructor, or a record field.  The other
-- kinds fail in one of two ways, both measured or read in Agda 2.8.0's
-- source: a pattern synonym or a macro reads as an expression Mimer drops
-- without a word; a module reads as no expression at all, so Agda
-- answered NotInScope for a name that is in scope, and a generalizable
-- variable outside a signature is Agda's @GeneralizeNotSupportedHere@.
unusableHint :: Text -> Text -> Maybe Text
unusableHint h msg = case parseWhyInScope msg of
  Nothing -> Nothing
  Just cands
    | any ((== "a variable") . scDescription) cands -> Just $
        "hint `" <> h <> "` names a variable of the hole's context, and the \
        \search drops a variable as a hint (it searches the context already); \
        \a hint is a defined name, a constructor, or a record field"
    | null cands || any ((`elem` kept) . kindOf) cands -> Nothing
    | otherwise -> Just $
        "hint `" <> h <> "` is in scope only as "
        <> T.intercalate " and " (nub (map (("a " <>) . kindOf) cands))
        <> ", which the search cannot use; a hint is a defined name, a \
           \constructor, or a record field"
  where
    kept =
      [ "defined name", "data type", "record type", "postulate"
      , "primitive function", "constructor", "coinductive constructor"
      , "record field" ]
    -- "a defined name M.x" is the kind "defined name": the article and the
    -- name dropped (Agda's names hold no spaces).
    kindOf c = case T.words (scDescription c) of
      (_ : ws@(_ : _ : _)) -> T.unwords (init ws)
      _                    -> scDescription c

-- | resetAware: the answer, once the re-load a found term owes is known.
--
-- A found term consumes the hole in the lane's state, and 'autoAt' re-loads
-- the file to put it back.  That re-load can fail (a dependency edited
-- between the search and the reset, say).  The term was found against the
-- state the search ran on, which the file no longer loads into, so it is
-- moot: the answer is the load's error, in band, naming the term it found,
-- rather than a found term the caller would judge against a file that does
-- not load (a Copilot catch on PR #230).  The lane is not left stale: a
-- failed load is retried on the next request ('ensureLoaded').
resetAware
  :: Maybe LoadReport
  -> (AutoOutcome, Maybe Text, Maybe Text, Maybe LiveError)
  -> (AutoOutcome, Maybe Text, Maybe Text, Maybe LiveError)
resetAware reset answer = case (reset, answer) of
  (Just lr, (OutcomeFound, Just t, _, _)) | Left msg <- lrOutcome lr ->
    ( OutcomeError, Nothing, Nothing
    , Just (loadError msg)
        { lveMessage = "the search found `" <> t <> "`, and re-loading the file \
                       \afterwards failed, so the term is moot; the lane re-loads \
                       \the file on the next call. Agda: " <> msg } )
  _ -> answer

-- | withResetEvidence: whether the call re-typechecked its file, counting
-- the reset.  A re-load of a file with open holes re-typechecks it, so a call
-- whose search ran on a reused load (@false@) and then reset did re-check the
-- file; reporting the first load's @false@ would contradict the field's own
-- meaning (a Copilot catch on PR #230).  Positive evidence from either load
-- wins; with no reset the first load's answer stands; otherwise unknown
-- evidence on either side leaves the field unknown, never a guess.
withResetEvidence :: Maybe Bool -> Maybe (Maybe Bool) -> Maybe Bool
withResetEvidence first reset = case (first, reset) of
  (_, Nothing)                -> first
  (Just True, _)              -> Just True
  (_, Just (Just True))       -> Just True
  (Just False, Just (Just False)) -> Just False
  _                           -> Nothing

-- | autoOptions: the hole contents Agda's option reader is given.
--
-- Built only from the declared fields, each hint already checked to be one
-- name-shaped word ('AgdaMCP.Types.AutoParams'), so every word here means
-- what its field says.  An absent field adds nothing and leaves Agda's own
-- default, which is why a call with no options sends the empty string, as the
-- reference measurement did.
autoOptions :: AutoParams -> Text
autoOptions p = T.unwords $
  maybe [] (\ms -> ["-t", T.pack (show ms) <> "ms"]) (apTimeoutMs p)
  <> maybe [] (\n -> ["-s", T.pack (show n)]) (apSkip p)
  <> (case apHintMode p of
        HintsOnly       -> []
        HintModule      -> ["-m"]
        HintUnqualified -> ["-u"])
  <> apHints p

-- | joinRendering: Agda's rendering of a term, onto one line.
--
-- Each line is stripped and the lines are joined with one space, so a
-- continuation's indentation (or its absence: Agda starts some at column 1)
-- becomes one space and nothing else changes.  That is safe for what the
-- search builds, which holds no layout block (no @let@, @where@, or @do@);
-- a string literal's own line break is printed as an escape, never as a
-- raw newline.
joinRendering :: Text -> Text
joinRendering = T.unwords . filter (not . T.null) . map T.strip . T.lines

-- | notInScopeName: the name a @NotInScope@ message says is missing, as
-- Agda prints it: @Not in scope:@ on one line, then the name, @at@, and its
-- range on the next.
notInScopeName :: Text -> Maybe Text
notInScopeName msg =
  case drop 1 (dropWhile (not . ("Not in scope:" `T.isInfixOf`)) (T.lines msg)) of
    (ln : _) -> listToMaybe (T.words ln)
    []       -> Nothing

-- | classifyAuto: an 'AutoAnswer' as the tool's outcome and the field that
-- carries it: the joined term, the search's message, or an in-band error.
classifyAuto
  :: [Text] -> AutoAnswer
  -> (AutoOutcome, Maybe Text, Maybe Text, Maybe LiveError)
classifyAuto hints answer = case answer of
  AutoTerm t       -> (OutcomeFound, Just (joinRendering t), Nothing, Nothing)
  AutoMessage m    -> (OutcomeNoSolution, Nothing, Just m, Nothing)
  AutoUnexpected m -> (OutcomeError, Nothing, Nothing, Just (LiveError "auto" Nothing m))
  AutoRefusal m    ->
    let code = errorCodeOf m
        err stage = Just (LiveError stage code m)
    in case (code, notInScopeName m) of
         (Just "NotInScope", Just name)
           | name `elem` hints -> (OutcomeError, Nothing, Nothing, err "hints")
           | otherwise         -> (OutcomeOutOfScope, Nothing, Nothing, err "term")
         _ -> (OutcomeError, Nothing, Nothing, err "auto")
