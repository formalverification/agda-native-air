/** ============================================================================
  *  RetrievalRecallSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/search/RetrievalRecallSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins the offline recall instrument of issue #19 against a canned corpus:
  *  the in-memory corpus's server semantics (substring, case-insensitive,
  *  code-point order, truncation, pretty module on the wire), the goal
  *  context reconstruction on real fixture sources (implicit insertion,
  *  clause rebinds, the unbound-premise cut), every ground-truth status the
  *  instrument can report and the rank it reports, the recall arithmetic
  *  over all names versus reachable ones, and the exclusion regimes (targets
  *  in the excluded pool, originals in the unexcluded one).
  *
  *  ============================================================================
  */
package struxdriver.search

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import cats.effect.unsafe.implicits.global
import java.nio.file.{Files, Paths}

import struxdriver.benchmark.{Difficulty, Obligation => IndexEntry}

final class RetrievalRecallSpec extends AnyFunSuite with Matchers {

  // --------------------------------------------------------------------------
  // The canned corpus: the shape of the agda-algebras extraction, on the wire.
  // --------------------------------------------------------------------------

  private def row(q: String, tpe: String, kind: String = "function"): SearchHit =
    SearchHit(q, tpe, kind, q.substring(0, q.lastIndexOf('.')), hasBody = true)

  /** The original a wholesale fixture restates: reachable, and the answer key. */
  private val original = row("Setoid.Functions.Inverses.IsInRange→IsInImage",
    "{F : Function.Bundles.Func 𝑨 𝑩} {b : Relation.Binary.Bundles.Setoid.Carrier 𝑩} →\nb Relation.Unary.∈ Setoid.Functions.Inverses.IsInRange F →\nSetoid.Functions.Inverses._.Image F ∋ b")
  /** The fair needle: a constructor, which the defKind filter never proposes. */
  private val eqCtor   = row("Setoid.Functions.Inverses.Image_∋_.eq", "…", kind = "constructor")
  /** Generic projections that flood the pool. */
  private val level    = row("Overture.Basic.ℓ₁", "Agda.Primitive.Level")
  private val idFunc   = row("Setoid.Functions.Basic.𝑖𝑑", "{𝑨 : Relation.Binary.Bundles.Setoid α ρᵃ} → Function.Bundles.Func 𝑨 𝑨")
  private val inv      = row("Setoid.Functions.Inverses.Inv", "(F : Function.Bundles.Func 𝑨 𝑩) {b : Relation.Binary.Bundles.Setoid.Carrier 𝑩} → Setoid.Functions.Inverses._.Image F ∋ b → Relation.Binary.Bundles.Setoid.Carrier 𝑨")
  /** A lemma whose module the fixture does not import. */
  private val foreign  = row("Setoid.Homomorphisms.Basic.𝒾𝒹", "Setoid.Homomorphisms.Basic.hom 𝑨 𝑨")

  private val corpus = new InMemoryCorpus(Vector(original, eqCtor, level, idFunc, inv, foreign))

  private val fixtureSource =
    """module Inverses-range-to-image where
      |
      |open import AgdaDojang.Debug
      |
      |open import Agda.Primitive   using ( Level )
      |open import Data.Product     using ( proj₁ ; proj₂ )
      |open import Relation.Binary  using ( Setoid )
      |open import Function.Bundles using ( Func )
      |
      |open import Setoid.Functions
      |
      |IsInRange→IsInImage′ : {α ρᵃ β ρᵇ : Level} {𝑨 : Setoid α ρᵃ} {𝑩 : Setoid β ρᵇ}
      |                       {F : Func 𝑨 𝑩} {b : Setoid.Carrier 𝑩}
      |  →  IsInRange F b → Image F ∋ b
      |IsInRange→IsInImage′ {𝑩 = 𝑩} w = {!!}
      |""".stripMargin

