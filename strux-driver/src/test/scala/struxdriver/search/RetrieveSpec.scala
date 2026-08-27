/** ============================================================================
  *  RetrieveSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/search/RetrieveSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins the P2 retrieval pipeline (issue #123) against a canned corpus whose
  *  rows are copied from a REAL stdlib extraction (fully qualified alias-form
  *  types, embedded newlines, nested record-module rows) — no server, no
  *  Agda: the `CorpusSearch` seam is a filter over the canned rows with the
  *  live tools' own semantics (substring match, lexicographic order,
  *  truncation at the limit), and the lane is a recording fake.  What is
  *  pinned: the statement normaliser, the goal tokeniser, the scorer's
  *  qualified-token reduction, the import-scope rule, both target-exclusion
  *  rules and their off-switch, the rendering ladder, the two candidate
  *  shapes, ranking determinism, composition with the base proposer, the
  *  per-goal memo, and the truncation stat.
  *
  *  ============================================================================
  */
package struxdriver.search

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import cats.effect.IO
import cats.effect.unsafe.implicits.global

final class RetrieveSpec extends AnyFunSuite with Matchers {

  // --------------------------------------------------------------------------
  // The canned corpus: row values from the real agda-stdlib extraction.
  // --------------------------------------------------------------------------

  private val plusComm = SearchHit(
    prettyQname = "Data.Nat.Properties.+-comm",
    tpe         = "Algebra.Definitions.Commutative Agda.Builtin.Equality._≡_\nAgda.Builtin.Nat._+_",
    defKind     = "function",
    module      = "Data.Nat.Properties",
    hasBody     = true)

  private val plusSuc = SearchHit(
    prettyQname = "Data.Nat.Properties.+-suc",
    tpe         = "(m n : Agda.Builtin.Nat.Nat) →\n(m Agda.Builtin.Nat.+ Agda.Builtin.Nat.Nat.suc n)\nAgda.Builtin.Equality.≡\nAgda.Builtin.Nat.Nat.suc (m Agda.Builtin.Nat.+ n)",
    defKind     = "function",
    module      = "Data.Nat.Properties",
    hasBody     = true)

  private val mulComm = SearchHit(
    prettyQname = "Data.Nat.Properties.*-comm",
    tpe         = "Algebra.Definitions.Commutative Agda.Builtin.Equality._≡_\nAgda.Builtin.Nat._*_",
    defKind     = "function",
    module      = "Data.Nat.Properties",
    hasBody     = true)

  /** A record-field projection sharing the target's bare name (real row). */
  private val ringComm = SearchHit(
    prettyQname = "Data.Nat.Properties.IsCommutativeRing.+-comm",
    tpe         = "{+ * : Algebra.Core.Op₂ Agda.Builtin.Nat.Nat} → …",
    defKind     = "function",
    module      = "Data.Nat.Properties._.IsCommutativeRing",
    hasBody     = true)

  /** A re-export: defined in Core, imported through …PropositionalEquality. */
  private val trans = SearchHit(
    prettyQname = "Relation.Binary.PropositionalEquality.Core.trans",
    tpe         = "{A : Set} {x y z : A} →\nAgda.Builtin.Equality._≡_ x y → Agda.Builtin.Equality._≡_ y z →\nAgda.Builtin.Equality._≡_ x z",
    defKind     = "function",
    module      = "Relation.Binary.PropositionalEquality.Core",
    hasBody     = true)

  private val leRefl = SearchHit(
    prettyQname = "Data.Nat.Properties.≤-refl",
    tpe         = "{n : Agda.Builtin.Nat.Nat} → Data.Nat.Base._≤_ n n",
    defKind     = "function",
    module      = "Data.Nat.Properties",
    hasBody     = true)

  private val someCtor = SearchHit(
    prettyQname = "Data.Nat.Properties.+-rec",
    tpe         = "whatever",
    defKind     = "constructor",
    module      = "Data.Nat.Properties",
    hasBody     = false)

  /** In a module the fixture does NOT import — reachable only through a
    * goal-token type query, and then cut by the scope filter.
    */
  private val mapId = SearchHit(
    prettyQname = "Data.List.Properties.map-id",
    tpe         = "(xs : Data.List.Base.List A) →\nAgda.Builtin.Equality._≡_ (Data.List.Base.map (λ x → x) xs) xs",
    defKind     = "function",
    module      = "Data.List.Properties",
    hasBody     = true)

