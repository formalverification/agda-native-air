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

  /** A corpus row with every field the server's decoder requires. */
  private def fullRow(q: String, kind: String, bodyJson: String): String = {
    val name = q.substring(q.lastIndexOf('.') + 1); val mod = q.substring(0, q.lastIndexOf('.'))
    s"""{"file":"$mod.lagda.md","module":"$mod._","name":"$name","qname":"$mod._.$name","prettyModule":"$mod","prettyName":"$name",""" +
      s""""prettyQname":"$q","type":"T","typeAstVersion":"0.3-v0","defKind":"$kind","dependencies":[],"astSize":1,"hasBody":true,"body":$bodyJson}"""
  }

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
    ks = Vector(1, 8), queryLimit = 5000, top = 3, allowUntypedContext = false)

  // --------------------------------------------------------------------------
  // InMemoryCorpus: the server's semantics
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

  test("definition table: the last row per name wins outright, so a bodyless duplicate removes an earlier body (#152 review)") {
    def j(s: String) = io.circe.parser.parse(s).toOption.get
    def full(q: String, kind: String, body: String) = j(fullRow(q, kind, body))
    val t = DefinitionTable.fromRows(Iterator(
      full("M.d", "function", "\"Σ A B\""),
      full("M.d", "constructor", "null"),
      full("M.e", "function", "\"x\""),
      full("M.e", "function", "\"y z\""),
      j("""{"defKind":"function","body":"nameless"}""")))
    t.bodyOf("M.d") shouldBe None                    // the constructor row won, and it has no body
    t.bodyOf("M.e") shouldBe Some(Vector("y", "z")) // the later body won
    t.size shouldBe 1
  }

  test("definition table: a row the server would drop is not a row here either, even as a later duplicate (#152 review, round two)") {
    def j(s: String) = io.circe.parser.parse(s).toOption.get
    val t = DefinitionTable.fromRows(Iterator(
      j(fullRow("M.d", "function", "\"Σ A B\"")),
      j("""{"prettyQname":"M.d","type":"T","defKind":"constructor","prettyModule":"M","body":null}"""), // wire fields only: the server drops it
      j("""{"prettyQname":"M.f","defKind":"function","body":"would-be-a-body"}""")))
    t.bodyOf("M.d") shouldBe Some(Vector("Σ", "A", "B"))  // the partial duplicate removed nothing
    t.bodyOf("M.f") shouldBe None                          // and the partial row contributed nothing
  }

  test("cli: an empty scorer or cut-off list is refused; an option as a value is refused; the diagnostic names --all (#152 review, round two)") {
    val base = List("--index", "i", "--corpus", "c", "--report", "r", "--project-root", ".", "--out", "o", "--all")
    RetrievalRecall.parseArgs(base ++ List("--scorers", "")).left.toOption.get should include ("--scorers")
    RetrievalRecall.parseArgs(base ++ List("--k", " , ")).left.toOption.get should include ("--k")
    RetrievalRecall.parseArgs(List("--index", "--all", "--corpus", "c")).left.toOption.get should include ("--index")
    RetrievalRecall.parseArgs(base ++ List("--scoreers", "x")).left.toOption.get should include ("--all")
    RetrievalRecall.parseArgs(base ++ List("--allow-untyped-context", "on")).map(_.allowUntypedContext) shouldBe Right(true)
    RetrievalRecall.parseArgs(base).map(_.allowUntypedContext) shouldBe Right(false)
  }

  test("cli: exactly one of --ids and --all, and --ids must name something (#152 review, round three)") {
    val base = List("--index", "i", "--corpus", "c", "--report", "r", "--project-root", ".", "--out", "o")
    RetrievalRecall.parseArgs(base ++ List("--ids", "")).left.toOption.get should include ("--ids")
    RetrievalRecall.parseArgs(base ++ List("--ids", " , ,")).left.toOption.get should include ("--ids")
    RetrievalRecall.parseArgs(base ++ List("--ids", "a", "--all")).left.toOption.get should include ("not both")
    RetrievalRecall.parseArgs(base).left.toOption.get should include ("--ids or --all")
    RetrievalRecall.parseArgs(base ++ List("--all")).map(_.ids) shouldBe Right(None)
    RetrievalRecall.parseArgs(base ++ List("--ids", "a, b")).map(_.ids) shouldBe Right(Some(Set("a", "b")))
  }

  test("context: a recorded context with a blank type is untyped; an explicitly empty one is typed (#152 review, round three)") {
    RetrievalRecall.untypedContext(None) shouldBe true
    RetrievalRecall.untypedContext(Some(Vector.empty)) shouldBe false
    RetrievalRecall.untypedContext(Some(Vector(CtxEntry("m", "ℕ", None)))) shouldBe false
    RetrievalRecall.untypedContext(Some(Vector(CtxEntry("m", "ℕ", None), CtxEntry("n", "  ", None)))) shouldBe true
    val idf = Scorers.idfUnfold.instantiate(DefinitionTable.empty)
    val blank = RetrievalRecall.RecordedGoal("Image F ∋ b", Some(Vector(CtxEntry("F", "Func 𝑨 𝑩", None), CtxEntry("b", "", None))))
    val fr = RetrievalRecall.evaluate(cfg(exclude = true), corpus, idf, entry, blank, fixtureSource).unsafeRunSync()
    fr.contextSource shouldBe "report"
    fr.degraded shouldBe true
    RetrievalRecall.untypedRefusal(Vector(idf), Vector("x"), allow = false).get should include ("typed context")
  }

  test("context: an arrow inside an identifier is not a binder boundary in the reconstruction (#152 review, round three)") {
    val src = "f : {A B : Set} → (p : A→B) → A → B\nf p a = {!!}\n"
    FixtureContext.reconstruct(src, "f") shouldBe Vector("A", "B", "p", "a")
    FixtureContext.telescope("(p : A→B) → A → B").map(_.name) shouldBe Vector(Some("p"), None)
  }

  test("a hypothesis-reading scorer over a report without context types is refused unless opted into, and then marked degraded (#152 review, round two)") {
    val idf = Scorers.idfUnfold.instantiate(DefinitionTable.empty)
    val tok = Scorers.default.instantiate(DefinitionTable.empty)
    RetrievalRecall.untypedRefusal(Vector(idf), Vector("a", "b"), allow = false).get should include ("idf-unfold")
    RetrievalRecall.untypedRefusal(Vector(tok), Vector("a"), allow = false) shouldBe None
    RetrievalRecall.untypedRefusal(Vector(idf), Vector.empty, allow = false) shouldBe None
    RetrievalRecall.untypedRefusal(Vector(idf), Vector("a"), allow = true) shouldBe None
    val untypedGoal = RetrievalRecall.RecordedGoal("Image F ∋ b", None)
    RetrievalRecall.evaluate(cfg(exclude = true), corpus, idf, entry, untypedGoal, fixtureSource).unsafeRunSync().degraded shouldBe true
    RetrievalRecall.evaluate(cfg(exclude = true), corpus, tok, entry, untypedGoal, fixtureSource).unsafeRunSync().degraded shouldBe false
    val typed = untypedGoal.copy(context = Some(Vector("F", "b").map(n => CtxEntry(n, "T", None))))
    RetrievalRecall.evaluate(cfg(exclude = true), corpus, idf, entry, typed, fixtureSource).unsafeRunSync().degraded shouldBe false
  }

  test("cli: an unknown option is refused rather than silently ignored (#152 review)") {
    val base = List("--index", "i", "--corpus", "c", "--report", "r", "--project-root", ".", "--out", "o", "--all")
    val typo = RetrievalRecall.parseArgs(base ++ List("--scoreers", "idf-unfold"))
    typo.isLeft shouldBe true
    typo.left.toOption.get should include ("--scoreers")
    RetrievalRecall.parseArgs(base ++ List("--scorers", "idf-unfold")).map(_.scorers.map(_.name)) shouldBe Right(Vector("idf-unfold"))
    RetrievalRecall.parseArgs(base ++ List("--scorers")).isLeft shouldBe true
  }

  test("corpus: a name query matches prettyName as well as prettyQname, as the server's search_by_name does (#152 review, round five)") {
    // A row whose prettyName is not a substring of its prettyQname: no row of
    // either published corpus is shaped so (prettyName is the last segment on
    // all 68,699), but the server's predicate has the second disjunct and the
    // replay mirrors it rather than resting on the measurement.
    val hit = row("Setoid.X.lemma", "A → B")
    val c   = new InMemoryCorpus(Vector(hit), Map("Setoid.X.lemma" -> "other-name"))
    c.byName("other", 10).unsafeRunSync() shouldBe Vector(hit)
    c.byName("X.lem", 10).unsafeRunSync() shouldBe Vector(hit)
    c.byName("missing", 10).unsafeRunSync() shouldBe Vector.empty
    // Without a recorded name the bare name stands in, which is the same
    // predicate whenever prettyName is the last segment.
    new InMemoryCorpus(Vector(hit)).byName("lemma", 10).unsafeRunSync() shouldBe Vector(hit)
    new InMemoryCorpus(Vector(hit)).byName("other", 10).unsafeRunSync() shouldBe Vector.empty
    // The loader records the field from the row itself.
    val rowJson = io.circe.parser.parse(
      """{"file":"f.lagda.md","module":"Setoid.X","name":"lemma","qname":"Setoid.X.lemma",
        |"prettyModule":"Setoid.X","prettyName":"other-name","prettyQname":"Setoid.X.lemma",
        |"type":"A → B","typeAstVersion":"0.3-v0","defKind":"function",
        |"dependencies":[],"astSize":3,"hasBody":true,"body":"x"}""".stripMargin).toOption.get
    val tmp = Files.createTempFile("recall-rows", ".jsonl")
    try {
      Files.write(tmp, rowJson.noSpaces.getBytes(java.nio.charset.StandardCharsets.UTF_8))
      val (loaded, bad, _) = InMemoryCorpus.load(tmp).unsafeRunSync()
      bad shouldBe 0
      loaded.byName("other-name", 10).unsafeRunSync().map(_.prettyQname) shouldBe Vector("Setoid.X.lemma")
      loaded.prettyNameOf(loaded.rows.head) shouldBe "other-name"
      // The server skips only the EMPTY line; a whitespace-only line reaches
      // its parser and counts as a dropped line, so it does here (round six).
      Files.write(tmp, (rowJson.noSpaces + "\n\n   \n" + rowJson.noSpaces + "\n").getBytes(java.nio.charset.StandardCharsets.UTF_8))
      val (loaded2, bad2, _) = InMemoryCorpus.load(tmp).unsafeRunSync()
      bad2 shouldBe 1
      loaded2.rows.size shouldBe 1 // the duplicate row: last wins
    } finally Files.delete(tmp)
  }

  test("corpus: a row is one the server's decoder keeps, projected to the wire subset (#152 review, rounds two and three)") {
    val full = io.circe.parser.parse(
      """{"file":"f.lagda.md","module":"Overture.Basic._","name":"𝑖𝑑","qname":"Overture.Basic._.𝑖𝑑",
        |"prettyModule":"Overture.Basic","prettyName":"𝑖𝑑","prettyQname":"Overture.Basic.𝑖𝑑",
        |"type":"(A : Set a) → A → A","typeAstVersion":"0.3-v0","typeAst":{},"kind":"definition","defKind":"function",
        |"dependencies":["Agda.Primitive.Set"],"astSize":19,"hasBody":true,"body":"λ x → x"}""".stripMargin).toOption.get
    SearchHit.fromCorpusRow(full) shouldBe Right(SearchHit("Overture.Basic.𝑖𝑑", "(A : Set a) → A → A", "function", "Overture.Basic", hasBody = true))
    // The wire subset alone is NOT a corpus row: the server requires the
    // extraction fields too, and drops a line without them.
    val wireOnly = io.circe.parser.parse(
      """{"prettyQname":"Overture.Basic.𝑖𝑑","type":"(A : Set a) → A → A","defKind":"function","prettyModule":"Overture.Basic","hasBody":true}""").toOption.get
    SearchHit.fromCorpusRow(wireOnly).isLeft shouldBe true
    SearchHit.fromCorpusRow(io.circe.Json.obj()).isLeft shouldBe true
    // `typeAst` is not required, and `hasBody` falls back to a nonempty body, as on the server.
    val noAstNoHasBody = full.mapObject(_.remove("typeAst").remove("hasBody"))
    SearchHit.fromCorpusRow(noAstNoHasBody).map(_.hasBody) shouldBe Right(true)
    SearchHit.fromCorpusRow(noAstNoHasBody.mapObject(_.add("body", io.circe.Json.Null))).map(_.hasBody) shouldBe Right(false)
    // The server parses `body` as optional text before `hasBody`: a non-text
    // body fails the row even with `hasBody` present (round four).
    SearchHit.fromCorpusRow(full.mapObject(_.add("body", io.circe.Json.fromInt(5)))).isLeft shouldBe true
    SearchHit.fromCorpusRow(full.mapObject(_.add("body", io.circe.Json.Null))).map(_.hasBody) shouldBe Right(true)
  }

  // --------------------------------------------------------------------------
  // FixtureContext: the goal context from the source
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

  test("context: the clause read is the one that carries the hole, not the first equation (#152 review, round six)") {
    val src =
      """f : (n : ℕ) → P n
        |f zero = base
        |f n = {!!}
        |""".stripMargin
    FixtureContext.reconstruct(src, "f") shouldBe Vector("n")
    // A clause spread over several lines is read whole, and a clause after
    // the hole's is not read at all.
    val src2 =
      """g : (x y : ℕ) → Q x y
        |g zero y = base
        |g x
        |  y = {!!}
        |g _ _ = other
        |""".stripMargin
    FixtureContext.reconstruct(src2, "g") shouldBe Vector("x", "y")
  }

  test("context: a parenthesised type is one anonymous premise, and a wildcard pattern binds nothing") {
    val src = "f : {A B : Set} → (A → B) → A → B\nf _ a = {!!}\n"
    FixtureContext.reconstruct(src, "f") shouldBe Vector("A", "B", "a")
    FixtureContext.reconstruct("nothing here", "f") shouldBe Vector.empty
  }

  // --------------------------------------------------------------------------
  // The instrument: statuses, ranks, regimes, arithmetic
  // --------------------------------------------------------------------------

  test("evaluate: every status by name, the target rank, and the original in the unexcluded pool") {
    val fr = RetrievalRecall.evaluate(cfg(exclude = true), corpus, TokenOverlapScorer, entry, recorded, fixtureSource).unsafeRunSync()
    fr.contextSource shouldBe "reconstructed"
    fr.goalTokens shouldBe Vector("Image", "∋")          // F and b are context names
    // The syntactic statement rule fires on the original: its corpus type and
    // the index prose differ in notation, so only the name rule could, and
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
    fr2.targets.last shouldBe TargetStatus("Setoid.Functions.Inverses.IsInRange→IsInImage", "target",
      Fate.Excluded("name:Setoid.Functions.Inverses.IsInRange→IsInImage"))
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
    // The same names in another order are a drift too: saturated tuples are
    // spelled over the context in order (#152 review, round two).
    val permuted = live.copy(context = Some(live.context.get.reverse))
    RetrievalRecall.evaluate(cfg(exclude = true), corpus, TokenOverlapScorer, entry, permuted, fixtureSource).unsafeRunSync()
      .reconstructionMatches shouldBe Some(false)
  }

  test("recall arithmetic: over all names and over reachable ones; MRR over reachable") {
    val ks = Vector(1, 8)
    val ss = Vector(
      TargetStatus("a", "target", Fate.Ranked(1, 1.0)),
      TargetStatus("b", "target", Fate.Ranked(4, 1.0)),
      TargetStatus("c", "target", Fate.NonFunction("constructor")),
      TargetStatus("d", "target", Fate.NotInCorpus))
    // The report's vocabulary reads off the fate: the label, rank and score
    // only when ranked, detail only when there is a reason to give.
    ss.map(_.status) shouldBe Vector("ranked", "ranked", "non-function", "not-in-corpus")
    ss.map(_.toJson.hcursor.downField("rank").focus.isDefined) shouldBe Vector(true, true, false, false)
    ss.map(_.toJson.hcursor.downField("detail").focus.isDefined) shouldBe Vector(false, false, true, false)
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

  test("corpus digest: the report pins the corpus by content, and reads the replayed run's own digest (#152 review, round six)") {
    val tmp = Files.createTempFile("digest", ".jsonl")
    try {
      Files.write(tmp, "abc".getBytes(java.nio.charset.StandardCharsets.UTF_8))
      Digest.sha256Hex(tmp).unsafeRunSync() shouldBe "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    } finally Files.delete(tmp)
    val withDigest = io.circe.parser.parse("""{"corpus":{"path":"c.jsonl","sha256":"deadbeef"},"outcomes":[]}""").toOption.get
    RetrievalRecall.reportCorpusDigest(withDigest) shouldBe Some("deadbeef")
    RetrievalRecall.reportCorpusDigest(io.circe.Json.obj("outcomes" -> io.circe.Json.arr())) shouldBe None
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
