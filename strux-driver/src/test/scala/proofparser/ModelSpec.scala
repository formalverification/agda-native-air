/** ============================================================================
 *  ModelSpec.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/test/scala/proofparser/ModelSpec.scala
 *  Package: proofparser
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  Unit tests for `AgdaData`, `AgdaDataOps`, and `asTrainRecord`.
 *  Specifically tests the normalization function to ensure it removes
 *  self-premises correctly.
 *
 * =============================================================================
 */

package proofparser

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

class ModelSpec extends AnyFunSuite with Matchers {
  test("AgdaDataOps.normalize removes self-premises") {
    val r = AgdaData(
      file     = "agda-example.agda",
      module   = Some("properties"),
      name     = "+-suc<40>",
      agdaType = "A",
      proof    = "P",
      premises = List(
        "agda-example.properties.+-suc<40>",
        "agda-example.agda.properties.+-suc"
      )
    )
    val cleaned = AgdaDataOps.normalize(r)
    cleaned.premises shouldBe empty
    cleaned.file shouldBe "agda-example" // baseFile applied
  }
}
