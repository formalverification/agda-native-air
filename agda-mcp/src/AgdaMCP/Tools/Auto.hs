-- | Auto.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Tools/Auto.hs
--
-- Description:
--   The auto tool (issue #205): Agda's own proof search at one hole, run on
--   the interaction lane, answering the term it found as a candidate.
--
--   Under the pinned Agda 2.8.0 the search is Mimer, which replaced Agsy in
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
--     between search steps) must sit inside the lane's deadline, the server's
--     @--timeout@; a request whose bound reaches that deadline could only end
--     in the lane being killed, so it is refused before anything is sent.
--
--   The lane is left describing the file after a found term ('runConsuming'
--   re-loads it, the reset a give owes), and an answer says what that cost
--   ('aurResetMs').

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Tools.Auto
  ( handleAuto
    -- * Exposed for testing
  , autoOptions
  , joinRendering
  , notInScopeName
  , classifyAuto
  ) where

import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import AgdaMCP.Agda (AgdaConfig (..))
import AgdaMCP.Holes (ResolvedHole (..), flavourOf, resolveHoleRef)
import AgdaMCP.Interaction
import AgdaMCP.Tools.LiveQueries
  ( LiveCtx (..), interactionFailure, liveMeta, loadError, pointForHole
  , withLiveFile )
import AgdaMCP.Types

-- | handleAuto: run the search at the addressed hole and shape the answer.
handleAuto
  :: InteractionLanes -> AgdaConfig -> AutoParams
  -> IO (Either ToolFailure AutoResult)
handleAuto lanes cfg0 p = case boundProblem of
  Just msg -> pure (Left (FailMessage msg))
  Nothing  ->
    withLiveFile lanes cfg0 (apFilePath p) (apReload p) $ \ctx ->
      case rhIndex <$> resolveHoleRef (lcAbsPath ctx) (flavourOf (lcAbsPath ctx)) (lcSource ctx) (apHole p) of
        Left miss -> pure (Left (FailMessage miss))
        Right idx -> case lrOutcome (lcLoad ctx) of
          Left loadMsg -> do
            meta <- liveMeta ctx
            pure . Right $ AutoResult OutcomeError Nothing Nothing
              (Just (loadError loadMsg)) opts Nothing Nothing meta
          Right li ->
            case pointForHole (flavourOf (lcAbsPath ctx)) (lcSource ctx) idx (liPoints li) of
              Nothing -> pure . Left . FailMessage $
                "the interaction lane's points do not line up with the hole scan \
                \at hole " <> T.pack (show idx) <> " of " <> T.pack (lcAbsPath ctx)
                <> ", so the search was not run rather than run at another hole"
              Just point -> do
                ran <- autoAt (lcHandle ctx) (lcAbsPath ctx)
                         (agdaFlags (lcConfig ctx)) (ipId point) opts
                case ran of
                  Left lf -> Left . FailInteraction
                               <$> interactionFailure (lcProject ctx) (lcConfig ctx)
                                                      (lcStartNs ctx) lf
                  Right run -> do
                    meta <- liveMeta ctx
                    let (outcome, term, message, err) =
                          classifyAuto (apHints p) (auAnswer run)
                    pure . Right $ AutoResult
                      { aurOutcome  = outcome
                      , aurTerm     = term
                      , aurMessage  = message
                      , aurError    = err
                      , aurOptions  = opts
                      , aurSearchMs = Just (auSearchUs run `div` 1000)
                      , aurResetMs  = (`div` 1000) <$> auResetUs run
                      , aurMeta     = meta
                      }
  where
    opts = autoOptions p

    -- The search's bound must end before the lane's own deadline does; a
    -- missing or non-positive --timeout is no deadline, the batch lane's
    -- convention, and leaves nothing to check against.
    boundProblem = case (apTimeoutMs p, agdaTimeout cfg0) of
      (Just ms, Just secs) | secs > 0, ms >= secs * 1000 -> Just $
        "timeoutMs " <> T.pack (show ms) <> " reaches this server's --timeout of "
        <> T.pack (show secs) <> " s, which bounds the whole call; a search \
        \that long could only end in the lane being killed. Ask for less than "
        <> T.pack (show (secs * 1000)) <> " ms."
      _ -> Nothing

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