  private val entry = IndexEntry(
    id = "algebras-inverses-range-to-image", source = "agda-algebras", module = "Setoid.Functions.Inverses",
    obligationPath = Paths.get("obl.agda"), goldPath = Paths.get("gold.agda"),
    goldTerm = "eq (proj₁ w) (Setoid.sym 𝑩 (proj₂ w))", hole = "IsInRange→IsInImage′",
    typeSig = "{α ρᵃ β ρᵇ : Level} {𝑨 : Setoid α ρᵃ} {𝑩 : Setoid β ρᵇ} {F : Func 𝑨 𝑩} {b : Setoid.Carrier 𝑩} → IsInRange F b → Image F ∋ b",
    difficulty = Difficulty.Compositional, domain = "setoid", proofStrategy = "constructor",
    tags = Vector("stratum:wholesale",
      "restates:Setoid.Functions.Inverses.IsInRange→IsInImage",
      "target:Setoid.Functions.Inverses.Image_∋_.eq",
      "target:Setoid.Functions.Inverses.Inv",
      "target:Relation.Binary.Bundles.Setoid.sym",
      "target:Setoid.Homomorphisms.Basic.𝒾𝒹"))

  private val recorded = RetrievalRecall.RecordedGoal("Image F ∋ b", None)

  private def cfg(exclude: Boolean) = RecallConfig(
    index = Paths.get("i"), corpus = Paths.get("c"), report = Paths.get("r"), projectRoot = Paths.get("."),
    out = Paths.get("o.json"), ids = None, scorers = Vector(Scorers.default), excludeTarget = exclude,
    ks = Vector(1, 8), queryLimit = 5000, top = 3)

  // --------------------------------------------------------------------------
  // InMemoryCorpus — the server's semantics
  // --------------------------------------------------------------------------

  test("corpus: substring, case-insensitive, code-point order, truncation, pretty module") {
    corpus.byName("setoid.functions.", 100).unsafeRunSync().map(_.prettyQname) shouldBe Vector(
      "Setoid.Functions.Basic.𝑖𝑑",           // U+1D456 sorts above every BMP letter in code-point order
      "Setoid.Functions.Inverses.Image_∋_.eq",
      "Setoid.Functions.Inverses.Inv",
      "Setoid.Functions.Inverses.IsInRange→IsInImage")
    corpus.byName("Setoid.Functions.", 2).unsafeRunSync().size shouldBe 2
    corpus.byType("image f ∋", 100).unsafeRunSync().map(_.bareName) shouldBe Vector("Inv", "IsInRange→IsInImage")
    corpus.lookup("Overture.Basic.ℓ₁").map(_.module) shouldBe Some("Overture.Basic")
    corpus.lookup("nope") shouldBe None
  }

  test("corpus: code-point order differs from UTF-16 order on astral glyphs, and we follow the server") {
    // `𝑨` is U+1D468 (a surrogate pair D835 DC68); `ﬂ` is U+FB02.  Java's
    // String order puts the pair first (D835 < FB02); Data.Text puts it last.
    InMemoryCorpus.codePointOrder.compare("𝑨", "ﬂ") should be > 0
    "𝑨".compareTo("ﬂ") should be < 0
    InMemoryCorpus.codePointOrder.compare("ab", "abc") should be < 0
    InMemoryCorpus.codePointOrder.compare("abc", "abc") shouldBe 0
  }

  test("corpus: the case fold is per code point, so a word-final Σ still matches Σ.fst (the server's Data.Text fold)") {
    val sigmaFst = row("Setoid.X.fst-of", "Agda.Builtin.Sigma.Σ.fst (p : Agda.Builtin.Sigma.Σ A B) → A")
    val sigmaEnd = row("Setoid.X.pair-of", "A → B → Agda.Builtin.Sigma.Σ A B")
    val c = new InMemoryCorpus(Vector(sigmaFst, sigmaEnd))
    c.byType("Agda.Builtin.Sigma.Σ", 10).unsafeRunSync().map(_.bareName) shouldBe Vector("fst-of", "pair-of")
    InMemoryCorpus.foldCase("Sigma.Σ") shouldBe "sigma.σ"
    "Sigma.Σ".toLowerCase should not be "sigma.σ" // Java's final-sigma rule, the thing we avoid
  }

