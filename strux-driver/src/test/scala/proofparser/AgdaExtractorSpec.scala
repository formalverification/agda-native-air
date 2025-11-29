/** ============================================================================
 *  AgdaExtractorSpec.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/test/scala/proofparser/AgdaExtractorSpec.scala
 *  Package: proofparser
 *  Copyright: (c) 2024 Thmpr Lab, LLC.
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

class AgdaExtractorSpec extends AnyFlatSpec with Matchers {

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

  // -------------------------------------------------------------

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

  // -------------------------------------------------------------

  behavior of "collectTheorems"

  it should "extract a single, simple (name : type) theorem" in {
    val src =
      """|module TestModule where
         |Thm1 : A → B
         |Thm1 = f x
         |""".stripMargin

    val got = AgdaExtractor.collectTheorems(src.linesIterator.toList)
    // API returns List[(name, typeString)]
    got should contain ("Thm1" -> "A → B")
  }

  it should "extract multiple theorems" in {
    val src =
      """|prop1 : A → A
         |prop1 = ...
         |prop2 : B → B
         |prop2 = ...
         |""".stripMargin

    val got = AgdaExtractor.collectTheorems(src.linesIterator.toList)
    got.map(_._1).toSet shouldBe Set("prop1", "prop2")
  }

  it should "ignore comments and non-definitions" in {
    val src =
      """|-- this is a comment
         |{- block comment -}
         |module Example where
         |someValue = 42
         |""".stripMargin

    val got = AgdaExtractor.collectTheorems(src.linesIterator.toList)
    // Your current extractor filters these out; expect empty.
    got shouldBe Nil
  }
}
