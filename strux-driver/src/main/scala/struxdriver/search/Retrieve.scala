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
  *  its own trait so premise-selection scores (docs/PLAN.md Phase 2) can
  *  replace token overlap without touching the proposer; ties break on the
  *  qname so ranking is total and deterministic.
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

  private val Delims: Set[Char] = Set('(', ')', '{', '}', '⦃', '⦄')

  /** Tokenise: delimiters are single tokens, everything else splits on
    * whitespace.  Total and allocation-simple; these strings are short.
    */
  def tokens(s: String): Vector[String] = {
    val out = Vector.newBuilder[String]
    val cur = new StringBuilder
    def flush(): Unit = { if (cur.nonEmpty) { out += cur.result(); cur.clear() } }
    s.foreach {
      case c if c.isWhitespace => flush()
      case c if Delims(c)      => flush(); out += c.toString
      case c                   => cur += c
    }
    flush()
    out.result()
  }

  /** The binder names of a token stream: inside each delimiter group, the
    * tokens before a `:` at that group's own level.  A group without a `:`
    * (a parenthesised type) binds nothing.
    */
  private def binderNames(ts: Vector[String]): Vector[String] = {
    val names = Vector.newBuilder[String]
    var i = 0
    while (i < ts.length) {
      if (Delims(ts(i).head) && (ts(i) == "(" || ts(i) == "{" || ts(i) == "⦃")) {
        // Collect simple name tokens until ':', a close, or a nested open.
        var j       = i + 1
        val pending = Vector.newBuilder[String]
        var decided = false
        while (j < ts.length && !decided) {
          ts(j) match {
            case ":"                            => names ++= pending.result(); decided = true
            case t if Delims(t.head)            => decided = true // nested group or close: not a binder group
            case t                              => pending += t; j += 1
          }
        }
      }
      i += 1
    }
    names.result()
  }

  def normalize(stmt: String): String = {
    val ts      = tokens(stmt).filterNot(_ == "∀")
    val renames = binderNames(ts).distinct.zipWithIndex.map { case (n, i) => n -> s"x${i + 1}" }.toMap
    ts.map(t => renames.getOrElse(t, t)).mkString(" ")
  }
}

/** The scoring seam: deterministic token overlap now, premise-selection
  * scores when the Phase 2 artifacts exist.  Higher is better; ties are
  * broken outside, on the qname.
  */
trait CandidateScorer {
  def score(goalTokens: Set[String], hit: SearchHit): Int
}

object TokenOverlapScorer extends CandidateScorer {

  /** A corpus type token, reduced to comparable form: last dot segment
    * (corpus types are fully qualified), outer underscores stripped (the
    * corpus writes `_+_` where a goal display shows infix `+`).
    */
  def bareToken(t: String): String = {
    val seg = t.substring(t.lastIndexOf('.') + 1)
    seg.stripPrefix("_").stripSuffix("_")
  }

  private val Structural = Set("(", ")", "{", "}", "⦃", "⦄", "→", ":", "∀", ".", ";")

  override def score(goalTokens: Set[String], hit: SearchHit): Int = {
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
      !goalTokens(t) && !Structural(t) && t.nonEmpty && !t.exists(_.isLetterOrDigit))
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

/** Query derivation from what the goal shows.  Local variables (the context's
  * assumption names), metas, numerals, and single latin letters carry no
  * retrieval signal and are dropped; operators and long identifiers remain.
  */
object Queries {
  private val MetaLike = """_[^\s]*_[0-9]+|_[0-9]+""".r