  test("corpus: duplicate qualified names collapse to the last row in file order, as the server's map does") {
    val a1 = row("M.dup", "first", kind = "function")
    val a2 = SearchHit("M.dup", "second", "constructor", "M", hasBody = false)
    val b  = row("M.other", "x")
    InMemoryCorpus.dedupLastWins(Vector(a1, b, a2)) shouldBe Vector(b, a2)
  }

  test("corpus: the wire row is the pretty subset of a full extraction row") {
    val json = io.circe.parser.parse(
      """{"prettyQname":"Overture.Basic.𝑖𝑑","type":"(A : Set a) → A → A","defKind":"function",
        |"module":"Overture.Basic._","prettyModule":"Overture.Basic","hasBody":true,"typeAst":{}}""".stripMargin).toOption.get
    InMemoryCorpus.hitOf(json) shouldBe Right(SearchHit("Overture.Basic.𝑖𝑑", "(A : Set a) → A → A", "function", "Overture.Basic", hasBody = true))
    InMemoryCorpus.hitOf(io.circe.Json.obj()).isLeft shouldBe true
  }

  // --------------------------------------------------------------------------
  // FixtureContext — the goal context from the source
  // --------------------------------------------------------------------------

  test("context: implicits are inserted eagerly, a clause rebind keeps its name, the premise takes the pattern's") {
    FixtureContext.reconstruct(fixtureSource, "IsInRange→IsInImage′") shouldBe
      Vector("α", "ρᵃ", "β", "ρᵇ", "𝑨", "𝑩", "F", "b", "w")
  }

  test("context: an unbound visible binder ends the context and starts the goal") {
    // ker-in-con′ h = {!!}: the trailing implicits θ x y are inserted, the
    // visible premise `proj₁ (kercon …) x y` is not bound, so it is the goal.
    val src =
      """ker-in-con′ : {𝓞 𝓥 α ρᵃ β ρᵇ ℓ : Level} {𝑆 : Signature 𝓞 𝓥}
        |              {𝑨 : Algebra {𝑆 = 𝑆} α ρᵃ} {𝑩 : Algebra β ρᵇ}
        |              (h : hom 𝑨 𝑩) {θ : Con 𝑨 ℓ}
        |              {x y : Setoid.Carrier 𝔻[ 𝑨 ]}
        |  →  proj₁ (kercon (πhom h θ)) x y → proj₁ θ x y
        |ker-in-con′ h = {!!}
        |""".stripMargin
    FixtureContext.reconstruct(src, "ker-in-con′") shouldBe
      Vector("𝓞", "𝓥", "α", "ρᵃ", "β", "ρᵇ", "ℓ", "𝑆", "𝑨", "𝑩", "h", "θ", "x", "y")
  }

  test("context: a clause with no patterns still binds the leading implicits; ∀-sugar binds visibly") {
    val src1 = "≥-refl′ : {𝓞 𝓥 α ρᵃ : Level} {𝑆 : Signature 𝓞 𝓥} {𝑨 𝑩 : Algebra {𝑆 = 𝑆} α ρᵃ}\n  →  𝑨 ≅ 𝑩 → 𝑨 ≥ 𝑩\n≥-refl′ = {!!}\n"
    FixtureContext.reconstruct(src1, "≥-refl′") shouldBe Vector("𝓞", "𝓥", "α", "ρᵃ", "𝑆", "𝑨", "𝑩")
    val src2 = "+-comm : ∀ (m n : ℕ) → m + n ≡ n + m\n+-comm m n = {!!}\n"
    FixtureContext.reconstruct(src2, "+-comm") shouldBe Vector("m", "n")
    val src3 = "+-identityʳ : ∀ n → n + 0 ≡ n\n+-identityʳ n = {!!}\n"
    FixtureContext.reconstruct(src3, "+-identityʳ") shouldBe Vector("n")
    // A name that merely prefixes the hole's name is not the hole.
    val src4 = "πhom : Level → Set\nπhom = {!!}\nπ : {I : Set} → I → I\nπ i = {!!}\n"
    FixtureContext.reconstruct(src4, "π") shouldBe Vector("I", "i")
  }

