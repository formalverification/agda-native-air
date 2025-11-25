/** ============================================================================
 *  Model.scala (shim)
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/Model.scala
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
 *  Package: proofparser
 *
 *  Description
 *  -----------
 *  Legacy compatibility layer.
 *
 *  Historically this file defined AgdaData and normalization helpers.
 *  It now forwards directly to the canonical definitions in:
 *
 *     proofparser.schema.AgdaSchema.scala
 *
 *  New code should always import from the schema package directly.
 *  The original version of Model.scala resides in the proofparser.legacy package.
 *  ============================================================================ */
package proofparser
import proofparser.schema.{ AgdaData, AgdaDataOps, TrainRecord }
object Model {
  // Type alias for backwards compatibility
  type AgdaData = proofparser.schema.AgdaData
  type TrainRecord = proofparser.schema.TrainRecord
  // Forwarders to canonical implementation
  def normalize(r: AgdaData): AgdaData = AgdaDataOps.normalize(r)
  def asTrainRecord(r: AgdaData): TrainRecord = AgdaDataOps.asTrainRecord(r)
}

