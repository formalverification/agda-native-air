/** ============================================================================
 *  SimpleSchema.scala (shim)
 *  ----------------------------------------------------------------------------
 *
 *  File: strux-driver/src/main/scala/struxdriver/SimpleSchema.scala
 *  Package: struxdriver
 *
 *  Description
 *  -----------
 *  Legacy compatibility for modules that previously imported
 *  TrainRecord from this file.
 *
 *  All definitions now live in `struxdriver.schema.AgdaSchema.scala`.
 * ============================================================================ */
package struxdriver
import struxdriver.schema.TrainRecord
object SimpleSchema {
  type TrainRecord = struxdriver.schema.TrainRecord
}
