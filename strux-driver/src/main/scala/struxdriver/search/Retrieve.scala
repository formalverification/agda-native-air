/** ============================================================================
  *  Retrieve.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/search/Retrieve.scala
  *  Package: struxdriver.search
  *
  *  Purpose
  *  -------
  *  The P2 retrieval proposer of issue #113 (sub-issue #123): candidates from
  *  the agda-mcp corpus search tools (`search_by_name` / `search_by_type` /
  *  `get_dependencies`, registered when the server is started with
  *  `--corpus`), behind the P1 `Proposer` seam and COMPOSED with the fixed
  *  space — closers, assumptions, and `using`-list applications stay (they
  *  carry the constructors the corpus does not row), retrieval adds the
  *  imported-module haystacks, so the P2 space is a superset of P1's by
  *  construction and any measured delta is attributable to retrieval.
  *
  *  Scope (the design decision recorded on #123)
  *  --------------------------------------------
  *  A candidate must resolve in the fixture's module, and `open import M
  *  using (xs)` still grants qualified access to ALL of `M` (verified
  *  against the pinned toolchain), so the legal pool is every corpus row
  *  whose module the fixture imports — module equal to an imported module or
  *  extending it (`Relation.Binary.PropositionalEquality.Core` under an
  *  import of `…PropositionalEquality`; nested record modules likewise).
  *  Rendering tries, in order: the bare name when the importing module's own
  *  `using` list already opens it (so the candidate dedups against the fixed
  *  space), the row's `prettyQname` verbatim (valid for rows nested inside
  *  the imported module), and the importing module qualifying the bare name
  *  (valid for re-exports, whose defining module is not itself imported).
  *  The interaction lane arbitrates: the first rendering `type_of` can
  *  answer wins, and a name the lane cannot type stays out of the space —
  *  exactly P1's rule for the fixed pool.
  *
  *  Target exclusion (the anti-gaming policy)
  *  -----------------------------------------
  *  Every M1-5 obligation IS a stdlib lemma, so the corpus contains the
  *  answers verbatim.  Two rules, both reported per fixture rather than
  *  silently applied: a row whose bare name equals the obligation's hole
  *  name is excluded (this also catches record-field projections of the
  *  target, deliberately — conservative), and a row whose type normalises
  *  to the obligation's stated type is excluded as an exact-statement
  *  alias.  The normalisation is syntactic (whitespace, `∀` sugar,
  *  positional binder renaming); a differently-STATED but convertible lemma
  *  is legitimately in the space — using it is a real proof step.  The
  *  whole policy can be switched off (`--exclude-target off`) for the
  *  clearly-labeled mechanism-control sweep, never for a headline.
  *
  *  Ranking (deterministic; the premise-selection seam)
  *  ---------------------------------------------------
  *  Corpus rows arrive with fully qualified, alias-form types
  *  (`Algebra.Definitions.Commutative Agda.Builtin.Equality._≡_ …`), so the
  *  scorer normalises corpus tokens to bare segments (`Agda.Builtin.Nat._+_`
  *  → `+`) before overlap with the goal display's own tokens; name-fragment
  *  matches break the alias opacity (`+-comm` contains `+`).  The scorer is
  *  its own trait (`CandidateScorer`) so premise-selection scores
  *  (docs/PLAN.md Phase 2) can replace token overlap without touching the
  *  proposer; ties break cheap-before-expensive on approximate arity, then on
  *  the qname, so ranking is total and deterministic.  A scorer sees the
  *  WHOLE pool it ranks (issue #19): the stage-two measurement on #123 found
  *  token overlap drowning the needles of 3,000-row wholesale pools under the
  *  library's generic projections, and the first thing a stronger
  *  deterministic scorer needs is the pool's own document frequencies.
  *  Scorers are selected by name (`Scorers.byName`, the `--scorer` knob); the
  *  default stays `token-overlap` so every published number reproduces.
  *
  *  The pool pipeline is shared (`RetrievalPool`)
  *  --------------------------------------------
  *  Query → union → scope → exclusion → `defKind` filter → rank is one pure
  *  function of the corpus tools, the fixture's scope, and the goal, used by
  *  the proposer here and by the offline recall instrument
  *  (RetrievalRecall.scala), which replays it over a corpus loaded in-process
  *  against a recorded goal display, so ranking is measured in seconds
  *  without a server or a loop-hour.  Only lane resolution and candidate
  *  shaping stay proposer-side.
  *
  *  Candidate shapes (three, the third forced by a wire answer)
  *  -----------------------------------------------------------
  *  Per ranked lemma, through the landed partial-application arithmetic and
  *  parenthesized (ADR decision 7): a hole-free `_`-argument form first
  *  (`(lemma _ _)` — closes in one probe when unification can solve the
  *  arguments), then argument-SATURATED forms over the goal context's
  *  assumptions (`(lemma m n)`, every tuple up to a small arity/combination
  *  bound), then the `{!!}`-refinement form P1 measured.  The saturated
  *  forms exist because of a wire fact the #123 design comment reserved as
  *  an open question and this PR pinned (captures
  *  wire-fill-hole-blocked-{subholes,metas}.json): fill_hole REFUSES a
  *  candidate whose metas or sub-holes carry blocked constraints —
  *  `(+-comm {!!} {!!})` at `m + n ≡ n + m` is a type_error
  *  ([UnsolvedConstraints], blocked on the argument metas under the
  *  non-injective `_+_`) and `(+-comm _ _)` likewise — so a lemma whose
  *  conclusion applies a defined function to its argument variables can
  *  ONLY commit fully applied.  That class (`Commutative`, `Associative`,
  *  the alias-stated equational family) is precisely what retrieval exists
  *  to reach.  Saturated and `_`-forms are hole-free compound candidates —
  *  the class that re-opens the P1 dedup A/B.  Binder counts come from lane
  *  `type_of` on the accepted rendering (which the wire shows expands alias
  *  types: `Data.Nat.Properties.+-comm` infers `(x y : ℕ) → x + y ≡ y + x`,
  *  capture wire-type-of-qualified.json), never from the corpus type string.
  *
  *  Integration
  *  -----------
  *  `CorpusSearch` abstracts the three tools so the pipeline is pure-testable
  *  against a canned corpus (RetrieveSpec); production wires Oracle's
  *  retrieval calls (phase "retrieval" in the timing ledger).  Consumed by
  *  LoopHarness.scala behind `--proposer retrieval`.
  *
  *  ============================================================================
  */
package struxdriver.search

import cats.effect.{IO, Ref}
import cats.syntax.all._
import scala.annotation.tailrec

/** The three corpus tools, as the proposer consumes them.  Implemented over
  * the live server by `Oracle` (ledgered, phase "retrieval") and over a
  * canned row set in the pure tests.
  */
trait CorpusSearch {
  def byName(pattern: String, limit: Int): IO[Vector[SearchHit]]
  def byType(pattern: String, limit: Int): IO[Vector[SearchHit]]
  def dependenciesOf(prettyQname: String): IO[Vector[SearchHit]]
}

/** Retrieval tunables.  `topK` bounds the LEMMAS proposed per goal — each
  * accepted lemma then contributes an `_`-form, zero or more bounded
  * saturated forms, and a `{!!}`-refinement form, so the candidate count
  * per lemma varies (see `shapes`); `queryLimit` is the per-query
  * result cap sent to the server — the server truncates lexicographically at
  * its own default of 20, so the client must ask wide (Data.Nat.Properties
  * alone is ~2000 rows) and rank itself, and a query that returns exactly
  * `queryLimit` rows is counted as truncated in the stats rather than passed
  * off as complete.  `expandDeps` adds `get_dependencies` neighbors of the
  * top-scored lemmas to the pool (one hop, before the topK cut).
  */