  test("context: a parenthesised type is one anonymous premise, and a wildcard pattern binds nothing") {
    val src = "f : {A B : Set} → (A → B) → A → B\nf _ a = {!!}\n"
    FixtureContext.reconstruct(src, "f") shouldBe Vector("A", "B", "a")
    FixtureContext.reconstruct("nothing here", "f") shouldBe Vector.empty
  }

  // --------------------------------------------------------------------------
  // The instrument — statuses, ranks, regimes, arithmetic
  // --------------------------------------------------------------------------

  test("evaluate: every status by name, the target rank, and the original in the unexcluded pool") {
    val fr = RetrievalRecall.evaluate(cfg(exclude = true), corpus, TokenOverlapScorer, entry, recorded, fixtureSource).unsafeRunSync()
    fr.contextSource shouldBe "reconstructed"
    fr.goalTokens shouldBe Vector("Image", "∋")          // F and b are context names
    // The syntactic statement rule fires on the original: its corpus type and
    // the index prose differ in notation, so only the name rule could — and
    // the hole carries a prime.  So the original stays IN the excluded pool;
    // that is exactly what the lane-form rule exists to catch, and exactly
    // what the instrument must report rather than hide.
    fr.pool.excluded shouldBe empty
    // Overture.Basic.ℓ₁ is out of scope (no Overture import) and never
    // enters the pool; the two Setoid.Functions rows the goal tokens touch
    // tie at 4 (two overlaps, ± the name bonus and the `∈` misfit for the
    // original) and split on arity, and 𝑖𝑑 trails at 0.
    fr.pool.ranked.map(_.prettyQname) shouldBe Vector(
      "Setoid.Functions.Inverses.IsInRange→IsInImage",
      "Setoid.Functions.Inverses.Inv",
      "Setoid.Functions.Basic.𝑖𝑑")
    fr.targets.map(t => (t.qname, t.status, t.rank, t.detail)) shouldBe Vector(
      ("Setoid.Functions.Inverses.Image_∋_.eq", "non-function", None, Some("constructor")),
      ("Setoid.Functions.Inverses.Inv",          "ranked",       Some(2), None),
      ("Relation.Binary.Bundles.Setoid.sym",     "not-in-corpus", None, None),
      ("Setoid.Homomorphisms.Basic.𝒾𝒹",          "out-of-scope", None, Some("Setoid.Homomorphisms.Basic")))
    fr.restates.map(t => (t.qname, t.status, t.rank)) shouldBe Vector(
      ("Setoid.Functions.Inverses.IsInRange→IsInImage", "ranked", Some(1)))
    fr.top.map(_._1) shouldBe fr.pool.ranked.take(3).map(_.prettyQname)
  }

  test("evaluate: the name rule excludes an original whose bare name is the hole's, and the status says so") {
    val unprimed = entry.copy(hole = "IsInRange→IsInImage")
    val fr = RetrievalRecall.evaluate(cfg(exclude = true), corpus, TokenOverlapScorer, unprimed, recorded, fixtureSource).unsafeRunSync()
    fr.pool.excluded.map(_._1) shouldBe Vector("name:Setoid.Functions.Inverses.IsInRange→IsInImage")
    // `restates:` is measured in the UNEXCLUDED pool regardless: still rank 1.
    fr.restates.head.status shouldBe "ranked"
    fr.restates.head.rank shouldBe Some(1)
    // A `target:` naming the excluded row would be reported as excluded, with the reason.
    val gamed = unprimed.copy(tags = unprimed.tags :+ "target:Setoid.Functions.Inverses.IsInRange→IsInImage")
    val fr2 = RetrievalRecall.evaluate(cfg(exclude = true), corpus, TokenOverlapScorer, gamed, recorded, fixtureSource).unsafeRunSync()
    fr2.targets.last shouldBe TargetStatus("Setoid.Functions.Inverses.IsInRange→IsInImage", "target", "excluded", None, None,
      Some("name:Setoid.Functions.Inverses.IsInRange→IsInImage"))
  }

