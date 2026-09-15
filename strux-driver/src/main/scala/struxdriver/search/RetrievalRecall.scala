/** ============================================================================
  *  RetrievalRecall.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/search/RetrievalRecall.scala
  *  Package: struxdriver.search
  *
  *  Purpose
  *  -------
  *  The offline, rank-only instrument of issue #19 ([M2-5]): measure how a
  *  named `CandidateScorer` ranks the lemmas a benchmark obligation needs,
  *  in seconds and without a server, instead of a loop-hour per sweep.  It
  *  is the "retrieval recall@k" column of #21's evaluation protocol,
  *  decoupled from downstream proof success.
  *
  *  What it replays
  *  ---------------
  *  For each fixture it takes the goal display a loop run recorded in its
  *  `report.json` (the display is Agda's, and only Agda can produce it), the
  *  fixture's imports (the legal scope), and a corpus loaded in-process, and
  *  runs exactly the pool pipeline the retrieval proposer runs before it asks
  *  the lane anything, `RetrievalPool.build`: queries with the server's own
  *  substring semantics, scope, target exclusion, the `defKind` filter, and
  *  the scorer's rank.  Two things the proposer does afterwards are NOT
  *  replayed, and the numbers here are conservative for both: lane
  *  resolution (a row the lane cannot render is skipped by the loop, which
  *  can only move a target UP the effective ranking) and the lane-form
  *  statement exclusion (which can only remove a row the syntactic rule
  *  missed).  The instrument reports, never decides: a target's status is
  *  its rank, or the named reason it has none.  The report records the
  *  sha256 of the corpus it loaded and, when the replayed run recorded its
  *  own (`corpus.sha256` in the loop report), whether the two agree; a
  *  mismatch is stated on stdout and in the report rather than refused,
  *  since replaying a run's goals against another corpus is a legitimate
  *  question as long as the report says so (PR #152 review, round six).
  *
  *  Ground truth
  *  ------------
  *  From the index tags (data/benchmarks/README.md, "Ranking ground truth"):
  *  `target:<prettyQname>` names a lemma the gold proof applies, measured in
  *  the pool WITH exclusion as configured (the fair regime); `restates:` names
  *  the library original the row was mined from, measured in the pool WITHOUT
  *  exclusion (the haystack regime the exclusion-off control depends on).  A
  *  target may be unreachable for a stated reason: not in this corpus (a
  *  standard-library name), a constructor (the `defKind` filter), out of
  *  scope, or excluded; each reason is reported by name rather than
  *  folded into a recall miss without comment.  Recall is quoted both over all
  *  recorded targets and over the reachable ones.
  *
  *  The goal context
  *  ----------------
  *  `Queries.goalTokens` drops the context's names from the goal display, so
  *  the instrument needs them.  A report written since this file landed
  *  carries `goalContext` per outcome; for an older report the names are
  *  reconstructed from the fixture source (`FixtureContext`: the signature's
  *  binders walked against the clause's patterns, with Agda's eager insertion
  *  of implicit binders), and the report says which source was used.  When
  *  both are available the reconstruction is checked against the live
  *  context and any mismatch is recorded, so the fallback is validated by
  *  every run that carries the real thing.  The fallback carries names
  *  only: a scorer that reads the hypotheses' types
  *  (`CandidateScorer.readsHypotheses`) would silently run as its
  *  no-hypotheses variant over it, so the instrument refuses that replay
  *  unless `--allow-untyped-context on` is passed, and then marks each such
  *  fixture `degraded` in the report and on stdout (PR #152 review, round
  *  two).
  *
  *  Invocation (see the proof-search-recall Make target)
  *  -----------------------------------------------------
  *    ROOT=/path/to/repo
  *    sbt "runMain struxdriver.search.RetrievalRecall
  *          --index $ROOT/data/benchmarks/benchmark-index.jsonl
  *          --corpus $ROOT/data/corpora/agda-algebras/v0.1/corpus.jsonl
  *          --report $ROOT/data/benchmarks/reports/proof-search/<run>/report.json
  *          --project-root $ROOT --out /path/to/recall.json
  *          [--scorers token-overlap,…] [--exclude-target on|off] [--k 8,32]
  *          [--ids id1,id2 | --all] [--top 8]"
  *
  *  Path flags are ordinary paths, resolved by the process that reads them
  *  (sbt forks with its cwd in strux-driver/, so the Make target passes them
  *  absolute); `--project-root` is where the index's own `obligation` paths,
  *  repo-relative by the index schema, resolve.
  *
  *  ============================================================================
  */
package struxdriver.search

import cats.effect.{ExitCode, IO, IOApp}
import cats.syntax.all._
import io.circe.Json
import io.circe.syntax._
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths}
import scala.annotation.tailrec

import struxdriver.benchmark.{Obligation => IndexEntry}

/** A corpus loaded in-process, answering the three tools with the server's
  * own semantics (agda-mcp `Corpus.hs`): case-insensitive substring match on
  * `prettyQname` OR `prettyName` (name search) or on the printed type (type
  * search), results
  * in the corpus map's key order, `Data.Text`'s `Ord`, which is code-point
  * order, not Java's UTF-16 unit order (they differ on the astral glyphs
  * agda-algebras names are full of), and truncated at the limit.  The wire
  * `module` field is the row's PRETTY module, as the server sends it.
  * Dependency expansion answers empty: the instrument measures the pool the
  * default configuration ranks, and `expandDeps` is off in every published
  * sweep.
  *
  * `prettyNames` is each row's `prettyName` by `prettyQname`, kept beside
  * the hit because the server's name search matches EITHER field and the
  * wire result carries only the qualified one (PR #152 review, round five).
  * A row without an entry is matched on its bare name, the last segment of
  * its qualified name, which is what `prettyName` is on every row of both
  * published corpora (68,699 rows, measured); the loader records the field
  * itself so the replay does not rest on that measurement.
  */
