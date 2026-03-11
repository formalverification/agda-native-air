/** ============================================================================
 *  Model.scala (shim)
 *  ----------------------------------------------------------------------------
 *
 *  File: strux-driver/src/main/scala/struxdriver/Model.scala
 *  Package: struxdriver
 *
 *  Description
 *  -----------
 *  Legacy compatibility layer.
 *
 *  Historically this file defined AgdaData and normalization helpers.
 *  It now forwards directly to the canonical definitions in:
 *
 *     struxdriver.schema.AgdaSchema.scala
 *
 *  New code should always import from the schema package directly.
 *  ============================================================================ */
package struxdriver
import struxdriver.schema.{ AgdaData, AgdaDataOps, TrainRecord }
object Model {
  // Type alias for backwards compatibility
  type AgdaData = struxdriver.schema.AgdaData
  type TrainRecord = struxdriver.schema.TrainRecord
  // Forwarders to canonical implementation
  def normalize(r: AgdaData): AgdaData = AgdaDataOps.normalize(r)
  def asTrainRecord(r: AgdaData): TrainRecord = AgdaDataOps.asTrainRecord(r)
}