  private val corpusRows =
    Vector(plusComm, plusSuc, mulComm, ringComm, trans, leRefl, someCtor, mapId)
      .sortBy(_.prettyQname) // the server's Map iteration order

  /** The live tools' semantics over the canned rows: case-insensitive
    * substring, lexicographic order, truncation at the limit.
    */
  private final class CannedCorpus(rows: Vector[SearchHit]) extends CorpusSearch {
    var calls: Vector[String] = Vector.empty
    private def q(kind: String, sel: SearchHit => String, pattern: String, limit: Int) =
      IO { calls = calls :+ s"$kind:$pattern"
           rows.filter(h => sel(h).toLowerCase.contains(pattern.toLowerCase)).take(limit) }
    def byName(pattern: String, limit: Int) = q("name", _.prettyQname, pattern, limit)
    def byType(pattern: String, limit: Int) = q("type", _.tpe, pattern, limit)
    def dependenciesOf(qname: String)       = IO { calls = calls :+ s"deps:$qname"; Vector.empty }
  }

  /** The recording lane fake: known names answer their printed type, unknown
    * names are rejected (Right(None)) — P1's FixedProposer contract.
    */
  private final class FakeLane(types: Map[String, String]) {
    var asked: Vector[String] = Vector.empty
    def lemmaType(name: String): IO[Either[String, Option[String]]] =
      IO { asked = asked :+ name; Right(types.get(name)) }
  }

  private val fixtureSource =
    """module Nat-plus-comm where
      |open import AgdaDojang.Debug
      |open import Data.Nat.Base using ( ℕ ; zero ; suc ; _+_ )
      |open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl ; cong ; sym )
      |open import Data.Nat.Properties using ( +-suc )
      |""".stripMargin

  private val laneTypes = Map(
    "+-suc"                                        -> "(m n : ℕ) → m + suc n ≡ suc (m + n)",
    "Data.Nat.Properties.*-comm"                   -> "(m n : ℕ) → m * n ≡ n * m",
    "Relation.Binary.PropositionalEquality.trans"  -> "{A : Set} {x y z : A} → x ≡ y → y ≡ z → x ≡ z",
    "Data.Nat.Properties.≤-refl"                   -> "{n : ℕ} → n ≤ n"
    // Note: the Core qname is deliberately ABSENT — the re-export rendering
    // ladder must fall through to the importing module's qualification.
  )

  private val goal = GoalView(
    goal    = "m + n ≡ n + m",
    context = Vector(CtxEntry("m", "ℕ", None), CtxEntry("n", "ℕ", None)),
    module  = Some("Nat-plus-comm"))

  private val scope     = ImportScope(Imports.imported(fixtureSource))
  private val exclusion = TargetExclusion("+-comm", "∀ (m n : ℕ) → m + n ≡ n + m")
  private val baseFixed = new Proposer {
    def propose(state: SearchState, target: Obligation, goal: GoalView): IO[Vector[String]] =
      IO.pure(Vector("refl", "m", "n"))
  }
  private val state0 = SearchState.initial("goal = {!!}", Vector(Obligation(1, 8, "m + n ≡ n + m")))
  private val cfg4   = RetrievalConfig.default.copy(topK = 4, queryLimit = 100)

  private def freshProposer(
    cfg:  RetrievalConfig    = cfg4,
    rows: Vector[SearchHit]  = corpusRows
  ): (RetrievalProposer, CannedCorpus, FakeLane) = {
    val corpus = new CannedCorpus(rows)
    val lane   = new FakeLane(laneTypes)
    val p = RetrievalProposer.create(baseFixed, corpus, scope, exclusion, lane.lemmaType, cfg)
      .unsafeRunSync()
    (p, corpus, lane)
  }

  // --------------------------------------------------------------------------
  // Statements — the normaliser behind the exact-statement-alias rule
  // --------------------------------------------------------------------------

  test("normalize: positional binder renaming makes alpha-variants equal") {
    Statements.normalize("∀ (m n : ℕ) → m + n ≡ n + m") shouldBe
      Statements.normalize("(x y : ℕ) → x + y ≡ y + x")
  }

  test("normalize: different statements stay different") {
    Statements.normalize("(m n : ℕ) → m + n ≡ n + m") should not be
      Statements.normalize("(m n : ℕ) → n + m ≡ m + n")
  }