final case class RetrievalConfig(
  topK:          Int,
  queryLimit:    Int,
  expandDeps:    Boolean,
  excludeTarget: Boolean
)
object RetrievalConfig {
  val default: RetrievalConfig =
    RetrievalConfig(topK = 8, queryLimit = 5000, expandDeps = false, excludeTarget = true)
}

/** What retrieval did for one fixture, for report.json — the honesty ledger:
  * nothing is silently dropped, every cut is counted and the exclusions are
  * NAMED, so a gamed run and a fair run are distinguishable from the report
  * alone.
  */
final case class RetrievalStats(
  queries:        Int            = 0,
  truncated:      Int            = 0,
  hits:           Int            = 0,
  inScope:        Int            = 0,
  excluded:       Vector[String] = Vector.empty, // "name:+-comm" | "statement:…"
  nonFunction:    Int            = 0,
  laneRejected:   Int            = 0,
  proposedLemmas: Vector[String] = Vector.empty  // accepted renderings, ranked
)

/** The fixture's import surface, as scope authority: which corpus rows are
  * legally reachable, and through which imported module.
  */
final case class ImportScope(modules: Vector[ImportedModule]) {

  /** The imported module a row is reachable through: equal to the row's
    * module, or a proper prefix of it at a dot boundary (nested record
    * modules, re-export `Core` modules).  Longest match wins, so the most
    * specific import qualifies the rendering.
    */
  def importingModuleOf(hitModule: String): Option[ImportedModule] =
    modules
      .filter(m => hitModule == m.module || hitModule.startsWith(m.module + "."))
      .sortBy(-_.module.length)
      .headOption
}

/** The obligation's own identity, for the exclusion policy. */
final case class TargetExclusion(holeName: String, statement: String) {
  def reasonFor(hit: SearchHit): Option[String] =
    if (hit.bareName == holeName) Some(s"name:${hit.prettyQname}")
    else if (Statements.normalize(hit.tpe) == Statements.normalize(statement))
      Some(s"statement:${hit.prettyQname}")
    else None
}

/** Syntactic statement normalisation for the exact-statement-alias rule:
  * whitespace collapsed, `∀` tokens dropped, and binder names renamed
  * positionally (`(m n : ℕ) → m + n ≡ n + m` and `(x y : ℕ) → x + y ≡ y + x`
  * normalise identically).  Deliberately NOT a convertibility check: `∀ n →`
  * sugar without an annotation, and alias-stated types, stay distinct — the
  * name rule carries those, and the residue is stated policy (see the file
  * header), not an oversight.
  */
object Statements {

  /** The bracket characters the tokenizer treats as single tokens: the
    * openers, the closers, and both together.  The binder telescope
    * (`Actions`), the piece splitter below, and the fixture-context
    * reconstruction (`FixtureContext`) count depth with the same sets.
    */
  val Opens:  Set[Char] = Set('(', '{', '⦃')
  val Closes: Set[Char] = Set(')', '}', '⦄')
  val Delims: Set[Char] = Opens ++ Closes

  /** The delimiters as tokens, for the token-level filters. */
  val DelimTokens: Set[String] = Delims.map(_.toString)

  /** The tokens that carry structure rather than meaning: the delimiters,
    * the arrow, the colon, `∀`, the dot, and the semicolon.  The placeholder
    * scorer's misfit penalty and the query filter skip them; the IDF family
    * adds `λ` and `=`, which the unfolded bodies contain (`IdfScorer`).
    */
  val Structural: Set[String] = DelimTokens ++ Set("→", ":", "∀", ".", ";")

  /** A token: one delimiter, or a maximal run of characters that are
    * neither whitespace nor delimiters (`\p{javaWhitespace}` is
    * `Char.isWhitespace`).
    */
  private val Token = """[(){}⦃⦄]|[^\p{javaWhitespace}(){}⦃⦄]+""".r

  /** Tokenize: delimiters are single tokens, everything else splits on
    * whitespace.  Total, and linear in the text (the bodies of a whole
    * corpus go through here at load).
    */
  def tokens(s: String): Vector[String] = Token.findAllIn(s).toVector

  /** The opener tokens that begin a binder group. */
  private val OpenTokens: Set[String] = Opens.map(_.toString)

  /** The binder names of a token stream: inside each delimiter group, the
    * tokens before a `:` at that group's own level.  A group without a `:`
    * (a parenthesized type) binds nothing, and so does one whose first
    * tokens open a nested group.  Every suffix of the stream that begins at
    * an opener is read once.
    */
  private def binderNames(ts: Vector[String]): Vector[String] =
    ts.tails.flatMap {
      case open +: rest if OpenTokens(open) =>
        val (names, after) = rest.span(t => t != ":" && !Delims(t.head))
        if (after.headOption.contains(":")) names else Vector.empty
      case _ => Vector.empty
    }.toVector

  /** One depth-0 piece of a segment: a bracket group, with the character
    * that opened it and its content, or the bare text between groups.
    */
  sealed trait Piece extends Product with Serializable
  final case class Group(open: Char, content: String) extends Piece
  final case class Bare(text: String)                 extends Piece

  /** The state of the piece scan: the pieces so far, where the piece under
    * construction begins, the bracket depth, and the opener of the group
    * being read.
    */
  private final case class PieceScan(out: Vector[Piece], start: Int, depth: Int, open: Char)

  /** Depth-0 pieces of one segment: the bracket groups (with their opener)
    * and the bare text between them, in order; nested brackets stay inside
    * their group's content.  A fold over the character positions, cutting
    * at the depth-0 brackets.  Shared by the binder telescope
    * (`Actions.domainBinders`) and the fixture-context reconstruction
    * (`FixtureContext`), which had one copy each.
    */
  def pieces(seg: String): Vector[Piece] = {
    // The pieces with the bare text from the piece's start to `end` appended, when there is any.
    def withBare(s: PieceScan, end: Int): Vector[Piece] = {
      val t = seg.substring(s.start, end).trim
      if (t.isEmpty) s.out else s.out :+ Bare(t)
    }
    val end = seg.indices.foldLeft(PieceScan(Vector.empty, 0, 0, ' ')) { (s, i) =>
      val c = seg.charAt(i)
      if (Opens(c))
        if (s.depth == 0) PieceScan(withBare(s, i), i + 1, 1, c) else s.copy(depth = s.depth + 1)
      else if (Closes(c))
        if (s.depth == 1) PieceScan(s.out :+ Group(s.open, seg.substring(s.start, i)), i + 1, 0, s.open)
        else s.copy(depth = s.depth - 1)
      else s
    }
    withBare(end, seg.length)
  }

  /** The brackets the arrow splitter counts as depth: the delimiters and
    * the square brackets of a bracket mixfix (see `splitTopLevelArrows`).
    */
  private val ArrowOpens:  Set[Char] = Opens + '['
  private val ArrowCloses: Set[Char] = Closes + ']'

