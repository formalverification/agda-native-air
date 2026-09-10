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
  *  the lane anything — `RetrievalPool.build`: queries with the server's own
  *  substring semantics, scope, target exclusion, the `defKind` filter, and
  *  the scorer's rank.  Two things the proposer does afterwards are NOT
  *  replayed, and the numbers here are conservative for both: lane
  *  resolution (a row the lane cannot render is skipped by the loop, which
  *  can only move a target UP the effective ranking) and the lane-form
  *  statement exclusion (which can only remove a row the syntactic rule
  *  missed).  The instrument reports, never decides: a target's status is
  *  its rank, or the named reason it has none.
  *
  *  Ground truth
  *  ------------
  *  From the index tags (data/benchmarks/README.md, "Ranking ground truth"):
  *  `target:<prettyQname>` names a lemma the gold proof applies, measured in
  *  the pool WITH exclusion as configured (the fair regime); `restates:` names
  *  the library original the row was mined from, measured in the pool WITHOUT
  *  exclusion (the haystack regime the exclusion-off control depends on).  A
  *  target may be unreachable for a stated reason — not in this corpus (a
  *  standard-library name), a constructor (the `defKind` filter), out of
  *  scope, or excluded — and each reason is reported by name rather than
  *  folded into a recall miss without comment; recall is quoted both over all
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
  *  every run that carries the real thing.
  *
  *  Invocation (see the proof-search-recall Make target)
  *  -----------------------------------------------------
  *    sbt "runMain struxdriver.search.RetrievalRecall
  *          --index data/benchmarks/benchmark-index.jsonl
  *          --corpus data/corpora/agda-algebras/v0.1/corpus.jsonl
  *          --report data/benchmarks/reports/proof-search/<run>/report.json
  *          --project-root /path/to/repo --out recall.json
  *          [--scorers token-overlap,…] [--exclude-target on|off] [--k 8,32]
  *          [--ids id1,id2 | --all] [--top 8]"
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

import struxdriver.benchmark.{Obligation => IndexEntry}

/** A corpus loaded in-process, answering the three tools with the server's
  * own semantics (agda-mcp `Corpus.hs`): case-insensitive substring match on
  * `prettyQname` (name search) or on the printed type (type search), results
  * in the corpus map's key order — `Data.Text`'s `Ord`, which is code-point
  * order, not Java's UTF-16 unit order (they differ on the astral glyphs
  * agda-algebras names are full of) — truncated at the limit.  The wire
  * `module` field is the row's PRETTY module, as the server sends it.
  * Dependency expansion answers empty: the instrument measures the pool the
  * default configuration ranks, and `expandDeps` is off in every published
  * sweep.
  */
final class InMemoryCorpus(val rows: Vector[SearchHit]) extends CorpusSearch {
  private val byQname: Map[String, SearchHit] = rows.map(h => h.prettyQname -> h).toMap
  private val ordered: Vector[SearchHit]      = rows.sortBy(_.prettyQname)(InMemoryCorpus.codePointOrder)

  def lookup(prettyQname: String): Option[SearchHit] = byQname.get(prettyQname)

  private val loweredQname: Vector[(SearchHit, String)] = ordered.map(h => h -> InMemoryCorpus.foldCase(h.prettyQname))
  private val loweredType:  Vector[(SearchHit, String)] = ordered.map(h => h -> InMemoryCorpus.foldCase(h.tpe))

  def byName(pattern: String, limit: Int): IO[Vector[SearchHit]] = IO.pure {
    val p = InMemoryCorpus.foldCase(pattern)
    loweredQname.collect { case (h, q) if q.contains(p) => h }.take(math.max(1, limit))
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
    val sb = new java.lang.StringBuilder(s.length)
    s.codePoints().forEach(cp => sb.appendCodePoint(Character.toLowerCase(cp)))
    sb.toString
  }

  /** Unicode code-point order — `Data.Text`'s `compare` on the UTF-8 text the
    * server indexes by.  `String.compareTo` orders by UTF-16 code unit, which
    * puts a surrogate pair (`𝑨`, U+1D468) below a BMP glyph such as `ﬂ`
    * (U+FB02) where code-point order puts it above.
    */
  val codePointOrder: Ordering[String] = new Ordering[String] {
    def compare(a: String, b: String): Int = {
      var i = 0
      var j = 0
      var r = 0
      while (r == 0 && i < a.length && j < b.length) {
        val ca = a.codePointAt(i)
        val cb = b.codePointAt(j)
        r = Integer.compare(ca, cb)
        i += Character.charCount(ca)
        j += Character.charCount(cb)
      }
      if (r != 0) r else Integer.compare(a.length - i, b.length - j)
    }
  }

