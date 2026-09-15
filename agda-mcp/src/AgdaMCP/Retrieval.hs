-- | Retrieval.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Retrieval.hs
--
-- Description:
--   The pure half of @search_in_scope@ (issue #17, phase 1): what the tool
--   does to the corpus BEFORE the interaction lane is asked anything.  This is
--   a port of the P2 driver's pool pipeline (strux-driver's
--   @RetrievalPool.build@, @TokenOverlapScorer@, @Statements@, @Queries@, and
--   @TargetExclusion@ in @search/Retrieve.scala@, PR #130), kept as one pure
--   function of the index, the file's import surface, the query, and the
--   caller's exclusions, so it is testable without a server and so the
--   honesty ledger's counts are a property of the pipeline rather than of the
--   handler's bookkeeping.
--
--   The pipeline, in order, each step a counted cut:
--
--   1.  Query match over the WHOLE corpus ('matchesQuery'): a case-insensitive
--       name substring, and/or type tokens meeting the row's bare type tokens
--       or its name.  The count is @hits@, taken before scope on purpose: a
--       row that exists and is not imported is the honest negative the
--       consumer brief asks for, and it reads as @hits > inScope@.
--   2.  Scope ('AgdaMCP.Scope.importingModulesOf'): in-scope rows keep the
--       import that admits them; the rest are @outOfScope@.
--   3.  Exclusion (the caller's policy, never the server's): a row whose bare
--       name is listed, or whose corpus type normalizes to the listed
--       statement, is set aside WITH its reason.  The lane-form statement
--       check runs later, in the handler, on Agda's printing.
--   4.  Kind: rows whose @defKind@ is not @function@ are counted
--       (@nonFunction@) and dropped, the driver's rule; constructors and
--       records are a stated follow-up.
--   5.  Rank ('rank'): the driver's token-overlap score, then cheap before
--       expensive on approximate visible arity, then the qualified name, so
--       the order is total and deterministic.  The scorer is one function
--       ('score') so the seam issue #19 grows on the driver side can be
--       followed here without touching the tool.
--
--   Tokenization and statement normalization are the driver's, ported
--   literally: a token is a single delimiter or a maximal run of characters
--   that are neither whitespace nor delimiters; a bare token is a token's last
--   dot segment with outer underscores stripped (@Agda.Builtin.Nat._+_@ meets
--   the goal display's @+@); a statement normalizes by dropping @∀@ and
--   renaming binder names positionally, which is syntactic on purpose (a
--   differently STATED but convertible lemma is a legitimate proof step, and
--   stays in the pool).
--
-- See also:
--   AgdaMCP.Scope: the import surface and the rendering ladder.
--   AgdaMCP.Tools.SearchInScope: the handler: lane resolution and the response.
--   AgdaMCP.Types: 'CorpusEntry', 'SearchQuery', 'SearchExclude'.

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Retrieval
  ( -- * Tokens
    tokens
  , bareToken
  , structuralTokens
  , bareTypeTokens
    -- * Statements
  , normalizeStatement
  , splitTopLevelArrows
  , approxVisibleArity
    -- * Queries
  , queryTokensOf
  , matchesQuery
  , queryTokenSet
    -- * The token index
  , tokenIndex
  , candidatesOf
    -- * The scorer and the rank
  , score
  , rank
    -- * Exclusion
  , exclusionReason
    -- * The pool pipeline
  , Pool (..)
  , Ranked (..)
  , buildPool
  ) where

import Data.Char (isDigit, isLetter, isSpace)
import Data.List (sortOn, tails)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import AgdaMCP.Scope (bareNameOf, importingModulesOf)
import AgdaMCP.Types
  ( CorpusEntry (..), CorpusIndex (..), ScopeExclusion (..), ScopeImport (..)
  , SearchExclude (..), SearchQuery (..)
  )


-- ---------------------------------------------------------------------------
-- Tokens
-- ---------------------------------------------------------------------------

-- | The bracket characters the tokenizer treats as single tokens.
delimiters :: Set Char
delimiters = Set.fromList "(){}⦃⦄"

-- | tokens: delimiters are single tokens, everything else splits on
-- whitespace.  Total and linear in the text.
tokens :: Text -> [Text]
tokens = go
  where
    go t = case T.uncons t of
      Nothing -> []
      Just (c, rest)
        | isSpace c              -> go rest
        | c `Set.member` delimiters -> T.singleton c : go rest
        | otherwise ->
            let (run, rest') = T.break (\x -> isSpace x || x `Set.member` delimiters) t
            in  run : go rest'

-- | structuralTokens: the tokens that carry structure rather than meaning;
-- the misfit penalty and the query filter skip them.
structuralTokens :: Set Text
structuralTokens =
  Set.fromList (map T.singleton (Set.toList delimiters) <> ["→", ":", "∀", ".", ";"])

-- | bareToken: a printed token reduced to comparable form: its last dot
-- segment (corpus types are fully qualified), outer underscores stripped
-- (the corpus writes @_+_@ where a goal display shows infix @+@).
bareToken :: Text -> Text
bareToken t =
  let seg = snd (T.breakOnEnd "." t)
      seg' = maybe seg id (T.stripPrefix "_" seg)
  in  maybe seg' id (T.stripSuffix "_" seg')

-- | bareTypeTokens: the set of bare tokens of a corpus type string.
bareTypeTokens :: Text -> Set Text
bareTypeTokens = Set.fromList . map bareToken . tokens


-- ---------------------------------------------------------------------------
-- Statements
-- ---------------------------------------------------------------------------

-- | normalizeStatement: whitespace collapsed, @∀@ dropped, binder names
-- renamed positionally, so @(m n : ℕ) → m + n ≡ n + m@ and
-- @(x y : ℕ) → x + y ≡ y + x@ normalize identically.  Deliberately not a
-- convertibility check (see the module header).
normalizeStatement :: Text -> Text
normalizeStatement stmt =
  let ts      = filter (/= "∀") (tokens stmt)
      names   = dedup (binderNames ts)
      renames = Map.fromList [ (n, "x" <> T.pack (show i)) | (n, i) <- zip names [1 :: Int ..] ]
  in  T.unwords (map (\t -> Map.findWithDefault t t renames) ts)
  where
    dedup = go Set.empty
      where
        go _ [] = []
        go seen (x : xs)
          | x `Set.member` seen = go seen xs
          | otherwise           = x : go (Set.insert x seen) xs

-- | binderNames: inside each delimiter group, the tokens before a @:@ at that
-- group's own level.  A group without a @:@ binds nothing, and so does one
-- whose first tokens open a nested group.
binderNames :: [Text] -> [Text]
binderNames ts = concat
  [ if take 1 after == [":"] then names else []
  | (open : rest) <- tails ts
  , open `Set.member` openers
  , let (names, after) = span (\t -> t /= ":" && not (isDelim t)) rest
  ]
  where
    openers = Set.fromList ["(", "{", "⦃"]
    isDelim t = T.length t == 1 && T.head t `Set.member` delimiters

-- | splitTopLevelArrows: a printed type split on its depth-0 arrows,
-- standalone ones only (whitespace or the text's boundary on both sides), so
-- an arrow inside an identifier (@IsInRange→IsInImage@) never splits the
-- type.  Depth counts the delimiters and square brackets (a bracket mixfix
-- such as @𝔻[ A → B ]@ encloses its arrow).  Whitespace is normalized first
-- and segments are trimmed.
splitTopLevelArrows :: Text -> [Text]
splitTopLevelArrows printed =
  let s      = T.unwords (T.words printed)
      chars  = T.unpack s
      n      = length chars
      -- The depth BEFORE each character, and each character's neighbours,
      -- so the scan is one linear pass rather than an index per position.
      depths = scanl step (0 :: Int) chars
      step d c
        | c `elem` ("({⦃[" :: String) = d + 1
        | c `elem` (")}⦄]" :: String) = max 0 (d - 1)
        | otherwise                    = d
      prevs  = ' ' : chars
      nexts  = drop 1 chars <> [' ']
      cuts   = [ i | (i, c, d, pc, nc) <- zip5 [0 ..] chars depths prevs nexts
                   , c == '→', d == 0, isSpace pc, isSpace nc ]
      bounds = (-1 : cuts) <> [n]
  in  [ T.strip (T.pack (take (to - from - 1) (drop (from + 1) chars)))
      | (from, to) <- zip bounds (drop 1 bounds) ]
  where
    zip5 (a : as) (b : bs) (c : cs) (d : ds) (e : es) = (a, b, c, d, e) : zip5 as bs cs ds es
    zip5 _ _ _ _ _ = []

-- | approxVisibleArity: the visible binders a corpus type string shows at
-- its top level, for the cheap-before-expensive tie-break only.  Each
-- domain segment counts its parenthesized binder groups (@(m n : ℕ)@ is two
-- visible binders, @{A : Set}@ none) or one for a bare, non-dependent
-- domain.  An alias-form type with no arrows counts zero, correctly
-- cheap-looking: its real binders surface only through the lane, which is
-- the authority on a row's type as ever.
approxVisibleArity :: Text -> Int
approxVisibleArity printed = case splitTopLevelArrows printed of
  segs@(_ : _ : _) -> sum (map domainBinders (init segs))
  _                -> 0
  where
    domainBinders seg =
      let ps = case pieces seg of
                 (Left "∀" : rest) -> rest
                 other             -> other
          groups = [ g | Right g <- ps ]
          onlyGroups = not (null ps) && length groups == length ps
          parensBind = all (\(o, c) -> o /= '(' || T.isInfixOf ":" c) groups
      in  if onlyGroups && parensBind
            then sum [ groupArity c | (o, c) <- groups, o == '(' ]
            else 1
    -- A group's binder count: the names before its ':', else one.
    groupArity content = case T.breakOn ":" content of
      (names, rest) | not (T.null rest) -> max 1 (length (T.words names))
      _                                  -> 1

-- | pieces: the depth-0 pieces of one segment, bracket groups (with their
-- opener and content) to the right and the bare text between them to the
-- left, in order.
pieces :: Text -> [Either Text (Char, Text)]
pieces seg = go 0 (0 :: Int) ' ' [] (T.unpack seg)
  where
    -- go: characters consumed so far into the current piece (as a reversed
    -- buffer), depth, current opener, pieces so far (reversed), rest.
    go :: Int -> Int -> Char -> [Either Text (Char, Text)] -> String -> [Either Text (Char, Text)]
    go _ _ _ acc [] = reverse acc
    go _ d open acc s@(c : rest)
      | c `elem` ("({⦃" :: String) && d == 0 =
          let (content, after) = takeBalanced 1 [] rest
          in  go 0 0 open (Right (c, T.pack content) : acc) after
      | otherwise =
          let (bareTxt, after) = break (`elem` ("({⦃" :: String)) s
              acc' = if T.null (T.strip (T.pack bareTxt)) then acc
                     else Left (T.strip (T.pack bareTxt)) : acc
          in  if null after then reverse acc' else go 0 d open acc' after

    takeBalanced :: Int -> String -> String -> (String, String)
    takeBalanced _ buf [] = (reverse buf, [])
    takeBalanced d buf (c : rest)
      | c `elem` ("({⦃" :: String) = takeBalanced (d + 1) (c : buf) rest
      | c `elem` (")}⦄" :: String) =
          if d == 1 then (reverse buf, rest) else takeBalanced (d - 1) (c : buf) rest
      | otherwise = takeBalanced d (c : buf) rest


-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

-- | queryTokensOf: the retrieval-bearing tokens of one displayed type,
-- given the goal context's names to drop.  Local variables, metas,
-- numerals, single latin letters, and structural tokens carry no retrieval
-- signal; operators and long identifiers remain, reduced to bare tokens.
-- This is how a goal-derived query is spelled when the caller gives none.
--
-- The bare reduction is load-bearing on the goal side too: a normalized
-- goal display in a file that imports with @using@ lists prints its names
-- QUALIFIED (@Data.Product.Σ@, @Setoid.Homomorphisms.IsHom@; measured on the
-- agda-algebras obligations while sizing the pool half), and the driver's
-- placeholder, which reduced only the corpus side, matched nothing on such a
-- goal (its @BareOverlapScorer@ is the fix; PR #152).  Both sides are bare
-- here.
queryTokensOf :: Text -> [Text] -> [Text]
queryTokensOf displayed ctxNames =
  dedup . filter (not . T.null) . map bareToken . filter keep $ tokens displayed
  where
    ctx = Set.fromList ctxNames
    keep t = not (singleLatin t) && not (T.all isDigit t) && not (t `Set.member` ctx)
             && not (metaLike t) && not (t `Set.member` structuralTokens)
    singleLatin t = T.length t == 1 && isLetter (T.head t) && T.head t <= 'z'
    -- _n_12, _x_7, _12: a meta as Agda prints it.
    metaLike t = case T.stripPrefix "_" t of
      Just rest ->
        let digits = T.takeWhileEnd isDigit rest
            body   = T.dropWhileEnd isDigit rest
        in  not (T.null digits) && (T.null body || "_" `T.isSuffixOf` body)
      Nothing -> False
    dedup = go Set.empty
      where
        go _ [] = []
        go seen (x : xs)
          | x `Set.member` seen = go seen xs
          | otherwise           = x : go (Set.insert x seen) xs

-- | matchesQuery: does a row answer the query?  A name pattern is a
-- case-insensitive substring of the row's @prettyQname@ or @prettyName@; type
-- tokens match when at least one meets the row's bare type tokens or is a
-- fragment of its bare name.  When both are given, both must hold.
--
-- This is the specification; 'buildPool' answers the same question through
-- the token index ('candidatesOf'), and the suite pins the two to agree.
matchesQuery :: SearchQuery -> CorpusEntry -> Bool
matchesQuery q e = matchesName q e && tokensOk
  where
    -- A bare token is a substring of the token it came from, which is a
    -- substring of the type, so the substring test is a necessary condition
    -- for the overlap and a cheap gate before tokenizing: over the
    -- agda-algebras corpus it spares the tokenizer some 11,000 of 11,865
    -- rows per query (measured while sizing the pool half; PR for #17).
    tokensOk = case queryTokenSet q of
      tset | Set.null tset -> True
      tset -> let bare = bareNameOf (cePrettyQname e)
                  typ  = ceType e
                  ts   = Set.toList tset
              in  any (`T.isInfixOf` bare) ts
                    || (any (`T.isInfixOf` typ) ts
                        && not (Set.null (Set.intersection tset (bareTypeTokens typ))))

-- | matchesName: the name half of 'matchesQuery'.
matchesName :: SearchQuery -> CorpusEntry -> Bool
matchesName q e = case sqName q of
  Nothing  -> True
  Just pat ->
    let p = T.toLower pat
    in  p `T.isInfixOf` T.toLower (cePrettyQname e)
          || p `T.isInfixOf` T.toLower (cePrettyName e)

-- | queryTokenSet: the query's tokens as the matcher and the scorer compare
-- them, bare-reduced (a caller may spell a token qualified, as a goal display
-- does) and never empty strings.
queryTokenSet :: SearchQuery -> Set Text
queryTokenSet q = Set.fromList (filter (not . T.null) (map bareToken (sqTokens q)))


-- ---------------------------------------------------------------------------
-- The token index
-- ---------------------------------------------------------------------------

-- | tokenIndex: every bare type token, to the @prettyQname@s whose type
-- carries it.  Built once at corpus load ('AgdaMCP.Corpus.corpusIndexOf'),
-- so a token query is a union of posting lists.  Measured on the
-- agda-algebras v0.1 corpus (11,865 rows): tokenizing every row per query put
-- a four-token pool at about 150 ms; through the index it is a few
-- milliseconds, and the tokenization is paid once, at load.
tokenIndex :: Map.Map Text CorpusEntry -> Map.Map Text (Set Text)
tokenIndex entries =
  Map.fromListWith Set.union
    [ (tok, Set.singleton qn)
    | (qn, e) <- Map.toList entries
    , tok <- Set.toList (bareTypeTokens (ceType e))
    , not (T.null tok)
    ]

-- | candidatesOf: the rows a token query can match, from the index: the
-- union of the tokens' posting lists, plus the rows whose bare name carries
-- a token as a fragment (the name bonus's own rule, which no type index
-- sees).  Exactly the rows 'matchesQuery' accepts on the token half.
candidatesOf :: CorpusIndex -> Set Text -> Set Text
candidatesOf idx toks =
  Set.unions
    ( [ Map.findWithDefault Set.empty t (ciTokens idx) | t <- Set.toList toks ]
      <> [ Set.fromList
             [ qn | qn <- Map.keys (ciEntries idx)
                  , let bare = bareNameOf qn
                  , any (`T.isInfixOf` bare) (Set.toList toks) ] ] )


-- ---------------------------------------------------------------------------
-- The scorer and the rank
-- ---------------------------------------------------------------------------

-- | score: the P2 placeholder.  Twice the overlap between the query tokens
-- and the row's bare type tokens, plus a name bonus capped at one (stdlib
-- names spell whole statements in operator glyphs, and an uncapped count
-- hands the top ranks to symbol soup), minus one per pure-symbol operator
-- the query never mentions (evidence of a different statement family).
-- Identifiers and numerals are never penalized.  A query with no tokens (a
-- name-only query) scores every row zero, so the rank falls through to
-- arity and name as the contract says; without this, the misfit penalty
-- would order such a query by operator content (Copilot's review of PR #161).
score :: Set Text -> Text -> Text -> Int
score queryTokens bare typ
  | Set.null queryTokens = 0
  | otherwise =
  let typeTokens = bareTypeTokens typ
      overlap    = Set.size (Set.intersection queryTokens typeTokens)
      nameHit    = if any (`T.isInfixOf` bare) (Set.toList queryTokens) then 1 else 0
      misfits    = Set.size (Set.filter misfit typeTokens)
      misfit t   = not (t `Set.member` queryTokens) && not (t `Set.member` structuralTokens)
                   && not (T.null t) && not (T.any (\c -> isLetter c || isDigit c) t)
  in  2 * overlap + nameHit - misfits

-- | Ranked: one row of the ranked pool: its score, the row, and the imports
-- that admit it (the rendering ladder is built from these).
data Ranked = Ranked
  { rkScore   :: Int
  , rkEntry   :: CorpusEntry
  , rkImports :: [ScopeImport]
  } deriving (Eq, Show)

-- | rank: score first, then cheap before expensive on approximate arity,
-- then the qualified name, so ranking is total and deterministic.  Each key
-- is computed once.
rank :: Set Text -> [(CorpusEntry, [ScopeImport])] -> [Ranked]
rank queryTokens rows =
  map snd . sortOn fst $
    [ ((negate s, approxVisibleArity (ceType e), cePrettyQname e), Ranked s e imps)
    | (e, imps) <- rows
    , let s = score queryTokens (bareNameOf (cePrettyQname e)) (ceType e)
    ]


-- ---------------------------------------------------------------------------
-- Exclusion
-- ---------------------------------------------------------------------------

-- | exclusionReason: why the caller's policy sets a row aside, if it does:
-- @name@ when the row's bare name is listed, @statement@ when its corpus
-- type normalizes to the listed statement.  The lane-form statement rule is
-- the handler's, on Agda's printing.
exclusionReason :: SearchExclude -> CorpusEntry -> Maybe Text
exclusionReason x e
  | bareNameOf (cePrettyQname e) `elem` sxNames x = Just "name"
  | Just stmt <- sxStatement x
  , normalizeStatement (ceType e) == normalizeStatement stmt = Just "statement"
  | otherwise = Nothing


-- ---------------------------------------------------------------------------
-- The pool pipeline
-- ---------------------------------------------------------------------------

-- | Pool: what the pipeline did for one query before the lane was asked
-- anything, with every cut counted.  The handler adds the lane half.
data Pool = Pool
  { poolHits        :: Int              -- ^ Rows matching the query, corpus-wide.
  , poolInScope     :: Int              -- ^ Hits whose module the file imports.
  , poolOutOfScope  :: Int              -- ^ The other hits.
  , poolExcluded    :: [ScopeExclusion] -- ^ In-scope hits the caller's policy set aside, with reasons.
  , poolNonFunction :: Int              -- ^ Kept rows dropped because @defKind@ is not @function@.
  , poolRanked      :: [Ranked]         -- ^ The survivors, in rank order.
  } deriving (Eq, Show)

-- | buildPool: query, scope, exclusion, kind, rank.  The token half of the
-- query goes through the index; the name half is a scan, over the whole
-- corpus for a name-only query and over the token candidates otherwise.
buildPool :: SearchQuery -> Maybe SearchExclude -> [ScopeImport] -> CorpusIndex -> Pool
buildPool q mExclude imports idx =
  let entries = ciEntries idx
      toks    = queryTokenSet q
      hits
        | Set.null toks = filter (matchesName q) (Map.elems entries)
        | otherwise     =
            [ e | qn <- Set.toAscList (candidatesOf idx toks)
                , Just e <- [Map.lookup qn entries]
                , matchesName q e ]
      scoped  = [ (e, imps) | e <- hits, let imps = importingModulesOf imports (cePrettyModule e) ]
      inScope = [ (e, imps) | (e, imps) <- scoped, not (null imps) ]
      (excluded, kept) = case mExclude of
        Nothing -> ([], inScope)
        Just x  -> partitionWith (\(e, imps) -> case exclusionReason x e of
                                     Just why -> Left (ScopeExclusion (cePrettyQname e) why)
                                     Nothing  -> Right (e, imps)) inScope
      functions = [ r | r@(e, _) <- kept, ceDefKind e == "function" ]
  in  Pool
        { poolHits        = length hits
        , poolInScope     = length inScope
        , poolOutOfScope  = length hits - length inScope
        , poolExcluded    = excluded
        , poolNonFunction = length kept - length functions
        , poolRanked      = rank (queryTokenSet q) functions
        }
  where
    partitionWith f xs = (mapMaybe (either Just (const Nothing) . f) xs,
                          mapMaybe (either (const Nothing) Just . f) xs)
