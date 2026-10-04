-- | Written.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Written.hs
--
-- Description:
--   A corpus type as a statement writes it (issue #202): the form
--   @search_by_type@ matches a query against unless the caller asks for the
--   corpus's own printing (@qualified: true@).
--
--   agda-strux prints every type from outside every module, so a statement
--   that reads @x ⁻¹ ∙ y ⁻¹ ≈ (x ∙ y) ⁻¹@ in its source, inside @open Group
--   G@, is printed
--
--   > (G Algebra.Bundles.AbelianGroup.≈
--   >  (G Algebra.Bundles.AbelianGroup.∙ (G Algebra.Bundles.AbelianGroup.⁻¹) x)
--   >  ((G Algebra.Bundles.AbelianGroup.⁻¹) y))
--   > ((G Algebra.Bundles.AbelianGroup.⁻¹)
--   >  ((G Algebra.Bundles.AbelianGroup.∙ x) y))
--
--   Two things separate the printing from the statement.  Every name is
--   qualified; and every definition of a parameterized module, and every
--   record field, takes the module's parameter (the bundle @G@) as its first
--   explicit argument, which Agda's printer puts into an operator's FIRST
--   hole and moves the operator's own last argument outside the parentheses
--   (@(G ≈ a) b@ for @a ≈ b@; @(G ⁻¹) x@ for @x ⁻¹@; @[ 𝒢 ⸴ x ] y@ for
--   @[ x ⸴ y ]@).  Dropping qualifiers alone therefore matches almost nothing
--   that a statement contains; the parameters have to go too.
--
--   The rendering, in order:
--
--   1.  Parse the printed type into tokens and bracket groups (the tokenizer
--       is 'AgdaMCP.Retrieval.tokens', shared with @search_in_scope@).
--   2.  Drop each definition's module parameters where it is applied
--       ('unsection'): after a prefix name, drop that many argument items;
--       for a mixfix operator, drop that many operands and move the
--       remaining ones, with the arguments that follow the section, into its
--       holes.  How many parameters a name takes is read off the corpus
--       itself ('parameterCounts'); no Agda is run.
--   3.  Drop qualifiers ('unqualify'), after giving Agda's builtins the
--       names the standard library re-exports them under ('builtinNames'):
--       the printer keeps the builtin's own name, so the corpus prints
--       @Agda.Builtin.Nat.-@ where every statement writes @∸@, and
--       @Agda.Builtin.Nat.Nat@ where it writes @ℕ@.
--
--   The display form ('writtenDisplay') keeps brackets; the matching key
--   ('writtenKey') drops them, collapses whitespace, and folds case, and a
--   query fragment gets the same key ('fragmentKey') without step 2, since
--   a statement is already written that way.  The index keeps the keys
--   alone; a search renders the display form for its hits.
--
--   How the parameter count is read.  A parameterized module's parameters
--   are the leading binders that every definition in it shares, printed the
--   same way in each; so, per module (the corpus row's @module@ field, which
--   keeps anonymous modules apart), the evidence is the module's own
--   @function@ rows.  Constructors are left out (they see the parameters as
--   hidden), and so are record and data types (they add their own
--   parameters), cubical @hcomp-@ and @transp-@ rows, and @constructor@ rows.
--   A record module takes the prefix at least half its rows share, since its
--   @Carrier@ field takes the record unnamed; any other module needs the
--   prefix every function row starts with; a module with one function row
--   gives no such evidence, so its row takes no parameter unless the module
--   is nested in a record's module and the row's first explicit argument is
--   a value of that record (@DecStrictPartialOrder.Eq.decSetoid@), and any
--   other one-row module's arguments stay in the written form.  A row's
--   count is its explicit binders inside that prefix, stopping at the first
--   one named like an operator: a module parameterized by an operation
--   (@Algebra.Definitions@'s @_≈_@) is used unapplied, and statements pass
--   the operation explicitly (@Commutative _≈_ _∙_@), whereas a module
--   parameterized by a bundle is
--   opened applied (@open Group-Op 𝒢@).  A two-row module could share a
--   prefix by coincidence, so there an operator's count is capped at its
--   explicit arity less its holes.  A record field the corpus has no row for
--   (the standard library's @Setoid._≈_@, printed in every agda-algebras
--   statement) is recognized by its qualifier, a name some binder in the
--   corpus is typed by, and takes one parameter: the record.
--
--   What it does not do, stated in the tool's contract: no @syntax@
--   declaration is applied (the corpus does not carry them, so
--   @conj-syntax g x@ stays that, not @x ^ g@); variable names are the
--   library's; and parentheses are ignored in matching, so a fragment can
--   match across a grouping it did not intend.  Every step is total: a shape
--   the rules do not recognize is left as printed, and the row is still
--   matched on its qualifier-free form.
--
-- See also:
--   AgdaMCP.Corpus: the index ('corpusIndexOf') and the search.
--   AgdaMCP.Retrieval: the tokenizer.
--   agda-mcp/README.md: the contract of search_by_type.

{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Written
  ( -- * Items
    Item (..)
  , parseItems
    -- * Operators and parameters
  , Part (..)
  , opParts
  , NameInfo (..)
  , WrittenTable (..)
  , writtenTable
  , parameterCounts
    -- * Rendering
  , unsection
  , unqualify
  , builtinNames
  , writtenDisplay
  , writtenKey
  , writtenKeys
  , fragmentKey
  ) where

import Data.Char (isAlphaNum)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import Data.Ord (Down (..))
import qualified Data.Set as Set
import Data.Set (Set)
import Data.Text (Text)
import qualified Data.Text as T

import AgdaMCP.Retrieval (tokens)
import AgdaMCP.Types
  (CorpusEntry (..), NameInfo (..), Part (..), WrittenTable (..))


-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------

-- | A printed type as tokens and bracket groups.  A group keeps its opening
-- and closing bracket, so it renders back as printed.
data Item
  = Tok Text
  | Grp Text [Item] Text
  deriving (Eq, Show)

-- | The brackets the tokenizer splits off, each with its closer.
closerOf :: Map Text Text
closerOf = Map.fromList [("(", ")"), ("{", "}"), ("⦃", "⦄")]

-- | parseItems: tokens to items.  Total: a closer that matches no opener is a
-- token, and an opener never closed is flattened back to a token.
parseItems :: [Text] -> [Item]
parseItems = finish . foldl' step ([], [])
  where
    -- The state is the current level's items, reversed, and a stack of the
    -- enclosing levels, each with its opener and its items so far, reversed.
    step (cur, stack) t
      | Map.member t closerOf = ([], (t, cur) : stack)
      | (o, saved) : rest <- stack, Map.lookup o closerOf == Just t =
          (Grp o (reverse cur) t : saved, rest)
      | otherwise = (Tok t : cur, stack)
    finish (cur, [])               = reverse cur
    finish (cur, (o, saved) : rest) = finish (cur <> (Tok o : saved), rest)

isTok :: Item -> Bool
isTok (Tok _) = True
isTok _       = False

-- | renderPlain: items back to text, as printed (used to compare binders).
renderPlain :: [Item] -> Text
renderPlain = T.unwords . map one
  where
    one (Tok t)       = t
    one (Grp o is c) = o <> renderPlain is <> c


-- ---------------------------------------------------------------------------
-- Binders
-- ---------------------------------------------------------------------------

-- | One name of a leading binder group: whether it is explicit, its name,
-- and its type as printed.
data Binder = Binder
  { bExplicit :: Bool
  , bName     :: Text
  , bType     :: Text
  } deriving (Eq, Ord, Show)

-- | The leading binder groups of a printed type, one 'Binder' per name, with
-- each group's type head: @{α ρ : Level} (𝒢 : Group α ρ) → …@ gives α, ρ,
-- and 𝒢.  Arrows between groups are skipped; the first item that is not a
-- binder group ends the telescope.
leadingBinders :: [Item] -> [(Binder, Maybe Text)]
leadingBinders = go
  where
    go (Tok "→" : rest) = go rest
    go (Grp o inner _ : rest)
      | Just bs <- binderGroup o inner = bs <> go rest
    go _ = []

binderGroup :: Text -> [Item] -> Maybe [(Binder, Maybe Text)]
binderGroup o inner = case break (== Tok ":") inner of
  (names@(_ : _), _ : ty) | all isTok names ->
    Just [ (Binder (o == "(") n (renderPlain ty), headTok ty) | Tok n <- names ]
  _ -> Nothing
  where
    headTok (Tok t : _) = Just t
    headTok _           = Nothing

-- | explicitArity: the explicit arguments a printed type takes before its
-- codomain, counting a named group's explicit names and an unnamed domain
-- as one each.  A type alias (@Op₂ A@, @Rel A ℓ@) counts as none, which is
-- why only a two-row module's operators are capped by it.
explicitArity :: [Item] -> Int
explicitArity items = sum (map count (dropLast (arrowSegments items)))
  where
    dropLast xs = take (length xs - 1) xs
    count seg
      | not (null seg), Just bss <- traverse group seg =
          length [ () | bs <- bss, (b, _) <- bs, bExplicit b ]
      | Tok "∀" : _ <- seg = 0
      | otherwise = 1
    group (Grp o inner _) = binderGroup o inner
    group _               = Nothing


-- ---------------------------------------------------------------------------
-- Operators and parameters
-- ---------------------------------------------------------------------------

-- | opParts: the parts of an operator name, or Nothing for a name with no
-- hole or no name part (@f@, @_@, @__@).
opParts :: Text -> Maybe [Part]
opParts n
  | any isName ps && Hole `elem` ps = Just ps
  | otherwise                       = Nothing
  where
    segs = T.splitOn "_" n
    ps   = concat (zipWith seg [0 :: Int ..] segs)
    seg i s = [ Name s | not (T.null s) ] <> [ Hole | i < length segs - 1 ]
    isName (Name _) = True
    isName Hole     = False

holes :: [Part] -> Int
holes = length . filter (== Hole)

-- | parameterCounts: each row's explicit module parameters, by
-- @prettyQname@ (the rules are in the module header).
parameterCounts :: Set Text -> [(CorpusEntry, Shape)] -> Map Text Int
parameterCounts records entries =
  Map.fromList (concatMap perModule (Map.toList byModule))
  where
    byModule = Map.fromListWith (flip (<>)) [ (ceModule e, [(e, sh)]) | (e, sh) <- entries ]
    junk e   = any (`T.isPrefixOf` cePrettyName e) ["hcomp-", "transp-"]
               || cePrettyName e == "constructor"
    binders  = map fst . shBinders
    perModule (m, es) =
      [ (cePrettyQname e, count e sh (binders sh)) | (e, sh) <- es ]
      where
        record   = m `Set.member` records
        evidence = [ binders sh | (e, sh) <- es, ceDefKind e == "function", not (junk e) ]
        prefix
          | record                  = majorityPrefix evidence
          | length evidence >= 2    = commonPrefix evidence
          | otherwise               = []
        count e sh bs =
          let shared = map fst (takeWhile (uncurry (==)) (zip bs prefix))
              p      = length (takeWhile (not . isOperation) (filter bExplicit shared))
          in case opParts (cePrettyName e) of
               Just ps | not record, length evidence < 3 ->
                 min p (max 0 (shArity sh - holes ps))
               _ | length evidence < 2, nestedInRecord sh -> 1
               _ -> p
        isOperation b = maybe False (const True) (opParts (bName b))
        -- A module with one function row gives no evidence of where its
        -- telescope ends.  One case is safe all the same: a module nested in
        -- a record's module (DecStrictPartialOrder.Eq, IsCongruent.Eq₁) whose
        -- row takes, as its first explicit argument, a value of that record:
        -- the record value is the parameter, as it is for the record's own
        -- fields.  Any other one-row module keeps its arguments (a stated
        -- limit; a Copilot catch on PR #231).
        nestedInRecord sh = case [ h | (b, h) <- shBinders sh, bExplicit b ] of
          Just h : _ -> h `elem` enclosing
          _          -> False
        enclosing = filter (`Set.member` records)
          [ T.intercalate "." (take k segs) | let segs = T.splitOn "." m, k <- [1 .. length segs - 1] ]

-- | The longest binder prefix that every sequence starts with.
commonPrefix :: [[Binder]] -> [Binder]
commonPrefix []       = []
commonPrefix (s : ss) = foldl' common s ss
  where common a b = map fst (takeWhile (uncurry (==)) (zip a b))

-- | The longest binder prefix that at least half the sequences (and two)
-- start with.
majorityPrefix :: [[Binder]] -> [Binder]
majorityPrefix seqs = go 1 []
  where
    need = max 2 ((length seqs + 1) `div` 2)
    go k best =
      let counts = Map.fromListWith (+) [ (take k s, 1 :: Int) | s <- seqs, length s >= k ]
      in case sortOn (Down . snd) (Map.toList counts) of
           (pre, n) : _ | n >= need -> go (k + 1) pre
           _                        -> best

-- | What the table reads from a row's type: its leading binders, with each
-- one's type head, and its explicit arity.  Kept instead of the parsed type,
-- so building the table never holds every parse at once.
data Shape = Shape
  { shBinders :: [(Binder, Maybe Text)]
  , shArity   :: !Int
  }

shapeOf :: CorpusEntry -> Shape
shapeOf e =
  let items = parseItems (tokens (ceType e))
      bs    = leadingBinders items
  in  length bs `seq` Shape bs (explicitArity items)

-- | writtenTable: the table for a corpus.
writtenTable :: [CorpusEntry] -> WrittenTable
writtenTable = writtenTableOf . map (\e -> (e, shapeOf e))

writtenTableOf :: [(CorpusEntry, Shape)] -> WrittenTable
writtenTableOf parsed = WrittenTable
  { wtNames   = Map.fromList [ (cePrettyQname e, info e) | e <- entries ]
  , wtFirsts  = Map.fromListWith (\_ old -> old)
      [ (cePrettyModule e <> "." <> firstName ps, info e)
      | e <- entries, Just ps <- [opParts (cePrettyName e)] ]
  , wtParts   = Set.fromList
      [ n | e <- entries, Just ps <- [opParts (cePrettyName e)], Name n <- ps ]
  , wtRecords = records
  }
  where
    entries = map fst parsed
    records = Set.fromList
      [ h | (_, sh) <- parsed
          , (_, Just h) <- shBinders sh
          , qualified h ]
    counts  = parameterCounts records parsed
    info e  = NameInfo (opParts (cePrettyName e)) (Map.findWithDefault 0 (cePrettyQname e) counts)
    firstName ps = case [ n | Name n <- ps ] of
      n : _ -> n
      []    -> ""


-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

-- | Whether a token is qualified (@A.B.c@), as opposed to a postfix
-- projection (@.fst@) or a bare name.
qualified :: Text -> Bool
qualified t = not ("." `T.isPrefixOf` t) && "." `T.isInfixOf` T.dropEnd 1 t

qualifierOf :: Text -> Text
qualifierOf = T.dropEnd 1 . fst . T.breakOnEnd "."

-- | builtinNames: Agda's builtins, as the corpus prints them, to the names
-- the pinned standard library (2.3) re-exports them under, read off its
-- @open import Agda.Builtin.* public ... renaming@ lines: Data.Nat.Base
-- (@Nat@ to @ℕ@, @_-_@ to @_∸_@, @_==_@ to @_≡ᵇ_@, @_<_@ to @_<ᵇ_@),
-- Data.Integer.Base (@Int@ to @ℤ@), and Data.Product.Base (@fst@ and @snd@
-- to @proj₁@ and @proj₂@).  Each name in each printed shape: prefix, an
-- infix part, a postfix projection.  Found by issue #202's arm, whose one
-- search_by_type call wrote @m + n ∸ o ≡ m + (n ∸ o)@ and matched nothing
-- while the lemma it described is printed with @Agda.Builtin.Nat.-@.
builtinNames :: Map Text Text
builtinNames = Map.fromList
  [ ("Agda.Builtin.Nat.Nat", "ℕ")
  , ("Agda.Builtin.Nat._-_", "_∸_"), ("Agda.Builtin.Nat.-", "∸")
  , ("Agda.Builtin.Nat._==_", "_≡ᵇ_"), ("Agda.Builtin.Nat.==", "≡ᵇ")
  , ("Agda.Builtin.Nat._<_", "_<ᵇ_"), ("Agda.Builtin.Nat.<", "<ᵇ")
  , ("Agda.Builtin.Int.Int", "ℤ")
  , ("Agda.Builtin.Sigma.Σ.fst", "proj₁"), (".Agda.Builtin.Sigma.Σ.fst", ".proj₁")
  , ("Agda.Builtin.Sigma.Σ.snd", "proj₂"), (".Agda.Builtin.Sigma.Σ.snd", ".proj₂")
  ]

-- | writtenName: a printed token as a statement writes it: the standard
-- library's name for a builtin, else the token with its qualifier dropped.
writtenName :: Text -> Text
writtenName tok = Map.findWithDefault (unqualify tok) tok builtinNames

-- | unqualify: a token's last dot segment; a postfix projection keeps its
-- dot (@.Agda.Builtin.Sigma.Σ.fst@ is @.fst@).
unqualify :: Text -> Text
unqualify t
  | Just rest <- T.stripPrefix "." t, not (T.null rest) = "." <> unqualify rest
  | qualified t = snd (T.breakOnEnd "." t)
  | otherwise   = t

-- | How a token takes part in an application.
data Role
  = Prefix Int          -- ^ a name with this many explicit parameters
  | Mixfix [Part] Int   -- ^ an operator's first name part
  | FieldOp             -- ^ a record field operator the corpus has no row for
  | OpPart              -- ^ another symbolic name the corpus has no row for
                        --   (the standard library's @¬@ in an agda-algebras
                        --   type): printed bare, so an operator's part
  | Plain

roleOf :: WrittenTable -> Text -> Role
roleOf t tok
  | Just ni <- Map.lookup tok (wtNames t)               = Prefix (niParams ni)
  | Just (NameInfo (Just ps) p) <- Map.lookup tok (wtFirsts t) = Mixfix ps p
  | qualified tok, qualifierOf tok `Set.member` wtRecords t =
      if symbolic (unqualify tok) then FieldOp else Prefix 1
  | qualified tok, symbolic (unqualify tok) = OpPart
  | otherwise = Plain
  where
    symbolic n = maybe False (not . isAlphaNum . fst) (T.uncons n)

-- | Tokens that end an application spine.
structural :: Set Text
structural = Set.fromList ["→", ":", "∀", "λ", "=", ";", "|"]

-- | Whether a token is a boundary: the item after it starts a new spine.
boundary :: WrittenTable -> Text -> Bool
boundary t tok = tok `Set.member` structural || tok `Set.member` wtParts t || case roleOf t tok of
  Mixfix _ _ -> True
  FieldOp    -> True
  OpPart     -> True
  _          -> False

-- | Whether an item is an explicit argument in a spine.
isArg :: WrittenTable -> Item -> Bool
isArg _ (Grp o _ _) = o == "("
isArg t (Tok tok)   = not ("." `T.isPrefixOf` tok) && not (boundary t tok)

-- | unsection: drop module parameters where names are applied (the module
-- header has the rules).  Total; a shape it does not recognize is left as it
-- was printed.
unsection :: WrittenTable -> [Item] -> [Item]
unsection t items = case break (== Tok ":") items of
  -- A binder group's contents: names, then a type to render.
  (names@(_ : _), colon : ty) | all isTok names -> names <> (colon : unsection t ty)
  _ -> go True (map inner items)
  where
    inner (Grp o is c) = Grp o (unsection t is) c
    inner x            = x

    -- The flag says whether the next item heads an application spine: only
    -- a head takes the items after it as arguments.
    go _ [] = []
    go atHead (it : rest) = case it of
      Grp "(" content _
        | Just (ps, p, operands) <- sectionIn t content ->
            let (extras, rest') = if atHead then span (isArg t) rest else ([], rest)
            in  renderOp ps p (operands <> map pure extras) <> go False rest'
      Tok tok -> case roleOf t tok of
        Mixfix ps p
          | p > 0, Name _ : _ <- ps, Name _ <- last ps
          , Just (operands, after) <- splitParts t (drop 1 ps) rest
          , all (not . null) operands ->
              let (extras, rest') = if atHead then span (isArg t) after else ([], after)
              in  renderOp ps p (operands <> map pure extras) <> go False rest'
        Prefix p
          | p > 0, atHead -> it : go False (dropArgs p rest)
        _ -> it : go (boundary t tok) rest
      _ -> it : go False rest

    -- Drop p explicit arguments, keeping hidden ones ({…}) in place.
    dropArgs :: Int -> [Item] -> [Item]
    dropArgs 0 xs = xs
    dropArgs n (x@(Grp "{" _ _) : xs) = x : dropArgs n xs
    dropArgs n (x : xs) | isArg t x   = dropArgs (n - 1) xs
    dropArgs _ xs = xs

-- | sectionIn: a group's contents, when they are exactly one application of
-- an operator with a leading hole and module parameters, printed with the
-- parameter in that hole: @G ≈ a@, @G ⁻¹@.  Returns its parts, its parameter
-- count, and its operands in order.
sectionIn :: WrittenTable -> [Item] -> Maybe ([Part], Int, [[Item]])
sectionIn t content
  | Tok ":" `elem` content = Nothing
  | otherwise = case candidates of
      (k, ps, p) : _
        | Just (operands, trailing) <- splitParts t (drop 2 ps) (drop (k + 1) content)
        , null trailing
        , let all' = take k content : operands
        , all (not . null) all' -> Just (ps, p, all')
      _ -> Nothing
  where
    lastIx = length content - 1
    candidates =
      [ c | (k, Tok tok) <- zip [0 ..] content, k > 0
          , Just c <- [candidate k tok] ]
    candidate k tok = case roleOf t tok of
      Mixfix ps@(Hole : Name _ : _) p | p > 0 -> Just (k, ps, p)
      FieldOp -> Just (k, if k == lastIx then [Hole, Name (unqualify tok)]
                                         else [Hole, Name (unqualify tok), Hole], 1)
      _ -> Nothing

-- | splitParts: given the parts that remain after a name part already
-- consumed, and the items after it, the operands between them and the
-- items after the last part.  A trailing hole takes the rest of the items.
-- Closed groups nested in an operand (@𝕌[ … ]@, another @[ … ⸴ … ]@) are
-- skipped as a whole, so their closers are not taken for this operator's.
splitParts :: WrittenTable -> [Part] -> [Item] -> Maybe ([[Item]], [Item])
splitParts t = go
  where
    go [] xs              = Just ([], xs)
    go [Hole] xs          = Just ([xs], [])
    go (Hole : Name n : ps) xs = do
      (before, after) <- scanTo n xs
      (ops, rest)     <- go ps after
      pure (before : ops, rest)
    go (Name n : ps) xs = case xs of
      Tok n' : xs' | n' == n -> go ps xs'
      _                      -> Nothing
    go (Hole : Hole : _) _ = Nothing

    -- The items before the first token n at this nesting depth, and the
    -- items after it.
    scanTo n = loop [] []
      where
        loop _ _ [] = Nothing
        loop acc stack (x : xs) = case x of
          Tok tok
            | null stack, tok == n -> Just (reverse acc, xs)
            | (top : stack') <- stack, tok == top -> loop (x : acc) stack' xs
            | Just closer <- opens tok -> loop (x : acc) (closer : stack) xs
          _ -> loop (x : acc) stack xs
    -- The closer a token opens: a closed operator's last part, or ] after a
    -- token ending in [ (Σ[, ∃[, 𝕌[).
    opens tok = case roleOf t tok of
      Mixfix ps _ | Name _ : _ <- ps, Name c <- last ps, length ps > 1 -> Just c
      _ | "[" `T.isSuffixOf` tok -> Just "]"
        | otherwise -> Nothing

-- | renderOp: an operator applied to its arguments with the first p dropped:
-- mixfix when enough remain to fill its holes, else its name, prefix.
renderOp :: [Part] -> Int -> [[Item]] -> [Item]
renderOp ps p args
  | length own < h =
      if null own then [Tok name] else [Grp "(" (Tok name : map wrap own) ")"]
  | null rest = [Grp "(" (fill ps filled) ")"]
  | otherwise = [Grp "(" (Grp "(" (fill ps filled) ")" : map wrap rest) ")"]
  where
    own             = drop p args
    h               = holes ps
    (filled, rest)  = splitAt h own
    name            = T.concat [ case x of Hole -> "_"; Name n -> n | x <- ps ]
    wrap [x]        = x
    wrap xs         = Grp "(" xs ")"
    fill (Hole : qs) (a : as) = wrap a : fill qs as
    fill (Name n : qs) as     = Tok n : fill qs as
    fill _ _                  = []

-- | The display form: qualifiers dropped, and the brackets that are always
-- safe to drop: around a single item, and around a whole arrow segment that
-- is not itself a function type or a binder (an arrow binds more weakly than
-- any operator).  Other brackets stay, since precedences are not known here.
renderDisplay :: [Item] -> Text
renderDisplay = T.intercalate " → " . map segment . arrowSegments
  where
    segment [Grp "(" is ")"]
      | Tok "→" `notElem` is, Tok ":" `notElem` is = renderDisplay is
    segment is = T.unwords (map one is)
    one (Tok tok) = writtenName tok
    one (Grp "(" [x] ")") = one x
    one (Grp o is c) = o <> renderDisplay is <> c

-- | A list of items split at its top-level arrows.
arrowSegments :: [Item] -> [[Item]]
arrowSegments = foldr cut [[]]
  where
    cut (Tok "→") acc  = [] : acc
    cut x (seg : acc)  = (x : seg) : acc
    cut x []           = [[x]]

-- | The matching key: qualifiers and brackets dropped, case folded.
renderKey :: [Item] -> Text
renderKey = T.toLower . T.unwords . go
  where
    go = concatMap one
    one (Tok tok)    = [writtenName tok]
    one (Grp _ is _) = go is

-- | writtenDisplay: a printed type as written, for reading.
writtenDisplay :: WrittenTable -> Text -> Text
writtenDisplay t = renderDisplay . unsection t . parseItems . tokens

-- | writtenKey: a printed type as written, for matching.
writtenKey :: WrittenTable -> Text -> Text
writtenKey t = renderKey . unsection t . parseItems . tokens

-- | writtenKeys: every entry's key, by @prettyQname@, with the table they
-- were rendered with.  The table is built from the same entries, so both
-- are properties of the corpus.
writtenKeys :: Map Text CorpusEntry -> (WrittenTable, Map Text Text)
writtenKeys entries =
  let t = writtenTable (Map.elems entries)
  in  (t, Map.map (writtenKey t . ceType) entries)

-- | fragmentKey: a query fragment's key.  A fragment is written as a
-- statement already is, so it is not unsectioned; @->@ is read as @→@, as
-- Agda reads it.
fragmentKey :: Text -> Text
fragmentKey = renderKey . parseItems . map arrow . tokens
  where
    arrow "->" = "→"
    arrow x    = x