  /** One corpus row as the server would serve it: the wire subset of the
    * full row (docs/representation.md §3), `module` = `prettyModule`.
    */
  def hitOf(json: Json): Either[String, SearchHit] = {
    val c = json.hcursor
    (for {
      qn   <- c.get[String]("prettyQname")
      tpe  <- c.get[String]("type")
      kind <- c.get[String]("defKind")
      mod  <- c.get[String]("prettyModule")
      body <- c.getOrElse[Boolean]("hasBody")(false)
    } yield SearchHit(qn, tpe, kind, mod, body)).leftMap(_.getMessage)
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
    IO.blocking {
      val src = scala.io.Source.fromFile(path.toFile, "UTF-8")
      try {
        val rows = Vector.newBuilder[SearchHit]
        val defs = scala.collection.mutable.LinkedHashMap.empty[String, Vector[String]]
        var bad  = 0
        src.getLines().foreach { line =>
          if (line.trim.nonEmpty)
            io.circe.parser.parse(line).leftMap(_.message) match {
              case Left(_) => bad += 1
              case Right(json) =>
                hitOf(json) match {
                  case Right(h) => rows += h
                  case Left(_)  => bad += 1
                }
                DefinitionTable.entryOf(json).foreach { case (q, toks) => defs.update(q, toks) }
            }
        }
        (new InMemoryCorpus(dedupLastWins(rows.result())), bad, new DefinitionTable(defs.toMap))
      } finally src.close()
    }

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
  * under the clause's pattern name — until the first visible binder the
  * clause does not bind, after which the rest of the telescope is the goal.
  */
object FixtureContext {

  final case class SigBinder(visibility: Visibility, name: Option[String])

  private val Opens  = Set('(', '{', '⦃')
  private val Closes = Set(')', '}', '⦄')

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

  /** Split on `→` at bracket depth 0. */
  private def splitArrows(s: String): Vector[String] = {
    val out   = Vector.newBuilder[String]
    val cur   = new StringBuilder
    var depth = 0
    s.foreach {
      case c if Opens(c)          => depth += 1; cur += c
      case c if Closes(c)         => depth -= 1; cur += c
      case '→' if depth == 0      => out += cur.result().trim; cur.clear()
      case c                      => cur += c
    }
    out += cur.result().trim
    out.result()
  }

  /** Depth-0 pieces of one segment: bracket groups (with their opener) and
    * the bare text between them.
    */
  private def pieces(seg: String): Vector[Either[String, (Char, String)]] = {
    val out   = Vector.newBuilder[Either[String, (Char, String)]]
    val cur   = new StringBuilder
    var depth = 0
    var open  = ' '
    def flushBare(): Unit = { val t = cur.result().trim; if (t.nonEmpty) out += Left(t); cur.clear() }
    seg.foreach {
      case c if Opens(c) =>
        if (depth == 0) { flushBare(); open = c } else cur += c
        depth += 1
      case c if Closes(c) =>
        depth -= 1
        if (depth == 0) { out += Right((open, cur.result())); cur.clear() } else cur += c
      case c => cur += c
    }
    flushBare()
    out.result()
  }

  private def depth0Colon(content: String): Option[Int] = {
    var depth = 0
    var i     = 0
    var found = -1
    while (found < 0 && i < content.length) {
      val c = content.charAt(i)
      if (Opens(c)) depth += 1
      else if (Closes(c)) depth -= 1
      else if (c == ':' && depth == 0) found = i
      i += 1
    }
    if (found < 0) None else Some(found)
  }

  /** The binder telescope of a signature body (everything after `name :`):
    * one segment per depth-0 arrow, the last being the codomain; in a
    * domain, each bracket group with a depth-0 colon binds the names before
    * the colon with the bracket's visibility, bare names after a `∀` bind
    * visibly, and a domain with no binder group at all is one anonymous
    * visible binder (a premise).
    */
  def telescope(signatureBody: String): Vector[SigBinder] = {
    val segs = splitArrows(signatureBody.replaceAll("\\s+", " ").trim)
    if (segs.size <= 1) Vector.empty
    else segs.init.flatMap { seg =>
      val ps        = pieces(seg)
      val forall    = ps.headOption.exists(_.left.exists(_.startsWith("∀")))
      val groups    = ps.collect { case Right((open, content)) => (open, content) }
      val binderGrp = groups.collect { case (open, content) if depth0Colon(content).isDefined =>
        content.substring(0, depth0Colon(content).get).trim.split("\\s+").toVector.filter(_.nonEmpty)
          .map(n => SigBinder(visibilityOf(open), Some(n)))
      }.flatten
      val forallBare =
        if (forall) ps.collect { case Left(t) => t }.flatMap(_.split("\\s+")).filterNot(t => t == "∀" || t.isEmpty)
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
    val rebinds  = Map.newBuilder[String, String]
    val visibles = Vector.newBuilder[Vector[String]]
    pieces(lhs).foreach {
      case Left(bare) =>
        bare.split("\\s+").filter(_.nonEmpty).foreach(t => visibles += (if (t == "_") Vector.empty else Vector(t)))
      case Right(('{', content)) if content.contains('=') =>
        val Array(l, r) = content.split("=", 2)
        rebinds += (l.trim -> r.trim)
      case Right(('{', _)) => () // a positional implicit pattern: not a shape the fixtures use
      case Right((_, content)) =>
        visibles += content.split("[\\s,]+").toVector.filter(t => t.nonEmpty && t != "_")
    }
    (rebinds.result(), visibles.result())
  }

  /** Walk the telescope against the patterns (see the object header). */
  def walk(binders: Vector[SigBinder], rebinds: Map[String, String], patterns: Vector[Vector[String]]): Vector[String] = {
    val out  = Vector.newBuilder[String]
    var ps   = patterns
    var stop = false
    binders.foreach { b =>
      if (!stop) b.visibility match {
        case Visibility.Visible =>
          if (ps.isEmpty) stop = true
          else { out ++= ps.head; ps = ps.tail }
        case _ =>
          b.name.foreach(n => out += rebinds.getOrElse(n, n))
      }
    }
    out.result().distinct
  }

  /** The context names at the `{!!}` hole of `hole`, from the fixture source;
    * empty when the signature or the clause cannot be located.
    */
  def reconstruct(source: String, hole: String): Vector[String] = {
    val lines    = source.linesIterator.toVector
    val sigStart = lines.indexWhere(l => startsWithName(l, hole) && l.trim.drop(hole.length).trim.startsWith(":"))
    val clauseIx = if (sigStart < 0) -1 else lines.indexWhere(l => startsWithName(l, hole), sigStart + 1)
    if (sigStart < 0 || clauseIx < 0) Vector.empty
    else {
      val sig     = lines.slice(sigStart, clauseIx).mkString(" ")
      val sigBody = sig.substring(sig.indexOf(':') + 1)
      val holeIx  = lines.indexWhere(_.contains("{!!}"), clauseIx)
      val clause  = lines.slice(clauseIx, (if (holeIx < 0) clauseIx else holeIx) + 1).mkString(" ")
      val lhs     = clause.substring(clause.indexOf(hole) + hole.length, math.max(clause.indexOf(hole) + hole.length, clause.lastIndexOf('=')))
      val (rebinds, visibles) = clausePatterns(lhs)
      walk(telescope(sigBody), rebinds, visibles)
    }
  }
}

/** One ground-truth name's fate in one ranked pool. */
final case class TargetStatus(
  qname:  String,
  role:   String,          // "target" | "restates"
  status: String,          // "ranked" | "excluded" | "non-function" | "out-of-scope" | "not-in-corpus" | "not-in-pool"
  rank:   Option[Int],     // 1-based, when ranked
  score:  Option[Double],  // the scorer's value, when ranked
  detail: Option[String]   // the exclusion reason, the defKind, the row's module
) {
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
  goalTokens:       Vector[String],
  hypothesisTokens: Vector[String],        // empty when the report carried no context types
  pool:             RetrievalPool.Built,   // exclusion as configured
  targets:          Vector[TargetStatus],
  restates:         Vector[TargetStatus],  // measured in the unexcluded pool
  top:              Vector[(String, Double)]
) {
  def reconstructionMatches: Option[Boolean] = reconstruction.map(_.toSet == context.toSet)
  def toJson: Json = Json.obj(
    "benchmarkId"           -> benchmarkId.asJson,
    "stratum"               -> stratum.asJson,
    "difficulty"            -> difficulty.asJson,
    "goal"                  -> goal.asJson,
    "contextSource"         -> contextSource.asJson,
    "context"               -> context.asJson,
    "reconstructionMatches" -> reconstructionMatches.asJson,
    "reconstruction"        -> reconstruction.asJson,
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
    val reach = statuses.filter(_.status == "ranked")
    RecallSummary(
      names     = statuses.size,
      reachable = reach.size,
      hitsAt    = ks.map(k => k -> statuses.count(_.hitAt(k))).toMap,
      mrr       = if (reach.isEmpty) 0.0 else reach.flatMap(_.rank).map(1.0 / _).sum / reach.size)
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
  top:           Int
)

object RetrievalRecall extends IOApp {

  private val usage: String =
    """usage: runMain struxdriver.search.RetrievalRecall
      |    --index PATH           benchmark-index.jsonl (the `target:` / `restates:` tags are the ground truth)
      |    --corpus PATH          agda-strux corpus JSONL, loaded in-process (no server)
      |    --report PATH          a loop run's report.json: the goal displays (and contexts, when recorded)
      |    --project-root PATH    repo root: index paths resolve here
      |    --out PATH             the JSON report to write
      |    (--ids id1,id2 | --all)
      |    [--scorers a,b]        scorers to rank with, by name (default: token-overlap)
      |    [--exclude-target on|off]  the pool the `target:` ranks are measured in (default on)
      |    [--k 8,32]             the recall cut-offs (default 8,32)
      |    [--query-limit N]      per-query cap, as the proposer sends it (default 5000)
      |    [--top N]              ranked rows to list per fixture (default 8)
      |""".stripMargin

  def run(args: List[String]): IO[ExitCode] =
    parseArgs(args) match {
      case Left(err)  => IO.println(s"error: $err\n\n$usage").as(ExitCode.Error)
      case Right(cfg) => runInstrument(cfg).as(ExitCode.Success)
    }

  private def parseArgs(args: List[String]): Either[String, RecallConfig] = {
    @annotation.tailrec
    def go(rest: List[String], m: Map[String, String]): Either[String, Map[String, String]] =
      rest match {
        case Nil                                      => Right(m)
        case "--all" :: xs                            => go(xs, m + ("all" -> "true"))
        case flag :: v :: xs if flag.startsWith("--") => go(xs, m + (flag.drop(2) -> v))
        case other :: _                               => Left(s"unrecognized argument: $other")
      }
    def intOf(m: Map[String, String], key: String, dflt: Int, min: Int): Either[String, Int] =
      m.get(key).fold[Either[String, Int]](Right(dflt))(s =>
        s.toIntOption.filter(_ >= min).toRight(s"bad --$key: $s"))
    for {
      m       <- go(args, Map.empty)
      ix      <- m.get("index").toRight("missing --index")
      corpus  <- m.get("corpus").toRight("missing --corpus")
      report  <- m.get("report").toRight("missing --report")
      root    <- m.get("project-root").toRight("missing --project-root")
      out     <- m.get("out").toRight("missing --out")
      ids      = m.get("ids").map(_.split(",").map(_.trim).filter(_.nonEmpty).toSet)
      _       <- if (ids.isEmpty && !m.contains("all")) Left("pass --ids or --all") else Right(())
      scorers <- m.getOrElse("scorers", Scorers.default.name).split(",").toVector.map(_.trim).filter(_.nonEmpty)
                   .traverse(Scorers.byName)
      excl    <- m.get("exclude-target").fold[Either[String, Boolean]](Right(true)) {
                   case "on"  => Right(true)
                   case "off" => Right(false)
                   case other => Left(s"bad --exclude-target: $other (on|off)")
                 }
      ks      <- m.getOrElse("k", "8,32").split(",").toVector.map(_.trim).filter(_.nonEmpty)
                   .traverse(s => s.toIntOption.filter(_ >= 1).toRight(s"bad --k: $s"))
      limit   <- intOf(m, "query-limit", RetrievalConfig.default.queryLimit, 1)
      top     <- intOf(m, "top", 8, 0)
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
      top           = top
    )
  }

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

  /** Statuses of the ground-truth names against one built pool. */
  def statuses(names: Vector[String], role: String, corpus: InMemoryCorpus, scope: ImportScope,
               built: RetrievalPool.Built, score: SearchHit => Double): Vector[TargetStatus] =
    names.map { q =>
      corpus.lookup(q) match {
        case None => TargetStatus(q, role, "not-in-corpus", None, None, None)
        case Some(row) =>
          if (scope.importingModuleOf(row.module).isEmpty)
            TargetStatus(q, role, "out-of-scope", None, None, Some(row.module))
          else built.excluded.find(_._2.prettyQname == q) match {
            case Some((reason, _)) => TargetStatus(q, role, "excluded", None, None, Some(reason))
            case None =>
              if (row.defKind != "function") TargetStatus(q, role, "non-function", None, None, Some(row.defKind))
              else {
                val i = built.ranked.indexWhere(_.prettyQname == q)
                if (i < 0) TargetStatus(q, role, "not-in-pool", None, None, Some("no query returned it (truncation?)"))
                else TargetStatus(q, role, "ranked", Some(i + 1), Some(score(row)), None)
              }
          }
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
      t1       <- IO.monotonic
      _        <- IO.println(s">> recall instrument: ${entries.size} obligation(s), corpus ${corpus.rows.size} rows (${badRows} unparsable, ${defs.size} definition bodies) in ${(t1 - t0).toMillis} ms; scorers ${cfg.scorers.map(_.name).mkString(",")}; exclusion ${if (cfg.excludeTarget) "on" else "off"}")
      sources  <- entries.traverse(e => IO.blocking(new String(Files.readAllBytes(cfg.projectRoot.resolve(e.obligationPath)), StandardCharsets.UTF_8)).map(e.id -> _)).map(_.toMap)
      perScorer <- cfg.scorers.traverse { spec =>
                     val sc = spec.instantiate(defs)
                     entries.traverse(e => evaluate(cfg, corpus, sc, e, goals(e.id), sources(e.id))).map(sc -> _)
                   }
      t2       <- IO.monotonic
      json      = reportJson(cfg, corpus.rows.size, badRows, perScorer, skippedNoGT, skippedNoGoal, (t2 - t1).toMillis)
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

  private def reportJson(cfg: RecallConfig, rows: Int, badRows: Int,
                         perScorer: Vector[(CandidateScorer, Vector[FixtureRecall])],
                         skippedNoGT: Vector[String], skippedNoGoal: Vector[String], wallMs: Long): Json =
    Json.obj(
      "schemaVersion" -> "proof-search-recall.v0".asJson,
      "timestamp"     -> java.time.Instant.now().toString.asJson,
      "config" -> Json.obj(
        "index"         -> cfg.index.toString.asJson,
        "corpus"        -> cfg.corpus.toString.asJson,
        "corpusRows"    -> rows.asJson,
        "corpusUnparsable" -> badRows.asJson,
        "report"        -> cfg.report.toString.asJson,
        "scorers"       -> cfg.scorers.map(_.name).asJson,
        "excludeTarget" -> cfg.excludeTarget.asJson,
        "k"             -> cfg.ks.asJson,
        "queryLimit"    -> cfg.queryLimit.asJson,
        "wallMs"        -> wallMs.asJson
      ),
      "skipped" -> Json.obj(
        "noGroundTruth"  -> skippedNoGT.asJson,
        "noRecordedGoal" -> skippedNoGoal.asJson
      ),
      "scorers" -> Json.arr(perScorer.map { case (sc, fs) =>
        Json.obj(
          "name"      -> sc.name.asJson,
          "summary"   -> summaries(fs, cfg.ks),
          "contextReconstructionMismatches" -> fs.filter(_.reconstructionMatches.contains(false)).map(_.benchmarkId).asJson,
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
        def one(t: TargetStatus) = t.status match {
          case "ranked" => s"${t.qname} #${t.rank.getOrElse(0)}"
          case other    => s"${t.qname} ${other}${t.detail.fold("")(d => s"($d)")}"
        }
        val mism = if (f.reconstructionMatches.contains(false)) " CONTEXT-MISMATCH" else ""
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
