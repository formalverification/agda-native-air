package proofparser
// import proofparser.AgdaExtractor._

import utest._
import proofparser.Agda2TrainTransformer.extractAgdaDataFromJson

object Agda2TrainTransformerSpec extends TestSuite {

  val tests = Tests {

    test("Extract Agda Data from JSON") {
      // Test with a sample JSON file path
      val jsonPath = "./src/test/resources/agda-example.json"

      // Expected result
      val expected = Seq(
        AgdaData(
          file = "agda-example.agda",
          module = Some("agda-example"),
          name = "+-comm",
          typ = "(m n : ℕ) → m + n ≡ n + m",
          proof = "+-comm zero     zero     = refl"
                + "+-comm zero     (suc n)  = cong suc (+-comm zero n)"
                + "+-comm (suc m)  zero     = cong suc (+-comm m zero)"
                + "+-comm (suc m)  (suc n)  = cong suc (trans (+-suc m n) (+-comm (suc m) n))"
                + "where +-suc : ∀ m n → m + suc n ≡ suc (m + n)"
                + "+-suc zero     n = refl"
                + "+-suc (suc m)  n = cong suc (+-suc m n)"
        ),
        AgdaData(
          file = "agda-example.agda",
          module = Some("agda-example"),
          name = "_+_",
          typ = "ℕ → ℕ → ℕ",
          proof = "zero   + n = n"
                + "suc m  + n = suc (m + n)"
        )
      )

      // Call the extraction function
      val result = extractAgdaDataFromJson(jsonPath)

      // Assert that the result matches the expected output
      assert(result == expected)
    }

    test("Handle Missing Module Name") {
      // Test with a JSON file that lacks the module name
      val jsonPath = "./src/test/resources/missingModule.json"
      val result = extractAgdaDataFromJson(jsonPath)

      assert(result.head.module.isEmpty) // Ensure the module is None
    }

    test("Handle Missing File Name") {
      // Test with a JSON file that lacks the file name
      val jsonPath = "./src/test/resources/missingFile.json"
      val result = extractAgdaDataFromJson(jsonPath)

      assert(result.head.file == "Unknown") // Ensure the file name defaults to "Unknown"
    }

    test("Empty Proof or Name Handling") {
      // Test with a JSON file that has an empty proof or name
      val jsonPath = "./src/test/resources/emptyFields.json"
      val result = extractAgdaDataFromJson(jsonPath)

      assert(result.isEmpty) // Should be an empty sequence since name/proof are missing
    }

    test("Complex Proof Extraction") {
      // Test with a JSON file containing multiline proofs
      val jsonPath = "./src/test/resources/complexProof.json"
      val result = extractAgdaDataFromJson(jsonPath)

      assert(result.nonEmpty)
      assert(result.head.proof.contains("\n")) // Check if proof contains new lines
    }
  }
}
