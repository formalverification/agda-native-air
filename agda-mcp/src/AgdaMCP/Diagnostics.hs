-- | Diagnostics.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Diagnostics.hs
--
-- Description:
--   Turn Agda's console output into structured diagnostics (issue #74).
--
--   This is the module that lets a client branch on a diagnostic's @code@ and
--   read its @range@ instead of regexing prose — the § 3.4 ask of
--   docs/feedback/flrp-agda-mcp-improvements.md, whose § 5 error corpus is the
--   fixture suite under test/resources/diagnostics/.  It is pure: every function
--   here maps Agda's captured stdout+stderr to values, so the whole surface is
--   testable without an Agda subprocess.
--
--   What Agda 2.8.0 actually prints, which is what this parses:
--
--   > Checking Consumer (/x/Consumer.agda).
--   > /x/Consumer.agda:3.20-43: warning: -W[no]ModuleDoesntExport
--   > The module Barrel doesn't export the following:
--   >   missing
--   > when scope checking the declaration
--   >   open import Barrel using (usable; missing)
--   >
--   > /x/Consumer.agda:5.5-12: error: [NotInScope]
--   > Not in scope:
--   >   missing
--   >   at /x/Consumer.agda:5.5-12
--   > when scope checking missing
--
--   Four things follow from that shape, and each is a defect this module fixes:
--
--   1. Positions are @LINE.COL-COL@ (or @LINE.COL-LINE.COL@ across lines).  The
--      previous extractor split on the comma of Agda's /old/ @LINE,COL-COL@
--      spelling, so under the pinned Agda 2.8.0 no diagnostic carried a position
--      at all.  Both spellings parse here, and both are pinned by tests.
--   2. A warning names its code as @-W[no]Code@, not @[Code]@; both are read.
--   3. Some errors have no position whatsoever — @error: [UnsolvedConstraints]@
--      begins at column 0 — so a parser keyed on @": error:"@ dropped them
--      entirely.  A header may equally well start the line.
--   4. The detail block under the header is the part an agent needs (the metas,
--      the candidates, the expected and actual types), and it was being thrown
--      away.  It is captured here, bounded, and mined for 'Involved'.
--
--   Design notes:
--
--   +  /Blocks, not lines/.  A diagnostic is a header line plus every line up to
--      the next header, progress line (@Checking M (…).@), or banner
--      (@———— All done …@).  Trailing blanks are dropped, so Agda's blank-line
--      separator does not leak into a message.
--   +  /Dedup/.  A warning-only run prints each warning twice — once as it is
--      raised and again under the "All done; warnings encountered" banner — so
--      identical diagnostics collapse to the first occurrence.  Without this the
--      counts double.
--   +  /Root-cause ordering/.  'diagnosticRank' sorts scope errors ahead of type
--      errors and the scope warnings that precede a hard error ahead of both, on
--      the reasoning that Agda reports consequences as loudly as causes and the
--      agent should read the cause first.  The sort is stable, so Agda's own
--      (source) order survives within a rank.
--   +  /Bounding/.  Messages are capped per diagnostic and the list is capped by
--      @maxDiagnostics@, with the pre-cap total always reported, so a broken
--      import list cannot return a hundred cascading errors and a short list is
--      never mistaken for a clean one.

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Diagnostics
  ( -- * Parsing Agda's output
    parseDiagnostics
    -- * Bounding the payload
  , capDiagnostics
  , defaultMaxDiagnostics
  , effectiveMaxDiagnostics
  , maxMessageLines
  , maxMessageChars
    -- * Root-cause ordering
  , diagnosticRank
    -- * Exposed for testing
  , parseHeaderLine
  , parseLocation
  , parseRange
  ) where

