/**
 * ModelSpec.scala
 *
 * FILE
 *   proof-parser/src/test/scala/proofparser/ModelSpec.scala
 *
 * DESCRIPTION
 *   Unit tests for AgdaData and AgdaDataOps.
 *   Specifically tests the normalization function to ensure it removes
 *   self-premises correctly.
 *
 * (c) 2025 Thmpr Lab, LLC.
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