final class InMemoryCorpus(val rows: Vector[SearchHit], prettyNames: Map[String, String] = Map.empty) extends CorpusSearch {
  private val byQname: Map[String, SearchHit] = rows.map(h => h.prettyQname -> h).toMap
  private val ordered: Vector[SearchHit]      = rows.sortBy(_.prettyQname)(InMemoryCorpus.codePointOrder)

  def lookup(prettyQname: String): Option[SearchHit] = byQname.get(prettyQname)

  /** The row's `prettyName` as the server indexes it (see the class header). */
  def prettyNameOf(h: SearchHit): String = prettyNames.getOrElse(h.prettyQname, h.bareName)

  private val loweredNames: Vector[(SearchHit, String, String)] =
    ordered.map(h => (h, InMemoryCorpus.foldCase(h.prettyQname), InMemoryCorpus.foldCase(prettyNameOf(h))))
  private val loweredType:  Vector[(SearchHit, String)] = ordered.map(h => h -> InMemoryCorpus.foldCase(h.tpe))

  def byName(pattern: String, limit: Int): IO[Vector[SearchHit]] = IO.pure {
    val p = InMemoryCorpus.foldCase(pattern)
    loweredNames.collect { case (h, q, n) if q.contains(p) || n.contains(p) => h }.take(math.max(1, limit))
  }
  def byType(pattern: String, limit: Int): IO[Vector[SearchHit]] = IO.pure {
    val p = InMemoryCorpus.foldCase(pattern)
    loweredType.collect { case (h, t) if t.contains(p) => h }.take(math.max(1, limit))
  }
  def dependenciesOf(prettyQname: String): IO[Vector[SearchHit]] = IO.pure(Vector.empty)
}

object InMemoryCorpus {

  /** `Data.Text.toLower`'s case fold: one code point at a time, with no
    * word-final context.  `String.toLowerCase` applies the Greek final-sigma
    * rule, so `Agda.Builtin.Sigma.Σ` folds to `…sigma.ς` at the end of a
    * pattern but to `…sigma.σ` inside `Σ.fst`, and a substring query the
    * server answers with every `Σ` row would miss the projections here.
    */
  def foldCase(s: String): String = {
    val folded = s.codePoints().map(cp => Character.toLowerCase(cp)).toArray
    new String(folded, 0, folded.length)
  }

  /** Unicode code-point order: `Data.Text`'s `compare` on the UTF-8 text the
    * server indexes by.  `String.compareTo` orders by UTF-16 code unit, which
    * puts a surrogate pair (`𝑨`, U+1D468) below a BMP glyph such as `ﬂ`
    * (U+FB02) where code-point order puts it above.
    */
  val codePointOrder: Ordering[String] = {
    import scala.math.Ordering.Implicits.seqOrdering
    Ordering.by[String, Seq[Int]](s => s.codePoints().toArray.toSeq)
  }

  /** Load a corpus JSONL.  Rows that do not parse are counted and dropped, as
    * the server drops them; the count is returned so a report can state it.
    * Rows are then deduplicated by `prettyQname`, keeping the LAST one in
    * file order: the server indexes the corpus as a map keyed by that name
    * (`Map.fromList` over the rows in file order), and the agda-algebras
    * v0.1 corpus carries 733 duplicate keys (record fields re-exported
    * through parameterised modules), so a search over all rows would count
    * hits the server never returns.
    */
  def load(path: Path): IO[(InMemoryCorpus, Int, DefinitionTable)] =
    Jsonl.parsed(path).compile.fold(Loading.empty)(_ line _).map { l =>
      (new InMemoryCorpus(dedupLastWins(l.rows), l.names), l.bad, new DefinitionTable(l.defs))
    }

  /** What loading accumulates, line by line: the rows the server would
    * index, in file order; their `prettyName`s by qualified name (the last
    * row per name wins, as in the server's index); the definition table
    * over them; and the count of lines the server drops, an unparsable line
    * or a row its decoder refuses.
    */
  private final case class Loading(rows: Vector[SearchHit], names: Map[String, String],
                                   defs: Map[String, Vector[String]], bad: Int) {
    def line(parsed: Either[io.circe.ParsingFailure, Json]): Loading = parsed.fold(_ => copy(bad = bad + 1), row)
    // Only a row the server would index reaches the definition table (PR
    // #152 review, round two).
    def row(json: Json): Loading = SearchHit.fromCorpusRow(json) match {
      case Right(h) =>
        copy(rows  = rows :+ h,
             names = names ++ json.hcursor.get[String]("prettyName").toOption.map(h.prettyQname -> _),
             defs  = DefinitionTable.record(defs, json))
      case Left(_)  => copy(bad = bad + 1)
    }
  }
  private object Loading { val empty: Loading = Loading(Vector.empty, Map.empty, Map.empty, 0) }

  /** One row per `prettyQname`, the last in input order winning (the server's
    * `Map.fromList` semantics); the survivors keep their input order.
    */
  def dedupLastWins(rows: Vector[SearchHit]): Vector[SearchHit] = {
    val lastIx = rows.zipWithIndex.map { case (h, i) => h.prettyQname -> i }.toMap
    rows.zipWithIndex.collect { case (h, i) if lastIx(h.prettyQname) == i => h }
  }
}

/** The goal context, reconstructed from a fixture's source when a report did
  * not record it.  Agda's `Cmd_goal_type_context` lists every variable bound
  * at the hole: the signature's binders in order, where an implicit or
  * instance binder is inserted eagerly under its signature name (or the name
  * the clause rebinds it to with `{x = p}`), and a visible binder enters
  * under the clause's pattern name, until the first visible binder the
  * clause does not bind, after which the rest of the telescope is the goal.
  */
