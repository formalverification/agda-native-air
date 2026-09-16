/** ============================================================================
  *  JudgeSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/JudgeSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins the judge's pure parts (issue #154): the frozen-text diff (module
  *  line and import lines, comments stripped, the commented-out attack of PR
  *  #158's review refused), and the gates as functions of Agda's answers: the
  *  statement rule over the extractor's elaborated type ASTs (binder names
  *  aside), the escape rule over Agda's safe-flag codes, the hole rule over `check_file`'s
  *  count, the original's derivation from the `restates:` tag, and the
  *  restatement rule over extractor rows captured verbatim from `agda-json`
  *  on archived final files.  Then the diff over every committed obligation
  *  and gold.  Agda itself is asked in AgentBenchIntegrationSpec.
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

  test("statement: the module line and the four original import lines; a text without them is refused") {
    st.moduleLine shouldBe "module Nat-plus-comm where"
    st.importLines.size shouldBe 4
    Statement.of("module M where\nf : A\nf = {!!}\n", "g").isLeft shouldBe true
    Statement.of("open import X\nf : A\nf = {!!}\n", "f").isLeft shouldBe true
  }

  test("imports: the gold keeps every frozen line and logs its where-block import") {
    Gates.imports(st, gold) shouldBe Right(Vector("open import Relation.Binary.PropositionalEquality.Properties"))
  }

  test("imports: a dropped import line, an edited one, and a changed module line fail preservation") {
    Gates.imports(st, gold.replace("open import Data.Nat.Properties using ( +-identityʳ ; +-suc )\n", "")).left.map(_.gate) shouldBe Left("preservation")
    Gates.imports(st, gold.replace("using ( _≡_ ; refl ; cong ; sym )", "using ( _≡_ ; refl ; cong ; sym ; trans )")).left.map(_.gate) shouldBe Left("preservation")
    Gates.imports(st, gold.replace("module Nat-plus-comm where", "module Nat-plus-comm2 where")).left.map(_.gate) shouldBe Left("preservation")
  }

  test("imports: comments and blank lines between frozen lines are tolerated; a commented-out copy is not code (Copilot on PR #158)") {
    val commented = gold.replace("open import AgdaDojang.Debug\n", "-- a note\nopen import AgdaDojang.Debug\n\n-- another\n")
    Gates.imports(st, commented).isRight shouldBe true
    val hidden = header.replace(
      "open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong ; sym )\n",
      "{-\nopen import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong ; sym )\n-}\nopen import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong ; sym ; trans )\n") +
      "+-comm : ∀ (m n : ℕ) → m + n ≡ n + m\n+-comm m n = refl\n"
    Gates.imports(st, hidden).left.map(_.gate) shouldBe Left("preservation")
  }

  // Two elaborated types as the extractor encodes them: the same statement
  // under different binder names, and a weakened one.
  private def pi(name: String, cod: io.circe.Json): io.circe.Json = io.circe.Json.obj(
    "tag" -> io.circe.Json.fromString("Type"), "sort" -> io.circe.Json.obj("tag" -> io.circe.Json.fromString("Inf")),
    "term" -> io.circe.Json.obj("tag" -> io.circe.Json.fromString("Pi"),
      "binder" -> io.circe.Json.obj("hiding" -> io.circe.Json.fromString("explicit"), "nameHint" -> io.circe.Json.fromString(name)),
      "dom" -> io.circe.Json.obj("tag" -> io.circe.Json.fromString("Def"), "qname" -> io.circe.Json.fromString("Agda.Builtin.Nat.Nat")),
      "cod" -> cod))
  private def eq(l: Int, r: Int): io.circe.Json = io.circe.Json.obj(
    "tag" -> io.circe.Json.fromString("Def"), "qname" -> io.circe.Json.fromString("Agda.Builtin.Equality._≡_"),
    "elims" -> io.circe.Json.arr(io.circe.Json.obj("ix" -> io.circe.Json.fromInt(l)), io.circe.Json.obj("ix" -> io.circe.Json.fromInt(r))))
  private val commAst   = pi("m", pi("n", eq(1, 0)))
  private val commAstXY = pi("x", pi("y", eq(1, 0)))
  private val weakAst   = pi("m", pi("n", eq(1, 1)))

  test("statement: the elaborated types agree structurally, binder names aside; a changed or missing definition fails") {
    val gold  = Vector(DefRow("Nat-plus-comm.+-comm", commAst, "(m n : ℕ) → m + n ≡ n + m", Vector.empty))
    val same  = Vector(DefRow("Nat-plus-comm.+-comm", commAstXY, "(x y : ℕ) → x + y ≡ y + x", Vector.empty))
    val weak  = Vector(DefRow("Nat-plus-comm.+-comm", weakAst, "(m n : ℕ) → m + n ≡ m + n", Vector.empty))
    Gates.statement("Nat-plus-comm", "+-comm", gold, same) shouldBe Right(StatementCheck("(m n : ℕ) → m + n ≡ n + m", "(x y : ℕ) → x + y ≡ y + x", equal = true))
    Gates.statement("Nat-plus-comm", "+-comm", gold, weak).left.map(_.gate) shouldBe Left("preservation")
    Gates.statement("Nat-plus-comm", "+-comm", gold, Vector.empty).left.map(_.gate) shouldBe Left("preservation")
    Gates.statement("Nat-plus-comm", "+-comm", Vector.empty, same).left.map(_.gate) shouldBe Left("statement")
    Gates.withoutNameHints(commAst) shouldBe Gates.withoutNameHints(commAstXY)
    Gates.withoutNameHints(commAst) should not be Gates.withoutNameHints(weakAst)
  }

  test("escape: Agda's safe-flag codes and the unsafe-import code, nothing else") {
    Vector("SafeFlagPostulate", "SafeFlagTerminating", "SafeFlagNonTerminating", "SafeFlagPragma",
      "SafeFlagNoPositivityCheck", "SafeFlagNoCoverageCheck", "CoInfectiveImport").forall(Gates.isEscapeCode) shouldBe true
    Vector("NotInScope", "UnsolvedInteractionMetas", "UnequalTerms", "UnsolvedMetaVariables").exists(Gates.isEscapeCode) shouldBe false
    val postulated = Checked(success = false, Some(42), 0, Vector("SafeFlagPostulate"), Map("SafeFlagPostulate" -> "Cannot postulate ax with safe flag"), 1)
    Gates.escape(postulated) shouldBe Left(GateFailure("escape", "SafeFlagPostulate: Cannot postulate ax with safe flag"))
    Gates.escape(Checked(success = true, Some(0), 0, Vector.empty, Map.empty, 1)) shouldBe Right(())
  }

  test("holes: the server's count, or Agda's unsolved-interaction-metas code") {
    Gates.holes(Checked(success = false, Some(42), 1, Vector("UnsolvedInteractionMetas"), Map.empty, 1)).left.map(_.gate) shouldBe Left("holes")
    Gates.holes(Checked(success = false, Some(42), 0, Vector("UnsolvedInteractionMetas"), Map.empty, 1)).left.map(_.gate) shouldBe Left("holes")
    Gates.holes(Checked(success = true, Some(0), 0, Vector.empty, Map.empty, 1)) shouldBe Right(())
  }

  test("original: the restates: tag first, else the index module and the prime-stripped name") {
    Gates.originalOf("Setoid.Functions.Basic", "lift∼lower′", Vector("stratum:wholesale", "restates:Setoid.Functions.Basic.lift∼lower")) shouldBe
      Original(Some("Setoid.Functions.Basic.lift∼lower"), "lift∼lower", true)
    Gates.originalOf("Setoid.Functions.Basic", "lift∼lower′", Vector.empty) shouldBe Original(Some("Setoid.Functions.Basic.lift∼lower"), "lift∼lower", true)
    // Untagged: the qualified name is a guess, so the bare name is evidence even when it is the hole's.
    Gates.originalOf("Data.Nat.Properties", "+-comm", Vector.empty) shouldBe Original(Some("Data.Nat.Properties.+-comm"), "+-comm", true)
    // Tagged with the hole's own name: the original is known exactly, so the bare name alone is not evidence.
    Gates.originalOf("Overture.Operations", "π", Vector("restates:Overture.Operations.π")) shouldBe
      Original(Some("Overture.Operations.π"), "π", false)
    Gates.originalOf("M", "foo′", Vector("restates:Some.Where.bar")) shouldBe Original(Some("Some.Where.bar"), "bar", true)
  }

  // Extractor rows captured from `agda-json` on archived final files (2026-09-15).
  private val noAst = io.circe.Json.Null
  private val monToHom = Vector(DefRow("Homs-mon-to-hom.mon→hom′", noAst, "", Vector("Setoid.Homomorphisms.Basic.mon→hom")))
  private val kerCon = Vector(
    DefRow("Kernels-ker-con.∣h∣", noAst, "", Vector.empty),
    DefRow("Kernels-ker-con.kercon′", noAst, "", Vector("Agda.Builtin.Sigma._,_", "Function.Bundles.Carrier", "Kernels-ker-con.∣h∣",
      "Overture.Relations.kerRel", "Overture.Relations.kerRelOfEquiv", "Setoid.Algebras.Basic.𝔻[_]",
      "Setoid.Congruences.Basic.mkcon", "Setoid.Homomorphisms.Kernels.HomKerComp")))
  private val plusComm = Vector(DefRow("Nat-plus-comm.+-comm", noAst, "", Vector("Agda.Builtin.Nat.Nat", "Agda.Builtin.Nat.Nat.suc",
    "Agda.Builtin.Nat.Nat.zero", "Agda.Builtin.Nat._+_", "Data.Nat.Properties.+-identityʳ", "Data.Nat.Properties.+-suc",
    "Nat-plus-comm.+-comm", "Relation.Binary.PropositionalEquality.Core.cong", "Relation.Binary.PropositionalEquality.Core.sym",
    "Relation.Binary.PropositionalEquality.Core.trans")))

  test("restatement: a body that refers to the original by its qualified name is restated") {
    val orig = Gates.originalOf("Setoid.Homomorphisms.Basic", "mon→hom′", Vector("restates:Setoid.Homomorphisms.Basic.mon→hom"))
    Gates.restatement("Homs-mon-to-hom", "mon→hom′", orig, monToHom) shouldBe Vector("ref Setoid.Homomorphisms.Basic.mon→hom")
  }

  test("restatement: a proof from other lemmas, through a where-bound helper, is not; a recursive call is not") {
    val orig = Gates.originalOf("Setoid.Homomorphisms.Kernels", "kercon′", Vector("restates:Setoid.Homomorphisms.Kernels.kercon"))
    Gates.restatement("Kernels-ker-con", "kercon′", orig, kerCon) shouldBe Vector.empty
    val origComm = Gates.originalOf("Data.Nat.Properties", "+-comm", Vector.empty)
    Gates.restatement("Nat-plus-comm", "+-comm", origComm, plusComm) shouldBe Vector.empty
  }

  test("restatement: the closure follows the file's own helpers; a library name equal to the original's bare name counts") {
    val orig = Gates.originalOf("Setoid.Homomorphisms.Kernels", "kercon′", Vector("restates:Setoid.Homomorphisms.Kernels.kercon"))
    val viaHelper = Vector(
      DefRow("Kernels-ker-con.kercon′", noAst, "", Vector("Kernels-ker-con.helper")),
      DefRow("Kernels-ker-con.helper", noAst, "", Vector("Setoid.Homomorphisms.Kernels.kercon")))
    Gates.restatement("Kernels-ker-con", "kercon′", orig, viaHelper) shouldBe Vector("ref Setoid.Homomorphisms.Kernels.kercon")
    // The index names Data.Nat.Base for 0<1+n; the lemma lives in Data.Nat.Properties.
    val origLt = Gates.originalOf("Data.Nat.Base", "0<1+n", Vector.empty)
    Gates.restatement("Nat-zero-lt-suc", "0<1+n", origLt, Vector(DefRow("Nat-zero-lt-suc.0<1+n", noAst, "", Vector("Data.Nat.Properties.0<1+n")))) shouldBe Vector("ref Data.Nat.Properties.0<1+n")
    // A missing row (the definition renamed away) yields no evidence rather than an error.
    Gates.restatement("X", "x", origLt, Vector.empty) shouldBe Vector.empty
  }

  test("restatement: a tag naming the hole's own name matches that name only, not a namesake elsewhere") {
    val orig = Gates.originalOf("Overture.Operations", "π", Vector("stratum:wholesale", "restates:Overture.Operations.π"))
    orig.bareIsEvidence shouldBe false
    val exact    = Vector(DefRow("Overture-proj-op.π", noAst, "", Vector("Overture.Operations.π")))
    val namesake = Vector(DefRow("Overture-proj-op.π", noAst, "", Vector("Data.Product.π", "Setoid.Algebras.Basic.𝔻[_]")))
    Gates.restatement("Overture-proj-op", "π", orig, exact) shouldBe Vector("ref Overture.Operations.π")
    Gates.restatement("Overture-proj-op", "π", orig, namesake) shouldBe Vector.empty
    // Untagged, the same shape: the module is a guess, so a namesake outside the file is the evidence there is.
    val guess = Gates.originalOf("Overture.Operations", "π", Vector.empty)
    guess.bareIsEvidence shouldBe true
    Gates.restatement("Overture-proj-op", "π", guess, namesake) shouldBe Vector("ref Data.Product.π")
  }

  test("every committed obligation reads as a statement and every gold keeps its frozen lines") {
    val root  = Paths.get("..").toAbsolutePath.normalize
    val index = root.resolve("data/benchmarks/benchmark-index.jsonl")
    assume(Files.isRegularFile(index), s"benchmark index not found at $index")
    val rows = Files.readAllLines(index, StandardCharsets.UTF_8).asScala.toVector.filter(_.trim.nonEmpty)
      .map(l => io.circe.parser.decode[struxdriver.benchmark.Obligation](l).toOption.get)
    rows.size should be >= 55
    rows.foreach { e =>
      val ob   = new String(Files.readAllBytes(root.resolve(e.obligationPath)), StandardCharsets.UTF_8)
      val gd   = new String(Files.readAllBytes(root.resolve(e.goldPath)), StandardCharsets.UTF_8)
      val stmt = Statement.of(ob, e.hole).fold(msg => fail(s"${e.id}: $msg"), identity)
      withClue(s"${e.id}: ") {
        Gates.imports(stmt, gd).isRight shouldBe true
        Gates.imports(stmt, ob).isRight shouldBe true
        if (e.source == "agda-algebras") Gates.originalOf(e.module, e.hole, e.tags).qualified.exists(_.contains(".")) shouldBe true
      }
    }
  }
}
