/** ============================================================================
  *  ProposeSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/search/ProposeSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins the P1 proposal machinery (issue #122): the `using`-import parser on
  *  real fixture text, the deliberately small pi-type splitter on types AS
  *  THE LANE PRINTED THEM (every case below was captured from the live
  *  server's type_of during the #122 wire probes), the peek compatibility
  *  matcher on the same captured material, and the fixed proposer's ordering
  *  and dedup.
  *
  *  ============================================================================
  */
package struxdriver.search

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import cats.effect.IO
import cats.effect.unsafe.implicits.global
import Visibility._

final class ProposeSpec extends AnyFunSuite with Matchers {

  // --------------------------------------------------------------------------
  // Imports.usingNames — the fixture's lemma pool
  // --------------------------------------------------------------------------

  test("usingNames: every name in every using list, in file order, deduped") {
    val src =
      """module Nat-plus-comm where
        |
        |open import AgdaDojang.Debug
        |
        |open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ )
        |open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong ; sym )
        |open import Data.Nat.Properties using ( +-identityʳ ; +-suc )
        |""".stripMargin
    Imports.usingNames(src) shouldBe Vector(
      "ℕ", "zero", "suc", "_+_", "_≡_", "refl", "cong", "sym", "+-identityʳ", "+-suc")
  }

  test("usingNames: an import without a using list contributes nothing") {
    Imports.usingNames("open import AgdaDojang.Debug\nopen import Relation.Nullary using ( Dec ; yes ; no )\n") shouldBe
      Vector("Dec", "yes", "no")
  }

  // --------------------------------------------------------------------------
  // Actions.bindersOfPrinted — the pi splitter, on lane-printed types
  // --------------------------------------------------------------------------

  private def visible(printed: String): Int =
    Actions.bindersOfPrinted(printed).count(_.visibility == Visible)

  test("splitter: simple function types (suc, _+_)") {
    visible("ℕ → ℕ") shouldBe 1
    visible("ℕ → ℕ → ℕ") shouldBe 2
  }

  test("splitter: hidden telescopes pass through with no holes (sym, cong — live captures)") {
    // type_of sym, verbatim (newline included as the lane printed it):
    visible("{A.a : Agda.Primitive.Level} {A : Set A.a} {x y : A} →\nx ≡ y → y ≡ x") shouldBe 1
    // type_of cong, verbatim — the (f : A → y) group is the first visible:
    visible("{A.a : Agda.Primitive.Level} {A : Set A.a}\n{B.a = x : Agda.Primitive.Level} {B = y : Set x} (f : A → y)\n{x = x₁ : A} {y = y₁ : A} →\nx₁ ≡ y₁ → f x₁ ≡ f y₁") shouldBe 2
  }

  test("splitter: named visible binders, multi-name groups (+-identityʳ, +-suc — live captures)") {
    visible("(A.a : ℕ) → A.a + 0 ≡ A.a") shouldBe 1
    visible("(A.a A : ℕ) → A.a + suc A ≡ suc (A.a + A)") shouldBe 2
  }

  test("splitter: meta-typed lemmas and dependent pairs (z≤n, s≤s, _,_ — live captures)") {
    visible("0 ≤ _n_5") shouldBe 0
    visible("_m_5 ≤ _n_6 → suc _m_5 ≤ suc _n_6") shouldBe 1
    visible("(fst : _A_10) (snd : _B_11 fst) → Data.Product.Base.Σ _A_10 _B_11") shouldBe 2
  }

  test("splitter: arrows inside groups do not split; a parenthesized domain is one visible") {
    visible("(A → B) → C") shouldBe 1
    visible("Set") shouldBe 0
  }

  test("splitter feeds the landed candidate constructor") {
    val binders = Actions.bindersOfPrinted("(fst : _A_10) (snd : _B_11 fst) → Data.Product.Base.Σ _A_10 _B_11")
    Actions.applicationCandidate("_,_", binders, Vector.empty) shouldBe "_,_ {!!} {!!}"
    Actions.applicationCandidate("z≤n", Actions.bindersOfPrinted("0 ≤ _n_5"), Vector.empty) shouldBe "z≤n"
  }

  // --------------------------------------------------------------------------
  // Peek — meta form and the compatibility matcher
  // --------------------------------------------------------------------------

  test("metaForm: every hole becomes a meta") {
    Peek.metaForm("cong suc {!!}") shouldBe "cong suc _"
    Peek.metaForm("_,_ {!!} {!!}") shouldBe "_,_ _ _"
    Peek.metaForm("refl") shouldBe "refl"
  }

