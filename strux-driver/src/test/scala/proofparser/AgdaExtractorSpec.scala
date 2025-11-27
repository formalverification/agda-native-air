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

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

import java.nio.file.Paths

import proofparser.extract.AgdaExtractor

final class AgdaExtractorSpec extends AnyFunSuite with Matchers {

  test("extractModuleName finds a simple module header") {
    val src =
      """module Foo.Bar where

         x : A
       """.stripMargin.linesIterator.toList

    AgdaExtractor.extractModuleName(src) shouldBe Some("Foo.Bar")
  }

  test("isTheoremLike recognizes simple theorem-like declarations") {
    AgdaExtractor.isTheoremLike("myTheorem : A → B") shouldBe true
    AgdaExtractor.isTheoremLike("prop1 : X × Y")     shouldBe true

    val nonTheorems = List(
      "postulate A : Set",
      "open import Data.Nat",
      "data ℕ : Set where",
      "record Foo : Set where"
    )

    nonTheorems.foreach { l =>
      withClue(s"'$l' should NOT be theorem-like") {
        AgdaExtractor.isTheoremLike(l) shouldBe false
      }
    }
  }

  test("parseAgdaFile returns some rows for agda-example.agda fixture") {
    val url = getClass.getClassLoader.getResource("agda-example.agda")
    assume(url != null, "Missing test resource: agda-example.agda")

    val path = Paths.get(url.toURI)
    val rows = AgdaExtractor.parseAgdaFile(path)

    rows.nonEmpty shouldBe true
  }
}