  /** Split a printed type on its depth-0 arrows, STANDALONE ones only: an
    * arrow separates two segments when whitespace (or the text's boundary)
    * sits on both sides of it, so an arrow inside an identifier
    * (`IsInRange→IsInImage`, `abelianGroup→group`, a name such as `→-cong`)
    * never splits the type.  Depth counts parentheses, braces, instance
    * braces, AND square brackets: a bracket mixfix such as `𝔻[ A → B ]` or
    * `𝕌[ … ]` encloses its argument, and an arrow inside it is not a binder
    * boundary (95 rows of the two published corpora carry one; PR #152
    * review, round four).  Whitespace is normalized first and segments are
    * trimmed.  The one arrow splitter behind the binder telescope
    * (`Actions.bindersOfPrinted`), the conclusion split (`IdfScorer`), and
    * the fixture-context reconstruction (`FixtureContext`); PR #152 review,
    * rounds two to four.
    */
  def splitTopLevelArrows(printed: String): Vector[String] = {
    val s = printed.replaceAll("\\s+", " ").trim
    def standalone(i: Int): Boolean =
      (i == 0 || s.charAt(i - 1).isWhitespace) && (i == s.length - 1 || s.charAt(i + 1).isWhitespace)
    // The depth before each character, then the cuts: the standalone arrows
    // at depth zero.  The segments are the text between consecutive cuts.
    val depths = s.iterator.scanLeft(0) { (d, c) =>
      if (ArrowOpens(c)) d + 1 else if (ArrowCloses(c)) math.max(0, d - 1) else d
    }.toVector
    val cuts   = s.indices.filter(i => s.charAt(i) == '→' && depths(i) == 0 && standalone(i)).toVector
    val bounds = (-1 +: cuts) :+ s.length
    bounds.zip(bounds.tail).map { case (from, to) => s.substring(from + 1, to).trim }
  }

  def normalize(stmt: String): String = {
    val ts      = tokens(stmt).filterNot(_ == "∀")
    val renames = binderNames(ts).distinct.zipWithIndex.map { case (n, i) => n -> s"x${i + 1}" }.toMap
    ts.map(t => renames.getOrElse(t, t)).mkString(" ")
  }
}

/** The scoring seam: deterministic scorers now, premise-selection scores
  * when the Phase 2 artifacts exist.  A scorer is handed the whole pool it
  * will rank, so it may precompute pool statistics (document frequencies for
  * the IDF family) before scoring rows; the returned function must be pure
  * and total over that pool.  Higher is better; ties are broken outside
  * (`RetrievalPool.rank`), cheap-before-expensive and then on the qname.
  * `name` is the knob value that selects the scorer (`--scorer`,
  * `PROOF_SEARCH_SCORER`) and is recorded in every run report.
  */
trait CandidateScorer {
  def name: String
  def scores(query: RankQuery, pool: Vector[SearchHit]): SearchHit => Double
  /** Whether the score depends on `RankQuery.hypothesisTokens`.  The offline
    * instrument refuses to replay such a scorer over a fixture whose context
    * types are not on record, since it would silently run as the
    * no-hypotheses variant under the scorer's own name (PR #152 review,
    * round two).
    */
  def readsHypotheses: Boolean = false
}

/** What a scorer is asked to rank against: the goal display's tokens and,
  * separately, the tokens of the local hypotheses' types (both through
  * `Queries`, so context names, numerals, and metas are already dropped).
  * The placeholder reads the goal alone; the hypotheses are there because
  * the lemmas that conclude the same thing differ in what they ASSUME:
  * `mon→hom`, `epi→hom`, `𝒾𝒹`, and `_≅_.to` all conclude `hom 𝑨 𝑩`, and only
  * the hypothesis `m : mon 𝑨 𝑩` says which one the goal wants (the haystack
  * tier's finding on #129, measured here on #19).
  */
final case class RankQuery(goalTokens: Set[String], hypothesisTokens: Set[String])
object RankQuery {
  def goalOnly(goalTokens: Set[String]): RankQuery = RankQuery(goalTokens, Set.empty)
}

/** A scorer by name, before it is bound to a corpus.  Scorers that unfold
  * definitions need the corpus's own bodies (`DefinitionTable`), which the
  * loop loads from its `--corpus` file and the instrument has in memory;
  * the rest ignore the table.
  */
final case class ScorerSpec(name: String, needsDefinitions: Boolean, instantiate: DefinitionTable => CandidateScorer)

/** The scorers by name.  `default` is the placeholder every published sweep
  * ranked with; it stays the default so those numbers reproduce, and a
  * stronger scorer is opted into by name (`--scorer`, `PROOF_SEARCH_SCORER`).
  * The IDF family is registered as an ablation grid so the offline
  * instrument can measure each rule alone (issue #19); `idf-unfold` is the
  * combination the measurements kept.
  */
object Scorers {
  private def fixed(sc: CandidateScorer): ScorerSpec = ScorerSpec(sc.name, needsDefinitions = false, _ => sc)
  private def idf(name: String, fragments: Boolean, conclusion: Double, nameWeight: Double,
                  unfold: Int = 0, normalize: Boolean = false, hypotheses: Double = 0.0): ScorerSpec =
    ScorerSpec(name, needsDefinitions = unfold > 0,
      table => new IdfScorer(name, fragments, conclusion, nameWeight, unfold, normalize,
                             if (unfold > 0) table else DefinitionTable.empty, hypotheses))

  val default: ScorerSpec = fixed(TokenOverlapScorer)

  /** The scorer the #19 measurements kept: every rule of the IDF family at
    * weight one: bare units on both sides, fragments, IDF over the pool, the
    * conclusion counted twice, the row's name, three unfolding steps through
    * the corpus bodies, the cosine norm, and the hypotheses' overlap with the
    * premises.  The name rule was first dropped on a confounded measurement
    * (name units stayed in the frequencies and the norm at weight zero) and
    * came back when the PR #152 review made the knob mean what it says: on
    * clean semantics it lifts fair-target recall@8 from 7/33 to 9/33 and
    * costs two originals at eight (14/21 to 12/21).  Against the placeholder
    * (1/33 and 5/21) the whole scorer is 9/33 and 12/21 at eight, 12/33 and
    * 20/21 at thirty-two (recall report `recall-ctx1-r2`, 2026-09-15); the
    * minus-one ablations below pin each rule's contribution.
    */
  val idfUnfold: ScorerSpec =
    idf("idf-unfold", fragments = true, conclusion = 1.0, nameWeight = 1.0, unfold = 3, normalize = true, hypotheses = 1.0)

  val all: Vector[ScorerSpec] = Vector(
    // The placeholders: the published one, and the same with the goal side bare-reduced.
    default,
    fixed(BareOverlapScorer),
    // The kept scorer and its minus-one-rule ablations.
    idfUnfold,
    idf("idf-unfold-no-fragments",  fragments = false, conclusion = 1.0, nameWeight = 1.0, unfold = 3, normalize = true,  hypotheses = 1.0),
    idf("idf-unfold-no-conclusion", fragments = true,  conclusion = 0.0, nameWeight = 1.0, unfold = 3, normalize = true,  hypotheses = 1.0),
    idf("idf-unfold-no-name",       fragments = true,  conclusion = 1.0, nameWeight = 0.0, unfold = 3, normalize = true,  hypotheses = 1.0),
    idf("idf-unfold-no-unfolding",  fragments = true,  conclusion = 1.0, nameWeight = 1.0, unfold = 0, normalize = true,  hypotheses = 1.0),
    idf("idf-unfold-no-norm",       fragments = true,  conclusion = 1.0, nameWeight = 1.0, unfold = 3, normalize = false, hypotheses = 1.0),
    idf("idf-unfold-no-hypotheses", fragments = true,  conclusion = 1.0, nameWeight = 1.0, unfold = 3, normalize = true,  hypotheses = 0.0),
    idf("idf-unfold-depth2",        fragments = true,  conclusion = 1.0, nameWeight = 1.0, unfold = 2, normalize = true,  hypotheses = 1.0),
    // The build-up ladder the #19 comment quotes, first hypothesis to last.
    idf("idf",                      fragments = false, conclusion = 0.0, nameWeight = 0.0),
    idf("idf-conclusion",           fragments = false, conclusion = 1.0, nameWeight = 0.0),
    idf("idf-name",                 fragments = false, conclusion = 0.0, nameWeight = 1.0),
    idf("idf-fragments",            fragments = true,  conclusion = 0.0, nameWeight = 0.0),
    idf("idf-full",                 fragments = true,  conclusion = 1.0, nameWeight = 1.0),
    idf("idf-norm",                 fragments = true,  conclusion = 1.0, nameWeight = 1.0, normalize = true),
    idf("idf-unfold3",              fragments = true,  conclusion = 1.0, nameWeight = 1.0, unfold = 3),
    idf("idf-unfold3-norm",         fragments = true,  conclusion = 1.0, nameWeight = 1.0, unfold = 3, normalize = true))