object FixtureContext {

  final case class SigBinder(visibility: Visibility, name: Option[String])

  import Statements.{Bare, Group}

  private def visibilityOf(open: Char): Visibility = open match {
    case '{' => Visibility.Hidden
    case '⦃' => Visibility.Instance
    case _   => Visibility.Visible
  }

  /** `name` followed by a token boundary: `π :`, `π i`, but not `πhom`. */
  private def startsWithName(line: String, name: String): Boolean = {
    val t = line.trim
    t.startsWith(name) && (t.length == name.length || " :{(=\t".contains(t.charAt(name.length)))
  }

  /** The index of the first `:` at bracket depth zero, if any: the depth
    * before each character by a scan, then the first colon at depth zero.
    */
  private def depth0Colon(content: String): Option[Int] = {
    val depths = content.iterator.scanLeft(0) { (d, c) =>
      if (Statements.Opens(c)) d + 1 else if (Statements.Closes(c)) d - 1 else d
    }.toVector
    content.indices.find(i => content.charAt(i) == ':' && depths(i) == 0)
  }

  /** The binder telescope of a signature body (everything after `name :`):
    * one segment per depth-0 arrow, the last being the codomain; in a
    * domain, each bracket group with a depth-0 colon binds the names before
    * the colon with the bracket's visibility, bare names after a `∀` bind
    * visibly, and a domain with no binder group at all is one anonymous
    * visible binder (a premise).
    */
  def telescope(signatureBody: String): Vector[SigBinder] = {
    // Standalone arrows only: a name such as `A→B` in a signature is one
    // token, not a binder boundary (PR #152 review, round three).
    val segs = Statements.splitTopLevelArrows(signatureBody)
    if (segs.size <= 1) Vector.empty
    else segs.init.flatMap { seg =>
      val ps     = Statements.pieces(seg)
      val forall = ps.headOption.exists { case Bare(t) => t.startsWith("∀"); case _ => false }
      val binderGrp = ps.flatMap {
        case Group(open, content) =>
          depth0Colon(content).toVector.flatMap(colon =>
            content.take(colon).trim.split("\\s+").toVector.filter(_.nonEmpty)
              .map(n => SigBinder(visibilityOf(open), Some(n))))
        case Bare(_) => Vector.empty
      }
      val forallBare =
        if (forall) ps.collect { case Bare(t) => t }.flatMap(_.split("\\s+")).filterNot(t => t == "∀" || t.isEmpty)
          .map(n => SigBinder(Visibility.Visible, Some(n)))
        else Vector.empty
      if (binderGrp.nonEmpty || forallBare.nonEmpty) binderGrp ++ forallBare
      else Vector(SigBinder(Visibility.Visible, None))
    }
  }

  /** The clause's patterns: implicit rebinds (`{𝑩 = 𝑩}` maps the signature's
    * `𝑩` to the pattern name) and the visible patterns in order, each a
    * vector of the names it binds (a bare name binds one; `_` binds none; a
    * parenthesised pattern binds every name token inside it).
    */
  def clausePatterns(lhs: String): (Map[String, String], Vector[Vector[String]]) = {
    val (rebinds, visibles) = Statements.pieces(lhs).flatMap[Either[(String, String), Vector[String]]] {
      case Bare(bare) =>
        bare.split("\\s+").toVector.filter(_.nonEmpty).map(t => Right(if (t == "_") Vector.empty else Vector(t)))
      case Group('{', content) if content.contains('=') =>
        val (name, pattern) = content.span(_ != '=')
        Vector(Left(name.trim -> pattern.drop(1).trim))
      case Group('{', _) => Vector.empty // a positional implicit pattern: not a shape the fixtures use
      case Group(_, content) =>
        Vector(Right(content.split("[\\s,]+").toVector.filter(t => t.nonEmpty && t != "_")))
    }.partitionMap(identity)
    (rebinds.toMap, visibles)
  }

  /** Walk the telescope against the patterns (see the object header). */
  def walk(binders: Vector[SigBinder], rebinds: Map[String, String], patterns: Vector[Vector[String]]): Vector[String] = {
    // A visible binder takes the next pattern, and the first visible binder
    // the clause does not bind ends the walk (the rest of the telescope is
    // the goal); an implicit or instance binder enters under its own name,
    // or the name the clause rebinds it to.
    @tailrec def go(bs: Vector[SigBinder], ps: Vector[Vector[String]], acc: Vector[String]): Vector[String] =
      (bs, ps) match {
        case (SigBinder(Visibility.Visible, _) +: rest, p +: more) => go(rest, more, acc ++ p)
        case (SigBinder(Visibility.Visible, _) +: _, _)            => acc
        case (SigBinder(_, name) +: rest, _) =>
          go(rest, ps, acc ++ name.map(n => rebinds.getOrElse(n, n)))
        case _ => acc
      }
    go(binders, patterns, Vector.empty).distinct
  }

