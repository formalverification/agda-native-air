/** ============================================================================
 *  AgdaDataOpsSpec.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/test/scala/proofparser/AgdaDataOpsSpec.scala
 *  Package: proofparser
 *  Copyright: (c) 2024 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  Focused tests on the normalization invariants for `AgdaDataOps.normalize`.
 *
 *  Run: `sbt test`
 *
 ** =========================================================================== */
package proofparser

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

import proofparser.schema.{ AgdaData, AgdaDataOps, DeclKind }

/** ========================================================================
  *  AgdaDataOpsSpec
  *  ------------------------------------------------------------------------
  *
  *  Focused tests on the normalization invariants for `AgdaDataOps.normalize`.
  *
  *  Invariants covered:
  *    - normalization never increases the number of premises
  *    - normalized premises are non-empty and duplicate-free
  *    - obvious self-premises are removed
  *    - basic identity fields (file / module / name / type / proof)
  *      are preserved when already well-formed
  *    - angle-bracket variants collapse to a single canonical premise
  * ======================================================================== */
final class AgdaDataOpsSpec extends AnyFunSuite with Matchers {

  /** Small helper to construct minimal AgdaData rows in tests. */
  private def mkRow(
    file:     String         = "Foo.agda",
    module:   Option[String] = Some("Foo"),
    name:     String         = "lem",
    agdaType: Option[String] = Some("A → B"),
    proof:    Option[String] = Some("lem = ?"),
    premises: List[String]   = Nil
  ): AgdaData =
    AgdaData(
      file      = file,
      module    = module,
      name      = name,
      agdaType  = agdaType,
      proof     = proof,
      premises  = premises,
      declKind  = DeclKind.Theorem,
      astSize   = 1
    )

  test("normalize never increases the number of premises") {
    val original = mkRow(
      premises = List("Foo.lem", "Bar.lem", "Foo.lem", "", "   ")
    )

    val normalized = AgdaDataOps.normalize(original)

    normalized.premises.size should be <= original.premises.size
  }

  test("normalize removes empty and duplicate premises") {
    val original = mkRow(
      premises = List(" Foo.lem ", "Foo.lem", "Bar.lem", "", "   ")
    )

    val normalized = AgdaDataOps.normalize(original)

    // no empty premises
    normalized.premises.foreach { p =>
      p.trim.isEmpty shouldBe false
    }

    // duplicates removed
    normalized.premises.distinct shouldEqual normalized.premises
  }

  test("normalize drops obvious self-premises") {
    val original = mkRow(
      file     = "Foo.agda",
      module   = Some("Foo"),
      name     = "lem",
      premises = List(
        "lem",
        "Foo.lem",
        "Foo.agda.lem",
        "Other.Module.otherLemma"
      )
    )

    val normalized = AgdaDataOps.normalize(original)

    normalized.premises shouldNot contain ("lem")
    normalized.premises shouldNot contain ("Foo.lem")
    normalized.premises shouldNot contain ("Foo.agda.lem")
    normalized.premises should contain ("Other.Module.otherLemma")
  }

  test("normalize preserves basic identity fields when already clean") {
    val original = mkRow(
      file     = "Foo.agda",
      module   = Some("Foo"),
      name     = "lem",
      agdaType = Some("A → B"),
      proof    = Some("lem = ?"),
      premises = List("Other.Module.otherLemma")
    )

    val normalized = AgdaDataOps.normalize(original)

    normalized.file     shouldEqual "Foo.agda"
    normalized.module   shouldEqual Some("Foo")
    normalized.name     shouldEqual "lem"
    normalized.agdaType shouldEqual Some("A → B")
    normalized.proof    shouldEqual Some("lem = ?")
  }

  test("normalize strips angle-bracket markup from premises") {
    val original = mkRow(
      premises = List(
        "Foo.<1>lem",
        "<2>Foo.lem",
        "Bar.<123>.other"
      )
    )

    val normalized = AgdaDataOps.normalize(original)

    normalized.premises.nonEmpty shouldBe true

    // No angle-bracket markup should remain.
    normalized.premises.foreach { p =>
      p.contains("<") shouldBe false
      p.contains(">") shouldBe false
    }
  }
}