  def names: Vector[String] = all.map(_.name)
  def byName(name: String): Either[String, ScorerSpec] =
    all.find(_.name == name).toRight(s"unknown scorer: $name (one of ${names.mkString("|")})")
}

/** The P2 placeholder (issue #123): token overlap between the goal display
  * and the corpus type, a name bonus capped at one, a penalty per operator
  * the goal never mentions.  `score` is the row-local integer the published
  * sweeps ranked by; `scores` lifts it to the pool-aware seam unchanged.
  */
object TokenOverlapScorer extends CandidateScorer {

  val name: String = "token-overlap"

  override def scores(query: RankQuery, pool: Vector[SearchHit]): SearchHit => Double =
    hit => score(query.goalTokens, hit).toDouble


  /** A corpus type token, reduced to comparable form: last dot segment
    * (corpus types are fully qualified), outer underscores stripped (the
    * corpus writes `_+_` where a goal display shows infix `+`).
    */
  def bareToken(t: String): String = {
    val seg = t.substring(t.lastIndexOf('.') + 1)
    seg.stripPrefix("_").stripSuffix("_")
  }

  def score(goalTokens: Set[String], hit: SearchHit): Int = {
    val typeTokens = Statements.tokens(hit.tpe).map(bareToken).toSet
    val overlap    = goalTokens.count(typeTokens)
    // The name bonus is capped at one: stdlib names spell whole statements in
    // operator glyphs (`[m+n]∸[m+o]≡n∸o` contains both `+` and `≡`), and an
    // uncapped count hands the top ranks to symbol-soup names over the lemma
    // families the goal actually mentions (measured on the first shakedown).
    val nameHit = if (goalTokens.exists(hit.bareName.contains(_))) 1 else 0
    // Operators the goal never mentions are evidence of a different statement
    // family: without this penalty the `+ ≡` goal ranks the `*`-and-`+`
    // semiring bundles above the `+` lemmas themselves (second shakedown).
    // Pure-symbol tokens only — identifiers and numerals are not penalized,
    // because record/alias heads and literals appear in perfectly relevant
    // statements.
    val misfits = typeTokens.count(t =>
      !goalTokens(t) && !Statements.Structural(t) && t.nonEmpty && !t.exists(_.isLetterOrDigit))
    2 * overlap + nameHit - misfits
  }

  /** Approximate visible arity read off the CORPUS type string, for the
    * cheap-before-expensive rank tie-break only.  An alias-form type
    * (`Commutative _≡_ _+_`, no arrows) counts 0 — correctly cheap-looking,
    * since its real binders surface only through the lane, which is the
    * authority as ever; the splitter tolerates the qualified names.
    */
  def approxVisibleArity(hit: SearchHit): Int =
    Actions.bindersOfPrinted(hit.tpe).count(_.visibility == Visibility.Visible)
}

/** Matching units for the IDF scorers: a bare token, or its fragments.  A
  * fragment is a maximal run of identifier characters (letters, digits, and
  * the sub/superscript and modifier letters agda-algebras names use) or a
  * single symbol, after NFKC normalisation (which folds the mathematical
  * alphabets onto ASCII, so `𝑖𝑑`, `𝒾𝒹`, and `id` become one unit and `ᵃ` becomes
  * `a`) and case folding; identifier runs are further split at camel-case
  * humps (`IsInRange` → `is`, `in`, `range`; `HomReduct` → `hom`, `reduct`),
  * and the separators names are built from (`-`, `_`, `→`, `∼`, `.`, `′`)
  * yield no unit of their own.  Deterministic and hand-list-free: nothing
  * here knows any particular name.
  */
object Fragments {

  private val Separators: Set[Int] = "-_→∼.′'‴″⁻".codePoints().toArray.toSet

  private def isIdentChar(cp: Int): Boolean =
    Character.isLetterOrDigit(cp) || {
      val t = Character.getType(cp)
      t == Character.OTHER_NUMBER || t == Character.MODIFIER_LETTER || t == Character.NON_SPACING_MARK
    }

  def normalize(s: String): String =
    java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFKC).toLowerCase(java.util.Locale.ROOT)

  private def lowerOrDigit(cp: Int): Boolean = Character.isLowerCase(cp) || Character.isDigit(cp)

  /** The string spelled by a sequence of code points. */
  private def spell(cps: Seq[Int]): String = { val a = cps.toArray; new String(a, 0, a.length) }

  /** Split one identifier run at camel-case humps, on the ORIGINAL casing
    * (the run is lower-cased afterwards): a hump is an upper-case letter
    * following a lower-case letter or digit.  The humps are the cut points;
    * the pieces are the code points between consecutive cuts.
    */
  private def camelSplit(run: String): Vector[String] = {
    val cps    = run.codePoints().toArray.toVector
    val humps  = cps.indices.drop(1).filter(i => Character.isUpperCase(cps(i)) && lowerOrDigit(cps(i - 1))).toVector
    val bounds = (0 +: humps) :+ cps.length
    bounds.zip(bounds.tail).map { case (from, to) => spell(cps.slice(from, to)) }.filter(_.nonEmpty)
  }

  /** The fragments of one bare token (see the object header): the code
    * points after NFKC, consumed left to right; a maximal identifier run
    * yields its camel-case pieces, a symbol yields itself, a separator or a
    * space yields nothing.
    */
  def of(bare: String): Vector[String] = {
    @tailrec def go(cps: Vector[Int], acc: Vector[String]): Vector[String] =
      cps.headOption match {
        case None => acc
        case Some(cp) if isIdentChar(cp) =>
          val (run, rest) = cps.span(isIdentChar)
          go(rest, acc ++ camelSplit(spell(run)).map(normalize).filter(_.nonEmpty))
        case Some(cp) if Separators(cp) || Character.isWhitespace(cp) =>
          go(cps.tail, acc)
        case Some(cp) =>
          go(cps.tail, acc :+ normalize(spell(Vector(cp))))
      }
    go(java.text.Normalizer.normalize(bare, java.text.Normalizer.Form.NFKC).codePoints().toArray.toVector, Vector.empty)
  }
}

/** The corpus's own definitions, for unfolding: qualified name → the tokens
  * of the definition's body, for every `function` row that has one.  Goal
  * displays reach the ranker NORMALISED (the interaction lane prints
  * `Cmd_goal_type_context Normalised`), so a goal about `hom 𝑨 𝑪` or `𝑨 ≤ 𝑪`
  * displays as its Σ-unfolding, while lemma types are stated in the alias
  * the library defines, and no token of `hom 𝑨 𝑩 → hom 𝑩 𝑪 → hom 𝑨 𝑪`
  * occurs in the display of its own conclusion.  Unfolding a row's type
  * tokens through the bodies of the definitions they name, a bounded number
  * of steps, states the row in the display's vocabulary (`hom` →
  * `Σ (Func 𝔻[ _ ] 𝔻[ _ ]) (IsHom _ _)`, `𝔻[_]` → `Algebra.Domain _`).
  * Bodies are keyed by the qualified names that printed types use, so the
  * lookup needs no name resolution; de Bruijn indices (`@0`) and bodies
  * above `MaxBodyTokens` (large proof terms, which are noise, not meaning)
  * are dropped.
  */
final class DefinitionTable(val bodies: Map[String, Vector[String]]) {

  def size: Int = bodies.size