  test("compatible: metas are wildcards (live shapes vs live goals)") {
    // refl at +-identityˡ: inferred _x_9 ≡ _x_9, goal displays n ≡ n.
    Peek.compatible("n ≡ n", "_x_9 ≡ _x_9") shouldBe true
    // sym _ at +-comm: two independent metas match anything ≡-shaped.
    Peek.compatible("m + n ≡ n + m", "_y_8 ≡ _x_7") shouldBe true
    // s≤s _ at 0 < suc n (displays 1 ≤ suc n once normalised).
    Peek.compatible("1 ≤ suc n", "suc _m_5 ≤ suc _n_6") shouldBe true
    // _,_ _ _ at the pair goal, qualified Σ on both sides.
    Peek.compatible("Data.Product.Base.Σ A (λ x → B)", "Data.Product.Base.Σ _A_10 _B_11") shouldBe true
  }

  test("compatible: the same meta must match the same text (the refl-vs-comm case)") {
    // refl at +-comm: _x_9 ≡ _x_9 cannot describe m + n ≡ n + m.
    Peek.compatible("m + n ≡ n + m", "_x_9 ≡ _x_9") shouldBe false
  }

  test("compatible: literal mismatches reject (the shapes fill_hole would refuse)") {
    // suc _ : ℕ at an equality goal.
    Peek.compatible("n ≡ n", "ℕ") shouldBe false
    // cong suc _ : suc-headed sides at a goal whose sides are not suc-headed.
    Peek.compatible("m + n ≡ n + m", "suc _x_9 ≡ suc _y_10") shouldBe false
    // A Set-typed candidate at a value goal.
    Peek.compatible("m + n ≡ n + m", "Set") shouldBe false
  }

  test("judge: in-body errors reject, lane failures keep (peeks inform, never veto by absence)") {
    val err = TypeOfBody(None, Some(TypeOfError("NotInScope", "tt is not in scope")), 2)
    Peek.judge("⊤", Right(err)) shouldBe a[Peek.Verdict.Reject]
    Peek.judge("⊤", Left("lane died")) shouldBe Peek.Verdict.Keep
    Peek.judge("n ≡ n", Right(TypeOfBody(Some("_x_9 ≡ _x_9"), None, 1))) shouldBe Peek.Verdict.Keep
    Peek.judge("n ≡ n", Right(TypeOfBody(Some("ℕ"), None, 1))) shouldBe a[Peek.Verdict.Reject]
  }

  // --------------------------------------------------------------------------
  // FixedProposer — ordering and dedup
  // --------------------------------------------------------------------------

  test("fixed proposer: closers, then assumptions, then applications cheap-first; duplicates keep first") {
    val fixtureSrc =
      """module M where
        |open import Data.Nat.Base using ( suc ; _+_ )
        |open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; sym )
        |""".stripMargin
    val types = Map(
      "suc"  -> "ℕ → ℕ",
      "_+_"  -> "ℕ → ℕ → ℕ",
      "_≡_"  -> "{A : Set} → A → A → Set",
      "refl" -> "_x_1 ≡ _x_1",
      "sym"  -> "{x y : A} → x ≡ y → y ≡ x"
    )
    val proposer = FixedProposer.create(fixtureSrc,
      name => IO.pure(Right(types.get(name)): Either[String, Option[String]])).unsafeRunSync()
    val goal = GoalView("m + n ≡ n + m", Vector(CtxEntry("m", "ℕ", None), CtxEntry("n", "ℕ", None)), None)
    val state = SearchState.initial("module M where\ngoal : T\ngoal = {!!}\n", Vector(Obligation(3, 8, "?")))
    val cands = proposer.propose(state, state.obligations.head, goal).unsafeRunSync()

    // Closers first; assumptions next; then applications ordered by remaining
    // holes (refl at 0 — deduped against the closer — then suc/sym at 1 in
    // import order, then the 2-hole applications).
    cands shouldBe Vector(
      "refl", "tt",                  // closers ("refl" the lemma dedups into this slot)
      "m", "n",                      // assumptions in context order
      "(suc {!!})", "(sym {!!})",    // 1-hole applications, import order, parenthesized
      "(_+_ {!!} {!!})", "(_≡_ {!!} {!!})") // 2-hole applications, import order
  }

  test("fixed proposer: a lemma the lane cannot type stays out of the space") {
    val src = "module M where\nopen import X using ( mystery ; suc )\n"
    val proposer = FixedProposer.create(src, {
      case "suc" => IO.pure(Right(Some("ℕ → ℕ")): Either[String, Option[String]])
      case _     => IO.pure(Left("lane failure"): Either[String, Option[String]])
    }).unsafeRunSync()
    val goal  = GoalView("ℕ", Vector.empty, None)
    val state = SearchState.initial("module M where\ngoal : T\ngoal = {!!}\n", Vector(Obligation(3, 8, "?")))
    proposer.propose(state, state.obligations.head, goal).unsafeRunSync() shouldBe
      Vector("refl", "tt", "(suc {!!})")
  }
}