  /** The context names at the `{!!}` hole of `hole`, from the fixture source;
    * empty when the signature or the clause cannot be located.  The clause
    * read is the one that carries the hole: the last clause head at or
    * before the `{!!}` line, since a definition may have several equations
    * and the earlier ones bind nothing at the hole (PR #152 review, round
    * six; every fixture of the suite has exactly one clause, so no report
    * moves).  Without a hole line, the first clause head is read alone.
    */
  def reconstruct(source: String, hole: String): Vector[String] = {
    val lines = source.linesIterator.toVector
    def lineFrom(from: Int)(p: String => Boolean): Option[Int] = lines.indices.drop(from).find(i => p(lines(i)))
    def isHead(i: Int): Boolean = startsWithName(lines(i), hole)
    val names = for {
      sigStart  <- lineFrom(0)(l => startsWithName(l, hole) && l.trim.drop(hole.length).trim.startsWith(":"))
      firstHead <- lines.indices.drop(sigStart + 1).find(isHead) // the signature ends at the first clause
    } yield {
      val holeLine  = lineFrom(firstHead)(_.contains("{!!}"))
      val clauseIx  = holeLine.map(h => lines.indices.slice(firstHead, h + 1).findLast(isHead).getOrElse(firstHead)).getOrElse(firstHead)
      val sigBody   = lines.slice(sigStart, firstHead).mkString(" ").split(":", 2).last
      val clause    = lines.slice(clauseIx, holeLine.getOrElse(clauseIx) + 1).mkString(" ")
      val afterName = clause.indexOf(hole) + hole.length
      val lhs       = clause.substring(afterName, math.max(afterName, clause.lastIndexOf('=')))
      val (rebinds, visibles) = clausePatterns(lhs)
      walk(telescope(sigBody), rebinds, visibles)
    }
    names.getOrElse(Vector.empty)
  }
}

/** One ground-truth name's fate in one ranked pool: its rank and score when
  * the pool ranks it, or the named reason it has none.  `label` is the
  * `status` the report writes; `detail` is the exclusion reason, the
  * defKind, or the row's module.
  */
sealed trait Fate extends Product with Serializable {
  def label:  String
  def rank:   Option[Int]    = None
  def score:  Option[Double] = None
  def detail: Option[String] = None
}
object Fate {
  final case class Ranked(at: Int, value: Double) extends Fate {
    val label: String = "ranked"
    override def rank:  Option[Int]    = Some(at)
    override def score: Option[Double] = Some(value)
  }
  final case class Excluded(reason: String) extends Fate {
    val label: String = "excluded"
    override def detail: Option[String] = Some(reason)
  }
  final case class NonFunction(defKind: String) extends Fate {
    val label: String = "non-function"
    override def detail: Option[String] = Some(defKind)
  }
  final case class OutOfScope(module: String) extends Fate {
    val label: String = "out-of-scope"
    override def detail: Option[String] = Some(module)
  }
  case object NotInCorpus extends Fate { val label: String = "not-in-corpus" }
  case object NotInPool extends Fate {
    val label: String = "not-in-pool"
    override def detail: Option[String] = Some("no query returned it (truncation?)")
  }
}

/** One ground-truth name, its role (`target` or `restates`), and its fate;
  * the report's vocabulary (`status`, `rank`, `score`, `detail`) reads off
  * the fate.
  */
final case class TargetStatus(qname: String, role: String, fate: Fate) {
  def status: String         = fate.label
  def rank:   Option[Int]    = fate.rank
  def score:  Option[Double] = fate.score
  def detail: Option[String] = fate.detail
  def hitAt(k: Int): Boolean = rank.exists(_ <= k)
  def toJson: Json = Json.obj(
    "qname"  -> qname.asJson,
    "role"   -> role.asJson,
    "status" -> status.asJson,
    "rank"   -> rank.asJson,
    "score"  -> score.asJson,
    "detail" -> detail.asJson
  ).dropNullValues
}

/** One fixture, one scorer: the pool as built, every ground-truth status, the
  * top of the ranking, and how the goal context was obtained.
  */
final case class FixtureRecall(
  benchmarkId:      String,
  stratum:          String,
  difficulty:       String,
  goal:             String,
  contextSource:    String,               // "report" | "reconstructed"
  context:          Vector[String],
  reconstruction:   Option[Vector[String]], // when the report had a context: what the fallback would have said
  degraded:         Boolean,                // a hypothesis-reading scorer replayed without the hypotheses' types
  goalTokens:       Vector[String],
  hypothesisTokens: Vector[String],        // empty when the report carried no context types
  pool:             RetrievalPool.Built,   // exclusion as configured
  targets:          Vector[TargetStatus],
  restates:         Vector[TargetStatus],  // measured in the unexcluded pool
  top:              Vector[(String, Double)]
) {
  /** Order and multiplicity included: the proposer spells saturated tuples
    * over the context in order, so a permuted reconstruction is a drift
    * (PR #152 review, round two).
    */
  def reconstructionMatches: Option[Boolean] = reconstruction.map(_ == context)
  def toJson: Json = Json.obj(
    "benchmarkId"           -> benchmarkId.asJson,
    "stratum"               -> stratum.asJson,
    "difficulty"            -> difficulty.asJson,
    "goal"                  -> goal.asJson,
    "contextSource"         -> contextSource.asJson,
    "context"               -> context.asJson,
    "reconstructionMatches" -> reconstructionMatches.asJson,
    "reconstruction"        -> reconstruction.asJson,
    "degraded"              -> degraded.asJson,
    "goalTokens"            -> goalTokens.asJson,
    "hypothesisTokens"      -> hypothesisTokens.asJson,
    "pool" -> Json.obj(
      "queries"     -> pool.queries.asJson,
      "truncated"   -> pool.truncated.asJson,
      "hits"        -> pool.hits.asJson,
      "inScope"     -> pool.inScope.size.asJson,
      "excluded"    -> pool.excluded.map(_._1).asJson,
      "nonFunction" -> pool.nonFunction.asJson,
      "ranked"      -> pool.ranked.size.asJson
    ),
    "targets"  -> Json.arr(targets.map(_.toJson): _*),
    "restates" -> Json.arr(restates.map(_.toJson): _*),
    "top"      -> Json.arr(top.map { case (q, s) => Json.obj("qname" -> q.asJson, "score" -> s.asJson) }: _*)
  ).dropNullValues
}

/** Recall over a set of statuses: `hitAt(k)` over ALL recorded names (an
  * unreachable name is a miss the searcher really suffers) and over the
  * reachable ones (the ranking question alone), plus the mean reciprocal rank
  * of the reachable ones.
  */