  test("normalize: a parenthesised type is not a binder group") {
    // (A → B) binds nothing; A and B must survive as themselves.
    Statements.normalize("(A → B) → A → B") should include ("A")
  }

  // --------------------------------------------------------------------------
  // Queries — goal tokens
  // --------------------------------------------------------------------------

  test("goalTokens: operators survive; context names, numerals, metas do not") {
    Queries.goalTokens(goal) shouldBe Vector("+", "≡")
    val g2 = GoalView("length (xs ++ ys) ≡ length xs + length ys",
      Vector(CtxEntry("xs", "List A", None), CtxEntry("ys", "List A", None)), None)
    Queries.goalTokens(g2) shouldBe Vector("length", "++", "≡", "+")
    val g3 = GoalView("1 ≤ suc _n_6", Vector.empty, None)
    Queries.goalTokens(g3) shouldBe Vector("≤", "suc")
  }

  // --------------------------------------------------------------------------
  // Scorer — qualified alias-form corpus types
  // --------------------------------------------------------------------------

  test("scorer: qualified corpus tokens reduce to bare segments; names break alias opacity") {
    val gts = Set("+", "≡")
    // +-suc's type mentions + and ≡ qualified, and its name contains "+".
    TokenOverlapScorer.score(gts, plusSuc) shouldBe 5
    // *-comm's alias-form type mentions only ≡ of the goal's tokens.
    TokenOverlapScorer.score(gts, mulComm) shouldBe 2
    TokenOverlapScorer.score(gts, leRefl) shouldBe 0
  }

  // --------------------------------------------------------------------------
  // ImportScope
  // --------------------------------------------------------------------------

  test("scope: exact, dot-prefix extension, and out-of-scope") {
    scope.importingModuleOf("Data.Nat.Properties").map(_.module) shouldBe Some("Data.Nat.Properties")
    scope.importingModuleOf("Data.Nat.Properties._.IsCommutativeRing").map(_.module) shouldBe Some("Data.Nat.Properties")
    scope.importingModuleOf("Relation.Binary.PropositionalEquality.Core").map(_.module) shouldBe Some("Relation.Binary.PropositionalEquality")
    scope.importingModuleOf("Data.List.Base") shouldBe None
    // A dot boundary, not a string prefix: Data.Nat.Base does not license Data.Nat.BaseX.
    scope.importingModuleOf("Data.Nat.BaseX") shouldBe None
  }

  // --------------------------------------------------------------------------
  // TargetExclusion
  // --------------------------------------------------------------------------

  test("exclusion: the name rule catches the target and its record-field projections") {
    exclusion.reasonFor(plusComm) shouldBe Some("name:Data.Nat.Properties.+-comm")
    exclusion.reasonFor(ringComm) shouldBe Some("name:Data.Nat.Properties.IsCommutativeRing.+-comm")
    exclusion.reasonFor(mulComm) shouldBe None
  }

  test("exclusion: the statement rule catches an alpha-equal restatement under another name") {
    val alias = SearchHit("Data.Nat.Properties.comm′", "(x y : ℕ) → x + y ≡ y + x",
      "function", "Data.Nat.Properties", hasBody = true)
    exclusion.reasonFor(alias) shouldBe Some("statement:Data.Nat.Properties.comm′")
  }

  // --------------------------------------------------------------------------
  // The proposer pipeline
  // --------------------------------------------------------------------------

  test("propose: composition, scope, exclusion, ranking, rendering ladder, shapes — deterministically") {
    val (proposer, _, lane) = freshProposer()
    val cands = proposer.propose(state0, state0.obligations.head, goal).unsafeRunSync()

    // Base first, verbatim.
    cands.take(3) shouldBe Vector("refl", "m", "n")

    // Retrieval, in score order: +-suc (5) bare — its importing module's
    // using list opens it; then *-comm (2) and trans (2) tied, qname order;
    // then ≤-refl (0), nullary so a single bare-name shape.  Per lemma: the
    // `_`-form, the saturated tuples over the context (m, n), then the
    // `{!!}`-form; every applied shape parenthesized.
    def threeShapes(l: String) = Vector(
      s"($l _ _)", s"($l m m)", s"($l m n)", s"($l n m)", s"($l n n)", s"($l {!!} {!!})")
    cands.drop(3) shouldBe (
      threeShapes("+-suc") ++
      threeShapes("Data.Nat.Properties.*-comm") ++
      threeShapes("Relation.Binary.PropositionalEquality.trans") :+
      "Data.Nat.Properties.≤-refl"
    )

    // The excluded target never reached the lane; the re-export ladder did
    // try the Core qname before falling through to the importing module.
    lane.asked should not contain "Data.Nat.Properties.+-comm"
    lane.asked should contain inOrder(
      "Relation.Binary.PropositionalEquality.Core.trans",
      "Relation.Binary.PropositionalEquality.trans")
    // The using-listed lemma resolved bare on the first rung.
    lane.asked should contain ("+-suc")
    lane.asked should not contain "Data.Nat.Properties.+-suc"

    // Determinism: a second proposer over the same world proposes the same.
    val (proposer2, _, _) = freshProposer()
    proposer2.propose(state0, state0.obligations.head, goal).unsafeRunSync() shouldBe cands
  }

