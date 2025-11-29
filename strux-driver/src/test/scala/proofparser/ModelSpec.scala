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

import proofparser.schema.{AgdaData, AgdaDataOps, DeclKind}

final class ModelSpec extends AnyFunSuite with Matchers {

  test("AgdaDataOps.normalize removes simple self-premises") {
    val r = AgdaData(
      file     = "agda-example.agda",
      module   = Some("properties"),
      name     = "+-suc<40>",
      agdaType = Some("A"),
      proof    = Some("P"),
      premises = List(
        // These match the current selfIdVariants logic in AgdaDataOps
        "agda-example.+-suc<40>",   // shortFile.name
        "properties.+-suc<40>",     // module.name
        "+-suc<40>"                 // bare name
      ),
      declKind = DeclKind.Definition,
      astSize  = 0
    )

    val cleaned = AgdaDataOps.normalize(r)

    cleaned.premises shouldBe empty
    cleaned.file     shouldBe "agda-example.agda"
    cleaned.module   shouldBe Some("properties")
    cleaned.name     shouldBe "+-suc<40>"
  }
}
