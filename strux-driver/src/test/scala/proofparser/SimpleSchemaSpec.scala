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

import proofparser.schema._

final class SimpleSchemaSpec extends AnyFunSuite with Matchers {

  test("TrainRecord JSON round-trip via upickle") {
    val rec = TrainRecord(
      module   = "Foo._.Bar.agda.",
      name     = "lem<12>",
      agdaType = "A → B",
      proof    = "proof term",
      premises = "p1 p2"
    )

    val json = write(rec)
    val back = read[TrainRecord](json)

    back shouldBe rec
  }
}