  def goalTokens(goal: GoalView): Vector[String] = {
    val ctxNames = goal.context.map(_.name).toSet
    Statements.tokens(goal.goal)
      .filterNot(t => t.length == 1 && t.head.isLetter && t.head <= 'z')
      .filterNot(t => t.forall(_.isDigit))
      .filterNot(ctxNames)
      .filterNot(t => MetaLike.matches(t))
      .filterNot(t => Set("(", ")", "{", "}", "⦃", "⦄", "→", "∀", ":", ".", ";").contains(t))
      .distinct
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

  private def cachedPool(goal: GoalView): IO[Vector[String]] =
    poolCache.get.flatMap(_.get(goal.goal) match {
      case Some(hit) => IO.pure(hit)
      case None      => buildPool(goal).flatTap(p => poolCache.update(_ + (goal.goal -> p)))
    })

  /** The pipeline: enumerate the legal haystacks (module-prefix queries are
    * the recall backbone; goal-token type queries add rows and exercise the
    * tool the issue names), then filter, rank, resolve renderings through
    * the lane, and shape candidates.
    */
  private def buildPool(goal: GoalView): IO[Vector[String]] = {
    val gts = Queries.goalTokens(goal)
    for {
      byModule <- scope.modules.traverse(m => query(corpus.byName(m.module + ".", cfg.queryLimit)))
      byType   <- gts.traverse(t => query(corpus.byType(t, cfg.queryLimit)))
      union     = (byModule.flatten ++ byType.flatten)
                    .groupBy(_.prettyQname).toVector.map(_._2.head)
      inScope   = union.filter(h => scope.importingModuleOf(h.module).isDefined)
      _        <- statsRef.update(s => s.copy(hits = s.hits + union.size, inScope = s.inScope + inScope.size))
      surviving <- if (cfg.excludeTarget) {
                     val (excluded, kept) = inScope.partitionMap(h =>
                       exclusion.reasonFor(h).toLeft(h))
                     statsRef.update(s => s.copy(excluded = (s.excluded ++ excluded).distinct)).as(kept)
                   } else IO.pure(inScope)
      functions = surviving.filter(_.defKind == "function")
      _        <- statsRef.update(s => s.copy(nonFunction = s.nonFunction + (surviving.size - functions.size)))
      goalSet   = gts.toSet
      ranked0   = functions.sortBy(rankKey(goalSet))
      expanded <- if (cfg.expandDeps) expandTop(ranked0, goalSet) else IO.pure(ranked0)
      resolved <- resolveTopK(expanded)
      _        <- statsRef.update(s => s.copy(proposedLemmas = (s.proposedLemmas ++ resolved.map(_._1)).distinct))
    } yield resolved.flatMap { case (rendered, binders) =>
      shapes(rendered, binders, goal.context.map(_.name))
    }
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
  private def expandTop(ranked: Vector[SearchHit], goalSet: Set[String]): IO[Vector[SearchHit]] =
    for {
      nss      <- ranked.take(3).traverse(h => corpus.dependenciesOf(h.prettyQname))
      known     = ranked.map(_.prettyQname).toSet
      fresh     = nss.flatten.groupBy(_.prettyQname).toVector.map(_._2.head)
                    .filterNot(h => known.contains(h.prettyQname))
      inScope   = fresh.filter(h => scope.importingModuleOf(h.module).isDefined)
      _        <- statsRef.update(s => s.copy(hits = s.hits + fresh.size, inScope = s.inScope + inScope.size))
      kept     <- if (cfg.excludeTarget) {
                    val (excluded, keep) = inScope.partitionMap(h =>
                      exclusion.reasonFor(h).toLeft(h))
                    statsRef.update(s => s.copy(excluded = (s.excluded ++ excluded).distinct)).as(keep)
                  } else IO.pure(inScope)
      functions = kept.filter(_.defKind == "function")
      _        <- statsRef.update(s => s.copy(nonFunction = s.nonFunction + (kept.size - functions.size)))
    } yield (ranked ++ functions).groupBy(_.prettyQname).toVector.map(_._2.head)
        .sortBy(rankKey(goalSet))

  /** The total rank: score first, then cheap before expensive (#112's lesson
    * four, on the retrieval pool — approximate arity from the corpus type),
    * then the qname so ranking is total and deterministic.
    */
  private def rankKey(goalSet: Set[String])(h: SearchHit): (Int, Int, String) =
    (-scorer.score(goalSet, h), TokenOverlapScorer.approxVisibleArity(h), h.prettyQname)

  private def query(q: IO[Vector[SearchHit]]): IO[Vector[SearchHit]] =
    q.flatTap(hs => statsRef.update(s => s.copy(
      queries   = s.queries + 1,
      truncated = s.truncated + (if (hs.size >= cfg.queryLimit) 1 else 0))))

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

  /** Every k-tuple over `names`, with repetition, in name order — `*-comm n n`
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