final case class RecallSummary(names: Int, reachable: Int, hitsAt: Map[Int, Int], mrr: Double) {
  def toJson(ks: Vector[Int]): Json = Json.obj(
    "names"     -> names.asJson,
    "reachable" -> reachable.asJson,
    "hitsAt"    -> Json.obj(ks.map(k => k.toString -> hitsAt.getOrElse(k, 0).asJson): _*),
    "recallAt"  -> Json.obj(ks.map(k => k.toString -> RecallSummary.ratio(hitsAt.getOrElse(k, 0), names).asJson): _*),
    "recallReachableAt" -> Json.obj(ks.map(k => k.toString -> RecallSummary.ratio(hitsAt.getOrElse(k, 0), reachable).asJson): _*),
    "mrr"       -> Scaffold.round3(mrr).asJson
  )
}
object RecallSummary {
  def ratio(num: Int, den: Int): Double = if (den == 0) 0.0 else Scaffold.round3(num.toDouble / den).toDouble
  def of(statuses: Vector[TargetStatus], ks: Vector[Int]): RecallSummary = {
    val ranks = statuses.collect { case TargetStatus(_, _, Fate.Ranked(at, _)) => at }
    RecallSummary(
      names     = statuses.size,
      reachable = ranks.size,
      hitsAt    = ks.map(k => k -> statuses.count(_.hitAt(k))).toMap,
      mrr       = if (ranks.isEmpty) 0.0 else ranks.map(1.0 / _).sum / ranks.size)
  }
}

final case class RecallConfig(
  index:         Path,
  corpus:        Path,
  report:        Path,
  projectRoot:   Path,
  out:           Path,
  ids:           Option[Set[String]],
  scorers:       Vector[ScorerSpec],
  excludeTarget: Boolean,
  ks:            Vector[Int],
  queryLimit:    Int,
  top:           Int,
  allowUntypedContext: Boolean
)

object RetrievalRecall extends IOApp {

  private val usage: String =
    """usage: runMain struxdriver.search.RetrievalRecall
      |    --index PATH           benchmark-index.jsonl (the `target:` / `restates:` tags are the ground truth)
      |    --corpus PATH          agda-strux corpus JSONL, loaded in-process (no server)
      |    --report PATH          a loop run's report.json: the goal displays (and contexts, when recorded)
      |    --project-root PATH    repo root: the index's obligation paths resolve here
      |    --out PATH             the JSON report to write
      |    (--ids id1,id2 | --all)
      |    [--scorers a,b]        scorers to rank with, by name (default: token-overlap)
      |    [--exclude-target on|off]  the pool the `target:` ranks are measured in (default on)
      |    [--k 8,32]             the recall cut-offs (default 8,32)
      |    [--query-limit N]      per-query cap, as the proposer sends it (default 5000)
      |    [--top N]              ranked rows to list per fixture (default 8)
      |    [--allow-untyped-context on|off]  replay a hypothesis-reading scorer over fixtures whose
      |                           report carries no context types, marking each as degraded (default off:
      |                           the run is refused, since the scorer would silently be its no-hypotheses variant)
      |""".stripMargin

  def run(args: List[String]): IO[ExitCode] =
    parseArgs(args) match {
      case Left(err)  => IO.println(s"error: $err\n\n$usage").as(ExitCode.Error)
      case Right(cfg) => runInstrument(cfg).as(ExitCode.Success)
    }

  /** The documented options; anything else is refused (Scaffold.parseFlags). */
  private val Keys: Set[String] = Set(
    "index", "corpus", "report", "project-root", "out", "ids",
    "scorers", "exclude-target", "k", "query-limit", "top", "allow-untyped-context")

  private[search] def parseArgs(args: List[String]): Either[String, RecallConfig] = {
    def intOf(m: Map[String, String], key: String, dflt: Int, min: Int): Either[String, Int] =
      m.get(key).fold[Either[String, Int]](Right(dflt))(s =>
        s.toIntOption.filter(_ >= min).toRight(s"bad --$key: $s"))
    for {
      m       <- Scaffold.parseFlags(args, Keys)
      ix      <- m.get("index").toRight("missing --index")
      corpus  <- m.get("corpus").toRight("missing --corpus")
      report  <- m.get("report").toRight("missing --report")
      root    <- m.get("project-root").toRight("missing --project-root")
      out     <- m.get("out").toRight("missing --out")
      ids     <- Scaffold.selection(m)
      scorers <- nonEmptyList(m, "scorers", Scorers.default.name).flatMap(_.traverse(Scorers.byName))
      excl    <- m.get("exclude-target").fold[Either[String, Boolean]](Right(true)) {
                   case "on"  => Right(true)
                   case "off" => Right(false)
                   case other => Left(s"bad --exclude-target: $other (on|off)")
                 }
      ks      <- nonEmptyList(m, "k", "8,32").flatMap(_.traverse(s => s.toIntOption.filter(_ >= 1).toRight(s"bad --k: $s")))
      limit   <- intOf(m, "query-limit", RetrievalConfig.default.queryLimit, 1)
      top     <- intOf(m, "top", 8, 0)
      untyped <- m.get("allow-untyped-context").fold[Either[String, Boolean]](Right(false)) {
                   case "on"  => Right(true)
                   case "off" => Right(false)
                   case other => Left(s"bad --allow-untyped-context: $other (on|off)")
                 }
    } yield RecallConfig(
      index         = Paths.get(ix),
      corpus        = Paths.get(corpus),
      report        = Paths.get(report),
      projectRoot   = Paths.get(root).toAbsolutePath.normalize,
      out           = Paths.get(out),
      ids           = ids,
      scorers       = scorers,
      excludeTarget = excl,
      ks            = ks.sorted,
      queryLimit    = limit,
      top           = top,
      allowUntypedContext = untyped
    )
  }

