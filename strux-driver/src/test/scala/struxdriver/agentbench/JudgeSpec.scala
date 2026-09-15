/** ============================================================================
  *  JudgeSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/JudgeSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins the agent-bench judge's syntactic gates (issue #154) before any
  *  model call: a gold passes every gate with no restatement evidence; the
  *  obligation itself fails the hole gate; a weakened signature fails
  *  preservation; a postulate and a pragma fail the escape gate; a file that
  *  names the library original (qualified, through a module alias, by import,
  *  or bare on a primed agda-algebras row) is flagged restated.  Then the same
  *  gates over every committed obligation/gold pair of the benchmark index,
  *  so the suite's own golds are the regression fixture.  Pure: no Agda.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Paths}
import scala.jdk.CollectionConverters._

final class JudgeSpec extends AnyFunSuite with Matchers {

  private val obligation: String =
    """-- Nat-plus-comm.agda
      |--
      |-- Benchmark obligation: stdlib-nat-plus-comm
      |--
      |module Nat-plus-comm where
      |
      |open import AgdaDojang.Debug
      |
      |open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ )
      |open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong ; sym )
      |
      |-- Prerequisites (provided, not to be proved here)
      |open import Data.Nat.Properties using ( +-identityʳ ; +-suc )
      |
      |+-comm : ∀ (m n : ℕ) → m + n ≡ n + m
      |+-comm m n = {!!}
      |""".stripMargin

  private val header: String =
    """module Nat-plus-comm where
      |
      |open import AgdaDojang.Debug
      |
      |open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ )
      |open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong ; sym )
      |
      |open import Data.Nat.Properties using ( +-identityʳ ; +-suc )
      |
      |""".stripMargin

  private val gold: String = header +
    """+-comm : ∀ (m n : ℕ) → m + n ≡ n + m
      |+-comm zero    n = sym (+-identityʳ n)
      |+-comm (suc m) n = begin
      |  suc m + n     ≡⟨⟩
      |  suc (m + n)   ≡⟨ cong suc (+-comm m n) ⟩
      |  suc (n + m)   ≡⟨ sym (+-suc n m) ⟩
      |  n + suc m     ∎
      |  where open import Relation.Binary.PropositionalEquality.Properties
      |              using ( module ≡-Reasoning )
      |        open ≡-Reasoning
      |""".stripMargin

  private val st: Statement = Statement.of(obligation, "+-comm").toOption.get

  private def firstGate(text: String): Option[String] = Judge.syntactic(st, text)._1.map(_.gate)

  test("statement: module line, four import lines, one signature, frozen blocks exclude the clause") {
    st.moduleLine shouldBe "module Nat-plus-comm where"
    st.importLines.size shouldBe 4
    st.signature shouldBe Vector("+-comm : ∀ (m n : ℕ) → m + n ≡ n + m")
    st.frozenBlocks.size shouldBe 6
    st.frozenBlocks.exists(_.head.startsWith("+-comm m n")) shouldBe false
  }

  test("gold passes every syntactic gate, logs its where-block import, and has no restatement evidence") {
    val (gate, added, evidence) = Judge.syntactic(st, gold)
    gate shouldBe None
    added shouldBe Vector("open import Relation.Binary.PropositionalEquality.Properties")
    evidence shouldBe Vector.empty
  }

  test("the obligation itself fails on the hole gate") {
    firstGate(obligation) shouldBe Some("holes")
  }

  test("a `{! ... !}` hole and a lone `?` are holes; `?` inside a name is not") {
    firstGate(header + "+-comm : ∀ (m n : ℕ) → m + n ≡ n + m\n+-comm m n = {! refl !}\n") shouldBe Some("holes")
    firstGate(header + "+-comm : ∀ (m n : ℕ) → m + n ≡ n + m\n+-comm m n = ?\n") shouldBe Some("holes")
    Gates.holes("f = g _≟_ x\n") shouldBe Right(())
    Gates.holes("f = dec? x\n") shouldBe Right(())
  }

  test("a weakened signature fails preservation, and so does a dropped import or module line") {
    firstGate(header + "+-comm : ∀ (m n : ℕ) → m + n ≡ m + n\n+-comm m n = refl\n") shouldBe Some("preservation")
    val noImport = gold.replace("open import Data.Nat.Properties using ( +-identityʳ ; +-suc )\n", "")
    firstGate(noImport) shouldBe Some("preservation")
    firstGate(gold.replace("module Nat-plus-comm where", "module Nat-plus-comm2 where")) shouldBe Some("preservation")
  }

  test("preservation tolerates comments and blank lines between frozen lines") {
    val commented = gold.replace("open import AgdaDojang.Debug\n", "-- a note\nopen import AgdaDojang.Debug\n\n-- another\n")
    firstGate(commented) shouldBe None
  }

  test("a postulate, a trustMe, and any pragma fail the escape gate; a postulate in a comment does not") {
    val post = header + "postulate\n  ax : ∀ (m n : ℕ) → m + n ≡ n + m\n\n+-comm : ∀ (m n : ℕ) → m + n ≡ n + m\n+-comm m n = ax m n\n"
    Judge.syntactic(st, post)._1 shouldBe Some(GateFailure("escape", "keyword postulate"))
    val prag = header + "+-comm : ∀ (m n : ℕ) → m + n ≡ n + m\n{-# TERMINATING #-}\n+-comm m n = +-comm m n\n"
    Judge.syntactic(st, prag)._1 shouldBe Some(GateFailure("escape", "pragma TERMINATING"))
    val opts = "{-# OPTIONS --type-in-type #-}\n" + gold
    Judge.syntactic(st, opts)._1 shouldBe Some(GateFailure("escape", "pragma OPTIONS"))
    val tm = header + "open import Relation.Binary.PropositionalEquality.TrustMe using ( trustMe )\n+-comm : ∀ (m n : ℕ) → m + n ≡ n + m\n+-comm m n = trustMe\n"
    Judge.syntactic(st, tm)._1 shouldBe Some(GateFailure("escape", "keyword trustMe"))
    val inComment = gold + "-- we could postulate this, but {- postulate -} we do not\n"
    firstGate(inComment) shouldBe None
  }

  test("naming the original qualified is restated: directly, through a module alias, or via an import list") {
    val direct = header + "+-comm : ∀ (m n : ℕ) → m + n ≡ n + m\n+-comm m n = Data.Nat.Properties.+-comm m n\n"
    Judge.syntactic(st, direct) match { case (g, _, ev) => g shouldBe None; ev shouldBe Vector("qualified Data.Nat.Properties.+-comm") }
    val alias = header + "import Data.Nat.Properties as P\n\n+-comm : ∀ (m n : ℕ) → m + n ≡ n + m\n+-comm m n = P.+-comm m n\n"
    Judge.syntactic(st, alias)._3 shouldBe Vector("qualified P.+-comm")
    val byImport = header + "open import Data.Nat.Properties using ( +-comm ) renaming ( +-suc to ps )\n+-comm : ∀ (m n : ℕ) → m + n ≡ n + m\n+-comm m n = refl\n"
    Judge.syntactic(st, byImport)._3 shouldBe Vector("import open import Data.Nat.Properties using ( +-comm ) renaming ( +-suc to ps )")
    val renamed = header + "+-comm : ∀ (m n : ℕ) → m + n ≡ n + m\n+-comm m n = c m n\n  where open import Data.Nat.Properties renaming ( +-comm to c )\n"
    Judge.syntactic(st, renamed)._3 shouldBe Vector("import open import Data.Nat.Properties renaming ( +-comm to c )")
  }

  test("a recursive call by the hole's own bare name is not evidence on an unprimed row") {
    Judge.syntactic(st, gold)._3 shouldBe Vector.empty
  }

  test("on a primed agda-algebras row the bare unprimed name is evidence; the primed name is not") {
    val ob =
      """module Functions-lift-lower where
        |
        |open import AgdaDojang.Debug
        |open import Setoid.Functions
        |
        |lift∼lower′ : (a : A)
        |  →  P a
        |lift∼lower′ 𝑨 a = {!!}
        |""".stripMargin
    val s2 = Statement.of(ob, "lift∼lower′").toOption.get
    s2.signature shouldBe Vector("lift∼lower′ : (a : A)", "  →  P a")
    Gates.originalOf("lift∼lower′") shouldBe (("lift∼lower", true))
    val bare = ob.replace("{!!}", "lift∼lower 𝑨 a")
    Judge.syntactic(s2, bare) match { case (g, _, ev) => g shouldBe None; ev shouldBe Vector("bare lift∼lower") }
    val recursive = ob.replace("{!!}", "lift∼lower′ 𝑨 a")
    Judge.syntactic(s2, recursive)._3 shouldBe Vector.empty
    val qualified = ob.replace("{!!}", "Setoid.Functions.Basic.lift∼lower 𝑨 a")
    Judge.syntactic(s2, qualified)._3 shouldBe Vector("qualified Setoid.Functions.Basic.lift∼lower")
  }

  test("a haystack row's frozen imports never count as restatement evidence") {
    val ob =
      """module Nat-plus-suc-diag where
        |open import AgdaDojang.Debug
        |open import Data.Nat.Base using ( ℕ ; suc ; _+_ )
        |open import Data.Nat.Properties using ( +-comm )
        |+-suc-diag : ∀ (m : ℕ) → m + suc m ≡ suc (m + m)
        |+-suc-diag m = {!!}
        |""".stripMargin
    val s3 = Statement.of(ob, "+-suc-diag").toOption.get
    val solved = ob.replace("{!!}", "Data.Nat.Properties.+-suc m m")
    Judge.syntactic(s3, solved) match { case (g, _, ev) => g shouldBe None; ev shouldBe Vector.empty }
  }

  test("Statement.of refuses a text without the hole's signature") {
    Statement.of("module M where\nf : A\nf = {!!}\n", "g").isLeft shouldBe true
  }

  test("every committed gold passes the syntactic gates with no restatement evidence; every obligation fails on holes") {
    val root  = Paths.get("..").toAbsolutePath.normalize
    val index = root.resolve("data/benchmarks/benchmark-index.jsonl")
    assume(Files.isRegularFile(index), s"benchmark index not found at $index")
    val rows = Files.readAllLines(index, StandardCharsets.UTF_8).asScala.toVector.filter(_.trim.nonEmpty)
      .map(l => io.circe.parser.decode[struxdriver.benchmark.Obligation](l).toOption.get)
    rows.size should be >= 43
    rows.foreach { e =>
      val ob   = new String(Files.readAllBytes(root.resolve(e.obligationPath)), StandardCharsets.UTF_8)
      val gd   = new String(Files.readAllBytes(root.resolve(e.goldPath)), StandardCharsets.UTF_8)
      val stmt = Statement.of(ob, e.hole).fold(msg => fail(s"${e.id}: $msg"), identity)
      withClue(s"${e.id} gold: ") {
        val (gate, _, evidence) = Judge.syntactic(stmt, gd)
        gate shouldBe None
        evidence shouldBe Vector.empty
      }
      withClue(s"${e.id} obligation: ") {
        Judge.syntactic(stmt, ob)._1.map(_.gate) shouldBe Some("holes")
      }
    }
  }
}
