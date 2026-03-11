/** ============================================================================
 *  Semantic.scala
 *  --------------
 *
 *  File: strux-driver/src/main/scala/proofparser/schema/Semantic.scala
 *  Package: proofparser.schema
 *  Copyright: (c) 2024 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  A set of utilities for classifying Agda declarations based on syntactic heuristics
 *  and later Agda reflection. This is meant to be the semantic “kernel” everything
 *  else will lean on.
 *
 *  Usage
 *  -----
 *      import proofparser.{DeclKind, SemanticInfo, Semantic}
 *      val info = Semantic.from(name, agdaType, module, proof)
 *
 *  Notes
 *  -----
 *  -  This is deliberately lightweight and coarse-grained.
 *  -  The main purpose is to provide signals for filtering, prioritization, and
 *     curriculum learning.
 *  -  Keep stable to avoid breaking existing corpora.
 *
 *  ============================================================================
 */

package proofparser.schema

import upickle.default.{ReadWriter, macroRW}


/**
 * Semantic
 * --------
 * Utility functions for guessing/deriving SemanticInfo from the
 * syntactic surface (name, type, proof). AgdaExtractor will call
 * into this *after* it has done any reflection/elaboration it wants.
 *
 * For "hybrid" mode we can later add hooks that:
 *   - start from guessKind(...)
 *   - adjust based on elaborated Agda info
 */
object Semantic {

  /**
   * Syntactic heuristic for DeclKind, based only on the name and maybe type.
   * This is deliberately cheap and conservative.
   */
  def guessKind(
    name: String,
    agdaType: Option[String],
    module: Option[String]
  ): DeclKind = {
    val n  = name.trim
    val nl = n.toLowerCase

    // name-based hints
    if (nl.contains("lemma"))   DeclKind.Lemma
    else if (nl.contains("thm") || nl.contains("theorem")) DeclKind.Theorem
    else if (nl.contains("axiom")) DeclKind.Axiom
    else if (nl.startsWith("record") || module.exists(_.toLowerCase.contains("record")))
      DeclKind.Record
    else if (nl.startsWith("data") || module.exists(_.toLowerCase.contains("data")))
      DeclKind.Data
    else if (nl.headOption.exists(_.isUpper)) {
      // Uppercase at head often signals data/record/constructor, but we keep it generic:
      DeclKind.Constructor
    } else {
      // Fallback: treat as definition; Agda reflection can refine this later.
      DeclKind.Definition
    }
  }

  /**
   * Cheap "AST-size" estimate by counting tokens in type and proof.
   * This is purely textual for now; later we can swap this out for a
   * reflection-based node count while preserving the signature.
   */
  def estimateAstSize(
    agdaType: Option[String],
    proof: Option[String]
  ): Int = {
    def tokens(sOpt: Option[String]): Int =
      sOpt.fold(0)(s => s.split("\\s+").count(_.nonEmpty))

    tokens(agdaType) + tokens(proof)
  }

  /**
   * Entry point used by AgdaExtractor:
   *
   *   - use syntactic guessKind(...) as the starting point;
   *   - compute a simple astSize;
   *   - later: allow "hybrid" refinement by injecting elaborated info.
   */
  def from(
    name: String,
    agdaType: Option[String],
    module: Option[String],
    proof: Option[String]
  ): SemanticInfo = {
    val kind    = guessKind(name, agdaType, module)
    val astSize = estimateAstSize(agdaType, proof)
    SemanticInfo(kind, astSize)
  }
}