  /** A comma-separated list option that must name at least one item: an
    * explicit `--scorers ""` is a configuration error, not a run with no
    * scorers that writes a report which looks complete (PR #152 review,
    * round two).
    */
  private def nonEmptyList(m: Map[String, String], key: String, dflt: String): Either[String, Vector[String]] = {
    val items = m.getOrElse(key, dflt).split(",").toVector.map(_.trim).filter(_.nonEmpty)
    if (items.isEmpty) Left(s"--$key needs at least one item") else Right(items)
  }

  /** The refusal a hypothesis-reading scorer earns when a fixture's report
    * carries no context types: the scorer would run as its no-hypotheses
    * variant under its own name.  `None` when nothing is at risk or the
    * caller opted into marked, degraded replay.
    */
  def untypedRefusal(scorers: Vector[CandidateScorer], untyped: Vector[String], allow: Boolean): Option[String] = {
    val readers = scorers.filter(_.readsHypotheses).map(_.name)
    if (allow || readers.isEmpty || untyped.isEmpty) None
    else Some(s"scorer(s) ${readers.mkString(", ")} read the hypotheses' types, but ${untyped.size} fixture(s) have no typed context on record " +
      s"(${untyped.mkString(", ")}); pass --allow-untyped-context on to replay them anyway, marked degraded, or use a report that carries goalContext")
  }

  /** The sha256 a loop report recorded for the corpus it retrieved from
    * (`ProofSearchLoop.corpusProvenance`), when it ran with one.
    */
  def reportCorpusDigest(report: Json): Option[String] =
    report.hcursor.downField("corpus").get[String]("sha256").toOption

  /** What a report recorded per fixture: the root goal display, and the
    * context when the report is recent enough to carry one.
    */
  final case class RecordedGoal(goal: String, context: Option[Vector[CtxEntry]]) {
    def contextNames: Option[Vector[String]] = context.map(_.map(_.name))
  }

  def recordedGoals(report: Json): Map[String, RecordedGoal] =
    report.hcursor.downField("outcomes").focus.flatMap(_.asArray).getOrElse(Vector.empty).flatMap { o =>
      val c = o.hcursor
      for {
        id   <- c.get[String]("benchmarkId").toOption
        goal <- c.get[String]("goal").toOption
        if c.get[String]("searchStatus").toOption.exists(_ != "anomaly")
      } yield id -> RecordedGoal(goal,
        c.downField("goalContext").focus.flatMap(_.asArray)
          .map(_.flatMap(e => e.hcursor.get[String]("name").toOption
            .map(n => CtxEntry(n, e.hcursor.get[String]("type").getOrElse(""), None)))))
    }.toMap

  /** A recorded context counts as untyped when it is absent or when any of
    * its entries lacks a type, since a hypothesis-reading scorer would then
    * see no hypothesis tokens for that entry; an explicitly empty context
    * (`Some(Vector.empty)`, a fixture with no hypotheses) is fully typed
    * (PR #152 review, round three).
    */
  def untypedContext(ctx: Option[Vector[CtxEntry]]): Boolean = ctx.forall(_.exists(_.tpe.trim.isEmpty))

  /** Statuses of the ground-truth names against one built pool. */
  def statuses(names: Vector[String], role: String, corpus: InMemoryCorpus, scope: ImportScope,
               built: RetrievalPool.Built, score: SearchHit => Double): Vector[TargetStatus] =
    names.map(q => TargetStatus(q, role, fateOf(q, corpus, scope, built, score)))

  /** One name's fate: the first reason it is unreachable, in the order the
    * pipeline applies them (the corpus, the scope, the exclusion, the
    * `defKind` filter, the queries), else its rank and score.
    */
  def fateOf(q: String, corpus: InMemoryCorpus, scope: ImportScope, built: RetrievalPool.Built,
             score: SearchHit => Double): Fate =
    corpus.lookup(q) match {
      case None                                                     => Fate.NotInCorpus
      case Some(row) if scope.importingModuleOf(row.module).isEmpty => Fate.OutOfScope(row.module)
      case Some(row) =>
        built.excluded.collectFirst { case (reason, h) if h.prettyQname == q => Fate.Excluded(reason) }.getOrElse {
          if (row.defKind != "function") Fate.NonFunction(row.defKind)
          else built.ranked.zipWithIndex
            .collectFirst { case (h, i) if h.prettyQname == q => Fate.Ranked(i + 1, score(row)) }
            .getOrElse(Fate.NotInPool)
        }
    }

  /** One fixture under one scorer. */
  def evaluate(cfg: RecallConfig, corpus: InMemoryCorpus, scorer: CandidateScorer,
               entry: IndexEntry, recorded: RecordedGoal, source: String): IO[FixtureRecall] = {
    val scope         = ImportScope(Imports.imported(source))
    val exclusion     = TargetExclusion(entry.hole, entry.typeSig)
    val reconstructed = FixtureContext.reconstruct(source, entry.hole)
    val (ctxSource, ctxEntries) = recorded.context match {
      case Some(entries) => ("report", entries)
      case None          => ("reconstructed", reconstructed.map(n => CtxEntry(n, "", None)))
    }
    val ctx     = ctxEntries.map(_.name)
    val goal    = GoalView(recorded.goal, ctxEntries, None)
    val query   = Queries.rankQuery(goal)
    val rcfg    = RetrievalConfig.default.copy(queryLimit = cfg.queryLimit, excludeTarget = cfg.excludeTarget)
    for {
      built    <- RetrievalPool.build(corpus, scope, exclusion, rcfg, scorer, goal)
      builtOff <- if (cfg.excludeTarget) RetrievalPool.build(corpus, scope, exclusion, rcfg.copy(excludeTarget = false), scorer, goal)
                  else IO.pure(built)
    } yield {
      val score    = scorer.scores(query, built.ranked)
      val scoreOff = scorer.scores(query, builtOff.ranked)
      FixtureRecall(
        benchmarkId    = entry.id,
        stratum        = entry.stratum,
        difficulty     = entry.difficulty.tag,
        goal           = recorded.goal,
        contextSource  = ctxSource,
        context        = ctx,
        reconstruction = recorded.context.map(_ => reconstructed),
        degraded       = untypedContext(recorded.context) && scorer.readsHypotheses,
        goalTokens     = Queries.goalTokens(goal),
        hypothesisTokens = Queries.hypothesisTokens(goal),
        pool           = built,
        targets        = statuses(entry.taggedValues("target:"), "target", corpus, scope, built, score),
        restates       = statuses(entry.taggedValues("restates:"), "restates", corpus, scope, builtOff, scoreOff),
        top            = built.ranked.take(cfg.top).map(h => (h.prettyQname, score(h)))
      )
    }
  }

