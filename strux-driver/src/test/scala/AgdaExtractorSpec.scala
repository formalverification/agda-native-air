package proofparser

import org.scalatest.funsuite.AnyFunSuite
import upickle.default._
// import AgdaExtractor // or wherever you defined it

class AgdaExtractorSpec extends AnyFunSuite {

  test("extractModule should find the correct module name") {
    val result = AgdaExtractor.extractModuleName(List("module My.Module.Name where"))
    assert(result.contains("My.Module.Name"))
  }

  test("isTheoremLike should detect a theorem line correctly") {
    val theoremLine = "myTheorem : A -> B"
    assert(AgdaExtractor.isTheoremLike(theoremLine))
  }

  test("isTheoremLike should reject irrelevant lines") {
    val nonTheoremLine = "open import Something"
    assert(!AgdaExtractor.isTheoremLike(nonTheoremLine))
  }

  test("collectTheorems should extract single-line theorem definitions") {
    val lines = Seq(
      "module MyMod where",
      "myThm : A -> B",
      "myThm = ...",
      "",
      "another : X"
    )
  // def collectTheorems(lines: List[String]): List[(String, String)] = {

    val theorems = AgdaExtractor.collectTheorems(lines.toList)
    assert(theorems.exists(_._1 == "myThm"))
    assert(theorems.exists(_._2.contains("A -> B")))
  }

  test("collectTheorems should handle multiple theorems") {
    val lines = Seq(
      "prop1 : A -> A",
      "prop1 = ...",
      "prop2 : B -> B",
      "prop2 = ...",
    )
    val theorems = AgdaExtractor.collectTheorems(lines.toList)
    assert(theorems.map(_._1).toSet == Set("prop1", "prop2"))
  }

  test("collectTheorems should ignore comments and non-definitions") {
    val lines = Seq(
      "-- this is a comment",
      "{- block comment -}",
      "module Example where",
      "someValue = 42"
    )
    val theorems = AgdaExtractor.collectTheorems(lines.toList)
    assert(theorems.map(_._1).toSet == Set("someValue"))
  }
}
