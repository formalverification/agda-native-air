package proofparser

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import upickle.default._

final class SimpleSchemaSpec extends AnyFunSuite with Matchers {
  test("TrainRecord round-trip and normalization") {
    val rec = TrainRecord(
      file = "Foo.agda",
      module = "Foo._.properties.agda.",
      decl = "lem<12>",
      context = List(CtxVar("x", "ℕ")),
      goalType = "A → B",
      solution = Some("..."),
      range = Some(Range(Pos(1,1), Pos(2,3))),
      imports = List("Data.Nat")
    )
    val norm = TrainRecordOps.normalize(rec)
    norm.module shouldBe "Foo.properties"
    norm.decl   shouldBe "lem"
    val json = write(norm)
    read[TrainRecord](json) shouldBe norm
  }
}