  /** The body a printed token names, if any: printed types and bodies spell
    * a definition inside an anonymous parameterised module with a `_`
    * segment (`Setoid.Subalgebras.Basic._.≤`) that the pretty name drops,
    * and spell an infix definition without its underscores (`M.≤`,
    * `M.IsSubalgebraOf` for `M._≤_`, `M._IsSubalgebraOf_`).
    */
  def bodyOf(token: String): Option[Vector[String]] =
    DefinitionTable.lookupKeys(token).iterator.map(bodies.get).collectFirst { case Some(b) => b }

  /** The tokens reachable from `tokens` by at most `depth` unfolding steps,
    * each definition unfolded once.  Deterministic: a breadth-first walk in
    * token order, one level per step; each level is a fold over its
    * frontier that unfolds the tokens not yet unfolded and carries the set
    * of those it has, and the bodies it emits are the next frontier.
    */
  def expand(tokens: Vector[String], depth: Int): Vector[String] = {
    @tailrec def go(frontier: Vector[String], seen: Set[String], steps: Int, acc: Vector[String]): Vector[String] =
      if (steps >= depth || frontier.isEmpty) acc
      else {
        val (unfolded, seen1) = frontier.foldLeft((Vector.empty[String], seen)) {
          case ((out, done), t) if done(t) => (out, done)
          case ((out, done), t)            => bodyOf(t).fold((out, done))(body => (out ++ body, done + t))
        }
        go(unfolded, seen1, steps + 1, acc ++ unfolded)
      }
    go(tokens, Set.empty, 0, Vector.empty)
  }
}

object DefinitionTable {

  val empty: DefinitionTable = new DefinitionTable(Map.empty)

  /** Bodies longer than this many tokens are proof terms, not abbreviations. */
  val MaxBodyTokens: Int = 200

  /** The table keys a printed token may stand for (see `bodyOf`): the token
    * with its `_` segments dropped, then the same with its last segment
    * wrapped in underscores.  A token that is not a qualified name (`@0`,
    * `λ`, a bound variable) yields only itself and is simply not in the table.
    */
  def lookupKeys(token: String): Vector[String] = {
    val segs = token.split("\\.").toVector.filter(sg => sg.nonEmpty && sg != "_")
    if (segs.size < 2) Vector(token)
    else {
      val plain = segs.mkString(".")
      val last  = segs.last
      val infix = if (last.startsWith("_") || last.endsWith("_")) plain else (segs.init :+ s"_${last}_").mkString(".")
      // A bracket mixfix prints as its opener (`𝔻[ 𝑨 ]` tokenises to `𝔻[`, `𝑨`,
      // `]`); the definition is `𝔻[_]`.  Bracket pairs only; no name is known here.
      val bracket = Brackets.get(last.last).map(close => (segs.init :+ s"${last}_$close").mkString("."))
      (Vector(plain, infix) ++ bracket).distinct
    }
  }

  private val Brackets: Map[Char, Char] = Map('[' -> ']', '⟦' -> '⟧', '⟨' -> '⟩', '⦅' -> '⦆')

  /** The body tokens worth keeping: no de Bruijn indices, no delimiters. */
  def bodyTokens(body: String): Vector[String] =
    Statements.tokens(body).filterNot(t => t.startsWith("@") || Statements.DelimTokens(t))

  /** A parsed corpus row as the table sees it: its qualified name, and its
    * body tokens when the row qualifies (a `function` row with a body of one
    * to `MaxBodyTokens` tokens).  `None` for a row the server would not
    * index (see below).
    */
  def rowOf(json: io.circe.Json): Option[(String, Option[Vector[String]])] =
    // A row is a corpus row only if the server's decoder would keep it
    // (SearchHit.fromCorpusRow); a partial row neither adds nor removes a
    // body, since the server never indexed it (PR #152 review, round two).
    SearchHit.fromCorpusRow(json).toOption.map { h =>
      // The server's `hasBody` is authoritative: a row it reports bodyless
      // contributes no unfolding, whatever its raw `body` field holds (PR
      // #152 review, round four; no row of the published corpora disagrees
      // with its own `body`).
      val body =
        if (h.defKind != "function" || !h.hasBody) None
        else json.hcursor.get[Option[String]]("body").toOption.flatten
          .map(bodyTokens).filter(toks => toks.nonEmpty && toks.size <= MaxBodyTokens)
      h.prettyQname -> body
    }

  /** Fold one parsed row into a table under construction: the table with
    * the row applied.  The LAST row per qualified name wins outright, as in
    * the server's `Map.fromList` index: a later duplicate that does not
    * qualify (a constructor, a bodyless row, a proof term over the bound)
    * REMOVES an earlier body rather than leaving it standing (PR #152
    * review).  Measured on the v0.1 corpus: 5 of its 733 duplicate names
    * are of that shape, none in a module the tier's fixtures import, so no
    * published rank moved; the semantics is now the stated one.
    */
  def record(table: Map[String, Vector[String]], json: io.circe.Json): Map[String, Vector[String]] =
    rowOf(json).fold(table) { case (qn, body) => body.fold(table - qn)(b => table.updated(qn, b)) }

  /** The table over a row stream, in file order (see `record`). */
  def fromRows(rows: Iterator[io.circe.Json]): DefinitionTable =
    new DefinitionTable(rows.foldLeft(Map.empty[String, Vector[String]])(record))

  /** Load the table from a corpus JSONL (the last row per name wins, as the
    * server's index does; see `record`).  Lines that do not parse are
    * skipped, as the server skips them; `InMemoryCorpus.load` counts them.
    */
  def load(path: java.nio.file.Path): IO[DefinitionTable] =
    Jsonl.parsed(path).collect { case Right(json) => json }
      .compile.fold(Map.empty[String, Vector[String]])(record)
      .map(new DefinitionTable(_))
}

/** A JSONL file as a stream, one parse attempt per non-blank line in file
  * order: `Right` the row, `Left` the parsing failure, so a loader can count
  * what the server would have dropped instead of stopping at it.
  */
object Jsonl {
  def parsed(path: java.nio.file.Path): fs2.Stream[IO, Either[io.circe.ParsingFailure, io.circe.Json]] =
    fs2.io.file.Files[IO].readUtf8Lines(fs2.io.file.Path.fromNioPath(path))
      .filter(_.trim.nonEmpty)
      .map(io.circe.parser.parse)
}

/** The IDF family (issue #19): inverse-document-frequency weighting of the
  * overlap between the goal's units and a row's, the frequencies counted
  * over the pool being ranked, so a unit every row in a `Setoid.*` haystack
  * carries (`level`, `setoid`, `algebra`, `func`) weighs almost nothing and
  * a unit few rows carry (`ishom`, `∋`, `iscongruence`) weighs a lot, which
  * is what demotes the generic projections without any hand list.  Both
  * sides are reduced to bare tokens first (the placeholder reduced only the
  * corpus side, so a qualified display token such as
  * `Setoid.Homomorphisms.Basic.IsHom` matched nothing; the whole pool tied
  * at zero and the arity tie-break handed the top to the nullary generics).
  *
  * Five optional rules, each a knob so the instrument can measure it alone:
  * `fragments` matches on `Fragments.of` units instead of whole bare tokens;
  * `conclusion` adds that weight again for units matched in the row's last
  * arrow segment (its conclusion, where the goal must be met); `nameWeight`
  * adds the units of the row's own name (and of its enclosing record or
  * module segment) at that weight, under the same IDF; `unfold` states the
  * row's type in the display's vocabulary by unfolding the definitions it
  * names through `table`, that many steps (see `DefinitionTable`), the
  * conclusion unfolded likewise; `normalize` divides by the row's own IDF
  * norm (a cosine), so a long type that mentions everything cannot outrank
  * a short one that says the right thing; `hypotheses` adds, at that
  * weight, the overlap between the row's PREMISES (every arrow segment but
  * the last) and the goal context's hypothesis types, because the lemmas
  * that conclude the same thing differ in what they assume.  At `nameWeight`
  * zero the name's units leave the row's document entirely, counting in
  * neither the frequencies nor the norm, so the knob means what it says and
  * the with-name ablation isolates the whole rule (PR #152 review).  Ties
  * still break cheap-before-expensive, then on the qname
  * (`RetrievalPool.rank`).
  */
