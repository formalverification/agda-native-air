-- | Holes.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Holes.hs
--
-- Description:
--   The hole model for agda-mcp (issues #71 and #73).
--
--   This module answers one question — "which spans of this source file are
--   holes?" — the way Agda itself would answer it, without running Agda:
--
--   1. Literate awareness.  For literate files, non-code text is first
--      blanked out ('maskNonCode'), porting the flavour rules of Agda 2.8.0's
--      @Agda.Syntax.Parser.Literate@ (its @illiterate . literateXY@
--      pipeline).  Masking, rather than extracting, preserves every character
--      position, so all spans below are in literate-file coordinates.
--   2. Lexical awareness.  The masked text is then scanned with a small model
--      of Agda's lexer: line comments (@--@ at a token boundary), nested
--      block comments (@{- … -}@), pragmas (@{-# … #-}@), string and
--      character literals, nested @{! … !}@ holes, and @?@ as a hole only
--      when it stands as a lexically separate token (so @op?@ or @_≟_@ never
--      match).
--
--   The result is that hole enumeration agrees with Agda's interaction-point
--   count, comment and prose tokens are never holes, and 'substituteHole' /
--   'injectReportExpr' splice the hole's actual span (one character for @?@,
--   arbitrary for @{! e !}@) instead of a fixed four-character token.
--
--   On top of the scan sits the /addressing/ model of issue #79: a 'HoleRef'
--   names one hole, either by its source-order index or by a @(line, column)@
--   position in the file as written.  The position is the handle to prefer — it
--   moves only when an edit above it moves the text, while every index after a
--   filled hole is renumbered whether or not anything moved — and
--   'resolveHoleRef' turns either spelling into an index, or into an error that
--   names the file's holes rather than guessing.
--
--   The functions here are pure; AgdaMCP.Tools.ProofState combines them with
--   the Agda subprocess layer in AgdaMCP.Agda.  The long-term plan (issue
--   #75) is to make Agda's interaction protocol the source of truth for live
--   queries; this scanner is the batch-mode approximation, kept honest by
--   Agda-parity tests in test/Main.hs.

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns      #-}
{-# LANGUAGE StrictData        #-}

module AgdaMCP.Holes
  ( -- * Literate flavours
    LiterateFlavour (..)
  , flavourOf
  , maskNonCode
    -- * Hole spans
  , HoleSpan (..)
  , findHoles
  , findNthHole
    -- * Hole addressing (issue #79)
  , HoleRef (..)
  , offsetOfPosition
  , holeIndexAtOffset
  , resolveHoleRef
  , describeHole
    -- * Splicing
  , substituteHole
  , injectReportExpr
  ) where

import Data.Char (isAlphaNum, isSpace, toLower)
import Data.List (isSuffixOf, sortOn)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T


-- ---------------------------------------------------------------------------
-- Literate flavours
-- ---------------------------------------------------------------------------

-- | The literate formats Agda 2.8.0 supports, plus plain @.agda@.
--
-- The constructors mirror the processors in @Agda.Syntax.Parser.Literate@;
-- @.lagda.typ@ (Typst) maps to 'LiterateMd' because Agda treats the two as
-- the same code-block syntax.
data LiterateFlavour
  = PlainAgda      -- ^ @.agda@ — the whole file is code.
  | LiterateTeX    -- ^ @.lagda@, @.lagda.tex@ — @\\begin{code}@ … @\\end{code}@.
  | LiterateMd     -- ^ @.lagda.md@, @.lagda.typ@ — @```agda@ (or bare @```@) fences.
  | LiterateRsT    -- ^ @.lagda.rst@ — a @::@ line, then the indented block.
  | LiterateOrg    -- ^ @.lagda.org@ — @#+begin_src agda2@ … @#+end_src@.
  | LiterateTree   -- ^ @.lagda.tree@ (Forester) — @\\agda{@ … @}@.
  deriving (Eq, Show)

-- | Decide the literate flavour from a file path's extension(s).
-- Unknown extensions are treated as plain Agda.
flavourOf :: FilePath -> LiterateFlavour
flavourOf path
  | has ".lagda.md"   = LiterateMd
  | has ".lagda.typ"  = LiterateMd
  | has ".lagda.tex"  = LiterateTeX
  | has ".lagda.rst"  = LiterateRsT
  | has ".lagda.org"  = LiterateOrg
  | has ".lagda.tree" = LiterateTree
  | has ".lagda"      = LiterateTeX
  | otherwise         = PlainAgda
  where
    lower   = map toLower path
    has ext = ext `isSuffixOf` lower

-- ---------------------------------------------------------------------------
-- Literate masking (port of Agda 2.8.0 Agda.Syntax.Parser.Literate)
-- ---------------------------------------------------------------------------

-- | Blank out the non-code parts of a literate file, preserving every
-- character position (the same trick as Agda's @illiterate@: non-code
-- characters become spaces, except newlines and other non-tab whitespace,
-- which are kept so line/column bookkeeping is unaffected).  For 'PlainAgda'
-- this is the identity.
maskNonCode :: LiterateFlavour -> Text -> Text
maskNonCode flav src = case flav of
  PlainAgda    -> src
  LiterateTeX  -> fromLines (texLayers   (toLines src))
  LiterateMd   -> fromLines (mdLayers    (toLines src))
  LiterateRsT  -> fromLines (rstLayers   (toLines src))
  LiterateOrg  -> fromLines (orgLayers   (toLines src))
  LiterateTree -> fromLines (treeLayers  (toLines src))
  where
    -- Split into lines, each keeping its trailing newline (Agda's caseLine).
    toLines :: Text -> [Text]
    toLines t
      | T.null t  = []
      | otherwise = case T.breakOn "\n" t of
          (l, rest) | T.null rest -> [l]
                    | otherwise   -> (l <> "\n") : toLines (T.drop 1 rest)

    fromLines :: [(Bool, Text)] -> Text
    fromLines = T.concat . map (\(code, t) -> if code then t else bleach t)

    -- Agda's bleach: keep non-tab whitespace (so newlines survive), blank
    -- everything else.
    bleach = T.map (\c -> if isSpace c && c /= '\t' then c else ' ')

-- Each layer function maps lines (with trailing newlines) to
-- (isCode, chunk) pairs whose concatenation is the original text.

-- | A line with its trailing newline stripped for matching (the trailing
-- @[[:space:]]*@ in Agda's regexes absorbs it).
noNl :: Text -> Text
noNl = T.dropWhileEnd (== '\n')

-- | Markdown (also Typst): a line whose content ends with @```agda@ or bare
-- @```@ opens an Agda block; a fence with any other tag (@```haskell@) opens
-- a non-Agda block whose body stays prose; a line of just @```@ closes.
mdLayers :: [Text] -> [(Bool, Text)]
mdLayers = prose
  where
    prose [] = []
    prose (l : rest)
      | mdBegin l      = (False, l) : code rest
      | mdBeginOther l = (False, l) : codeOther rest
      | otherwise      = (False, l) : prose rest

    code [] = []
    code (l : rest)
      | mdEnd l   = (False, l) : prose rest
      | otherwise = (True, l)  : code rest

    codeOther [] = []
    codeOther (l : rest)
      | mdEnd l   = (False, l) : prose rest
      | otherwise = (False, l) : codeOther rest

    -- rex "(.*)([[:space:]]*```(agda)?[[:space:]]*)"
    mdBegin l =
      let s = T.stripEnd (noNl l)
      in  "```agda" `T.isSuffixOf` s || "```" `T.isSuffixOf` s

    -- rex "[[:space:]]*```[a-zA-Z0-9-]*[[:space:]]*"
    mdBeginOther l =
      case T.stripPrefix "```" (T.strip (noNl l)) of
        Just tag -> T.all (\c -> isAlphaNum c || c == '-') tag
        Nothing  -> False

    -- rex "([[:space:]]*```[[:space:]]*)"
    mdEnd l = T.strip (noNl l) == "```"

-- | TeX (@.lagda@, @.lagda.tex@): @\\begin{code}@ opens (unless commented
-- out by a preceding unescaped @%@ or stray @\\@ on the line), a line of
-- blanks + @\\end{code}@ closes.  The newline of the @\\begin{code}@ line is
-- code in Agda's decomposition, but it is whitespace either way, so we treat
-- both marker lines as non-code without affecting positions.
texLayers :: [Text] -> [(Bool, Text)]
texLayers = envLayers "\\begin{code}" "\\end{code}"

-- | Forester (@.lagda.tree@): @\\agda{@ opens, a line of blanks + @}@ closes.
treeLayers :: [Text] -> [(Bool, Text)]
treeLayers = envLayers "\\agda{" "}"

-- | Shared TeX-style environment scanner.
--   Begin: rex "(([^\\%]|\\\\.)*)(<begin>[^\n]*)(\n)?" — any prefix free of
--   unescaped @\\@ or @%@, then the begin marker; rest of line is markup.
--   End: rex "([[:blank:]]*)(<end>)(.*)" — blanks, then the end marker.
envLayers :: Text -> Text -> [Text] -> [(Bool, Text)]
envLayers beginTok endTok = prose
  where
    prose [] = []
    prose (l : rest)
      | beginsEnv (noNl l) = (False, l) : code rest
      | otherwise          = (False, l) : prose rest

    code [] = []
    code (l : rest)
      | endsEnv (noNl l) = (False, l) : prose rest
      | otherwise        = (True, l)  : code rest

    beginsEnv = go
      where
        go t
          | T.null t                  = False
          | beginTok `T.isPrefixOf` t = True
          | otherwise = case T.head t of
              '\\' -> not (T.null (T.tail t)) && go (T.drop 2 t)
              '%'  -> False
              _    -> go (T.tail t)

    endsEnv l = endTok `T.isPrefixOf` T.dropWhile isBlankChar l

isBlankChar :: Char -> Bool
isBlankChar c = isSpace c && c /= '\n'

-- | reStructuredText: a non-comment line ending in @::@ starts a code block;
-- the block is the following indented lines (all-blank lines pass through as
-- markup); the first non-indented, non-blank line ends it.
rstLayers :: [Text] -> [(Bool, Text)]
rstLayers = maybeCode
  where
    maybeCode [] = []
    maybeCode (l : rest)
      | rstComment (noNl l) = (False, l) : maybeCode rest
      | rstCode (noNl l)    = (False, l) : codeStart rest
      | otherwise           = (False, l) : maybeCode rest

    -- Find the first indented line of the block.
    codeStart [] = []
    codeStart (l : rest)
      | T.all isSpace (noNl l) = (False, l) : codeStart rest
      | otherwise =
          let ind = T.takeWhile isBlankChar (noNl l)
          in  if T.null ind
                then maybeCode (l : rest)
                else (True, l) : indented ind rest

    indented _   [] = []
    indented ind (l : rest)
      | T.all isSpace (noNl l)      = (True, l) : indented ind rest
      | ind `T.isPrefixOf` noNl l   = (True, l) : indented ind rest
      | otherwise                   = maybeCode (l : rest)

    -- rex "(.*)(::)([[:space:]]*)"
    rstCode l = "::" `T.isSuffixOf` T.stripEnd l

    -- rex "[[:space:]]*\\.\\.([[:space:]].*)?"
    rstComment l =
      case T.stripPrefix ".." (T.stripStart l) of
        Just rest -> T.null rest || isSpace (T.head rest)
        Nothing   -> False

-- | Org mode: a line containing @#+begin_src agda2@ followed by whitespace
-- (case-insensitive) opens; a line whose content starts with @#+end_src@
-- (case-insensitive) closes.
orgLayers :: [Text] -> [(Bool, Text)]
orgLayers = prose
  where
    prose [] = []
    prose (l : rest)
      | orgBegin l = (False, l) : code rest
      | otherwise  = (False, l) : prose rest

    code [] = []
    code (l : rest)
      | orgEnd (noNl l) = (False, l) : prose rest
      | otherwise       = (True, l)  : code rest

    -- rex' "\\`(.*)([[:space:]]*\\#\\+begin_src agda2[[:space:]]+)"
    -- (start-anchored only; the line's newline supplies the trailing space).
    -- The greedy (.*) means Agda accepts ANY occurrence of the marker that
    -- has the required trailing whitespace, so an occurrence that fails the
    -- whitespace check must not end the search.
    orgBegin l = go (T.toLower l)
      where
        marker = "#+begin_src agda2"
        go t = case T.breakOn marker t of
          (_, rest)
            | T.null rest -> False
            | otherwise   ->
                let after = T.drop (T.length marker) rest
                in  (not (T.null after) && isSpace (T.head after))
                      || go (T.drop 1 rest)

    -- rex' "\\`([[:space:]]*\\#\\+end_src[[:space:]]*)(.*)"
    orgEnd l = "#+end_src" `T.isPrefixOf` T.toLower (T.stripStart l)


-- ---------------------------------------------------------------------------
-- Hole scanning
-- ---------------------------------------------------------------------------

-- | A located hole in source text.  All offsets and line/column numbers are
-- coordinates in the file as given — for a literate file, literate-file
-- coordinates, exactly as an editor (or Agda's own error messages) would
-- report them.
data HoleSpan = HoleSpan
  { hsStart :: Int    -- ^ 0-based character offset (Text index) of the hole's first character.
  , hsEnd   :: Int    -- ^ 0-based character offset one past the hole's last character.
  , hsLine  :: Int    -- ^ 1-based line number of the hole's first character.
  , hsCol   :: Int    -- ^ 1-based column number of the hole's first character.
  } deriving (Eq, Show)

-- | Characters that terminate an Agda name.  Anything else — including
-- @?@, @!@, @-@, primes, backslash, and all the operator symbols — may be
-- part of a name, which is why @op?@ and @_≟_@ must never be read as holes
-- and why @x--y@ is a name rather than a comment.  Backslash is genuinely a
-- name character (Agda 2.8.0 Lexer.x: @$idchar = [ $idstart ' \\\\ ]@, and
-- @\@start@ admits @\\@ followed by a non-alphabetic name character), so
-- @\\?@ is one identifier and its @?@ is not a hole; the lambda in @\\x@
-- works because a name cannot start with @\\@ + letter, not because @\\@
-- breaks names.
isNameBreak :: Char -> Bool
isNameBreak c = isSpace c || c `elem` ("(){};.@\"" :: String)

-- | Find all holes in source text, in order.  The flavour selects the
-- literate masking applied first; the scan itself recognizes every Agda hole
-- syntax — @{!!}@, @{! … !}@ with nesting, and standalone @?@ — while
-- skipping comments, pragmas, and string/character literals, so a hole token
-- in a comment or in literate prose is never counted.
findHoles :: LiterateFlavour -> Text -> [HoleSpan]
findHoles flav src = scan 0 1 1 True (maskNonCode flav src)
  where
    -- afterBreak: was the previous character a token break (or BOF)?
    -- Needed because "--", "?", and "'" only begin their token when they are
    -- not glued to a preceding name (x--y, op?, x' are single names).
    scan :: Int -> Int -> Int -> Bool -> Text -> [HoleSpan]
    scan !off !ln !col !afterBreak txt = case T.uncons txt of
      Nothing -> []
      Just (c, rest)
        -- {! … !} hole (nesting on {! / !}); braces always break names.
        | c == '{', "!" `T.isPrefixOf` rest ->
            let len   = holeLen 1 2 (T.drop 1 rest)
                token = T.take len txt
                nls   = T.count "\n" token
                ln'   = ln + nls
                col'  = if nls == 0
                          then col + len
                          else 1 + T.length (T.takeWhileEnd (/= '\n') token)
            in  HoleSpan off (off + len) ln col
                  : scan (off + len) ln' col' True (T.drop len txt)
        -- Pragma {-# … #-}: skip to #-} (holes cannot occur inside).
        | c == '{', "-#" `T.isPrefixOf` rest ->
            skipTo "#-}" off ln col txt
        -- Nested block comment {- … -}.
        | c == '{', "-" `T.isPrefixOf` rest ->
            comment 1 (off + 2) ln (col + 2) (T.drop 1 rest)
        -- String literal.
        | c == '"' ->
            string (off + 1) ln (col + 1) rest
        -- Constructs that only start at a token boundary:
        | afterBreak, c == '-', "-" `T.isPrefixOf` rest ->
            -- Line comment: "--" to end of line (Agda's comment rule wins
            -- over any operator munch, so -- always comments here).
            lineComment off ln col txt
        | afterBreak, c == '?', maybe True (isNameBreak . fst) (T.uncons rest) ->
            -- Standalone ? — a hole only as a lexically separate token.
            HoleSpan off (off + 1) ln col
              : scan (off + 1) ln (col + 1) True rest
        | afterBreak, c == '\'' ->
            charLit off ln col rest
        | c == '\n' ->
            scan (off + 1) (ln + 1) 1 True rest
        | otherwise ->
            scan (off + 1) ln (col + 1) (isNameBreak c) rest

    -- Inside {! … !}: count nesting; returns the token length measured from
    -- the opening '{'.  An unterminated hole extends to end of file (Agda
    -- would reject the file; we stay well-defined).
    holeLen :: Int -> Int -> Text -> Int
    holeLen 0 !len _ = len
    holeLen !depth !len rest = case T.uncons rest of
      Nothing -> len
      Just ('{', r) | "!" `T.isPrefixOf` r -> holeLen (depth + 1) (len + 2) (T.drop 1 r)
      Just ('!', r) | "}" `T.isPrefixOf` r -> holeLen (depth - 1) (len + 2) (T.drop 1 r)
      Just (_, r) -> holeLen depth (len + 1) r

    -- Inside {- … -}: count nesting (Agda comments nest).
    comment :: Int -> Int -> Int -> Int -> Text -> [HoleSpan]
    comment 0 !off !ln !col rest = scan off ln col True rest
    comment !depth !off !ln !col rest = case T.uncons rest of
      Nothing -> []
      Just ('{', r) | "-" `T.isPrefixOf` r -> comment (depth + 1) (off + 2) ln (col + 2) (T.drop 1 r)
      Just ('-', r) | "}" `T.isPrefixOf` r -> comment (depth - 1) (off + 2) ln (col + 2) (T.drop 1 r)
      Just ('\n', r) -> comment depth (off + 1) (ln + 1) 1 r
      Just (_, r)    -> comment depth (off + 1) ln (col + 1) r

    -- "-- …" to end of line.
    lineComment !off !ln !col txt =
      let (skipped, rest) = T.breakOn "\n" txt
      in  scan (off + T.length skipped) ln (col + T.length skipped) True rest

    -- Skip to just past a delimiter (or end of file), tracking position.
    skipTo :: Text -> Int -> Int -> Int -> Text -> [HoleSpan]
    skipTo delim !off !ln !col txt = case T.uncons txt of
      Nothing -> []
      Just (c, rest)
        | delim `T.isPrefixOf` txt ->
            let n = T.length delim
            in  scan (off + n) ln (col + n) True (T.drop n txt)
        | c == '\n' -> skipTo delim (off + 1) (ln + 1) 1 rest
        | otherwise -> skipTo delim (off + 1) ln (col + 1) rest

    -- Inside "…": backslash escapes; a newline also ends the literal
    -- (Agda strings are single-line; stay well-defined on bad input).
    string :: Int -> Int -> Int -> Text -> [HoleSpan]
    string !off !ln !col rest = case T.uncons rest of
      Nothing -> []
      Just ('\\', r) -> case T.uncons r of
        Nothing      -> []
        Just (e, r') -> string (off + 2) (if e == '\n' then ln + 1 else ln)
                               (if e == '\n' then 1 else col + 2) r'
      Just ('"', r)  -> scan (off + 1) ln (col + 1) True r
      Just ('\n', r) -> scan (off + 1) (ln + 1) 1 True r
      Just (_, r)    -> string (off + 1) ln (col + 1) r

    -- A ' at a token boundary: consume a character literal if one closes on
    -- this line, otherwise treat the quote as an ordinary name character
    -- (defensive; Agda would reject the latter).
    charLit !off !ln !col rest =
      case litLen rest of
        Just n  -> scan (off + 1 + n) ln (col + 1 + n) True (T.drop n rest)
        Nothing -> scan (off + 1) ln (col + 1) False rest
      where
        litLen t = go' 0 t
          where
            go' :: Int -> Text -> Maybe Int
            go' !n u = case T.uncons u of
              Nothing         -> Nothing
              Just ('\n', _)  -> Nothing
              Just ('\\', u') -> case T.uncons u' of
                Nothing       -> Nothing
                Just (_, u'') -> go' (n + 2) u''
              Just ('\'', _)  -> Just (n + 1)
              Just (_, u')    -> go' (n + 1) u'

-- | Find the n-th hole (0-indexed) in source text.
findNthHole :: LiterateFlavour -> Int -> Text -> Maybe HoleSpan
findNthHole flav n src
  | n < 0     = Nothing
  | otherwise = let holes = findHoles flav src
                in  if n < length holes then Just (holes !! n) else Nothing


-- ---------------------------------------------------------------------------
-- Hole addressing (issue #79)
-- ---------------------------------------------------------------------------

-- | How a tool call names the hole it means.
--
-- 'ByPosition' is the handle to prefer, and the honest statement of why is a
-- comparison rather than an absolute.  A hole's @(line, column)@ describes where
-- its text sits, so it survives exactly the edits that do not move that text: a
-- fill later in the file never disturbs it, and a fill earlier in the file
-- disturbs it only when the candidate differs in length or line count from the
-- hole token it replaced (then holes after it shift — by the length difference
-- on the same line, by the line difference below).  'ByIndex' is a 0-based index
-- into the source-order hole list, so /every/ hole after a filled one is
-- renumbered, whether or not a character moved.  That unconditional shift is the
-- bookkeeping § 3.8 of the feedback document records an agent losing track of
-- between calls.
--
-- Neither survives an arbitrary edit, which is why the tools answer with the
-- re-anchored hole list: after a fill a client keeps, the next address comes
-- from that response, not from coordinates cached before it.
--
-- Positions are 1-based coordinates in the file /as written/ — literate-file
-- coordinates for literate sources, exactly what 'HoleSpan' reports and what
-- @get_diagnostics@, @check_file@, and @fill_hole@ list back.
data HoleRef
  = ByIndex Int        -- ^ 0-based index into the source-order hole list.
  | ByPosition Int Int -- ^ 1-based line and column in the file as written.
  deriving (Eq, Show)

-- | The 0-based character offset of a 1-based @(line, column)@ position, or
-- @Nothing@ when the text has no such position.
--
-- A column one past a line's last character is accepted — that is where a
-- line's end sits, and it is a position Agda itself prints in ranges — but a
-- column beyond it is a miss rather than a silent clamp onto the next line.
offsetOfPosition :: Int -> Int -> Text -> Maybe Int
offsetOfPosition line col src
  | line < 1 || col < 1 = Nothing
  | otherwise           = go (line - 1) 0 src
  where
    go :: Int -> Int -> Text -> Maybe Int
    go 0 !off rest
      | col <= T.length (T.takeWhile (/= '\n') rest) + 1 = Just (off + col - 1)
      | otherwise                                        = Nothing
    go !n !off rest = case T.breakOn "\n" rest of
      (_, r) | T.null r -> Nothing          -- the text has fewer lines than that
      (l, r)            -> go (n - 1) (off + T.length l + 1) (T.drop 1 r)

-- | The index of the hole whose span covers an offset: @start <= off < end@, so
-- a position at the hole's first character counts and one past its last does
-- not.  Spans never overlap (the scanner resumes after each hole), so at most
-- one can match.
holeIndexAtOffset :: [HoleSpan] -> Int -> Maybe Int
holeIndexAtOffset holes off =
  listToMaybe [ i | (i, h) <- zip [0 ..] holes, hsStart h <= off, off < hsEnd h ]

-- | describeHole: one hole named the way an error message and a hole listing
-- both name it.
describeHole :: Int -> HoleSpan -> Text
describeHole i h = T.concat
  [ "index ", tshow i, " at line ", tshow (hsLine h), ", column ", tshow (hsCol h) ]

-- | Resolve a 'HoleRef' against a source file to a hole index, or explain the
-- miss loudly.
--
-- Loudly, because the alternative is the failure mode the whole issue is about:
-- an address that no longer means what the caller thinks it means, answered
-- with a plausible wrong hole.  A miss therefore reports what the file actually
-- contains — the nearest holes to a position that hit nothing, the census of
-- holes behind an out-of-range index — so the caller's next call can be right
-- rather than merely different.
--
-- The result is an /index/ because that is what the splicing functions take;
-- resolution is the only place the two spellings meet.
resolveHoleRef :: FilePath -> LiterateFlavour -> Text -> HoleRef -> Either Text Int
resolveHoleRef path flav src ref = case ref of
  ByIndex i
    | i >= 0, i < length holes -> Right i
    | otherwise -> Left $ T.concat
        [ "Hole index ", tshow i, " not found in ", T.pack path
        , " (holeIndex is a 0-based index into the source-order hole list, and"
        , " every index after a filled hole shifts down by one).\n"
        , census "the holes it does have" (take maxListed indexed)
        , addressingHint
        ]
  ByPosition ln col ->
    case offsetOfPosition ln col src >>= holeIndexAtOffset holes of
      Just i  -> Right i
      Nothing -> Left $ T.concat
        [ "No hole at line ", tshow ln, ", column ", tshow col
        , " in ", T.pack path
        , " (a position addresses the hole whose span contains it; starting at"
        , " it counts).\n"
        , census "nearest holes" (nearestTo ln col)
        , addressingHint
        ]
  where
    holes   = findHoles flav src
    indexed = zip [0 ..] holes

    -- Enough holes to orient a caller, few enough not to bury the message in a
    -- file with hundreds of them.
    maxListed  = 8
    maxNearest = 3

    -- Nearest by line, ties broken by column: robust even when the requested
    -- line does not exist in the file, where there is no offset to measure from.
    nearestTo ln col =
      take maxNearest (sortOn (\(_, h) -> (abs (hsLine h - ln), abs (hsCol h - col))) indexed)

    census lead shown
      | null holes = "  " <> T.pack path <> " has no holes.\n"
      | otherwise  = T.concat
          [ "  ", lead, " (", tshow (length holes), " in the file):\n"
          , T.concat [ "    " <> describeHole i h <> "\n" | (i, h) <- shown ]
          ]

    addressingHint =
      "  Address a hole by the (line, column) its own listing reports — \
      \get_diagnostics.holes, check_file.holes, or the holes list every \
      \fill_hole response carries.\n\
      \  Take that listing from the latest response: a fill above a hole moves \
      \it when the candidate is a different length, and renumbers it always."

-- | tshow: 'show' into 'Text', for the message builders above.
tshow :: Show a => a -> Text
tshow = T.pack . show


-- | Replace the n-th hole's actual span with a candidate term.
substituteHole :: LiterateFlavour -> Int -> Text -> Text -> Maybe Text
substituteHole flav n candidate src = do
  hole <- findNthHole flav n src
  pure (spliceSpan hole candidate src)

-- | Replace the n-th hole's actual span with the reporting expression
-- applied to @?@ (e.g. @reportGoalCtx ?@ — the saturated call shape the
-- AgdaDojang.Debug macros require, issue #70).
injectReportExpr :: Text -> LiterateFlavour -> Int -> Text -> Maybe Text
injectReportExpr rexpr flav n src = do
  hole <- findNthHole flav n src
  pure (spliceSpan hole (rexpr <> " ?") src)

-- | Splice a replacement over a hole's exact span.
spliceSpan :: HoleSpan -> Text -> Text -> Text
spliceSpan hole replacement src =
  let (before, rest) = T.splitAt (hsStart hole) src
      after          = T.drop (hsEnd hole - hsStart hole) rest
  in  before <> replacement <> after
