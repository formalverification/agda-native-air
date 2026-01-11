{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

-- | Extract.hs
--
-- File: agda-backend-jsonl/src/AgdaJsonl/Extract.hs
--
-- Description:
--   Extraction code: after Agda has checked a module (either by actual
--   typechecking OR by loading a cached .agdai interface), we emit one JSONL
--   row per definition.
--
--   This is the heart of issue #38:
--
--     +  We are not doing syntactic scraping of .agda files.
--     +  We are asking Agda (as a library) what it accepted and what it
--        computed as types for declarations.
--
--   Key design choice:
--     We no longer just extract from the Interface signature returned by
--     typeCheckMain*, but now use the global mutable state (getSignature).
--
--     **However** when Agda loads a cached interface, it may not populate the same
--     global signature/state that getSignature reads from; typeCheckMain still
--     returns a CheckResult containing the interface (and its signature).  So, we
--     still need to verify that the new approach works correctly when Agda loads
--     from cache.
--
--   Output fields (v0):
--     - file    : input file path (as passed to CLI)
--     - qname   : qualified name (pretty-printed by Agda)
--     - type    : type of the definition (pretty-printed by Agda)
--     - kind    : placeholder ("definition" for now)
--     - astSize : cheap proxy feature (length of pretty-printed type)
--
--   Later (v1+), this is where we'll extend rows with:
--     - def clauses / patterns / compiled clauses
--     - definition kind (data/record/function/postulate/...)
--     - telescope/context info, etc.

module AgdaJsonl.Extract
  ( dumpCheckResultAsJsonl
  , DumpStats(..)
  ) where

import Control.Monad (forM_, when)
import Control.Monad.IO.Class (liftIO)
import Data.Char (ord, isLetter, isAlphaNum)
import Data.List (sortOn)
import qualified Data.HashMap.Strict as HM
import qualified Data.Text as T
import qualified Data.Set as Set
-- import System.FilePath (takeBaseName)
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
  )
import Agda.Syntax.Common.Pretty (prettyShow, pretty)
import Agda.TypeChecking.Pretty (PrettyTCM, prettyTCM)


--------------------------------------------------------------------------------
-- | Stats
--
-- Small stats bundle so callers can distinguish:
-- - "interface signature empty" (almost certainly a bug)
-- - "module had 0 local definitions" (can be legitimate)
data DumpStats = DumpStats
  { dsMainModule  :: T.Text
  , dsTotalDefs   :: Int     -- total defs seen (root + sections)
  , dsWrittenDefs :: Int     -- written after filtering to “belongs to this file”
  }

--------------------------------------------------------------------------------
-- Helpers: name splitting and normalization

-- | Split Name
-- Split a qualified name like "A.B.C.f" into ("A.B.C", "f").
-- If there is no '.', we treat the whole thing as the name.
splitQName :: T.Text -> (T.Text, T.Text)
splitQName q =
  let (modDot, nm) = T.breakOnEnd "." q
  in if T.null modDot
        then ("", q)
        else (T.dropEnd 1 modDot, nm)  -- drop trailing '.'

-- | Normalize Name
-- Drop anonymous/section-y segments from a qualified name.
-- Conservative rule: remove path segments that are "_" or start with "_" .
-- (We can tighten/loosen later once we see actual Agda pretty output.)
normalizeQNameText :: T.Text -> T.Text
normalizeQNameText q =
  let segs = T.splitOn "." q
      keep s =
        not (T.null s)
        && s /= "_"
        && not ("_" `T.isPrefixOf` s)
      segs' = filter keep segs
  in T.intercalate "." segs'

-- normalizeModuleText :: T.Text -> T.Text
-- normalizeModuleText = fst . splitQName . normalizeQNameText . (<> ".dummy")
-- -- ^ hack: append ".dummy" so splitQName works for module-only strings


-- ------------------------------------------------------------------------------
-- | v0.1: defKind
--
-- A coarse classification of Agda definitions.  We keep this stable for downstream
-- consumers; anything we don't recognize is "other".
defKindOf :: Definition -> T.Text
defKindOf = defKindOfDefn . theDef

-- | Map Agda Constructors
-- Map Agda's internal definition constructors to our stable schema enum.
-- Anything unfamiliar collapses to "other".
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
-- v0.1: dependencies (stable version)
--------------------------------------------------------------------------------

-- | Extract Dependencies
-- Extract a coarse list of "dependency-like" identifiers from the pretty-printed type.
--
-- This is intentionally stable across Agda internal API changes:
-- + We still rely on Agda to compute the type (semantic),
-- + but avoid importing / pattern matching on internal Term constructors.
--
-- Heuristic:
-- + tokenize into identifier-ish chunks
-- + keep tokens that look like names (start with a letter) and are not tiny noise
-- + return unique tokens (sorted) for determinism
--
-- Implementation Note: dependencies are currently extracted heuristically from the
-- pretty-printed type (v0.1), not from internal term traversal.
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

-- | Tokenize
-- Tokenize into chunks of letters/digits/._'
-- (Unicode letters are handled by 'isLetter'.)
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
          | ok c      -> go acc (T.snoc cur c) rest
          | T.null cur -> go acc cur rest
          | otherwise -> go (cur : acc) T.empty rest




-- ------------------------------------------------------------------------------
-- | Pretty Print
-- Pretty-print an Agda internal thing using Agda's own pretty-printer,
-- inside the typechecking monad.
pp :: PrettyTCM a => a -> TCM T.Text
pp x = do
  doc <- prettyTCM x
  pure (T.pack (prettyShow doc))