final class IdfScorer(
  val name:    String,
  fragments:   Boolean,
  conclusion:  Double,
  nameWeight:  Double,
  unfold:      Int             = 0,
  normalize:   Boolean         = false,
  table:       DefinitionTable = DefinitionTable.empty,
  hypotheses:  Double          = 0.0
) extends CandidateScorer {

  override def readsHypotheses: Boolean = hypotheses > 0.0

  /** The structural tokens, plus the two the unfolded bodies carry. */
  private val Structural = Statements.Structural ++ Set("λ", "=")

  private def units(tokens: Iterable[String]): Set[String] = {
    val bare = tokens.iterator.map(TokenOverlapScorer.bareToken).filter(t => t.nonEmpty && !Structural(t))
    if (fragments) bare.flatMap(Fragments.of).toSet else bare.toSet
  }

  /** A printed type split at its last standalone depth-0 arrow: (premises,
    * conclusion).  Agda identifiers may contain the arrow
    * (`IsInRange→IsInImage`; 290 rows of the v0.1 corpus carry one glued to
    * a name), and a character scan cut such a name in two (PR #152 review,
    * round two); the split is `Statements.splitTopLevelArrows`, shared with
    * the binder telescope and the context reconstruction (round three).
    */
  private def splitConclusion(printed: String): (String, String) = {
    val segs = Statements.splitTopLevelArrows(printed)
    if (segs.size <= 1) ("", segs.headOption.getOrElse(""))
    else (segs.init.mkString(" → "), segs.last)
  }

  private def nameUnits(hit: SearchHit): Set[String] = {
    val enclosing = hit.module.substring(hit.module.lastIndexOf('.') + 1)
    units(Vector(hit.bareName, enclosing))
  }

  /** A printed type's units, unfolded `unfold` steps through the table. */
  private def typeUnits(printed: String): Set[String] = {
    val toks = Statements.tokens(printed)
    units(if (unfold > 0) toks ++ table.expand(toks, unfold) else toks)
  }

  override def scores(query: RankQuery, pool: Vector[SearchHit]): SearchHit => Double = {
    val goalUnits = units(query.goalTokens)
    val hypUnits  = units(query.hypothesisTokens)
    val split     = pool.map(h => h.prettyQname -> splitConclusion(h.tpe)).toMap
    val rowType   = pool.map(h => h.prettyQname -> typeUnits(h.tpe)).toMap
    val rowConcl  = pool.map(h => h.prettyQname -> typeUnits(split(h.prettyQname)._2)).toMap
    val rowPrem   = pool.map(h => h.prettyQname -> typeUnits(split(h.prettyQname)._1)).toMap
    val rowName   = pool.map(h => h.prettyQname -> (if (nameWeight > 0.0) nameUnits(h) else Set.empty[String])).toMap
    val n         = pool.size.toDouble
    val df        = pool.iterator.flatMap(h => rowType(h.prettyQname) ++ rowName(h.prettyQname)).toVector
                      .groupBy(identity).map { case (u, us) => u -> us.size }
    def idf(u: String): Double = StrictMath.log((n + 1.0) / (df.getOrElse(u, 0) + 1.0))
    // Summed in unit order so the Double result is the same on every run.
    def sum(us: Set[String]): Double = us.toVector.sorted.foldLeft(0.0)((acc, u) => acc + idf(u))
    def norm(us: Set[String]): Double = StrictMath.sqrt(us.toVector.sorted.foldLeft(0.0)((acc, u) => acc + idf(u) * idf(u)))
    hit => {
      val t   = rowType(hit.prettyQname)
      val raw = sum(goalUnits.intersect(t)) +
        conclusion * sum(goalUnits.intersect(rowConcl(hit.prettyQname))) +
        nameWeight * sum(goalUnits.intersect(rowName(hit.prettyQname))) +
        hypotheses * sum(hypUnits.intersect(rowPrem(hit.prettyQname)))
      if (!normalize) raw
      else { val d = norm(t ++ rowName(hit.prettyQname)); if (d == 0.0) 0.0 else raw / d }
    }
  }
}

/** The placeholder with the goal side bare-reduced too: isolates the effect
  * of the normalisation fix from the effect of IDF weighting.
  */
object BareOverlapScorer extends CandidateScorer {
  val name: String = "bare-overlap"
  override def scores(query: RankQuery, pool: Vector[SearchHit]): SearchHit => Double = {
    val bare = query.goalTokens.map(TokenOverlapScorer.bareToken)
    hit => TokenOverlapScorer.score(bare, hit).toDouble
  }
}

/** Query derivation from what the goal shows.  Local variables (the context's
  * assumption names), metas, numerals, and single latin letters carry no
  * retrieval signal and are dropped; operators and long identifiers remain.
  */
object Queries {
  private val MetaLike = """_[^\s]*_[0-9]+|_[0-9]+""".r

  /** The retrieval-bearing tokens of one displayed type, given the context's
    * names to drop.
    */
  def tokensOf(displayed: String, ctxNames: Set[String]): Vector[String] =
    Statements.tokens(displayed)
      .filterNot(t => t.length == 1 && t.head.isLetter && t.head <= 'z')
      .filterNot(t => t.forall(_.isDigit))
      .filterNot(ctxNames)
      .filterNot(t => MetaLike.matches(t))
      .filterNot(Statements.Structural)
      .distinct

  def goalTokens(goal: GoalView): Vector[String] =
    tokensOf(goal.goal, goal.context.map(_.name).toSet)

  /** The hypotheses' tokens: every context entry's displayed type, through
    * the same filter.  Empty when the context carries no types (an older
    * report replayed by the recall instrument).
    */
  def hypothesisTokens(goal: GoalView): Vector[String] = {
    val ctxNames = goal.context.map(_.name).toSet
    goal.context.flatMap(c => tokensOf(c.tpe, ctxNames)).distinct
  }

  def rankQuery(goal: GoalView): RankQuery =
    RankQuery(goalTokens(goal).toSet, hypothesisTokens(goal).toSet)
}

/** The pool pipeline shared by the proposer and the offline recall instrument
  * (issue #19): what retrieval does for one goal BEFORE the lane is asked
  * anything.  Kept as one function so the instrument measures exactly the
  * ranking the loop searches.
  */
object RetrievalPool {

  /** One goal's pool, with the counts the honesty ledger reports: queries
    * issued and how many returned exactly the limit (truncated), distinct
    * hits, the in-scope rows, the exclusions with their reasons, the rows the
    * `defKind` filter dropped, and the surviving function rows in rank order.
    */
  final case class Built(
    queries:     Int,
    truncated:   Int,
    hits:        Int,
    inScope:     Vector[SearchHit],
    excluded:    Vector[(String, SearchHit)], // reason ("name:…" | "statement:…") -> row
    nonFunction: Int,
    ranked:      Vector[SearchHit],
    seen:        Set[String]                  // every distinct qname the queries returned, whatever became of it
  )