  test("propose: the stats ledger names every cut") {
    val (proposer, _, _) = freshProposer()
    proposer.propose(state0, state0.obligations.head, goal).unsafeRunSync()
    val s = proposer.stats.unsafeRunSync()
    s.excluded should contain ("name:Data.Nat.Properties.+-comm")
    s.excluded should contain ("name:Data.Nat.Properties.IsCommutativeRing.+-comm")
    s.nonFunction shouldBe 1              // the constructor row
    s.inScope should be < s.hits          // Data.List.Base.map was cut by scope
    s.laneRejected shouldBe 0
    s.proposedLemmas shouldBe Vector(
      "+-suc", "Data.Nat.Properties.*-comm",
      "Relation.Binary.PropositionalEquality.trans", "Data.Nat.Properties.≤-refl")
    s.truncated shouldBe 0
  }

  test("propose: exclusion off admits the target — the labeled control, never a headline") {
    val lane   = new FakeLane(laneTypes + ("Data.Nat.Properties.+-comm" -> "(m n : ℕ) → m + n ≡ n + m"))
    val corpus = new CannedCorpus(corpusRows)
    val p = RetrievalProposer.create(baseFixed, corpus, scope, exclusion, lane.lemmaType,
      cfg4.copy(excludeTarget = false)).unsafeRunSync()
    val cands = p.propose(state0, state0.obligations.head, goal).unsafeRunSync()
    cands should contain ("(Data.Nat.Properties.+-comm _ _)")
  }

  test("propose: the pool is memoised per goal display") {
    val (proposer, corpus, _) = freshProposer()
    proposer.propose(state0, state0.obligations.head, goal).unsafeRunSync()
    val callsAfterFirst = corpus.calls.size
    proposer.propose(state0, state0.obligations.head, goal).unsafeRunSync()
    corpus.calls.size shouldBe callsAfterFirst
  }

  test("propose: a query returning exactly the limit is counted truncated, not passed off as complete") {
    val (proposer, _, _) = freshProposer(cfg = cfg4.copy(queryLimit = 2))
    proposer.propose(state0, state0.obligations.head, goal).unsafeRunSync()
    proposer.stats.unsafeRunSync().truncated should be > 0
  }

  test("tuples: cartesian power with repetition, in name order; saturation stays bounded") {
    RetrievalProposer.tuples(Vector("m", "n"), 2) shouldBe Vector(
      Vector("m", "m"), Vector("m", "n"), Vector("n", "m"), Vector("n", "n"))
    RetrievalProposer.tuples(Vector("a"), 3) shouldBe Vector(Vector("a", "a", "a"))
    // Above the caps the proposer emits no saturated forms: a 4-visible lemma
    // gets only the `_`-form and the `{!!}`-form whatever the context is.
    val big = SearchHit("Data.Nat.Properties.big4", "t", "function", "Data.Nat.Properties", hasBody = true)
    val lane = new FakeLane(Map(
      "Data.Nat.Properties.big4" -> "(a b c d : ℕ) → a + b + c + d ≡ d + c + b + a"))
    val corpus = new CannedCorpus(Vector(big))
    val p = RetrievalProposer.create(baseFixed, corpus, scope, exclusion, lane.lemmaType, cfg4)
      .unsafeRunSync()
    val cands = p.propose(state0, state0.obligations.head, goal).unsafeRunSync()
    cands.drop(3) shouldBe Vector(
      "(Data.Nat.Properties.big4 _ _ _ _)",
      "(Data.Nat.Properties.big4 {!!} {!!} {!!} {!!})")
  }
}
