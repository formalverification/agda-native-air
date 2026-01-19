{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

-- | StructAst.hs
--
-- File: agda-backend-jsonl/src/AgdaJsonl/StructAst.hs
--
-- Structural AST encoder for Agda internal syntax (v0).
--
-- This module converts Agda's internal representation of types/terms
-- ('Agda.Syntax.Internal') into a small JSON AST intended for downstream ML/ETL.
--
-- Goals:
--   + Total: never throws; unknown constructors are bucketed as "Other*".
--   + Stable-ish: tags/field names should evolve conservatively (versioned).
--   + Useful structure: preserve binders (Pi/Lam), application spines, hiding.
--
-- Non-goals (for v0):
--   + Full fidelity reconstruction of surface syntax.
--   + Exhaustive coverage of all Agda internal constructors.
--
-- The top-level encoding of a type is:
--   { "tag": "Type", "sort": <sort>, "term": <term> }
--
-- Version: 0.3-v0 (see 'typeAstVersion' in JSONL rows).

module AgdaJsonl.StructAst
  ( typeToAst
  ) where

import Data.Aeson (Value, object, (.=))
import qualified Data.Text as T

import Agda.TypeChecking.Monad (TCM)

import qualified Agda.Syntax.Internal as I
import Agda.Syntax.Common (Hiding(..), Arg(..), getHiding)  -- Arg is common for Apply args
import Agda.Syntax.Common.Pretty (prettyShow, pretty)


-- NOTE:
-- This is a "v0" encoder: covers common constructors and buckets the rest.
-- It is deliberately total (never fails).

-----------------------------------------------------------------------------
-- Levels
-----------------------------------------------------------------------------

-- Agda 2.8.0:
--   type Level = Level' Term
--   data Level' t      = Max Integer [PlusLevel' t]
--   data PlusLevel' t  = Plus Integer t
--
-- For v0 we keep it simple but structural:
--   { tag: "Level", max: <int>, plus: [ { k: <int>, atom: <term-ast> }, ... ] }

-- | Convert Agda Level to AST
levelToAst :: I.Level' I.Term -> Value
levelToAst = \case
  I.Max n ps ->
    object
      [ "tag"  .= ("Level" :: T.Text)
      , "max"  .= n
      , "plus" .= fmap plusLevelToAst ps
      ]
  _ ->
    -- Fallback for future/unknown Level' constructors to preserve totality.
    object
      [ "tag" .= ("OtherLevel" :: T.Text)
      ]

-- | Convert Agda PlusLevel to AST
plusLevelToAst :: I.PlusLevel' I.Term -> Value
plusLevelToAst = \case
  I.Plus k t ->
    object
      [ "k"    .= k
      , "atom" .= termToAst t
      ]
  other ->
    object
      [ "tag" .= ("OtherPlusLevel" :: T.Text)
      , "ctor" .= ctorName other
      ]

-- | Convert Agda Type to AST
typeToAst :: I.Type -> TCM Value
typeToAst = \case
  I.El s t ->
    pure $ object
      [ "tag"  .= ("Type" :: T.Text)
      , "sort" .= sortToAst s
      , "term" .= termToAst t
      ]

-- | Convert Agda Sort to AST
sortToAst :: I.Sort -> Value
sortToAst = \case
  -- These constructors are typical in Agda internals; if any name differs
  -- in the Agda build, adjust the patterns accordingly.
  I.Type l ->
    object [ "tag" .= ("Set" :: T.Text), "level" .= levelToAst l ]
  I.Prop l ->
    object [ "tag" .= ("Prop" :: T.Text), "level" .= levelToAst l ]
  I.Inf _ _ ->
    object [ "tag" .= ("Inf" :: T.Text) ]
  other ->
    object [ "tag" .= ("OtherSort" :: T.Text), "ctor" .= ctorName other ]


