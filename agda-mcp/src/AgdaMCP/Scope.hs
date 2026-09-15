-- | Scope.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Scope.hs
--
-- Description:
--   The import surface of a loaded file, and the rendering ladder built on it
--   (issue #17, phase 1: @search_in_scope@).
--
--   This module answers two pure questions for the retrieval tool:
--
--   1.  Which modules does this file import, and how?  'parseImports' reads
--       every @import@ and @open import@ statement off the CODE-ONLY view of
--       the source ('AgdaMCP.Holes.codeOnly': comments, pragmas, literate
--       prose, and hole interiors blanked), with its modifiers: @public@,
--       @as N@, and a @using@, @hiding@, or @renaming@ list, on one line or
--       spanning several.
--   2.  Which imported module admits a corpus row, and how can the file spell
--       the row's name?  'importingModulesOf' applies the scope rule the P2
--       driver settled on issue #123 (a row is reachable iff its module equals
--       an imported module or extends one at a dot boundary; the longest such
--       prefix is the import that qualifies the rendering), and 'renderings'
--       builds the ladder: the bare name when the import opens it, the row's
--       @prettyQname@ verbatim (valid for rows nested inside the imported
--       module), and the importing module qualifying the bare name (valid for
--       re-exports whose defining module is not itself imported).
--
--   THE ASK-AGDA RULE, AND WHY THIS MODULE EXISTS ANYWAY.  The interaction
--   protocol has no command that enumerates a file's imports or the names in
--   its scope (the @scope_at@ finding on issue #75; ADR 0002 § 2), so the
--   import surface is a DERIVED answer: a pre-flight approximation read from
--   source text, exactly the kind of answer ADR 0002 § 4 says may inform and
--   never decide.  It is subordinated completely: every rendering this module
--   proposes is validated by the caller through lane @type_of@ before it is
--   returned, so a misparsed import costs a rendering (the row is reported as
--   lane-rejected, with the renderings tried) or a module (the row is counted
--   out of scope), and can never produce a name the file cannot write.  A
--   future Agda that exposes the scope should replace 'parseImports' with the
--   protocol's answer and leave the ladder alone.
--
--   What is deliberately not parsed, and why it is safe: @open M@ of an
--   already-imported module (the module is still admitted through its
--   @import@, qualified), module-level @using (module N)@ entries (treated as
--   names that match no row), and imports inside a @where@ block (they are
--   parsed like any other line; the lane refuses the rendering if the scope
--   does not reach the query point).  Each degrades to a qualified rendering
--   or an out-of-scope count, never to a wrong name.
--
-- See also:
--   AgdaMCP.Retrieval: the query, scorer, and pool pipeline.
--   AgdaMCP.Tools.SearchInScope: the handler that runs the ladder on the lane.
--   strux-driver/.../search/Retrieve.scala (ImportScope, resolve) and
--   Propose.scala (Imports): the P2 driver this ports from.

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Scope
  ( -- * The import surface
    parseImports
    -- * The scope rule
  , bareNameOf
  , importingModulesOf
    -- * The rendering ladder
  , bareRenderingOf
  , renderings
  ) where

import Data.Char (isSpace)
import Data.List (sortOn)
import Data.Maybe (mapMaybe)
import Data.Ord (Down (..))
import Data.Text (Text)
import qualified Data.Text as T

import AgdaMCP.Types (Rung (..), ScopeImport (..))


-- ---------------------------------------------------------------------------
-- The import surface
-- ---------------------------------------------------------------------------

-- | parseImports: every @import@ and @open import@ statement of a code-only
-- source view, in file order.
--
-- A statement starts on a line whose first token is @import@ or @open@
-- followed by @import@, and continues onto the following lines by Agda's own
-- layout rule: a line indented strictly more than the statement's first
-- token is part of it (so a @using@ list that opens on the next line, or
-- wraps over several, is read whole), a blank line is skipped, and the first
-- line at the statement's indentation or less ends it.  An open bracket list
-- also carries the statement on, whatever the indentation.  Anything the
-- statement carries that this parser does not recognize (a stray token, an
-- unbalanced list at end of file) leaves the import in place with the
-- modifiers that did parse: an import misread in its modifiers still admits
-- its module qualified, and the lane arbitrates the rest.
parseImports :: Text -> [ScopeImport]
parseImports src = go (T.lines src)
  where
    go [] = []
    go (l : rest) = case importHead l of
      Nothing -> go rest
      Just (opened, afterKeyword) ->
        let (stmt, rest') = gather (indentOf l) afterKeyword rest
        in  case parseStatement opened stmt of
              Just imp -> imp : go rest'
              Nothing  -> go rest'

    indentOf :: Text -> Int
    indentOf = T.length . T.takeWhile isSpace

    -- importHead: is this line the start of an import statement?  Answers
    -- whether it is opened and the text after the keyword(s).
    importHead :: Text -> Maybe (Bool, Text)
    importHead l =
      let ws = T.words l
      in  case ws of
            ("open" : "import" : _) -> Just (True,  dropWords 2 l)
            ("import" : _)          -> Just (False, dropWords 1 l)
            _                       -> Nothing

    -- dropWords: the line after its first n whitespace-separated words.
    dropWords :: Int -> Text -> Text
    dropWords 0 t = t
    dropWords n t =
      let t' = T.dropWhile isSpace t
      in  dropWords (n - 1) (T.dropWhile (not . isSpace) t')

    -- gather: pull following lines into the statement while they continue
    -- it: a blank line, a line indented past the statement's first token, or
    -- any line while a bracket list is still open.  The list delimiters of
    -- import modifiers are parentheses.
    gather :: Int -> Text -> [Text] -> (Text, [Text])
    gather headIndent acc rest = case rest of
      [] -> (acc, [])
      (l : ls)
        | T.all isSpace l         -> gather headIndent acc ls
        | indentOf l > headIndent -> gather headIndent (acc <> " " <> l) ls
        | depth acc > 0           -> gather headIndent (acc <> " " <> l) ls
        | otherwise               -> (acc, rest)

    depth :: Text -> Int
    depth = T.foldl' (\d c -> case c of
                                '(' -> d + 1
                                ')' -> d - 1
                                _   -> d) 0

-- | parseStatement: the module name and modifiers of one gathered statement.
parseStatement :: Bool -> Text -> Maybe ScopeImport
parseStatement opened stmt = case statementTokens stmt of
  []              -> Nothing
  (m : modifiers)
    | T.null m    -> Nothing
    | otherwise   -> Just (applyModifiers modifiers ScopeImport
        { siModule   = m
        , siOpened   = opened
        , siPublic   = False
        , siAs       = Nothing
        , siUsing    = Nothing
        , siHiding   = []
        , siRenaming = []
        })

-- | statementTokens: whitespace-separated tokens, except that a
-- parenthesized list is one token (its parentheses included).
statementTokens :: Text -> [Text]
statementTokens = go . T.strip
  where
    go t
      | T.null t = []
      | T.head t == '(' =
          let (grp, rest) = takeGroup t
          in  grp : go (T.stripStart rest)
      | otherwise =
          let (w, rest) = T.break (\c -> isSpace c || c == '(') t
          in  w : go (T.stripStart rest)

    -- takeGroup: the balanced parenthesized prefix of a text starting with
    -- '(' and what follows it.  An unbalanced group runs to the end.
    takeGroup :: Text -> (Text, Text)
    takeGroup t = walk 0 0 t
      where
        walk :: Int -> Int -> Text -> (Text, Text)
        walk !n !d rest = case T.uncons rest of
          Nothing -> (t, T.empty)
          Just (c, rest')
            | c == '('  -> walk (n + 1) (d + 1) rest'
            | c == ')'  -> if d == 1 then T.splitAt (n + 1) t
                                     else walk (n + 1) (d - 1) rest'
            | otherwise -> walk (n + 1) d rest'

-- | applyModifiers: fold the modifier tokens into the import.  Modifier
-- order is free in Agda, so each keyword is looked for wherever it stands.
applyModifiers :: [Text] -> ScopeImport -> ScopeImport
applyModifiers toks imp = case toks of
  [] -> imp
  ("public" : rest) -> applyModifiers rest imp { siPublic = True }
  ("as" : alias : rest) -> applyModifiers rest imp { siAs = Just alias }
  ("using" : grp : rest) | isGroup grp ->
    applyModifiers rest imp { siUsing = Just (maybe [] id (siUsing imp) <> listNames grp) }
  ("hiding" : grp : rest) | isGroup grp ->
    applyModifiers rest imp { siHiding = siHiding imp <> listNames grp }
  ("renaming" : grp : rest) | isGroup grp ->
    applyModifiers rest imp { siRenaming = siRenaming imp <> renamingPairs grp }
  (_ : rest) -> applyModifiers rest imp
  where
    isGroup g = "(" `T.isPrefixOf` g

-- | listNames: the entries of a @using@ / @hiding@ list, split on @;@.
-- A @module N@ entry is kept as the two-word text it is, so it matches no
-- row's bare name.
listNames :: Text -> [Text]
listNames grp =
  filter (not . T.null) . map T.strip . T.splitOn ";" $ inner grp

-- | renamingPairs: the @old to new@ entries of a @renaming@ list.
renamingPairs :: Text -> [(Text, Text)]
renamingPairs grp = mapMaybe pair (listNames grp)
  where
    pair entry = case T.words entry of
      [old, "to", new] -> Just (old, new)
      _                -> Nothing

-- | inner: the text between a group's outer parentheses.
inner :: Text -> Text
inner grp =
  let t = T.strip grp
  in  T.dropWhileEnd (== ')') (T.drop 1 t)


-- ---------------------------------------------------------------------------
-- The scope rule
-- ---------------------------------------------------------------------------

-- | bareNameOf: the unqualified name of a corpus row, its last dot segment.
-- Agda identifiers cannot contain a dot, so this is exact rather than
-- heuristic (the driver's @SearchHit.bareName@).
bareNameOf :: Text -> Text
bareNameOf qname = snd (T.breakOnEnd "." qname)

-- | importingModulesOf: the imports that admit a row whose module is the
-- given name: those whose module equals it or is a proper prefix of it at a
-- dot boundary.  The longest module wins (the most specific import qualifies
-- the rendering); several imports of that one module are all returned, since
-- each may contribute a rung (one opens the name, another aliases the
-- module).  Empty means the row is out of scope.
importingModulesOf :: [ScopeImport] -> Text -> [ScopeImport]
importingModulesOf imports rowModule =
  case sortOn (Down . T.length . siModule) (filter admits imports) of
    []          -> []
    best@(b : _) -> takeWhile ((== siModule b) . siModule) best
  where
    admits imp =
      rowModule == siModule imp || (siModule imp <> ".") `T.isPrefixOf` rowModule


-- ---------------------------------------------------------------------------
-- The rendering ladder
-- ---------------------------------------------------------------------------

-- | bareRenderingOf: the unqualified spelling an import gives a name, if any.
--
-- An @open import@ with no @using@ list opens everything the module exports;
-- with one, only the listed names; a @hiding@ list withholds its names; a
-- @renaming@ entry opens the name under its new spelling.  A plain @import@
-- opens nothing.
bareRenderingOf :: ScopeImport -> Text -> Maybe Text
bareRenderingOf imp name
  | not (siOpened imp)                    = Nothing
  | Just new <- lookup name (siRenaming imp) = Just new
  | name `elem` siHiding imp              = Nothing
  | otherwise = case siUsing imp of
      Nothing    -> Just name
      Just names -> if name `elem` names then Just name else Nothing

-- | renderings: the ladder for one corpus row under the imports that admit
-- it, in the order to try them: bare first (so an accepted row dedups
-- against what the file already writes), then the qualified spellings from
-- the most specific to the least.  A row's module extends the importing
-- module by a tail of segments (@Basic.IsHom@ for the row
-- @Setoid.Homomorphisms.Basic.IsHom.compatible@ under an import of
-- @Setoid.Homomorphisms@), and which spelling the file can write depends on
-- how the imported module reached the row: its own qualified name when the
-- module is nested inside the imported one (the whole tail, rung
-- @qualified@), the importing module plus a suffix of the tail when a file
-- in between re-exports a nested record module (rung @re-export@), and the
-- importing module alone when the row itself is re-exported (the empty tail,
-- rung @importing-module@).  So the ladder tries every drop of the tail's
-- leading segments, in order, and the lane arbitrates.  An @as N@ alias
-- replaces the imported module's name in every qualified rung, since under
-- an alias the original module name is not in scope.  Duplicates keep their
-- first occurrence.
renderings :: [ScopeImport] -> Text -> [(Rung, Text)]
renderings imports qname = dedup (bare <> qualified)
  where
    name = bareNameOf qname
    -- The row's module: everything before the bare name.
    rowModule = T.dropWhileEnd (== '.') (fst (T.breakOnEnd "." qname))

    bare = [ (RungBare, r) | imp <- imports, Just r <- [bareRenderingOf imp name] ]

    -- For each admitting import, the tail of the row's module below it, and
    -- one rung per drop of its leading segments.
    qualified =
      [ (rungAt k len, T.intercalate "." (prefixOf imp : drop k tailSegs <> [name]))
      | imp <- imports
      , let tailSegs = tailBelow (siModule imp) rowModule
            len      = length tailSegs
      , k <- [0 .. len]
      ]

    rungAt k len
      | k == 0    = RungQualified
      | k == len  = RungImporting
      | otherwise = RungReexport k

    -- The segments of the row's module below the importing module (empty
    -- when they are the same module).
    tailBelow imported rowMod = case T.stripPrefix imported rowMod of
      Just rest | T.null rest -> []
                | otherwise   -> T.splitOn "." (T.drop 1 rest)
      Nothing -> T.splitOn "." rowMod

    prefixOf imp = maybe (siModule imp) id (siAs imp)

    dedup = go []
      where
        go _ [] = []
        go seen ((rung, r) : rest)
          | r `elem` seen = go seen rest
          | otherwise     = (rung, r) : go (r : seen) rest
