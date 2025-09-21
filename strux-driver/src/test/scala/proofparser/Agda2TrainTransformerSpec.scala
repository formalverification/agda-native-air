/**
 * Unit tests for Agda2TrainTransformer
 *
 * File: agda-ai-prover/proof-parser/src/test/scala/proofparser/Agda2TrainTransformerSpec.scala
 *
 * Copyright (c) 2024 Thmpr.
 */

package proofparser

import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers
import scala.io.Source

class Agda2TrainTransformerSpec extends AnyFlatSpec with Matchers {

  "extractAgdaDataFromJson" should "correctly extract name, type, and proof from agda2train JSON output" in {
    val testJsonPath = "/home/williamdemeo/git/AI/PROJECTS/agda-ai-prover/proof-parser/src/test/resources/agda-example.json"
    val rawData = Source.fromFile(testJsonPath).getLines().mkString
    println(s"Raw data length: ${rawData.length}")

    val jsonData = ujson.read(rawData)
    println(s"Parsed JSON keys: ${jsonData.obj.keys.mkString(", ")}")

    if (jsonData.obj.contains("name")) {
      println(s"Name found: ${jsonData("name").str}")
    } else {
      println("Name not found!")
    }

    val agdaDataList = Agda2TrainTransformer.extractAgdaDataFromJson(testJsonPath)

    // Check that the list is not empty
    agdaDataList should not be empty

    // Check a specific theorem that we know exists in the agda-example.json
    val expectedData = AgdaData(
      file = "agda-example.agda",
      module = Some("agda-example"),
      name = "+-comm",
      agdaType = "(m n : ℕ) → (m + n) ≡ (n + m)",
      proof = "+-comm zero zero = refl | +-comm zero (suc n) = cong suc (+-comm zero n) | +-comm (suc m) zero = cong suc (+-comm m zero) | +-comm (suc m) (suc n) = cong suc (trans (agda-example.+-suc m n m n) (+-comm (suc m) n))"
    )

    agdaDataList should contain (expectedData)
  }

  it should "handle missing or malformed JSON gracefully" in {
    val invalidJsonPath = "path/to/nonexistent.json"
    val result = Agda2TrainTransformer.extractAgdaDataFromJson(invalidJsonPath)
    result shouldBe empty
  }

  it should "return empty when the JSON structure does not contain expected fields" in {
    val malformedJsonPath = "path/to/malformed.json"
    val result = Agda2TrainTransformer.extractAgdaDataFromJson(malformedJsonPath)
    result shouldBe empty
  }

  it should "handle cases where the type or proof is missing" in {
    val incompleteJsonPath = "path/to/incomplete.json"
    val result = Agda2TrainTransformer.extractAgdaDataFromJson(incompleteJsonPath)

    // Check that the result is empty or properly handled
    result shouldBe empty
  }
}