-- | Dump JSOL Row
-- After type-checking, dump one JSONL row per definition  currently in scope from
-- the returned interface signature. Returns the number of rows written for tests and
-- debugging.
dumpCheckResultAsJsonl :: Handle -> FilePath -> CheckResult -> TCM DumpStats
dumpCheckResultAsJsonl h file cr = do
  let iface :: Interface
      iface = crInterface cr

      sig :: Signature
      sig = iSignature iface

      -- Agda 2.8.x: Signature exposes `_sigDefinitions`
      defsAll = HM.toList (_sigDefinitions sig)
      -- defsAll :: [(Agda.Syntax.Common.Name.QName, Definition)]
      -- defsAll = HM.toList (collectDefsRecursive sig)

      mainMod :: T.Text
      -- IMPORTANT: do NOT use takeBaseName for modules like Base/Relations/Discrete.agda
      mainMod = T.pack (prettyShow (pretty (iModuleName iface)))
      -- mainMod =
      --    -- Prefer Agda’s module name (correct for Base/Relations/Discrete.agda)
      --   -- Fallback keeps old behavior if API differs.
      --   case safePrettyModule iface of
      --     Just m  -> m
      --     Nothing -> T.pack (takeBaseName file)

      -- belongsToThisFile :: (Agda.Syntax.Common.Name.QName, Definition) -> Bool
      belongsToThisFile (qname, _defn) =
        let qnTxt            = T.pack (prettyShow (pretty qname))
            (modTxt, _nmTxt) = splitQName qnTxt
        in modTxt == mainMod || (mainMod <> ".") `T.isPrefixOf` modTxt

      -- isMainModuleDef :: (Agda.Syntax.Common.Name.QName, Definition) -> Bool
      -- isMainModuleDef (qname, _defn) =
      --   let qnTxt            = T.pack (prettyShow (pretty qname))
      --       (modTxt, _nmTxt) = splitQName qnTxt
      --   in modTxt == mainMod

      -- defsFiltered = filter isMainModuleDef defsAll
      -- defsFiltered :: [(Agda.Syntax.Common.Name.QName, Definition)]
      defsFiltered = filter belongsToThisFile defsAll

      -- defsSorted :: [(Agda.Syntax.Common.Name.QName, Definition)]
      defsSorted = sortOn (\(qname,_) -> T.pack (prettyShow (pretty qname))) defsFiltered

  -- Extra debug to stderr if we ever get an empty signature.
  when (null defsAll) $
    liftIO $ hPutStrLn stderr $
      "agda-json DEBUG: interface + sections yielded 0 definitions; output will be empty."

  forM_ defsSorted $ \(qname, defn) -> do
    let qnTxt = T.pack (prettyShow (pretty qname))   -- stable, internal-ish
        (modTxt, nameTxt) = splitQName qnTxt

        prettyQn   = normalizeQNameText qnTxt
        (pMod, pNm) = splitQName prettyQn

    tyTxt <- pp (defType defn)                       -- keep type pretty-printing in TCM

    let astSize = T.length tyTxt
        kind    = "definition"    --  keep existing field stable
        defKind = defKindOf defn
        deps    = dependenciesFromTypeText tyTxt

        line =
          jsonObj
            [ ("file",    jsonStr (T.pack file))
            , ("module",  jsonStr modTxt)
            , ("name",    jsonStr nameTxt)
            , ("qname",   jsonStr qnTxt)
            , ("prettyModule", jsonStr pMod)
            , ("prettyName",   jsonStr pNm)
            , ("prettyQname",  jsonStr prettyQn)
            , ("type",    jsonStr tyTxt)
            , ("kind",    jsonStr kind)
            , ("defKind", jsonStr defKind)
            , ("dependencies", jsonArr (map jsonStr deps))
            , ("astSize", jsonNum astSize)
            ]

    liftIO $ hPutStrLn h (T.unpack line)

  pure $ DumpStats
    { dsMainModule  = mainMod
    , dsTotalDefs   = length defsAll
    , dsWrittenDefs = length defsSorted
    }

-- -- | Helper: try to pretty-print the interface module name if available.
-- safePrettyModule :: Interface -> Maybe T.Text
-- safePrettyModule iface =
--   -- If Agda exposes iModuleName :: Interface -> ModuleName
--   -- then prettyShow (pretty ...) should work.
--   -- If this doesn't compile, temporarily return Nothing and
--   -- keep the fallback while we adjust imports/types.
--   Just (T.pack (prettyShow (pretty (iModuleName iface))))

-- ------------------------------------------------------------------------------
-- | Tiny JSON encoder (no extra deps)
--
-- Render a JSON object from already-rendered JSON values.
-- (Keys are rendered as JSON strings.)
jsonObj :: [(T.Text, T.Text)] -> T.Text
jsonObj kvs = "{" <> T.intercalate "," (map field kvs) <> "}"
  where field (k, v) = jsonStr k <> ":" <> v

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

-- | Render a codepoint as four hex digits.
hex4 :: Int -> String
hex4 n =
  let h = "0123456789abcdef"
      d0 = h !! ((n `div` 4096) `mod` 16)
      d1 = h !! ((n `div` 256)  `mod` 16)
      d2 = h !! ((n `div` 16)   `mod` 16)
      d3 = h !! (n `mod` 16)
  in [d0, d1, d2, d3]

