/** ============================================================================
 *  AgdaEndToEndSpec.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: strux-driver/src/test/scala/proofparser/AgdaEndToEndSpec.scala
 *  Package: proofparser
 *
 *  Description
 *  -----------
 *  A small integration-style test that exercises the full "lightweight" pipeline.
 * ============================================================================ */


package proofparser

import java.nio.file.{ Files, Paths }
import java.nio.charset.StandardCharsets

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

import upickle.default._

import proofparser.extract.AgdaExtractor
import proofparser.schema.{ AgdaData, AgdaDataOps }

/** ========================================================================
  *  AgdaEndToEndSpec
  *  ------------------------------------------------------------------------
  *
  *  A small integration-style test that exercises the full "lightweight"
  *  pipeline:
  *
  *    .agda source
  *      → regex extractor (AgdaExtractor)
  *      → normalization (AgdaDataOps.normalize)
  *      → JSONL-style encoding / decoding via upickle
  *
  *  This is intentionally minimal and does not require calling Agda.
  * ======================================================================== */
final class AgdaEndToEndSpec extends AnyFunSuite with Matchers {

  private val agdaSource: String =
    """module SimpleTheorems where

       open import Agda.Builtin.Nat

       lemma₁ : Nat
       lemma₁ = 0

       lemma₂ : Nat
       lemma₂ = 1
       """.stripMargin

  test("regex extractor + normalization + JSONL round-trip") {
    // Write a temporary .agda file so the test is fully self-contained.
    val tmpDir   = Files.createTempDirectory("agda-end-to-end")
    val agdaPath = tmpDir.resolve("SimpleTheorems.agda")

    Files.write(agdaPath, agdaSource.getBytes(StandardCharsets.UTF_8))

    val lines: List[String] = {
      val src = scala.io.Source.fromFile(agdaPath.toFile, "UTF-8")
      try src.getLines().toList
      finally src.close()
    }

    val rawRows: Vector[AgdaData] =
      AgdaExtractor.extractTheorems(
        lines      = lines,
        fileName   = agdaPath.toString,
        moduleName = Some("SimpleTheorems")
      )
    rawRows.size shouldBe 2

    val normalized: Vector[AgdaData] = rawRows.map(AgdaDataOps.normalize)

    // Basic structural invariants on the rows.
    normalized.foreach { r =>
      r.file should include ("SimpleTheorems.agda")
      r.module shouldEqual Some("SimpleTheorems")
      r.name.nonEmpty shouldBe true
    }

    // JSONL-style encoding (one JSON object per line) using upickle.
    val jsonLines: Vector[String] = normalized.map(write(_: AgdaData))

    jsonLines.size shouldBe normalized.size

    // Extra safety: decode back and compare.
    val decoded: Vector[AgdaData] = jsonLines.map(str => read[AgdaData](str))
    decoded shouldEqual normalized
  }
}