  private def runInstrument(cfg: RecallConfig): IO[Unit] =
    for {
      entries0 <- Scaffold.readIndex(cfg.index, cfg.ids)
      report   <- IO.blocking(new String(Files.readAllBytes(cfg.report), StandardCharsets.UTF_8))
                    .flatMap(s => IO.fromEither(io.circe.parser.parse(s).leftMap(e => new RuntimeException(s"bad report: ${e.message}"))))
      goals     = recordedGoals(report)
      withGT    = entries0.filter(e => e.taggedValues("target:").nonEmpty || e.taggedValues("restates:").nonEmpty)
      skippedNoGT   = entries0.filterNot(withGT.contains).map(_.id)
      skippedNoGoal = withGT.filterNot(e => goals.contains(e.id)).map(_.id)
      entries   = withGT.filter(e => goals.contains(e.id))
      _        <- IO.raiseWhen(entries.isEmpty)(new RuntimeException("no obligation has both a recorded goal and ground-truth tags"))
      t0       <- IO.monotonic
      loaded   <- InMemoryCorpus.load(cfg.corpus)
      (corpus, badRows, defs) = loaded
      digest   <- Digest.sha256Hex(cfg.corpus)
      reportDigest = reportCorpusDigest(report)
      _        <- reportDigest.filter(_ != digest).traverse_(rd => IO.println(
                    s"!! the corpus differs from the one the replayed run retrieved from (sha256 ${digest.take(12)}… vs ${rd.take(12)}…): the ranks below are not a replay of that run"))
      t1       <- IO.monotonic
      _        <- IO.println(s">> recall instrument: ${entries.size} obligation(s), corpus ${corpus.rows.size} rows (${badRows} unparsable, ${defs.size} definition bodies) in ${(t1 - t0).toMillis} ms; scorers ${cfg.scorers.map(_.name).mkString(",")}; exclusion ${if (cfg.excludeTarget) "on" else "off"}")
      instantiated = cfg.scorers.map(_.instantiate(defs))
      untyped   = entries.filter(e => untypedContext(goals(e.id).context)).map(_.id)
      _        <- untypedRefusal(instantiated, untyped, cfg.allowUntypedContext)
                    .traverse_(msg => IO.raiseError[Unit](new RuntimeException(msg)))
      _        <- IO.whenA(untyped.nonEmpty && instantiated.exists(_.readsHypotheses))(
                    IO.println(s"!! ${untyped.size} fixture(s) replayed without hypothesis types; hypothesis-reading scorers are marked degraded there: ${untyped.mkString(", ")}"))
      sources  <- entries.traverse(e => IO.blocking(new String(Files.readAllBytes(cfg.projectRoot.resolve(e.obligationPath)), StandardCharsets.UTF_8)).map(e.id -> _)).map(_.toMap)
      perScorer <- instantiated.traverse { sc =>
                     entries.traverse(e => evaluate(cfg, corpus, sc, e, goals(e.id), sources(e.id))).map(sc -> _)
                   }
      t2       <- IO.monotonic
      json      = reportJson(cfg, corpus.rows.size, badRows, digest, reportDigest, perScorer, skippedNoGT, skippedNoGoal, (t2 - t1).toMillis)
      _        <- IO.blocking { Option(cfg.out.getParent).foreach(Files.createDirectories(_)); Files.write(cfg.out, json.spaces2.getBytes(StandardCharsets.UTF_8)) }
      _        <- IO.println(render(cfg, perScorer, skippedNoGT, skippedNoGoal))
      _        <- IO.println(s">> wrote ${cfg.out}")
    } yield ()

  private def strataOf(fs: Vector[FixtureRecall]): Vector[String] = fs.map(_.stratum).distinct

  private def summaries(fs: Vector[FixtureRecall], ks: Vector[Int]): Json = {
    def block(sel: Vector[FixtureRecall]): Json = {
      val withTargets = sel.filter(_.targets.nonEmpty)
      Json.obj(
        "fixtures"          -> sel.size.asJson,
        "fixturesWithTargets" -> withTargets.size.asJson,
        "targets"           -> RecallSummary.of(sel.flatMap(_.targets), ks).toJson(ks),
        "fixturesAllTargetsAt" -> Json.obj(ks.map(k =>
          k.toString -> withTargets.count(_.targets.forall(_.hitAt(k))).asJson): _*),
        "restates"          -> RecallSummary.of(sel.flatMap(_.restates), ks).toJson(ks)
      )
    }
    Json.obj(
      "overall"    -> block(fs),
      "perStratum" -> Json.obj(strataOf(fs).map(s => s -> block(fs.filter(_.stratum == s))): _*)
    )
  }