  /** Enumerate the legal haystacks (module-prefix name queries are the recall
    * backbone; goal-token type queries add rows and exercise the tool the
    * issue names), then filter, exclude, drop non-function rows, and rank.
    */
  def build(
    corpus:    CorpusSearch,
    scope:     ImportScope,
    exclusion: TargetExclusion,
    cfg:       RetrievalConfig,
    scorer:    CandidateScorer,
    goal:      GoalView
  ): IO[Built] = {
    val gts = Queries.goalTokens(goal)
    for {
      byModule <- scope.modules.traverse(m => corpus.byName(m.module + ".", cfg.queryLimit))
      byType   <- gts.traverse(t => corpus.byType(t, cfg.queryLimit))
    } yield {
      val replies = byModule ++ byType
      val union   = replies.flatten.groupBy(_.prettyQname).toVector.map(_._2.head)
      val inScope = union.filter(h => scope.importingModuleOf(h.module).isDefined)
      val (excluded, kept) =
        if (cfg.excludeTarget) inScope.partitionMap(h => exclusion.reasonFor(h).map(r => (r, h)).toLeft(h))
        else (Vector.empty[(String, SearchHit)], inScope)
      val functions = kept.filter(_.defKind == "function")
      Built(
        queries     = replies.size,
        truncated   = replies.count(_.size >= cfg.queryLimit),
        hits        = union.size,
        inScope     = inScope,
        excluded    = excluded,
        nonFunction = kept.size - functions.size,
        ranked      = rank(scorer, Queries.rankQuery(goal), functions),
        seen        = union.map(_.prettyQname).toSet
      )
    }
  }

  /** The total rank: score first, then cheap before expensive (#112's lesson
    * four, on the retrieval pool: approximate arity from the corpus type),
    * then the qname so ranking is total and deterministic.  A zero score is
    * normalised so `-0.0` and `0.0` cannot split a tie.
    */
  def rank(scorer: CandidateScorer, query: RankQuery, rows: Vector[SearchHit]): Vector[SearchHit] = {
    val s = scorer.scores(query, rows)
    def key(h: SearchHit): (Double, Int, String) = {
      val v = s(h)
      (if (v == 0.0) 0.0 else -v, TokenOverlapScorer.approxVisibleArity(h), h.prettyQname)
    }
    // Each key is computed once: `sortBy` would recompute it per comparison,
    // and the arity re-parses the row's type each time.
    rows.map(h => key(h) -> h)
      .sortBy(_._1)(Ordering.Tuple3(Ordering.Double.TotalOrdering, Ordering.Int, Ordering.String))
      .map(_._2)
  }
}

/** The retrieval proposer.  Wraps the P1 base proposer (composition, see the
  * file header); all corpus work is memoised per goal display, because the
  * loop re-selects the same goal across beam states.
  */
