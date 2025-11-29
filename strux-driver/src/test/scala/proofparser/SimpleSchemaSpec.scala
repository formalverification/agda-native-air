/** ===========================================================================
 *  SimpleSchemaSpec.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/test/scala/proofparser/SimpleSchemaSpec.scala
 *  Package: proofparser
 *
 *  Description
 *  -----------
 *  Simple round-trip unit test using the `TrainRecord`.
 ** ============================================================================= */
package proofparser

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import upickle.default._

final class SimpleSchemaSpec extends AnyFunSuite with Matchers {
  test("TrainRecord round-trip and normalization") {
    // Test TrainRecordOps
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

    // Test serialization
    val json = write(norm)
    read[TrainRecord](json) shouldBe norm

    // Additional normalization cases
    val norm2 = TrainRecordOps.normalize(
      TrainRecord("X.agda", "A._.B.agda.", "n<1>", Nil, "T")
    )
    norm2.module shouldBe "A.B"

  }
}
