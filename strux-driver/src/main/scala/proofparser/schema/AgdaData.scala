/** ============================================================================
 *  AgdaData.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/schema/AgdaData.scala
 *  Package: proofparser.schema
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  Canonical schema for Agda “theorem-like” declarations
 *  (definitions, postulates, theorems, lemmas, etc.).
 *
 *  Usage
 *  -----
 *     import proofparser.schema.{AgdaData, AgdaDataOps}
 *     val record = AgdaDataOps.normalize(AgdaData(...))
 *
 *  Notes
 *  -----
 *  - Keep stable to avoid breaking existing corpora.
 *  - Centralize normalization logic in AgdaDataOps.
 *
 * ============================================================================
 */

package proofparser.schema

import upickle.default._

/**
  * Canonical representation of one “theorem-like” Agda declaration
  * as seen by the ML pipeline.
  *
  * Intended invariants (after [[AgdaDataOps.normalize]]):
  *
  *   - `file`:
  *       non-empty, trimmed absolute (or repo-relative) path.
  *
  *   - `module`:
  *       Some(trimmedName) for normal modules;
  *       None only when the extractor genuinely has no module.
  *
  *   - `name`:
  *       bare declaration name, trimmed. No module prefix.
  *
  *   - `agdaType`, `proof`:
  *       whitespace-normalized (collapsed to single spaces),
  *       no leading/trailing whitespace.
  *
  *   - `premises`:
  *       unique, sorted, whitespace-normalized names of
  *       other declarations this one depends on.
  *
  * This shape is meant to be:
  *   - friendly to git/JSONL (no huge nested structures),
  *   - easy to map to Spark Datasets/DataFrames,
  *   - a stable contract between “extractor” and “trainer”.
  */
final case class AgdaData(
  file: String,
  module: Option[String],
  name: String,
  agdaType: String,
  proof: String,
  premises: List[String]
)

object AgdaData {

  /** upickle JSON (de)serialization */
  implicit val rw: ReadWriter[AgdaData] = macroRW

  /**
    * Convenience constructor for legacy call-sites that don’t care about
    * optional module and premises normalization yet.
    */
  def fromLegacy(
    file: String,
    module: Option[String],
    name: String,
    agdaType: String,
    proof: String,
    premises: Seq[String]
  ): AgdaData =
    AgdaData(
      file      = file,
      module    = module,
      name      = name,
      agdaType  = agdaType,
      proof     = proof,
      premises  = premises.toList
    )
}

/**
  * Pure helper operations on [[AgdaData]].
  *
  * Kept separate from the case class so they feel more like
  * “library utilities” than methods with hidden side effects.
  */
object AgdaDataOps {

  /** Collapse all whitespace to single spaces and trim. */
  private def stripWhitespace(s: String): String =
    s.replaceAll("\\s+", " ").trim

  /**
    * Normalize premise list:
    *   - strip whitespace from each name,
    *   - drop empties,
    *   - deduplicate,
    *   - sort for a stable order.
    */
  private def canonicalPremises(ps: List[String]): List[String] =
    ps.map(stripWhitespace)
      .filter(_.nonEmpty)
      .distinct
      .sorted

  /**
    * Return a normalized copy of the record satisfying the invariants
    * documented on [[AgdaData]].
    */
  def normalize(r: AgdaData): AgdaData =
    r.copy(
      file     = r.file.trim,
      module   = r.module.map(_.trim).filter(_.nonEmpty),
      name     = r.name.trim,
      agdaType = stripWhitespace(r.agdaType),
      proof    = stripWhitespace(r.proof),
      premises = canonicalPremises(r.premises)
    )
}
