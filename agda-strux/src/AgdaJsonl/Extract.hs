{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

-- | Extract.hs
--
-- File: agda-strux/src/AgdaJsonl/Extract.hs
--
-- Purpose
-- =======
-- After Agda has checked a module (either by actual typechecking OR by loading a
-- cached .agdai interface), we emit one JSONL row per definition.
--
-- We are NOT scraping surface syntax. We ask Agda (as a library) for:
--   * the fully elaborated type of each definition
--   * a coarse "definition kind"
--   * (NEW) "proof-ish" bodies for functions/theorems (as Agda internal syntax)
--
-- About "proof extraction"
-- ========================
-- In Agda, theorems are just functions whose bodies inhabit their types.
-- So, to capture proofs we focus on function definitions:
--   * `theDef defn` yields a `Defn`
--   * For function-like defs, `funClauses :: Defn -> [Clause]`
--     (NOTE: it is a selector on Defn, not on FunctionData). :contentReference[oaicite:1]{index=1}
--   * Each `Clause` has an optional `clauseBody :: Maybe Term`
--     which we pretty-print using Agda's pretty-printer inside TCM.
--
-- Caveats:
--   * The "body" we emit is Agda's *internal* syntax, not original source text.
--   * Some functions may have no clause bodies (e.g. postulated/abstract/opaque),
--     in which case `body = null` and `hasBody = false`.
--
-- Output fields
-- =============
-- Existing required fields are preserved. We add two OPTIONAL fields:
--   - body    : null | string
--   - hasBody : bool
--
-- These are optional so older validators/tests that enforce a fixed required-key
-- set won't fail until we intentionally make them required.

module AgdaJsonl.Extract
  ( dumpCheckResultAsJsonl
  , DumpStats(..)
  ) where

import Control.Monad (forM_, when)
import Control.Monad.IO.Class (liftIO)
import Data.Char (ord, isLetter, isAlphaNum)
import Data.List (sortOn)
import Data.Maybe (catMaybes, isJust)
import qualified Data.HashMap.Strict as HM
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Aeson as A
import qualified Data.Aeson.Text as AT
import System.IO (Handle, hPutStrLn, stderr)

import Agda.Interaction.Imports (CheckResult, crInterface)
import Agda.TypeChecking.Monad (TCM)

import Agda.TypeChecking.Monad.Base
  ( Signature(..)
  , Interface
  , Definition
  , defType
  , theDef
  , Defn(..)
  , iSignature
  , iModuleName
  , funClauses        -- IMPORTANT: selector on Defn (Agda 2.8.x) :contentReference[oaicite:2]{index=2}
  )
import Agda.Syntax.Common.Pretty (prettyShow, pretty)
import qualified Agda.Syntax.Internal as I
import Agda.TypeChecking.Pretty (PrettyTCM, prettyTCM)
import qualified AgdaJsonl.Cli as Cli
import AgdaJsonl.StructAst (typeToAst)
--------------------------------------------------------------------------------
-- Stats
--------------------------------------------------------------------------------

-- | Small stats bundle so callers can distinguish:
--   * "interface signature empty" (almost certainly a bug)
--   * "module had 0 local definitions" (can be legitimate)
data DumpStats = DumpStats
  { dsMainModule  :: T.Text
  , dsTotalDefs   :: Int     -- total defs seen (root + sections)
  , dsWrittenDefs :: Int     -- written after filtering to “belongs to this file”
  }

--------------------------------------------------------------------------------
-- Helpers: name splitting and normalization
--------------------------------------------------------------------------------

-- | Split a qualified name like @"A.B.C.f"@ into @"A.B.C"@ and @"f"@.
-- If there is no '.', we treat the whole thing as the name.
splitQName :: T.Text -> (T.Text, T.Text)
splitQName q =
  let (modDot, nm) = T.breakOnEnd "." q
  in if T.null modDot
        then ("", q)
        else (T.dropEnd 1 modDot, nm)  -- drop trailing '.'

-- | Normalize a qualified name by dropping anonymous/section-y segments.
-- Conservative rule: remove only segments that are exactly "_" (anonymous module markers).
normalizeQNameText :: T.Text -> T.Text
normalizeQNameText q =
  let segs  = T.splitOn "." q
      keep s = not (T.null s) && s /= "_"
  in T.intercalate "." (filter keep segs)

--------------------------------------------------------------------------------
-- v0.1: defKind (stable classification)
--------------------------------------------------------------------------------

-- | A coarse classification of Agda definitions.
-- We keep this stable for downstream consumers; anything unrecognized is "other".
defKindOf :: Definition -> T.Text
defKindOf = defKindOfDefn . theDef

-- | Map Agda's internal definition constructors to a stable schema enum.
defKindOfDefn :: Defn -> T.Text
defKindOfDefn = \case
  FunctionDefn{}      -> "function"
  DatatypeDefn{}      -> "data"
  RecordDefn{}        -> "record"
  ConstructorDefn{}   -> "constructor"
  AxiomDefn{}         -> "postulate"
  PrimitiveDefn{}     -> "primitive"
  PrimitiveSortDefn{} -> "primitive"
  AbstractDefn d      -> defKindOfDefn d
  _                   -> "other"

--------------------------------------------------------------------------------
-- v0.1: dependencies (heuristic, stable)
--------------------------------------------------------------------------------

-- | Extract a coarse list of dependency-like identifiers from the pretty-printed type.
-- Heuristic: tokenize and keep identifier-ish tokens.
dependenciesFromTypeText :: T.Text -> [T.Text]
dependenciesFromTypeText =
  Set.toList
    . Set.fromList
    . filter keep
    . tokenize
  where
    keep tok =
      T.length tok >= 2
        && isLetter (T.head tok)
        && tok `notElem` [ "Set", "Prop", "Type" , "∀", "forall" ]

-- | Tokenize into chunks of letters/digits/._'
tokenize :: T.Text -> [T.Text]
tokenize =
  go [] T.empty
  where
    ok c = isAlphaNum c || c == '_' || c == '\'' || c == '.'

    go acc cur txt =
      case T.uncons txt of
        Nothing ->
          let acc' = if T.null cur then acc else cur : acc
          in reverse acc'
        Just (c, rest)
          | ok c       -> go acc (T.snoc cur c) rest
          | T.null cur -> go acc cur rest
          | otherwise  -> go (cur : acc) T.empty rest

--------------------------------------------------------------------------------
-- Pretty printing helpers
--------------------------------------------------------------------------------

-- | Pretty-print an Agda internal thing using Agda's own pretty-printer inside TCM.
pp :: PrettyTCM a => a -> TCM T.Text
pp x = do
  doc <- prettyTCM x
  pure (T.pack (prettyShow doc))

--------------------------------------------------------------------------------
-- Proof-ish extraction (function clause bodies)
--------------------------------------------------------------------------------

-- | Attempt to extract a "body" for a definition.
--
-- We only attempt this for function-like defs, because:
--   * in Agda, proofs are function bodies
--   * function bodies live (after elaboration) in the clause bodies
--
-- Returns:
--   * Nothing if there is no meaningful body to report
--   * Just text if at least one clause body exists
ppDefnBody :: Defn -> TCM (Maybe T.Text)
ppDefnBody = \case
  -- If a definition is wrapped as abstract, peel and continue.
  AbstractDefn d ->
    ppDefnBody d

  -- IMPORTANT (Agda 2.8.x):
  -- `funClauses` is a selector on Defn, not on FunctionData. :contentReference[oaicite:3]{index=3}
  --
  -- So we must keep the whole Defn around (d@...) and call funClauses d.
  d@FunctionDefn{} -> do
    let cls = funClauses d
    bodies <- catMaybes <$> mapM ppClauseBody cls
    pure $ if null bodies
      then Nothing
      else Just (T.intercalate "\n" bodies)

  -- Everything else: not a proof-bearing definitional equality.
  _ ->
    pure Nothing

-- | Pretty-print the body of a single clause, if it exists.
-- Clause bodies are Agda internal terms (I.Term).
ppClauseBody :: I.Clause -> TCM (Maybe T.Text)
ppClauseBody cl =
  case I.clauseBody cl of
    Nothing -> pure Nothing
    Just t  -> Just <$> pp t

--------------------------------------------------------------------------------
-- Main entry: dump one JSONL row per definition in the checked interface
--------------------------------------------------------------------------------

dumpCheckResultAsJsonl :: Handle -> FilePath -> CheckResult -> Cli.OutputFormat -> TCM DumpStats
dumpCheckResultAsJsonl h file cr fmt = do
  let iface :: Interface
      iface = crInterface cr

      sig :: Signature
      sig = iSignature iface

      -- Agda 2.8.x: Signature exposes `_sigDefinitions`
      defsAll = HM.toList (_sigDefinitions sig)

      mainMod :: T.Text
      mainMod = T.pack (prettyShow (pretty (iModuleName iface)))

      -- Keep only defs that "belong" to this file/module (main module + nested).
      belongsToThisFile (qname, _defn) =
        let qnTxt            = T.pack (prettyShow (pretty qname))
            (modTxt, _nmTxt) = splitQName qnTxt
        in modTxt == mainMod || (mainMod <> ".") `T.isPrefixOf` modTxt

      defsFiltered = filter belongsToThisFile defsAll
      defsSorted   = sortOn (\(qname,_) -> T.pack (prettyShow (pretty qname))) defsFiltered

  -- Extra debug to stderr if we ever get an empty signature.
  when (null defsAll) $
    liftIO $ hPutStrLn stderr $
      "agda-json DEBUG: interface + sections yielded 0 definitions; output will be empty."

  forM_ defsSorted $ \(qname, defn) -> do
    let qnTxt              = T.pack (prettyShow (pretty qname))   -- stable, internal-ish
        (modTxt, nameTxt)  = splitQName qnTxt

        prettyQn           = normalizeQNameText qnTxt
        (pMod, pNm)        = splitQName prettyQn

    tyTxt   <- pp (defType defn)
    tyAst   <- typeToAst (defType defn)
    bodyTxt <- ppDefnBody (theDef defn)
    let hasBody = isJust bodyTxt

    let astSize = T.length tyTxt
        kind    = "definition"
        defKind = defKindOf defn
        deps    = dependenciesFromTypeText tyTxt

        line = case fmt of
          Cli.Human ->
            jsonObj
              [ ("name", jsonStr nameTxt)
              , ("type", jsonStr tyTxt)
              , ("body", maybe jsonNull jsonStr bodyTxt)
              ]
          Cli.Full  ->
            jsonObj
              [ ("file",           jsonStr (T.pack file))
              , ("module",         jsonStr modTxt)
              , ("name",           jsonStr nameTxt)
              , ("qname",          jsonStr qnTxt)
              , ("prettyModule",   jsonStr pMod)
              , ("prettyName",     jsonStr pNm)
              , ("prettyQname",    jsonStr prettyQn)
              , ("type",           jsonStr tyTxt)
              , ("typeAstVersion", jsonStr "0.3-v0")
              , ("typeAst",        jsonVal tyAst)
              , ("kind",           jsonStr kind)
              , ("defKind",        jsonStr defKind)
              , ("dependencies",   jsonArr (map jsonStr deps))
              , ("astSize",        jsonNum astSize)
              , ("body",           maybe jsonNull jsonStr bodyTxt)
              , ("hasBody",        jsonBool hasBody)
              ]

    liftIO $ hPutStrLn h (T.unpack line)

  pure $ DumpStats
    { dsMainModule  = mainMod
    , dsTotalDefs   = length defsAll
    , dsWrittenDefs = length defsSorted
    }

--------------------------------------------------------------------------------
-- Tiny JSON encoder (no extra deps)
--------------------------------------------------------------------------------

-- | Render a JSON object from already-rendered JSON values.
jsonObj :: [(T.Text, T.Text)] -> T.Text
jsonObj kvs = "{" <> T.intercalate "," (map field kvs) <> "}"
  where
    field (k, v) = jsonStr k <> ":" <> v

-- | Render a JSON string with basic escaping.
jsonStr :: T.Text -> T.Text
jsonStr t = "\"" <> escape t <> "\""
  where
    escape = T.concatMap esc1
    esc1 '"'  = "\\\""
    esc1 '\\' = "\\\\"
    esc1 '\n' = "\\n"
    esc1 '\r' = "\\r"
    esc1 '\t' = "\\t"
    esc1 c
      | ord c < 0x20 = T.pack ("\\u" <> hex4 (ord c))
      | otherwise    = T.singleton c

-- | Render a JSON array from already-rendered JSON values.
jsonArr :: [T.Text] -> T.Text
jsonArr xs = "[" <> T.intercalate "," xs <> "]"

-- | Render a JSON number (only Int for now).
jsonNum :: Int -> T.Text
jsonNum = T.pack . show

-- | JSON null value.
jsonNull :: T.Text
jsonNull = "null"

-- | Render a JSON boolean.
jsonBool :: Bool -> T.Text
jsonBool True  = "true"
jsonBool False = "false"

-- | Embed a nested aeson value as raw JSON (not a JSON string).
jsonVal :: A.Value -> T.Text
jsonVal = TL.toStrict . AT.encodeToLazyText

-- | Render a codepoint as four hex digits.
hex4 :: Int -> String
hex4 n =
  let h  = "0123456789abcdef"
      d0 = h !! ((n `div` 4096) `mod` 16)
      d1 = h !! ((n `div` 256)  `mod` 16)
      d2 = h !! ((n `div` 16)   `mod` 16)
      d3 = h !! (n `mod` 16)
  in [d0, d1, d2, d3]
