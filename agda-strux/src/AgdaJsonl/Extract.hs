-- | src/AgdaJsonl/Extract.hs
--
-- File: agda-backend-jsonl/src/AgdaJsonl/Extract.hs
--
-- Description:
--   Pure-ish extraction code: once Agda has parsed + typechecked a module,
--   we inspect the current signature and emit *one JSONL row per definition*.
--
--   This is the heart of issue #38:
--
--     +  We are not doing syntactic scraping of .agda files.
--     +  We are asking Agda (as a library) what it accepted and what it
--        computed as types for declarations.
--
--   v0 output fields:
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

{-# LANGUAGE OverloadedStrings #-}

module AgdaJsonl.Extract
  ( dumpSignatureAsJsonl
  ) where

import Control.Monad (forM_)
import Control.Monad.IO.Class (liftIO)
import Data.Char (ord)
import qualified Data.HashMap.Strict as HM
import qualified Data.Text as T
import System.IO (Handle, hPutStrLn)

-- Agda internals (post-typechecking)
import Agda.TypeChecking.Monad (TCM)
import Agda.TypeChecking.Monad.State (getSignature)
import Agda.TypeChecking.Monad.Base (Signature(..), defType)
import Agda.Syntax.Common.Pretty (prettyShow)
import Agda.TypeChecking.Pretty (PrettyTCM, prettyTCM)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- | After `typeCheckMain`, dump one JSONL row per definition currently in scope.
--
-- IMPORTANT:
-- The signature is *global-ish*: after typechecking, it contains all the
-- definitions Agda has loaded so far (including imports).
-- For v0, that’s fine: it’s still “one row per declaration Agda knows about”.
-- If we later want only the “main module’s declarations”, we’ll filter by module
-- name or by the interface of the main file.
dumpSignatureAsJsonl :: Handle -> FilePath -> TCM ()
dumpSignatureAsJsonl h file = do
  sig <- getSignature

  -- Agda 2.8.x: Signature exposes `_sigDefinitions` (NOT `sigDefinitions`).
  -- Your compile error and GHC hint confirm this field name.
  let defs = HM.toList (_sigDefinitions sig)

  forM_ defs $ \(qname, defn) -> do
    qnTxt <- pp qname
    tyTxt <- pp (defType defn)

    let astSize = cheapSize tyTxt
        kind    = "definition"  -- v0 placeholder; refine later.

        line =
          jsonObj
            [ ("file",    jsonStr (T.pack file))
            , ("qname",   jsonStr qnTxt)
            , ("type",    jsonStr tyTxt)
            , ("kind",    jsonStr kind)
            , ("astSize", jsonNum astSize)
            ]

    liftIO $ hPutStrLn h (T.unpack line)

--------------------------------------------------------------------------------
-- Pretty printing inside TCM
--------------------------------------------------------------------------------

-- | Pretty-print an Agda internal thing using Agda’s own pretty-printer,
-- inside the typechecking monad.
pp :: PrettyTCM a => a -> TCM T.Text
pp x = do
  doc <- prettyTCM x
  pure (T.pack (prettyShow doc))

--------------------------------------------------------------------------------
-- Tiny JSON encoder (no extra deps)
--------------------------------------------------------------------------------

-- | Render a JSON object from already-rendered JSON values.
-- (Keys are rendered as JSON strings.)
jsonObj :: [(T.Text, T.Text)] -> T.Text
jsonObj kvs =
  "{" <> T.intercalate "," (map field kvs) <> "}"
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

-- | Render a codepoint as four hex digits.
hex4 :: Int -> String
hex4 n =
  let h = "0123456789abcdef"
      d0 = h !! ((n `div` 4096) `mod` 16)
      d1 = h !! ((n `div` 256)  `mod` 16)
      d2 = h !! ((n `div` 16)   `mod` 16)
      d3 = h !! (n `mod` 16)
  in [d0, d1, d2, d3]

-- | Render a JSON number (only Int for now).
jsonNum :: Int -> T.Text
jsonNum = T.pack . show

-- | Cheap feature: the character length of some text.
cheapSize :: T.Text -> Int
cheapSize = T.length
