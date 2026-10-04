-- | Declaration.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Declaration.hs
--
-- Description:
--   What a definition says, read from its source (issue #185).
--
--   @definition_of@ answers where a name is defined: the file and the range of
--   the name at its binding site, which Agda's WhyInScope answer carries.  This
--   module supplies what is written there: the lines of the declaration that
--   the binding site opens (the signature and its clauses, a @where@ block
--   included), quoted verbatim from the file, bounded, with the line range
--   quoted and the line where the declaration ends, so a reader can check the
--   quotation against the tree and knows when it stopped short.
--
--   It does not elaborate.  The text is the source as written, not Agda's
--   internal term; the elaborated body is the long road of issue #164.
--
--   Design note: the extent is derived, and says so.
--     No interaction command answers a declaration's range (the binding site
--     is the name's range alone), so the extent is cut by Agda's layout rule
--     over the source, read in the 'AgdaMCP.Holes.codeWithHoles' view
--     (literate prose, comments, and pragmas blanked, holes kept, every
--     position preserved).  Let @i@ be the indentation of the binding site's
--     line.  A later line belongs to the declaration when it is indented
--     deeper than @i@ (a continuation, a clause body, a @where@ block, a
--     constructor or a field), when it lies inside a hole that began on an
--     earlier line, or when it sits at @i@ and is another clause of the same
--     definition: its left-hand side starts with a name the signature
--     declares, or with @...@, or carries a part of a declared mixfix name (so
--     @𝑨 IsSubalgebraOf 𝑩 = …@ is a clause of @_IsSubalgebraOf_@).  The first
--     other line at @i@ or shallower ends it, and blank lines are never its
--     last line.  A declaration headed by a keyword (@data@, @record@,
--     @module@, @postulate@, …) has no clauses at its own indentation, so for
--     one of those only deeper lines continue it.  A signature may declare
--     several names and break before its colon (agda-algebras writes
--     @_≥_@ on one line and @_IsSupalgebraOf_ : …@ indented under it), so a
--     binding site on such a continuation starts the quote at the line that
--     opens the signature, a line of names alone, indented less.  ADR 0002
--     § 4's rule is
--     that a derived answer is a fallback where Agda can answer; here Agda
--     cannot, and the quoted range is the evidence a reader checks.
--
--   Design note: the bound (issue #184's discipline).
--     A quote stops after 'defaultQuoteLines' lines unless the caller asks for
--     more (@maxLines@, 0 for the whole declaration).  Over the 92 distinct
--     sites the archived agent-bench arms asked @definition_of@ about, the
--     declarations ran to a median of 2 lines (135 characters), 15 lines at
--     the 90th percentile, 29 at the 95th, and one module to 686 lines; 40
--     lines quotes 87 of the 92 whole.

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Declaration
  ( DeclQuote (..)
  , defaultQuoteLines
  , declarationLines
  , quoteDeclaration
  ) where

import Data.Char (isSpace)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import AgdaMCP.Holes (HoleSpan (..), LiterateFlavour, codeWithHoles, findHoles)

-- | A quotation of one declaration.
--
-- The quoted lines are @[dqStartLine .. dqEndLine]@ of the file as written;
-- the declaration itself runs to 'dqDeclEndLine', so the quote stopped short
-- exactly when the two differ.
data DeclQuote = DeclQuote
  { dqStartLine   :: Int   -- ^ First quoted line (1-based): the one the
                           --   declaration opens on.
  , dqEndLine     :: Int   -- ^ Last quoted line.
  , dqText        :: Text  -- ^ Those lines, byte for byte: the file's text
                           --   from the start of the first to the end of the
                           --   last, its line endings (CRLF included) as
                           --   written, without the last line's newline.
  , dqDeclEndLine :: Int   -- ^ The declaration's last line, by the layout rule.
  } deriving (Eq, Show)

-- | The lines a quote carries unless the caller asks otherwise; see the
-- module header for the measurement behind the number.
defaultQuoteLines :: Int
defaultQuoteLines = 40

-- | quoteDeclaration: the declaration whose binding site is the name at
-- @(line, col)@ to @endCol@, quoted to at most @maxLines@ lines (0 or less:
-- the whole declaration); 'Nothing' when the file has no such line.
quoteDeclaration
  :: Int -> LiterateFlavour -> Text -> Int -> Int -> Int -> Maybe DeclQuote
quoteDeclaration maxLines flav src line col endCol = do
  (start, end) <- declarationLines flav src line col endCol
  -- Compared before it is added, so a huge maxLines (the wire accepts any
  -- Int, maxBound included) cannot overflow past the declaration's end.
  let quotedEnd
        | maxLines > 0, maxLines <= end - start = start + maxLines - 1
        | otherwise                              = end
  pure DeclQuote
    { dqStartLine   = start
    , dqEndLine     = quotedEnd
    , dqText        = T.intercalate "\n" (take (quotedEnd - start + 1) (drop (start - 1) raw))
    , dqDeclEndLine = end
    }
  where
    -- Split on LF alone and rejoin with it, so a CRLF file's carriage returns
    -- stay where they were and the quote is the file's own text for the range.
    raw = T.splitOn "\n" src

-- | declarationLines: the first and last lines of the declaration the binding
-- site at @(line, col)@ to @endCol@ opens, by the layout rule of the module
-- header; 'Nothing' when the file has no such line.
declarationLines :: LiterateFlavour -> Text -> Int -> Int -> Int -> Maybe (Int, Int)
declarationLines flav src line col endCol
  | line < 1 || line > length view = Nothing
  | otherwise = Just (start, go start (drop start numbered))
  where
    view     = T.splitOn "\n" (codeWithHoles flav src)
    numbered = zip [1 ..] view
    at k     = maybe "" id (lookup k numbered)

    -- The name at the binding site, as written there.
    name = case drop (line - 1) (T.splitOn "\n" src) of
      (l : _) | endCol > col -> T.take (endCol - col) (T.drop (col - 1) l)
              | otherwise    -> T.takeWhile (not . isTokenBreak) (T.drop (col - 1) l)
      []                     -> ""

    -- Where the declaration opens: the site's own line, unless the site
    -- continues a signature that names several things and broke before its
    -- colon; then the line of names above it that opens the signature.
    start = walkBack line
    walkBack l = case previousCode l of
      Just k | " : " `T.isInfixOf` at line
             , indentation (at k) < indentation (at l)
             , namesAlone (at k) -> walkBack k
      _ -> l
    previousCode l = case [ k | k <- [l - 1, l - 2 .. 1], not (T.all isSpace (at k)) ] of
      (k : _) -> Just k
      []      -> Nothing

    i0       = indentation (at start)
    keyword  = maybe False (`elem` keywords) (firstToken (at start))
    declared = declaredNames name
                 (at start : map snd (takeWhile (deeper i0 . snd) (drop start numbered)))

    go :: Int -> [(Int, Text)] -> Int
    go end [] = end
    go end ((k, l) : more)
      | k `Set.member` holeInterior = go k more
      | T.all isSpace l            = go end more
      | indentation l > i0         = go k more
      | indentation l < i0         = end
      | keyword                    = end
      | isSignature l              = end
      | isClauseOf declared l      = go k more
      | otherwise                  = end

    -- Lines inside a hole that began on an earlier line: Agda reads a hole as
    -- one token, so its interior has no layout.
    holeInterior = Set.fromList
      [ k
      | h <- findHoles flav src
      , let lastLine = hsLine h + T.count "\n" (T.take (hsEnd h - hsStart h) (T.drop (hsStart h) src))
      , k <- [hsLine h + 1 .. lastLine]
      ]

-- | namesAlone: a line of names and nothing else (no keyword, colon, or
-- @=@), the first line of a signature that breaks before its colon.
namesAlone :: Text -> Bool
namesAlone l = case tokens l of
  ts@(t : _) -> t `notElem` keywords && all (`notElem` [":", "=", "where", "→"]) ts
  []         -> False

-- | The words that open a declaration with no clauses of its own: everything
-- it holds is indented deeper.  @let@ is among them for the same reason: a
-- @let@ on a line of its own opens a block of local definitions, and is never
-- the first line of a signature that breaks before its colon, so a local's
-- quote must not walk back to it (Copilot, PR #229).
keywords :: [Text]
keywords =
  [ "data", "record", "module", "open", "import", "postulate", "field"
  , "constructor", "infix", "infixl", "infixr", "pattern", "syntax"
  , "instance", "private", "abstract", "mutual", "macro", "variable"
  , "interleaved", "opaque", "unfolding", "primitive", "unquoteDecl"
  , "unquoteDef", "eta-equality", "no-eta-equality", "inductive"
  , "coinductive", "let"
  ]

-- | The names a signature declares: the words before its first @ : @, read
-- across the binding line and its continuation lines (a signature may name
-- several, and may break before its colon).  When the text before the colon
-- holds an @=@ it is a clause, not a signature, and only the site's own name
-- is declared.
declaredNames :: Text -> [Text] -> [Text]
declaredNames name ls = name : case T.breakOn " : " (T.unwords (map T.strip (take 6 ls))) of
  (before, after)
    | not (T.null after), not ("=" `T.isInfixOf` before) -> tokens before
  _ -> []

-- | isSignature: a line of the form @names : type@ (no @=@ before the colon).
isSignature :: Text -> Bool
isSignature l = case T.breakOn " : " (T.strip l) of
  (before, after) -> not (T.null after) && not (T.null before) && not ("=" `T.isInfixOf` before)

-- | isClauseOf: a line at the declaration's own indentation that is another
-- clause of it.  Its left-hand side (the text before @=@, @with@, or @|@)
-- starts with a declared name or with @...@, or carries a part of a declared
-- mixfix name.
isClauseOf :: [Text] -> Text -> Bool
isClauseOf names l = case tokens lhs of
  (t : ts) -> t == "..." || t `elem` names || any (`elem` (t : ts)) parts
  []       -> False
  where
    lhs   = fst (T.breakOn " = " (fst (T.breakOn " with " (fst (T.breakOn " | " (T.strip l))))))
    parts = concat [ filter (not . T.null) (T.splitOn "_" n) | n <- names, "_" `T.isInfixOf` n ]

-- | The words of a line, broken where an Agda name breaks.
tokens :: Text -> [Text]
tokens = filter (not . T.null) . T.split isTokenBreak

firstToken :: Text -> Maybe Text
firstToken l = case tokens l of
  (t : _) -> Just t
  []      -> Nothing

isTokenBreak :: Char -> Bool
isTokenBreak c = isSpace c || c `elem` ("(){};" :: String)

indentation :: Text -> Int
indentation = T.length . T.takeWhile isSpace

deeper :: Int -> Text -> Bool
deeper i0 l = T.all isSpace l || indentation l > i0