final class RetrievalProposer private (
  base:      Proposer,
  corpus:    CorpusSearch,
  scope:     ImportScope,
  exclusion: TargetExclusion,
  scorer:    CandidateScorer,
  lemmaType: String => IO[Either[String, Option[String]]],
  cfg:       RetrievalConfig,
  poolCache: Ref[IO, Map[String, Vector[String]]],           // goal display -> candidate texts
  nameCache: Ref[IO, Map[String, Option[(String, Vector[Binder], String)]]], // qname -> accepted (rendering, binders, lane-printed type)
  targetRef: Ref[IO, Option[Option[String]]],                // fetched? -> target's lane-printed type (None inside = lane could not type it)
  statsRef:  Ref[IO, RetrievalStats]
) extends Proposer {

  def stats: IO[RetrievalStats] = statsRef.get

  override def propose(state: SearchState, target: Obligation, goal: GoalView): IO[Vector[String]] =
    for {
      baseCands <- base.propose(state, target, goal)
      retrieved <- cachedPool(goal)
    } yield (baseCands ++ retrieved).distinct

  private def cachedPool(goal: GoalView): IO[Vector[String]] = {
    val key = RetrievalProposer.poolKey(goal)
    poolCache.get.flatMap(_.get(key) match {
      case Some(hit) => IO.pure(hit)
      case None      => buildPool(goal).flatTap(p => poolCache.update(_ + (key -> p)))
    })
  }

  /** The corpus as the pool pipeline sees it from inside the proposer: every
    * reply is counted into the ledger AS IT ARRIVES (a query issued, a reply
    * at the limit), so a corpus failure mid-pipeline leaves the work already
    * done on the record for the anomaly report (#130 review round 3; PR #152
    * review caught the shared pipeline moving the counts to after the build).
    */
  private val counting: CorpusSearch = new CorpusSearch {
    private def count(q: IO[Vector[SearchHit]]): IO[Vector[SearchHit]] =
      q.flatTap(hs => statsRef.update(s => s.copy(
        queries   = s.queries + 1,
        truncated = s.truncated + (if (hs.size >= cfg.queryLimit) 1 else 0))))
    def byName(pattern: String, limit: Int): IO[Vector[SearchHit]] = count(corpus.byName(pattern, limit))
    def byType(pattern: String, limit: Int): IO[Vector[SearchHit]] = count(corpus.byType(pattern, limit))
    // A dependency expansion is a server request too; it counts as a query
    // (no limit applies, so it can never be truncated).  PR #152 review,
    // round two: these calls had bypassed the ledger.
    def dependenciesOf(prettyQname: String): IO[Vector[SearchHit]] =
      corpus.dependenciesOf(prettyQname).flatTap(_ => statsRef.update(s => s.copy(queries = s.queries + 1)))
  }

  /** The pipeline: the shared pool (RetrievalPool: queries, scope,
    * exclusion, `defKind` filter, rank), its counts into the ledger, then the
    * proposer-side steps: optional dependency expansion, rendering
    * resolution through the lane, and candidate shaping.
    */
  private def buildPool(goal: GoalView): IO[Vector[String]] =
    for {
      built    <- RetrievalPool.build(counting, scope, exclusion, cfg, scorer, goal)
      _        <- statsRef.update(s => s.copy(
                    hits        = s.hits + built.hits,
                    inScope     = s.inScope + built.inScope.size,
                    excluded    = (s.excluded ++ built.excluded.map(_._1)).distinct,
                    nonFunction = s.nonFunction + built.nonFunction))
      query     = Queries.rankQuery(goal)
      expanded <- if (cfg.expandDeps) expandTop(built.ranked, built.seen, query) else IO.pure(built.ranked)
      resolved <- resolveTopK(expanded)
      _        <- statsRef.update(s => s.copy(proposedLemmas = (s.proposedLemmas ++ resolved.map(_._1)).distinct))
    } yield resolved.flatMap { case (rendered, binders) =>
      shapes(rendered, binders, goal.context.map(_.name))
    }

  /** Walk the ranked list, resolving renderings through the lane, until
    * `topK` lemmas have been ACCEPTED or the list is exhausted.  The cut is
    * taken after resolution, not before: a high-ranked row the ladder cannot
    * render must not consume a slot, or eight rejections starve the pool
    * while rank nine resolves (#130 review; the b-sweep ledger showed 18 of
    * 22 fixtures under-filled this way, e.g. one accepted lemma from 166
    * available).  Rejections still pay their lane calls and still count in
    * `laneRejected`.
    */
  private def resolveTopK(ranked: Vector[SearchHit]): IO[Vector[(String, Vector[Binder])]] =
    ranked.foldLeftM(Vector.empty[(String, Vector[Binder])]) { (acc, hit) =>
      if (acc.size >= cfg.topK) IO.pure(acc)
      else resolve(hit).flatMap {
        case None => IO.pure(acc)
        case Some((rendered, binders, printed)) =>
          // The lane-form statement check (#130 review): the syntactic rule
          // in TargetExclusion compares corpus text against index prose,
          // two notations that agree only in unit tests — the published
          // sweeps recorded ZERO statement exclusions.  Here both sides are
          // the LANE's printing, so the exact-statement-alias rule finally
          // has teeth: a differently named row whose lane-printed type
          // normalises to the target's is excluded, NAMED, and its slot
          // stays open.
          targetPrinted.flatMap {
            case Some(t) if cfg.excludeTarget &&
                Statements.normalize(printed) == Statements.normalize(t) =>
              statsRef.update(st => st.copy(
                excluded = (st.excluded :+ s"statement:${hit.prettyQname}").distinct)).as(acc)
            case _ => IO.pure(acc :+ ((rendered, binders)))
          }
      }
    }

  /** The target's own lane-printed type, fetched once per fixture through
    * the same `type_of` door the candidates use (the hole's definition is in
    * scope in its own module).  `Some(None)` records a lane that could not
    * type it — the check is then skipped and the name rule carries alone.
    */
  private def targetPrinted: IO[Option[String]] =
    targetRef.get.flatMap {
      case Some(cached) => IO.pure(cached)
      case None =>
        lemmaType(exclusion.holeName)
          .map(_.toOption.flatten)
          .flatTap(t => targetRef.set(Some(t)))
    }

  /** One-hop dependency expansion of the top-scored lemmas.  Fresh neighbors
    * go through the SAME honesty-ledger accounting as initial hits — counted
    * into `hits`/`inScope`, exclusions NAMED in `excluded`, the non-function
    * cut counted — so an expansion-only target is reported, never silently
    * dropped (#130 review); survivors re-rank with everything else before
    * the topK cut.
    */
  private def expandTop(ranked: Vector[SearchHit], seen: Set[String], query: RankQuery): IO[Vector[SearchHit]] =
    for {
      nss      <- ranked.take(3).traverse(h => counting.dependenciesOf(h.prettyQname))
      // A neighbor the initial queries already returned is not a fresh hit,
      // whether it was ranked, excluded, out of scope, or non-function; only
      // rows never seen enter the ledger again (PR #152 review, round four).
      fresh     = nss.flatten.groupBy(_.prettyQname).toVector.map(_._2.head)
                    .filterNot(h => seen.contains(h.prettyQname))
      inScope   = fresh.filter(h => scope.importingModuleOf(h.module).isDefined)
      _        <- statsRef.update(s => s.copy(hits = s.hits + fresh.size, inScope = s.inScope + inScope.size))
      kept     <- if (cfg.excludeTarget) {
                    val (excluded, keep) = inScope.partitionMap(h =>
                      exclusion.reasonFor(h).toLeft(h))
                    statsRef.update(s => s.copy(excluded = (s.excluded ++ excluded).distinct)).as(keep)
                  } else IO.pure(inScope)
      functions = kept.filter(_.defKind == "function")
      _        <- statsRef.update(s => s.copy(nonFunction = s.nonFunction + (kept.size - functions.size)))
    } yield RetrievalPool.rank(scorer, query,
        (ranked ++ functions).groupBy(_.prettyQname).toVector.map(_._2.head))

  /** Resolve a row to the rendering the lane accepts (see the file header's
    * rendering ladder), with the binder telescope read off the lane's
    * answer.  Cached per qname: a lemma's rendering and type never change
    * within one fixture's search.
    */
  private def resolve(hit: SearchHit): IO[Option[(String, Vector[Binder], String)]] =
    nameCache.get.flatMap(_.get(hit.prettyQname) match {
      case Some(done) => IO.pure(done)
      case None =>
        val importing = scope.importingModuleOf(hit.module)
        val ladder = (
          importing.filter(_.usingNames.contains(hit.bareName)).map(_ => hit.bareName).toVector :+
            hit.prettyQname
        ) ++ importing.map(m => s"${m.module}.${hit.bareName}").filter(_ != hit.prettyQname)
        tryLadder(ladder.distinct)
          .flatTap {
            case None => statsRef.update(s => s.copy(laneRejected = s.laneRejected + 1))
            case _    => IO.unit
          }
          .flatTap(r => nameCache.update(_ + (hit.prettyQname -> r)))
    })

  private def tryLadder(renderings: Vector[String]): IO[Option[(String, Vector[Binder], String)]] =
    renderings match {
      case r +: rest =>
        lemmaType(r).flatMap {
          case Right(Some(printed)) => IO.pure(Some((r, Actions.bindersOfPrinted(printed), printed)))
          case _                    => tryLadder(rest)
        }
      case _ => IO.pure(None)
    }

  /** The three candidate shapes per lemma (see the file header): the `_`-form,
    * the saturated forms over the context's assumptions, the `{!!}`-form —
    * hole-free closers-class first, every applied form parenthesized so it is
    * the same term in argument position as on a right-hand side.  Saturation
    * is bounded (arity and combination caps) because it is cartesian; the
    * peek prunes wrong tuples in milliseconds (no metas — the inferred type
    * is exact), and the probe budget prices the rest.
    */
  private def shapes(rendered: String, binders: Vector[Binder], assumptions: Vector[String]): Vector[String] = {
    val visible = binders.count(_.visibility == Visibility.Visible)
    if (visible == 0) Vector(rendered)
    else {
      val underscore = (rendered +: Vector.fill(visible)("_")).mkString("(", " ", ")")
      val saturated =
        if (visible <= RetrievalProposer.MaxSaturationArity && assumptions.nonEmpty &&
            math.pow(assumptions.size.toDouble, visible.toDouble) <= RetrievalProposer.MaxSaturationCombos)
          RetrievalProposer.tuples(assumptions, visible)
            .map(args => s"(${Actions.applicationCandidate(rendered, binders, args)})")
        else Vector.empty
      (underscore +: saturated) :+ s"(${Actions.applicationCandidate(rendered, binders, Vector.empty)})"
    }
  }
}

object RetrievalProposer {

  /** Saturation bounds: at most cube-of-three tuples per lemma, so a wide
    * context cannot explode an expansion.  Both caps are part of the stated
    * space, not silent truncation — the candidate list IS the report of what
    * was tried.
    */
  val MaxSaturationArity:  Int = 3
  val MaxSaturationCombos: Int = 27

  /** The pool memo's key: the goal display AND the local context, names and
    * types.  The ranking reads the hypotheses (`RankQuery`) and the saturated
    * shapes are spelled over the assumption names, so one display under two
    * contexts is two pools (PR #152 review; the shape half predates the
    * branch).  Within one fixture's search the context never changes, since
    * a sub-hole inside an application binds nothing, so the memo still hits
    * on every re-selection of a goal.
    */
  def poolKey(goal: GoalView): String =
    goal.goal + "\u0000" + goal.context.map(c => c.name + ":" + c.tpe).mkString("\u0001")

  /** Every k-tuple over `names`, with repetition, in name order; `*-comm n n`
    * is a legitimate candidate.
    */
  def tuples(names: Vector[String], k: Int): Vector[Vector[String]] =
    Vector.fill(k)(names).foldLeft(Vector(Vector.empty[String])) {
      (acc, ns) => acc.flatMap(t => ns.map(t :+ _))
    }

  def create(
    base:      Proposer,
    corpus:    CorpusSearch,
    scope:     ImportScope,
    exclusion: TargetExclusion,
    lemmaType: String => IO[Either[String, Option[String]]],
    cfg:       RetrievalConfig,
    scorer:    CandidateScorer = TokenOverlapScorer
  ): IO[RetrievalProposer] =
    for {
      pool   <- Ref.of[IO, Map[String, Vector[String]]](Map.empty)
      names  <- Ref.of[IO, Map[String, Option[(String, Vector[Binder], String)]]](Map.empty)
      target <- Ref.of[IO, Option[Option[String]]](None)
      stats  <- Ref.of[IO, RetrievalStats](RetrievalStats())
    } yield new RetrievalProposer(base, corpus, scope, exclusion, scorer, lemmaType, cfg, pool, names, target, stats)
}