  test("evaluate: a recorded context is used as is, and the reconstruction is checked against it") {
    val live = RetrievalRecall.RecordedGoal("Image F ∋ b",
      Some(Vector("α", "ρᵃ", "β", "ρᵇ", "𝑨", "𝑩", "F", "b", "w").map(n => CtxEntry(n, "", None))))
    val fr = RetrievalRecall.evaluate(cfg(exclude = true), corpus, TokenOverlapScorer, entry, live, fixtureSource).unsafeRunSync()
    fr.contextSource shouldBe "report"
    fr.reconstructionMatches shouldBe Some(true)
    val drifted = live.copy(context = Some(Vector(CtxEntry("F", "", None), CtxEntry("b", "", None))))
    RetrievalRecall.evaluate(cfg(exclude = true), corpus, TokenOverlapScorer, entry, drifted, fixtureSource).unsafeRunSync()
      .reconstructionMatches shouldBe Some(false)
  }

  test("recall arithmetic: over all names and over reachable ones; MRR over reachable") {
    val ks = Vector(1, 8)
    val ss = Vector(
      TargetStatus("a", "target", "ranked", Some(1), Some(1.0), None),
      TargetStatus("b", "target", "ranked", Some(4), Some(1.0), None),
      TargetStatus("c", "target", "non-function", None, None, Some("constructor")),
      TargetStatus("d", "target", "not-in-corpus", None, None, None))
    val s = RecallSummary.of(ss, ks)
    s.names shouldBe 4
    s.reachable shouldBe 2
    s.hitsAt shouldBe Map(1 -> 1, 8 -> 2)
    s.mrr shouldBe (1.0 + 0.25) / 2
    val j = s.toJson(ks)
    j.hcursor.downField("recallAt").get[Double]("8") shouldBe Right(0.5)
    j.hcursor.downField("recallReachableAt").get[Double]("8") shouldBe Right(1.0)
    RecallSummary.of(Vector.empty, ks).mrr shouldBe 0.0
  }

  test("recordedGoals: goals and contexts come from the outcomes; anomalies are skipped") {
    val report = io.circe.parser.parse(
      """{"outcomes":[
        |  {"benchmarkId":"a","goal":"m + n ≡ n + m","searchStatus":"exhausted",
        |   "goalContext":[{"name":"m","type":"ℕ"},{"name":"n","type":"ℕ"}]},
        |  {"benchmarkId":"b","goal":"T","searchStatus":"solved"},
        |  {"benchmarkId":"c","goal":"?","searchStatus":"anomaly"}]}""".stripMargin).toOption.get
    RetrievalRecall.recordedGoals(report) shouldBe Map(
      "a" -> RetrievalRecall.RecordedGoal("m + n ≡ n + m", Some(Vector(CtxEntry("m", "ℕ", None), CtxEntry("n", "ℕ", None)))),
      "b" -> RetrievalRecall.RecordedGoal("T", None))
  }

  test("index model: stratum and tagged values") {
    entry.stratum shouldBe "agda-algebras/wholesale"
    entry.copy(tags = Vector.empty).stratum shouldBe "agda-algebras"
    entry.taggedValues("restates:") shouldBe Vector("Setoid.Functions.Inverses.IsInRange→IsInImage")
    entry.taggedValues("target:").size shouldBe 4
  }

  test("the committed index: every agda-algebras row carries one restates: tag; the frozen stdlib rows carry none") {
    val index = Paths.get(sys.props("user.dir")).getParent.resolve("data/benchmarks/benchmark-index.jsonl")
    assume(Files.exists(index), s"index not found at $index")
    val rows = Scaffold.readIndex(index, None).unsafeRunSync()
    val alg  = rows.filter(_.source == "agda-algebras")
    alg.size shouldBe 21
    alg.foreach(e => e.taggedValues("restates:").size shouldBe 1)
    alg.count(_.taggedValues("target:").nonEmpty) shouldBe 18
    rows.filter(_.source == "agda-stdlib").filterNot(_.id.startsWith("haystack-"))
      .foreach(e => e.tags.exists(t => t.startsWith("restates:") || t.startsWith("target:")) shouldBe false)
  }
}