-- | Convert Agda Term to AST
termToAst :: I.Term -> Value
termToAst = \case
  I.Var ix es ->
    object [ "tag" .= ("Var" :: T.Text)
           , "ix"  .= ix
           , "elims" .= fmap elimToAst es
           ]

  I.Def q es ->
    object [ "tag" .= ("Def" :: T.Text)
           , "qname" .= prettyQName q
           , "elims" .= fmap elimToAst es
           ]

  I.Con ch _ci es ->
    object [ "tag" .= ("Con" :: T.Text)
           , "qname" .= prettyConHead ch
           , "elims" .= fmap elimToAst es
           ]

  I.Lam info absBody ->
    object
      [ "tag"      .= ("Lam" :: T.Text)
      , "hiding"   .= hidingToText (getHiding info)
      , "nameHint" .= absNameHint absBody
      , "body"     .= termToAst (absBodyTerm absBody)
      ]

  I.Pi dom cod ->
    object
      [ "tag"    .= ("Pi" :: T.Text)
      , "binder" .= object
          [ "hiding"   .= hidingToText (getHiding (I.domInfo dom))
          , "nameHint" .= absNameHint cod
          ]
      , "dom"    .= typeToAstPure (I.unDom dom)
      , "cod"    .= typeToAstPure (absBodyType cod)
      ]

  I.Lit lit ->
    object [ "tag" .= ("Lit" :: T.Text), "lit" .= T.pack (show lit) ]

  I.Sort s ->
    object [ "tag" .= ("Sort" :: T.Text), "sort" .= sortToAst s ]

  I.MetaV m es ->
    object
      [ "tag"  .= ("Meta" :: T.Text)
      , "id"   .= T.pack (show m)
      , "elims" .= fmap elimToAst es
      ]

  I.DontCare t ->
    object [ "tag" .= ("DontCare" :: T.Text), "term" .= termToAst t ]

  t ->
    object [ "tag" .= ("Other" :: T.Text), "ctor" .= ctorName t ]


-- | Eliminations (application spine)
elimToAst :: I.Elim -> Value
elimToAst = \case
  I.Apply (Arg ai t) ->
    object
      [ "tag"    .= ("Apply" :: T.Text)
      , "hiding" .= hidingToText (getHiding ai)
      , "term"   .= termToAst t
      ]

  I.Proj _projOrigin q ->
    object
      [ "tag"   .= ("Proj" :: T.Text)
      , "qname" .= prettyQName q
      ]

  e ->
    object
      [ "tag"  .= ("OtherElim" :: T.Text)
      , "ctor" .= ctorName e
      ]


-- -----------------------------------------------------------------------------
-- Small helpers
-- ------------------------------------------------------------------------------
hidingToText :: Hiding -> T.Text
hidingToText = \case
  NotHidden  -> "explicit"
  Hidden     -> "implicit"
  Instance{} -> "instance"

-- Abs helpers (names differ slightly across Agda versions; these patterns usually work)
absNameHint :: I.Abs a -> Maybe T.Text
absNameHint = \case
  I.Abs x _   -> Just (T.pack x)
  I.NoAbs _ _ -> Nothing

absBodyTerm :: I.Abs I.Term -> I.Term
absBodyTerm = \case
  I.Abs _ b   -> b
  I.NoAbs _ b -> b

absBodyType :: I.Abs I.Type -> I.Type
absBodyType = \case
  I.Abs _ b   -> b
  I.NoAbs _ b -> b

-- Since typeToAst is in TCM, but termToAst is pure, we encode nested types in Pi
-- by stripping the outer El and calling termToAst.
typeToAstPure :: I.Type -> Value
typeToAstPure (I.El s t) =
  object
    [ "tag"  .= ("Type" :: T.Text)
    , "sort" .= sortToAst s
    , "term" .= termToAst t
    ]

prettyQName :: I.QName -> T.Text
prettyQName = T.pack . prettyShow . pretty

prettyConHead :: I.ConHead -> T.Text
prettyConHead = prettyQName . I.conName

ctorName :: Show a => a -> T.Text
ctorName = T.pack . take 64 . show
