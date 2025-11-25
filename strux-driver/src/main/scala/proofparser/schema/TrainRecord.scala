/** ============================================================================
 *  TrainRecord.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/schema/TrainRecord.scala
 *  Package: proofparser.schema
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  Flat, string-only representation used by downstream ETL/ML code
 *  (JSONL → CSV → Parquet) where premises are squashed into a single string column.
 *
 *  Usage
 *  -----
 *     import proofparser.schema.TrainRecord
 *     val record = TrainRecord.fromAgdaData(agdaData)
 *
 *  Notes
 *  -----
 *  - Keep stable to avoid breaking existing corpora.
 *
 *  ============================================================================
 */

package proofparser.schema

/**
  * Flat, string-only representation used by downstream ETL/ML code.
  *
  * This is intentionally simpler than [[AgdaData]]:
  *   - `module` is always a String (no Option) so it can be a single column.
  *   - `premises` are concatenated into one string, which plays nicer with
  *     basic feature extractors or simple text models.
  *
  * Higher-level code (Spark, Python trainers) can decide whether to:
  *   - treat these as raw text fields; or
  *   - explode the `premises` string back into a sequence.
  */
final case class TrainRecord(
  module: String,
  name: String,
  agdaType: String,
  proof: String,
  premises: String
)

object TrainRecord {

  /**
    * Lossy but convenient projection from [[AgdaData]] to [[TrainRecord]].
    *
    * Design choices:
    *   - missing module → "<none>" (so it remains a single string column),
    *   - premises joined by spaces (simple and token-friendly).
    */
  def fromAgdaData(d: AgdaData): TrainRecord = {
    val moduleString = d.module.getOrElse("<none>")
    val premisesStr  = d.premises.mkString(" ")
    TrainRecord(
      module   = moduleString,
      name     = d.name,
      agdaType = d.agdaType,
      proof    = d.proof,
      premises = premisesStr
    )
  }
}
