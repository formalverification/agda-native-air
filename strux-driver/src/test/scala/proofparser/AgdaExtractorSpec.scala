/** ============================================================================
 *  AgdaExtractorSpec.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: strux-driver/src/test/scala/proofparser/AgdaExtractorSpec.scala
 *  Package: proofparser
 *
 *  Description
 *  -----------
 *  Unit tests for the pure, text-based utilities in AgdaExtractor.
 *  This suite intentionally does NOT spin up Agda or the JSON bridge.
 *  It verifies the current public API surface of AgdaExtractor:
 *
 *      - extractModuleName(lines: List[String]): Option[String]
 *      - isTheoremLike(line: String): Boolean
 *      - collectTheorems(lines: List[String]): List[(String, String)]
 *
 *  Design Notes
 *  ------------
 *  * We assert behavior, not implementation details.
 *  * We keep the tests deterministic with tiny inlined sources.
 *  * The “ignore comments/non-definitions” test expects an EMPTY result,
 *    matching your recent run where "someValue" was (correctly) filtered.
 *
 *  Run: `sbt test`
 *
 ** ============================================================================ */

package proofparser

import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers
import org.scalatest.OptionValues

import proofparser.extract.AgdaExtractor
import proofparser.schema.AgdaData

final class AgdaExtractorSpec extends AnyFlatSpec
  with Matchers
  with OptionValues {

  behavior of "extractModuleName"

  it should "find the declared module name when present" in {
    val src =
      """|module My.Module.Name where
         |postulate A : Set
         |""".stripMargin

    val got = AgdaExtractor.extractModuleName(src.linesIterator.toList)
    got shouldBe Some("My.Module.Name")
  }

  it should "return None when no module is declared" in {
    val src =
      """|-- no module here
         |postulate A : Set
         |""".stripMargin

    val got = AgdaExtractor.extractModuleName(src.linesIterator.toList)
    got shouldBe None
  }

  // ---------------------------------------------------------------------------

  behavior of "isTheoremLike"

  it should "detect a theorem-like declaration (name : type)" in {
    AgdaExtractor.isTheoremLike("myTheorem : A → B") shouldBe true
    AgdaExtractor.isTheoremLike("prop1 : X × Y")     shouldBe true
  }

  it should "reject comments and irrelevant lines" in {
    val lines = List(
      "-- comment",
      "open import Data.Nat",
      "postulate A : Set",
      "someValue = 42" // not a theorem declaration
    )
    lines.foreach { l =>
      AgdaExtractor.isTheoremLike(l) shouldBe false
    }
  }

  // ---------------------------------------------------------------------------

  behavior of "extractTheorems"

  it should "extract a single, simple (name : type) theorem" in {
    val src =
      """|module TestModule where
         |Thm1 : A → B
         |Thm1 = f x
         |""".stripMargin

    val lines  = src.linesIterator.toList
    val module = AgdaExtractor.extractModuleName(lines)
    val rows   = AgdaExtractor.extractTheorems(lines, fileName = "TestModule.agda", moduleName = module)

    rows should have size 1
    val only = rows.head

    only.name shouldBe "Thm1"
    only.agdaType.value shouldBe "A → B"
    only.proof.value    shouldBe "f x"
  }

  it should "extract multiple theorems" in {
    val src =
      """|prop1 : A → A
         |prop1 = ...
         |prop2 : B → B
         |prop2 = ...
         |""".stripMargin

    val lines  = src.linesIterator.toList
    val rows   = AgdaExtractor.extractTheorems(lines, fileName = "NoModule.agda", moduleName = None)
    val names  = rows.map(_.name).toSet

    names shouldBe Set("prop1", "prop2")
  }

  it should "ignore comments and non-definitions" in {
    val src =
      """|-- this is a comment
         |{- block comment -}
         |module Example where
         |someValue = 42
         |""".stripMargin

    val lines = src.linesIterator.toList
    val rows  = AgdaExtractor.extractTheorems(lines, fileName = "Example.agda", moduleName = AgdaExtractor.extractModuleName(lines))

    rows shouldBe empty
  }
}
