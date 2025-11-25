/** ============================================================================
 *  Row.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/schema/Row.scala
 *  Package: proofparser.schema
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  This module defines the core `Row` type that we use in evaluation / small
 *  analyses: a denormalised view of one declaration with its premises expanded as a
 *  sequence.
 *
 *  Usage
 *  -----
 *      import proofparser.schema.Row
 *      val row = Row.fromAgdaData(agdaData)
 *
 * ============================================================================
 */
package proofparser.schema

import upickle.default._

/**
  * Denormalised representation of a declaration used in evaluation
  * and small-scale analysis tools.
  *
  * Compared to [[AgdaData]]:
  *   - `module` is a plain String (for convenience when tabulating),
  *   - `premises` is a Vector instead of List (nice for indexing),
  *   - everything is fully materialised, ready for JSON lines or
  *     Spark Datasets.
  *
  * This type deliberately stays “minimal”; if you need additional
  * derived metrics (lengths, counts, etc.), prefer defining a
  * separate StatsRow or similar in the analysis module.
  */
final case class Row(
  name: String,
  module: String,
  agdaType: String,
  proof: String,
  premises: Vector[String]
)

object Row {

  implicit val rw: ReadWriter[Row] = macroRW

  /**
    * Convert from the canonical [[AgdaData]].
    *
    * Missing module is rendered as "<none>" to keep the field total.
    */
  def fromAgdaData(d: AgdaData): Row =
    Row(
      name      = d.name,
      module    = d.module.getOrElse("<none>"),
      agdaType  = d.agdaType,
      proof     = d.proof,
      premises  = d.premises.toVector
    )
}
