/** ============================================================================
  *  ActionsSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/search/ActionsSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins #112 lesson two — the partial-application arithmetic
  *  (drop_first_k_visible) — and the candidate constructor built on it,
  *  including a property over arbitrary telescopes: supplied arguments consume
  *  visible binders only, hidden and instance binders pass through untouched
  *  and are never granted holes.
  *
  *  ============================================================================
  */
package struxdriver.search

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import org.scalatestplus.scalacheck.ScalaCheckPropertyChecks
import org.scalacheck.Gen
import Visibility._

final class ActionsSpec extends AnyFunSuite with Matchers with ScalaCheckPropertyChecks {

  private def v(t: String) = Binder(Visible, t)
  private def h(t: String) = Binder(Hidden, t)
  private def i(t: String) = Binder(Instance, t)

  test("drop_first_k_visible: visible binders are consumed in order") {
    val tele = Vector(v("A"), v("B"), v("C"))
    Actions.remainingAfterApply(tele, 0) shouldBe tele
    Actions.remainingAfterApply(tele, 2) shouldBe Vector(v("C"))
    Actions.remainingAfterApply(tele, 3) shouldBe Vector.empty
    Actions.remainingAfterApply(tele, 9) shouldBe Vector.empty
  }

  test("drop_first_k_visible: hidden and instance binders pass through untouched") {
    // The exact shape that is easy to get wrong: hidden binders interleaved.
    val tele = Vector(h("ℓ"), v("A"), h("x"), i("Eq A"), v("B"), h("y"))
    Actions.remainingAfterApply(tele, 1) shouldBe Vector(h("ℓ"), h("x"), i("Eq A"), v("B"), h("y"))
    Actions.remainingAfterApply(tele, 2) shouldBe Vector(h("ℓ"), h("x"), i("Eq A"), h("y"))
  }

  test("applicationCandidate: one hole per REMAINING visible binder") {
    Actions.applicationCandidate("sym", Actions.symBinders, Vector.empty) shouldBe "sym {!!}"
    Actions.applicationCandidate("cong", Actions.congBinders, Vector("suc")) shouldBe "cong suc {!!}"
    Actions.applicationCandidate("cong", Actions.congBinders, Vector("suc", "p")) shouldBe "cong suc p"
    Actions.applicationCandidate("suc", Actions.sucBinders, Vector.empty) shouldBe "suc {!!}"
  }

  private val genBinder: Gen[Binder] = for {
    vis <- Gen.oneOf[Visibility](Visible, Hidden, Instance)
    t   <- Gen.alphaStr.map(s => if (s.isEmpty) "T" else s.take(6))
  } yield Binder(vis, t)

  test("property: k supplied arguments remove exactly min(k, visible) visible binders and nothing else") {
    forAll(Gen.listOf(genBinder).map(_.toVector), Gen.chooseNum(0, 8)) { (tele: Vector[Binder], k: Int) =>
      val remaining  = Actions.remainingAfterApply(tele, k)
      val visBefore  = tele.count(_.visibility == Visible)
      val visAfter   = remaining.count(_.visibility == Visible)
      visAfter shouldBe math.max(0, visBefore - k)
      // Hidden/instance binders survive with multiplicity and order preserved.
      remaining.filter(_.visibility != Visible) shouldBe tele.filter(_.visibility != Visible)
      // And the constructor grants holes to remaining VISIBLE binders only.
      val cand = Actions.applicationCandidate("f", tele, Vector.fill(k)("a"))
      cand.sliding(4).count(_ == "{!!}") shouldBe visAfter
    }
  }

  test("the stub action space is fixed at k=6 and includes both closers and multi-obligation shapes") {
    val space = Actions.stubActionSpace
    space should have size 6
    space should contain ("refl")
    space should contain ("tt")
    space should contain ("sym {!!}")
    space should contain ("cong suc {!!}")
  }
}