import Data.Char (isDigit, isSpace)
import Data.List (sortOn)
import Data.Maybe (fromMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import AgdaMCP.Types
  ( DiagRange (..), DiagSeverity (..), Diagnostic (..), Involved (..)
  , noInvolved
  )


-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

-- | parseDiagnostics: every diagnostic in Agda's captured output, deduplicated
-- and ordered most-likely-root-cause first.
--
-- The whole output is accepted (stdout and stderr concatenated, as the tools
-- capture it): Agda 2.8.0 prints diagnostics on stdout, earlier versions on
-- stderr, and the caller need not know which.  Nothing is capped here —
-- 'capDiagnostics' does that, so the caller can report the true total.
parseDiagnostics :: Text -> [Diagnostic]
parseDiagnostics =
  sortOn diagnosticRank . dedupe . map blockToDiagnostic . blocksOf . T.lines


-- ---------------------------------------------------------------------------
-- Bounding the payload
-- ---------------------------------------------------------------------------

-- | The default @maxDiagnostics@: enough for the cascade an agent can actually
-- act on in one iteration, few enough that a broken import list does not spend
-- its context window on consequences of a single missing name.
defaultMaxDiagnostics :: Int
defaultMaxDiagnostics = 10

-- | effectiveMaxDiagnostics: resolve a caller's request to a bound.  Absent
-- means the default; a non-positive number means "no cap", the spelling
-- @--timeout 0@ already uses in this server.
effectiveMaxDiagnostics :: Maybe Int -> Maybe Int
effectiveMaxDiagnostics Nothing = Just defaultMaxDiagnostics
effectiveMaxDiagnostics (Just n)
  | n <= 0    = Nothing
  | otherwise = Just n

-- | capDiagnostics: keep at most the requested number, and report how many
-- there were.  The total is over the input list, so a caller that has prepended
-- its own entries (the timeout notice) sees them counted too.
capDiagnostics :: Maybe Int -> [Diagnostic] -> ([Diagnostic], Int)
capDiagnostics mMax ds =
  (maybe ds (`take` ds) (effectiveMaxDiagnostics mMax), length ds)

-- | How many lines of one diagnostic's message survive.  Chosen against the
-- field report's worst case: an @UnsolvedConstraints@ dump ran ~20 lines of
-- internal meta names, and its structured form is in 'Involved' anyway.
maxMessageLines :: Int
maxMessageLines = 24

-- | A second bound, for a message whose few lines are each enormous (a
-- normalized type can be thousands of characters).
maxMessageChars :: Int
maxMessageChars = 2000


-- ---------------------------------------------------------------------------
-- Root-cause ordering
-- ---------------------------------------------------------------------------

-- | diagnosticRank: how likely this diagnostic is to be the /cause/ rather than
-- a consequence — lower sorts first.
--
-- The order follows the phases Agda runs in, since a diagnostic from an earlier
-- phase is upstream of everything later:
--
--   0. the file could not be resolved at all (a wrong library file or module
--      name makes every other diagnostic untrustworthy);
--   1. scope /warnings/ that precede a hard error — @ModuleDoesntExport@ is the
--      field report's own example, raised on the @open import@ whose missing
--      name then fails to resolve;
--   2. scope errors, which are upstream of every type error in the module;
--   3. type errors;
--   4. unsolved metas and constraints, which are reported after checking and are
--      usually downstream of whatever is above;
--   5. remaining warnings, which by construction did not stop the build;
--   6. informational output.
--
-- Codes are matched by name, so an unrecognized error simply lands with the
-- type errors — the ranking degrades to Agda's own order rather than to
-- nonsense.  A diagnostic with no code (ours, e.g. the timeout notice) ranks
-- with the type errors for the same reason.
diagnosticRank :: Diagnostic -> Int
diagnosticRank d = case diagSeverity d of
  DiagInfo -> 6
  DiagWarning
    | inSet precursorWarningCodes -> 1
    | otherwise                   -> 5
  DiagError
    | inSet resolutionErrorCodes -> 0
    | inSet scopeErrorCodes      -> 2
    | inSet unsolvedCodes        -> 4
    | otherwise                  -> 3
  where
    inSet s = maybe False (`Set.member` s) (diagCode d)

-- | Codes meaning "this file was never really loaded": until one of these is
-- fixed, nothing else Agda said about the module can be trusted.
resolutionErrorCodes :: Set.Set Text
resolutionErrorCodes = Set.fromList
  [ "LibraryError"
  , "ModuleNameDoesntMatchFileName"
  , "ModuleDefinedInOtherFile"
  , "OverlappingProjects"
  , "FileNotFound"
  ]

-- | Warnings whose whole content is "a name will not resolve", so the hard error
-- below them is the consequence and this is the cause (feedback document § 5).
precursorWarningCodes :: Set.Set Text
precursorWarningCodes = Set.fromList
  [ "ModuleDoesntExport"
  , "UnknownNamesInFixityDecl"
  , "UnknownFixityInMixfixDecl"
  ]

-- | Scope-checking errors.  Agda scope-checks a module before type-checking it,
-- so these are upstream of any type error in the same file.
scopeErrorCodes :: Set.Set Text
scopeErrorCodes = Set.fromList
  [ "NotInScope"
  , "AmbiguousName"
  , "AmbiguousModule"
  , "AmbiguousConstructor"
  , "ClashingDefinition"
  , "ClashingModule"
  , "ClashingImport"
  , "ClashingModuleImport"
  , "NoSuchModule"
  , "NotAModuleExpr"
  ]

-- | The end-of-check leftovers: reported last by Agda, and downstream of
-- whatever left them unsolved.
unsolvedCodes :: Set.Set Text
unsolvedCodes = Set.fromList
  [ "UnsolvedMetaVariables"
  , "UnsolvedConstraints"
  , "UnsolvedInteractionMetas"
  ]


-- ---------------------------------------------------------------------------
-- Blocking: header line + its detail lines
-- ---------------------------------------------------------------------------

-- | A parsed diagnostic header line.
data Header = Header
  { hdrSeverity :: DiagSeverity
  , hdrCode     :: Maybe Text       -- ^ @[Code]@ (errors) or @-W[no]Code@ (warnings).
  , hdrFile     :: Maybe FilePath
  , hdrRange    :: Maybe DiagRange
  , hdrRest     :: Text             -- ^ Header text that was neither location nor code.
  } deriving (Eq, Show)

-- | blocksOf: split Agda's output into (header, detail-lines) blocks, in the
-- order Agda printed them.  Lines before the first header, and lines after a
-- boundary, belong to no block and are dropped.
-- Note: foldl' is re-exported from Prelude in GHC 9.10+ (base 4.20+), as
-- 'AgdaMCP.Agda.parseGoalContext' already relies on.
blocksOf :: [Text] -> [(Header, [Text])]
blocksOf = finish . foldl' step (Nothing, [])
  where
    step (cur, done) ln =
      case parseHeaderLine ln of
        Just h                -> (Just (h, []), close cur done)
        Nothing
          | isBoundaryLine ln -> (Nothing, close cur done)
          | otherwise         -> (fmap (\(h, body) -> (h, ln : body)) cur, done)

    close Nothing          done = done
    close (Just (h, body)) done = (h, reverse body) : done

    finish (cur, done) = reverse (close cur done)

-- | isBoundaryLine: output that is certainly not part of a diagnostic's detail
-- block — Agda's progress lines and its end-of-run banner.  Without the banner
-- case, a warning-only run would swallow @———— All done … ————@ into the
-- warning above it.
isBoundaryLine :: Text -> Bool
isBoundaryLine ln =
  "—" `T.isPrefixOf` s
  || progress "Checking " || progress "Loading " || progress "Finished "
  where
    s = T.stripStart ln
    -- "Checking M (/x/M.agda)." — required to end like one, so that a message
    -- line merely beginning with the word is not mistaken for progress.
    progress p = p `T.isPrefixOf` s && "." `T.isSuffixOf` T.stripEnd s


-- ---------------------------------------------------------------------------
-- Header parsing
-- ---------------------------------------------------------------------------

-- | parseHeaderLine: recognize a diagnostic header and take it apart.
--
-- Both shapes Agda 2.8.0 emits are accepted:
--
-- > /x/M.agda:11.5-17: error: [UnsolvedMetaVariables]
-- > /x/M.agda:3.20-43: warning: -W[no]ModuleDoesntExport
-- > error: [UnsolvedConstraints]
--
-- The location-less shape is only recognized at column 0, where Agda prints it;
-- requiring that keeps an indented detail line from posing as a header.
parseHeaderLine :: Text -> Maybe Header
parseHeaderLine ln = do
  (locPart, sev, afterMarker) <- severitySplit ln
  let (mFile, mRange, locLeftover) = parseLocation locPart
      (mCode, prose)               = parseCode afterMarker
      rest = T.strip (T.unwords (filter (not . T.null) [locLeftover, T.strip prose]))
  pure Header
    { hdrSeverity = sev
    , hdrCode     = mCode
    , hdrFile     = mFile
    , hdrRange    = mRange
    , hdrRest     = rest
    }

-- | severitySplit: (text before the severity marker, severity, text after it).
severitySplit :: Text -> Maybe (Text, DiagSeverity, Text)
severitySplit ln =
  case (breakAt ": error:" DiagError, breakAt ": warning:" DiagWarning) of
    (Just a, Just b) -> Just (earlier a b)
    (Just a, Nothing) -> Just a
    (Nothing, Just b) -> Just b
    (Nothing, Nothing) ->
      case T.stripPrefix "error:" ln of
        Just post -> Just ("", DiagError, post)
        Nothing   -> (\post -> ("", DiagWarning, post)) <$> T.stripPrefix "warning:" ln
  where
    breakAt marker sev =
      let (pre, post) = T.breakOn marker ln
      in  if T.null post
            then Nothing
            else Just (pre, sev, T.drop (T.length marker) post)

    earlier a@(preA, _, _) b@(preB, _, _)
      | T.length preA <= T.length preB = a
      | otherwise                      = b

-- | parseCode: the machine-readable name, and whatever prose shared the header
-- line with it.
--
-- Errors spell it @[NotInScope]@; warnings spell it @-W[no]ModuleDoesntExport@,
-- naming the flag that would silence them.  A header whose remainder is neither
-- has no code, and its text becomes the first line of the message.
parseCode :: Text -> (Maybe Text, Text)
parseCode raw =
  case T.stripPrefix "[" t of
    Just rest ->
      let (code, after) = T.breakOn "]" rest
      in  if T.null after || T.null code || T.any isSpace code
            then (Nothing, t)
            else (Just code, T.drop 1 after)
    Nothing ->
      case stripWarningFlag t of
        Nothing   -> (Nothing, t)
        Just rest ->
          let (code, after) = T.break isSpace rest
          in  if T.null code then (Nothing, t) else (Just code, after)
  where
    t = T.stripStart raw
    stripWarningFlag s = case T.stripPrefix "-W[no]" s of
      Just r  -> Just r
      Nothing -> T.stripPrefix "-W" s

-- | parseLocation: split @\/x\/M.agda:9.12-13@ into its file and range.
--
-- Returns the input unchanged as the third component when it is not a location,
-- so nothing Agda printed is silently dropped: the caller folds that leftover
-- back into the message.  The file is taken up to the /last/ colon, so a path
-- that itself contains one still parses.
parseLocation :: Text -> (Maybe FilePath, Maybe DiagRange, Text)
parseLocation locPart
  | T.null s = (Nothing, Nothing, "")
  | otherwise =
      let (before, rangeT) = T.breakOnEnd ":" s
          file             = T.dropEnd 1 before
      in  case parseRange rangeT of
            Just r | not (T.null file) -> (Just (T.unpack file), Just r, "")
            _                          -> (Nothing, Nothing, s)
  where
    s = T.strip locPart

-- | parseRange: Agda's printed range, in either spelling.
--
-- > 9.12-13     -- Agda >= 2.6.2, same line
-- > 9.12-11.5   -- Agda >= 2.6.2, spanning lines
-- > 10,5-15     -- older Agda, same line
-- > 10,5-11,3   -- older Agda, spanning lines
-- > 9.12        -- a single position
--
-- The separator between line and column is the only difference between the two
-- generations, and both are accepted wherever one appears — which is the whole
-- fix for "no diagnostic carries a source position" under Agda 2.8.0.
parseRange :: Text -> Maybe DiagRange
parseRange t = do
  let (startT, dashRest) = T.break (== '-') t
      endT               = T.drop 1 dashRest
  (sl, sc) <- parsePos startT
  if T.null dashRest
    then Just (DiagRange sl sc sl sc)
    else case parsePos endT of
      -- "9.12-11.5": the end names its own line.
      Just (el, ec) -> Just (DiagRange sl sc el ec)
      -- "9.12-13": the end is a column on the start's line.
      Nothing       -> (\ec -> DiagRange sl sc sl ec) <$> readInt endT

-- | parsePos: @LINE.COL@ or @LINE,COL@.
parsePos :: Text -> Maybe (Int, Int)
parsePos t
  | T.null rest = Nothing
  | otherwise   = (,) <$> readInt lineT <*> readInt (T.drop 1 rest)
  where
    (lineT, rest) = T.break (\c -> c == '.' || c == ',') t

-- | readInt: a whole non-negative number, or nothing.
readInt :: Text -> Maybe Int
readInt t
  | T.null t || not (T.all isDigit t) = Nothing
  | otherwise                         = Just (read (T.unpack t))


-- ---------------------------------------------------------------------------
-- Block → Diagnostic
-- ---------------------------------------------------------------------------

-- | blockToDiagnostic: assemble the structured diagnostic from its block.
blockToDiagnostic :: (Header, [Text]) -> Diagnostic
blockToDiagnostic (h, rawBody) = Diagnostic
  { diagSeverity = hdrSeverity h
  , diagCode     = hdrCode h
  , diagFile     = hdrFile h
  , diagRange    = hdrRange h
  , diagMessage  = if T.null message
                     then fromMaybe "(no message)" (hdrCode h)
                     else message
  , diagInvolved = involvedOf (hdrCode h) body
  }
  where
    body    = dropTrailingBlanks rawBody
    message = boundMessage . T.intercalate "\n" $
                filter (not . T.null) [hdrRest h] <> body

-- | dropTrailingBlanks: Agda separates diagnostics with a blank line; it is not
-- part of the message above it.
dropTrailingBlanks :: [Text] -> [Text]
dropTrailingBlanks = reverse . dropWhile (T.null . T.strip) . reverse

-- | boundMessage: the full body, bounded in lines and then in characters, with
-- the elision stated rather than silent.
boundMessage :: Text -> Text
boundMessage t
  | T.length capped > maxMessageChars = T.take maxMessageChars capped <> "…"
  | otherwise                         = capped
  where
    ls = T.lines t
    capped
      | length ls > maxMessageLines =
          T.intercalate "\n" (take maxMessageLines ls)
            <> "\n… (" <> T.pack (show (length ls - maxMessageLines)) <> " more lines)"
      | otherwise = t

-- | dedupe: keep the first of each identical diagnostic.
--
-- A run that ends in warnings prints each of them twice — once where it was
-- raised, once under the "All done; warnings encountered" banner — so without
-- this every such warning is reported and counted twice.
dedupe :: [Diagnostic] -> [Diagnostic]
dedupe = go Set.empty
  where
    go _ [] = []
    go seen (d : ds)
      | k `Set.member` seen = go seen ds
      | otherwise           = d : go (Set.insert k seen) ds
      where k = dedupeKey d

    dedupeKey d = T.intercalate "\US"
      [ T.pack (show (diagSeverity d))
      , fromMaybe "" (diagCode d)
      , maybe "" T.pack (diagFile d)
      , maybe "" (T.pack . show) (diagRange d)
      , diagMessage d
      ]


-- ---------------------------------------------------------------------------
-- The `involved` payload (feedback document § 5, third column)
-- ---------------------------------------------------------------------------

-- | involvedOf: lift the entities a diagnostic is about out of its prose.
--
-- Keyed on the code, because that is what tells us how to read the body; see
-- 'AgdaMCP.Types.Involved' for the per-code contract.  Extraction is
-- best-effort by construction — Agda's messages are prose, and a future release
-- may reword them — so every branch degrades to an empty payload rather than to
-- a wrong one, and the full message is always there to fall back on.
involvedOf :: Maybe Text -> [Text] -> Involved
involvedOf Nothing body = mismatchOf body
involvedOf (Just code) body
  | code `Set.member` unsolvedCodes =
      noInvolved { invMetaTypes = firstIndentedRun body }
  | code == "NotInScope" =
      noInvolved { invCandidates = didYouMean body }
  | code `Set.member` ambiguityCodes =
      noInvolved { invCandidates = ambiguityCandidates body }
  | code == "ModuleDoesntExport" =
      noInvolved { invCandidates = firstIndentedRun body }
  | code `Set.member` clashCodes =
      noInvolved { invCandidates = previousDefinitionOrigin body }
  | otherwise = mismatchOf body

-- | Codes whose message lists the candidates a name could refer to.
ambiguityCodes :: Set.Set Text
ambiguityCodes = Set.fromList
  [ "AmbiguousName", "AmbiguousModule", "AmbiguousConstructor" ]

-- | Codes whose message names where the pre-existing definition came from.
clashCodes :: Set.Set Text
clashCodes = Set.fromList
  [ "ClashingDefinition", "ClashingModule", "ClashingImport", "ClashingModuleImport" ]

-- | firstIndentedRun: the first indented list in a message body.
--
-- > Unsolved metas at the following locations:
-- >   /x/M.agda:7.5-6
-- >   /x/M.agda:9.5-6
--
-- Keyed on the indentation rather than on the sentence above it, because that
-- sentence is filled to the terminal width and its continuation lines sit at
-- the left margin — so a long module name can move "…the following:" onto a
-- second line, and a phrase-matching parser would then find nothing.  Indented
-- lines are unambiguous: Agda indents the items of a list and nothing else.
firstIndentedRun :: [Text] -> [Text]
firstIndentedRun = indentedRun . dropWhile (not . isIndented)

-- | indentedRun: the leading run of indented lines, stripped.  A line back at
-- the left margin ends the list — which is exactly how Agda separates a list
-- from the @when checking …@ trailer below it.
indentedRun :: [Text] -> [Text]
indentedRun = map T.strip . takeWhile isIndented

-- | isIndented: a non-blank line that starts with whitespace.
isIndented :: Text -> Bool
isIndented ln = not (T.null (T.strip ln)) && T.head ln `elem` (" \t" :: String)

-- | didYouMean: the suggestions Agda offers for a name that is not in scope,
-- qualified as it prints them — so the module that would export each candidate
-- is visible without a second query.
--
-- >   at /x/M.agda:4.9-14
-- >     (did you mean
-- >        'Agda.Builtin.Nat.Nat.zero' or
-- >        'Nat.zero' or
-- >        'zero'?)
--
-- Agda also writes the one-suggestion case inline on the @did you mean@ line,
-- so both are read; and a message that lists several out-of-scope names carries
-- one such block each, so the scan continues past the first.  A name with a
-- prime in it survives: exactly one quote is stripped from each end.
didYouMean :: [Text] -> [Text]
didYouMean body = case break (marker `T.isInfixOf`) body of
  (_, [])         -> []
  (_, hdr : rest) ->
    let inline          = T.drop (T.length marker) (snd (T.breakOn marker hdr))
        (quoted, after) = span startsQuoted rest
        here            = [ n | ln <- inline : quoted
                              , let n = suggestion ln, not (T.null n) ]
    in  here <> didYouMean after
  where
    marker = "did you mean"

    startsQuoted ln = "'" `T.isPrefixOf` T.strip ln

    -- "'Nat.zero' or" and "'zero'?)" both reduce to the name.
    suggestion = unquote . T.dropWhileEnd (`elem` ("?)., " :: String)) . dropOr . T.strip
    dropOr ln  = fromMaybe ln (T.stripSuffix " or" (T.stripEnd ln))
    unquote ln = let a = fromMaybe ln (T.stripPrefix "'" ln)
                 in  fromMaybe a (T.stripSuffix "'" a)

-- | ambiguityCandidates: the qualified names an ambiguous name could refer to.
--
-- > Ambiguous name foo. It could refer to any one of
-- >   A1.foo bound at
-- >     /x/A1.agda:3.1-4
-- >   A2.foo bound at
-- >     /x/A2.agda:3.1-4
--
-- As with 'firstIndentedRun', the list is found by its indentation rather than
-- by the sentence introducing it, which Agda fills to the terminal width.  The
-- provenance line under each candidate is indented too, but a location is not a
-- name, so tokens carrying a colon are skipped.
ambiguityCandidates :: [Text] -> [Text]
ambiguityCandidates body =
  [ tok
  | ln <- firstIndentedRun body
  , tok : _ <- [T.words ln]
  , not (":" `T.isInfixOf` tok)
  ]

-- | previousDefinitionOrigin: where the definition being clashed with lives.
--
-- > Multiple definitions of least. Previous definition at
-- > /x/M.agda:4.9-14
--
-- Agda wraps that sentence freely, so the body is rejoined before the phrase is
-- located; the answer is the token that follows it.
previousDefinitionOrigin :: [Text] -> [Text]
previousDefinitionOrigin body =
  case T.breakOn marker (T.unwords (map T.strip body)) of
    (_, rest) | T.null rest -> []
              | otherwise   -> take 1 (T.words (T.drop (T.length marker) rest))
  where
    marker = "Previous definition at"

-- | mismatchOf: the two sides of Agda's inequality line.
--
-- > Bool !=< Nat
-- > when checking that the expression true has type Nat
--
-- @!=<@ is "is not a subtype of", and Agda writes the actual (inferred) type on
-- its left, the expected one on its right; @!=@ is the same shape for terms,
-- with an @of type T@ trailer that belongs to neither side.  Everything from the
-- @when …@ trailer on is context, not the mismatch, so it is cut first.
mismatchOf :: [Text] -> Involved
mismatchOf body = case splitOnEither ["!=<", "!="] joined of
  Nothing -> noInvolved
  Just (lhs, rhs)
    | T.null actual || T.null expected -> noInvolved
    | otherwise -> noInvolved { invActual = Just actual, invExpected = Just expected }
    where
      actual   = T.strip lhs
      expected = T.strip (fst (T.breakOn " of type " rhs))
  where
    joined = T.unwords (map T.strip (takeWhile (not . isTrailer) body))
    isTrailer ln = "when " `T.isPrefixOf` T.strip ln

    splitOnEither [] _ = Nothing
    splitOnEither (sep : seps) t =
      case T.breakOn sep t of
        (_, rest) | T.null rest -> splitOnEither seps t
        (pre, rest)             -> Just (pre, T.drop (T.length sep) rest)
