package proofparser

import org.scalatest.funsuite.AnyFunSuite
import upickle.default._

import proofparser.AgdaExtractor._ // or wherever you defined it

class AgdaExtractorSpec extends AnyFunSuite {

  test("extractModule should find the correct module name") {
    val result = extractModuleName(List("module My.Module.Name where"))
    assert(result.contains("My.Module.Name"))
  }

  test("isTheoremLike should detect a theorem line correctly") {
    val theoremLine = "myTheorem : A -> B"
    assert(isTheoremLike(theoremLine))
  }

  test("isTheoremLike should reject irrelevant lines") {
    val nonTheoremLine = "open import Something"
    assert(!isTheoremLike(nonTheoremLine))
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

    val theorems = collectTheorems(lines.toList)
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
    val theorems = collectTheorems(lines.toList)
    assert(theorems.map(_._1).toSet == Set("prop1", "prop2"))
  }

  test("collectTheorems should ignore comments and non-definitions") {
    val lines = Seq(
      "-- this is a comment",
      "{- block comment -}",
      "module Example where",
      "someValue = 42"
    )
    val theorems = collectTheorems(lines.toList)
    assert(theorems.map(_._1).toSet == Set("someValue"))
  }

  test("Declaration followed by proof.") {
   val lines = Seq(
     "Thm1 : A → B",
     "Thm1 = f x"
   )
   val expected = Seq(AgdaData("file.agda", Some("TestModule"), "Thm1", "A → B", "f x"))
   assert(extractTheorems(lines, "file.agda", Some("TestModule")) == expected)
  }

  test("Proof without preceding declaration.") {
   val lines = Seq(
     "Thm1 = f x"
   )
   val expected = Seq(AgdaData("file.agda", Some("TestModule"), "Thm1", "", "f x"))
   assert(extractTheorems(lines, "file.agda", Some("TestModule")) == expected)
  }

  test("Test 3: Declaration without proof.") {
   val lines = Seq(
     "Thm2 : X × Y"
   )
   val expected = Seq(AgdaData("file.agda", Some("TestModule"), "Thm2", "X × Y", ""))
   assert(extractTheorems(lines, "file.agda", Some("TestModule")) == expected)
  }

  test("Test 4: Multiple theorems") {
   val lines = Seq(
     "Thm1 : A → B",
     "Thm1 = f x",
     "Thm2 : X × Y",
     "Thm2 = pair x y"
   )
   val expected = Seq(
     AgdaData("file.agda", Some("TestModule"), "Thm1", "A → B", "f x"),
     AgdaData("file.agda", Some("TestModule"), "Thm2", "X × Y", "pair x y")
   )
   assert(extractTheorems(lines, "file.agda", Some("TestModule")) == expected)
  }
}
