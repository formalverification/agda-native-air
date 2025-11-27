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

import proofparser.schema._
import proofparser.schema.AgdaDataOps

final class ModelSpec extends AnyFunSuite with Matchers {

  test("AgdaDataOps.normalize trims whitespace and drops obvious self-premises") {
    val raw = AgdaData(
      file     = " src/Properties.agda ",
      module   = Some("  Foo.Bar  "),
      name     = "  +-suc<40> ",
      agdaType = Some("  A  "),
      proof    = Some("  P  "),
      premises = List(
        " Foo.Bar.+-suc<40> ",   // self-premise (should be dropped)
        " Foo.Baz.other-lemma "  // keep
      ),
      declKind = DeclKind.Theorem,
      astSize  = 42
    )

    val cleaned = AgdaDataOps.normalize(raw)

    cleaned.file shouldBe "src/Properties.agda"
    cleaned.module shouldBe Some("Foo.Bar")
    cleaned.name shouldBe "+-suc<40>"
    cleaned.agdaType shouldBe Some("A")
    cleaned.proof shouldBe Some("P")

    // self-premise should be gone
    cleaned.premises.exists(_.contains("+-suc<40>")) shouldBe false

    // but non-self premise should survive (normalized)
    cleaned.premises.exists(_.contains("other-lemma")) shouldBe true
  }

  test("AgdaDataOps.asTrainRecord flattens premises into a space-separated string") {
    val r = AgdaData(
      file     = "F.agda",
      module   = Some("M"),
      name     = "n",
      agdaType = Some("A → B"),
      proof    = Some("P"),
      premises = List("p1", "p2"),
      declKind = DeclKind.Theorem,
      astSize  = 1
    )

    val t = AgdaDataOps.asTrainRecord(r)

    t.module   shouldBe "M"
    t.name     shouldBe "n"
    t.agdaType shouldBe "A → B"
    t.proof    shouldBe "P"
    t.premises shouldBe "p1 p2"
  }
}