  private def reportJson(cfg: RecallConfig, rows: Int, badRows: Int, corpusSha256: String, reportCorpusSha256: Option[String],
                         perScorer: Vector[(CandidateScorer, Vector[FixtureRecall])],
                         skippedNoGT: Vector[String], skippedNoGoal: Vector[String], wallMs: Long): Json =
    Json.obj(
      "schemaVersion" -> "proof-search-recall.v0".asJson,
      "timestamp"     -> java.time.Instant.now().toString.asJson,
      "config" -> Json.obj(
        "index"         -> cfg.index.toString.asJson,
        "corpus"        -> cfg.corpus.toString.asJson,
        "corpusSha256"  -> corpusSha256.asJson,
        "corpusRows"    -> rows.asJson,
        "corpusUnparsable" -> badRows.asJson,
        "report"        -> cfg.report.toString.asJson,
        // The digest the replayed run recorded, and whether this corpus is
        // that one; absent when the run recorded none.
        "reportCorpusSha256"  -> reportCorpusSha256.asJson,
        "corpusMatchesReport" -> reportCorpusSha256.map(_ == corpusSha256).asJson,
        "scorers"       -> cfg.scorers.map(_.name).asJson,
        "excludeTarget" -> cfg.excludeTarget.asJson,
        "k"             -> cfg.ks.asJson,
        "queryLimit"    -> cfg.queryLimit.asJson,
        "wallMs"        -> wallMs.asJson
      ).dropNullValues,
      "skipped" -> Json.obj(
        "noGroundTruth"  -> skippedNoGT.asJson,
        "noRecordedGoal" -> skippedNoGoal.asJson
      ),
      "scorers" -> Json.arr(perScorer.map { case (sc, fs) =>
        Json.obj(
          "name"      -> sc.name.asJson,
          "summary"   -> summaries(fs, cfg.ks),
          "contextReconstructionMismatches" -> fs.filter(_.reconstructionMatches.contains(false)).map(_.benchmarkId).asJson,
          "degradedFixtures" -> fs.filter(_.degraded).map(_.benchmarkId).asJson,
          "fixtures"  -> Json.arr(fs.map(_.toJson): _*)
        )
      }: _*)
    )

  /** The stdout rendering: one summary table per scorer, then the per-fixture
    * statuses, so a sweep reads at a glance and pastes into an issue.
    */
  private def render(cfg: RecallConfig, perScorer: Vector[(CandidateScorer, Vector[FixtureRecall])],
                     skippedNoGT: Vector[String], skippedNoGoal: Vector[String]): String = {
    val ks = cfg.ks
    def pct(n: Int, d: Int): String = if (d == 0) "-" else f"${100.0 * n / d}%.0f%%"
    def row(label: String, sel: Vector[FixtureRecall]): String = {
      val t  = RecallSummary.of(sel.flatMap(_.targets), ks)
      val r  = RecallSummary.of(sel.flatMap(_.restates), ks)
      val wt = sel.filter(_.targets.nonEmpty)
      val tCols = ks.map(k => s"${t.hitsAt(k)}/${t.names} (${pct(t.hitsAt(k), t.names)})").mkString(" | ")
      val fCols = ks.map(k => s"${wt.count(_.targets.forall(_.hitAt(k)))}/${wt.size}").mkString(" | ")
      val rCols = ks.map(k => s"${r.hitsAt(k)}/${r.names} (${pct(r.hitsAt(k), r.names)})").mkString(" | ")
      s"| $label | ${sel.size} | ${t.reachable}/${t.names} | $tCols | ${f"${t.mrr}%.3f"} | $fCols | $rCols |"
    }
    val header =
      s"| stratum | fixtures | targets reachable | ${ks.map(k => s"targets @$k").mkString(" | ")} | MRR | ${ks.map(k => s"fixtures all @$k").mkString(" | ")} | ${ks.map(k => s"originals @$k (excl. off)").mkString(" | ")} |\n" +
      s"|---|---|---|${ks.map(_ => "---").mkString("|")}|---|${ks.map(_ => "---").mkString("|")}|${ks.map(_ => "---").mkString("|")}|"
    val tables = perScorer.map { case (sc, fs) =>
      val strata = strataOf(fs).map(s => row(s, fs.filter(_.stratum == s)))
      val details = fs.map { f =>
        def one(t: TargetStatus) = t.fate match {
          case Fate.Ranked(at, _) => s"${t.qname} #$at"
          case other              => s"${t.qname} ${other.label}${other.detail.fold("")(d => s"($d)")}"
        }
        val mism = (if (f.reconstructionMatches.contains(false)) " CONTEXT-MISMATCH" else "") +
                   (if (f.degraded) " DEGRADED(no hypothesis types on record)" else "")
        s"  ${f.benchmarkId} [${f.stratum}] pool=${f.pool.ranked.size} ctx=${f.contextSource}$mism\n" +
          f.targets.map(t => s"      target   ${one(t)}").mkString("\n") + (if (f.targets.isEmpty) "      target   (none recorded)" else "") + "\n" +
          f.restates.map(t => s"      restates ${one(t)}").mkString("\n")
      }
      s"\n== scorer ${sc.name} (targets in the pool with exclusion ${if (cfg.excludeTarget) "on" else "off"}; originals in the unexcluded pool) ==\n" +
        header + "\n" + (strata :+ row("overall", fs)).mkString("\n") + "\n" + details.mkString("\n")
    }
    val skipped =
      (if (skippedNoGT.nonEmpty) s"\nskipped, no ground-truth tags: ${skippedNoGT.mkString(", ")}" else "") +
      (if (skippedNoGoal.nonEmpty) s"\nskipped, no recorded goal in the report: ${skippedNoGoal.mkString(", ")}" else "")
    tables.mkString("\n") + skipped
  }
}
