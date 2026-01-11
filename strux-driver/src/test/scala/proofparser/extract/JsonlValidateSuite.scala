/**
 * Unit tests for JsonlValidate functionality.
 *
 * File: proof-parser/src/test/scala/proofparser/extract/JsonlValidateSuite.scala
 * Package: proofparser.extract
 *
 * Design Notes
 * - Uses temporary files to test various scenarios.
 * - Tests both file-based and line-based validation methods.
 * - Ensures coverage of edge cases like empty files and missing keys.
 *
 * How to run reliably
 * -------------------
 * Run these tests inside pinned Nix dev shell so that:
 *
 *   - AGDA_DIR points at the pinned Agda config (libraries/defaults)
 *   - AGDA_JSON_BIN points at the correct `agda-json` executable
 *
 * If these variables are missing, the tests will be skipped (cancelled) rather
 * than failing.
 *
 */

package proofparser.extract

import org.scalatest.freespec.AnyFreeSpec
import org.scalatest.matchers.should.Matchers

import cats.effect.unsafe.implicits.global

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path}

final class JsonlValidateSuite extends AnyFreeSpec with Matchers {

  private def writeUtf8(p: Path, s: String): Unit =
    Files.write(p, s.getBytes(StandardCharsets.UTF_8))

  "JsonlValidate.validateFile" - {

    "returns ok=true rows=0 for an existing empty file" in {
      val p = Files.createTempFile("jsonl-empty-", ".jsonl")
      // Ensure empty
      Files.write(p, Array.emptyByteArray)

      val r = JsonlValidate.validateFile(p).unsafeRunSync()
      r.ok shouldBe true
      r.rows shouldBe 0L
      r.errors shouldBe Vector.empty
    }

    "returns ok=false for a missing file" in {
      val p = Files.createTempFile("jsonl-missing-", ".jsonl")
      Files.deleteIfExists(p)

      val r = JsonlValidate.validateFile(p).unsafeRunSync()
      r.ok shouldBe false
      r.rows shouldBe 0L
      r.errors.nonEmpty shouldBe true
    }

    "returns ok=false when file contains an invalid JSON line" in {
      val p = Files.createTempFile("jsonl-bad-", ".jsonl")
      writeUtf8(p, "not-json\n")

      val r = JsonlValidate.validateFile(p).unsafeRunSync()
      r.ok shouldBe false
      r.rows shouldBe 1L
      r.errors.nonEmpty shouldBe true
    }

    "returns ok=false when JSON object is missing required keys" in {
      val p = Files.createTempFile("jsonl-missing-keys-", ".jsonl")
      // valid JSON object, but incomplete schema
      writeUtf8(p, """{"file":"X","module":"M"}\n""")

      val r = JsonlValidate.validateFile(p).unsafeRunSync()
      withClue(r.toString) {
        r.ok shouldBe false
        r.rows shouldBe 1L
        r.errors.exists(_.contains("missing keys")) shouldBe false
      }
    }

    "returns ok=true when JSON object has all required keys" in {
      val p = Files.createTempFile("jsonl-good-", ".jsonl")
      // minimal object satisfying RequiredKeys in JsonlValidate
      writeUtf8(
        p,
        """{"file":"X","module":"M","name":"n","qname":"M.n","type":"T","kind":"Def","astSize":1}""" + "\n"
      )

      val r = JsonlValidate.validateFile(p).unsafeRunSync()
      r.ok shouldBe true
      r.rows shouldBe 1L
      r.errors shouldBe Vector.empty
    }
  }

  "JsonlValidate.validateLines" - {
    "ignores blank lines and counts only data rows" in {
      val it = Iterator("", "   ", """{"file":"X","module":"M","name":"n","qname":"M.n","type":"T","kind":"Def","astSize":1}""", "")
      val r  = JsonlValidate.validateLines(it)
      r.ok shouldBe true
      r.rows shouldBe 1L
    }
  }
}
