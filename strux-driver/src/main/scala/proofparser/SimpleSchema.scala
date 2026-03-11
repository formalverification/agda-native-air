/** ============================================================================
 *  SimpleSchema.scala (shim)
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/SimpleSchema.scala
 *  Package: proofparser
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  Legacy compatibility for modules that previously imported
 *  TrainRecord from this file.
 *
 *  All definitions now live in `proofparser.schema.AgdaSchema.scala`.
 * ============================================================================ */
package proofparser
import proofparser.schema.TrainRecord
object SimpleSchema {
  type TrainRecord = proofparser.schema.TrainRecord
}
