/** ============================================================================
 *  AgdaExtractorProps.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/test/scala/proofparser/AgdaExtractorProps.scala
 *  Package: proofparser
 *  Copyright: (c) 2024 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  Property-based tests for AgdaExtractor.
 *
 *  Run: `sbt test`
 ** ============================================================================ */

package proofparser

import org.scalatest.wordspec.AnyWordSpec
import org.scalatest.matchers.should.Matchers
import org.scalatestplus.scalacheck.ScalaCheckPropertyChecks
import org.scalacheck.Gen

import proofparser.extract.AgdaExtractor
import proofparser.schema.AgdaData

/**
 * Property-based tests for AgdaExtractor.
 *
 * Uses:
 *   - TestKit.genIdent / arbIdent for theorem names
 *   - ScalaCheckPropertyChecks.forAll for properties
 */
final class AgdaExtractorProps
    extends AnyWordSpec
    with Matchers
    with ScalaCheckPropertyChecks
    with TestKit {

  // ---------------------------------------------------------------------------
  // Generators
  // ---------------------------------------------------------------------------

  // Non-empty "type" or "rhs" strings: keep it simple (letters only).
  private val genNonEmptyAlpha: Gen[String] =
    Gen.nonEmptyListOf(Gen.alphaChar).map(_.mkString)

  // ---------------------------------------------------------------------------
  // Properties for removeComments
  // ---------------------------------------------------------------------------

  "removeComments" should {
    "never return lines starting with line or block comment markers" in {
      forAll { lines: List[String] =>
        val cleaned = AgdaExtractor.removeComments(lines)

        cleaned.foreach { line =>
          val t = line.trim
          t.startsWith("--") shouldBe false
          t.startsWith("{-") shouldBe false
          t.startsWith("-}") shouldBe false
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Properties for isTheoremLike
  // ---------------------------------------------------------------------------

  "isTheoremLike" should {
    "always return false for comment and block-comment-start lines" in {
      forAll { body: String =>
        AgdaExtractor.isTheoremLike(s"-- $body") shouldBe false
        AgdaExtractor.isTheoremLike(s"{- $body") shouldBe false
        AgdaExtractor.isTheoremLike("")          shouldBe false
        AgdaExtractor.isTheoremLike("   ")       shouldBe false
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Properties for extractTheorems
  // ---------------------------------------------------------------------------

  "extractTheorems" should {
    "round-trip a synthesized (name : type) + (name = rhs) pair into one AgdaData row" in {
      forAll(genIdent, genNonEmptyAlpha, genNonEmptyAlpha) {
        (name: String, tpeBody: String, rhsBody: String) =>
          val src =
            s"""$name : $tpeBody
               |$name = $rhsBody
               |""".stripMargin

          val lines = src.linesIterator.toList
          val rows  = AgdaExtractor.extractTheorems(
            lines,
            fileName   = "Test.agda",
            moduleName = None
          )

          rows should have length 1
          val r = rows.head

          r.name                shouldBe name
          r.agdaType.value      shouldBe tpeBody
          r.proof.value         shouldBe rhsBody
          r.file                shouldBe "Test.agda"
          r.module              shouldBe None
        }
    }

    "not emit rows for forbidden first tokens like `postulate`, `module`, etc." in {
      val forbidden = List(
        "postulate", "open", "import", "module",
        "data", "record", "mutual", "where",
        "infix", "infixl", "infixr", "syntax", "pragma", "private"
      )

      forAll(Gen.oneOf(forbidden), genNonEmptyAlpha, genNonEmptyAlpha) {
        (kw: String, tpeBody: String, rhsBody: String) =>
          val src =
            s"""$kw : $tpeBody
               |$kw = $rhsBody
               |""".stripMargin

          val lines = src.linesIterator.toList
          val rows  = AgdaExtractor.extractTheorems(
            lines,
            fileName   = "Forbidden.agda",
            moduleName = None
          )

          rows shouldBe empty
      }
    }
  }
}
