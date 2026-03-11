/** ===========================================================================
 *  SimpleSchemaSpec.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: strux-driver/src/test/scala/struxdriver/SimpleSchemaSpec.scala
 *  Package: struxdriver
 *
 *  Description
 *  -----------
 *  Simple round-trip unit test using the `TrainRecord`.
 ** ============================================================================= */

package struxdriver

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import upickle.default._

import struxdriver.schema.TrainRecord

final class SimpleSchemaSpec extends AnyFunSuite with Matchers {

  test("TrainRecord JSON round-trip via upickle") {
    val rec = TrainRecord(
      module   = "Algebra.Group",
      name     = "assoc",
      agdaType = "∀ x y z → x ⋆ (y ⋆ z) ≡ (x ⋆ y) ⋆ z",
      proof    = "λ x y z → proof_0",
      premises = "Algebra.Group.left-id Algebra.Group.right-id"
    )

    val json = write(rec)
    val back = read[TrainRecord](json)

    back shouldBe rec
  }
}
