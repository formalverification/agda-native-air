/** ============================================================================
  *  SingleStepHarness.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/search/SingleStepHarness.scala
  *  Package: struxdriver.search
  *
  *  Purpose
  *  -------
  *  The P0 single-step harness of issue #113 (sub-issue #119): given M1-5
  *  benchmark obligations, propose k candidates from the fixed stub action
  *  space, probe each against agda-mcp, report which close each obligation,
  *  and measure the oracle-time vs proposal-time split that settles the
  *  host-language fork.
  *
  *  Flow, per fixture and pass
  *  --------------------------
  *    1. Copy the obligation file to a per-pass working directory (a crash can
  *       never dirty a committed fixture; agda-mcp restores its own edits).
  *    2. check_file — the baseline: exactly one open obligation expected.
  *    3. get_goal at that obligation — what a real proposer would see.
  *    4. Propose (stub, timed) and probe every candidate (fill_hole, timed,
  *       memoised per pass).
  *    5. Rank outcomes (Rank.order), commit the best Ok candidate to the
  *       working copy, and — only if no obligation remains — claim solved via
  *       the final batch check (SolvedClaim).
  *
  *  Passes: `--passes 2` runs the whole sweep twice against ONE server
  *  process; the second pass reads warm `.agdai` interfaces, and the report
  *  keeps the passes separate so the split is quoted from the warm one.  The
  *  probe memo is deliberately per-pass: sharing it across passes would turn
  *  every warm-pass probe into a cache hit and measure nothing.
  *
  *  Output, under --out-dir/--run-id
  *  --------------------------------
  *    results.jsonl — one row per probed candidate in the existing
  *      eval-proof-completion.v0 attempt shape, so these sit beside the
  *      policy-backend baseline (status is fill_hole's own vocabulary; rc is
  *      the verdict exit code; logPath names the raw reply capture).
  *    timing.jsonl  — the proof-search-timing.v0 ledger (Oracle.scala).
  *    report.json   — aggregates: the split per pass and per difficulty tier,
  *      and per-fixture outcomes.
  *    work/, logs/  — working copies and raw replies.
  *
  *  Invocation (see the proof-search-* Make targets)
  *  ------------------------------------------------
  *    sbt "runMain struxdriver.search.SingleStepHarness
  *          --index data/benchmarks/benchmark-index.jsonl
  *          --ids stdlib-nat-plus-identity-l | --all
  *          --out-dir data/benchmarks/reports/proof-search
  *          --run-id r1 --passes 1
  *          --server-bin /path/to/agda-mcp --project-root /path/to/repo"
  *
  *  ============================================================================
  */
package struxdriver.search

import cats.effect.{ExitCode, IO, IOApp}
import cats.syntax.all._
import io.circe.Json
import io.circe.syntax._
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths, StandardCopyOption}
import scala.jdk.CollectionConverters._

import struxdriver.benchmark.{Obligation => IndexEntry}

/** Harness configuration, parsed from argv. */
final case class HarnessConfig(
  index:         Path,
  ids:           Option[Set[String]], // None = --all
  outDir:        Path,
  runId:         String,
  serverBin:     Path,
  agdaFlags:     String,
  serverTimeout: Int,
  projectRoot:   Path,
  passes:        Int
) {
  def runRoot: Path = outDir.resolve(runId)
}

/** One results.jsonl row: the eval-proof-completion.v0 attempt shape, so the
  * harness's judgements land in the same format the policy-backend evaluator
  * writes (issue #113's "no private format" acceptance).
  */
final case class AttemptRow(
  fixtureId:     String,
  module:        String,
  fixturePath:   String,
  holeIndex:     Int,
  holeLine:      Int,
  holeCol:       Int,
  candidateRank: Int,
  candidate:     String,
  status:        String,
  elapsedMs:     Long,
  rc:            Int,
  logPath:       String
) {
  def toJson: Json = Json.obj(
    "fixtureId"     -> fixtureId.asJson,
    "module"        -> module.asJson,
    "fixturePath"   -> fixturePath.asJson,
    "holeIndex"     -> holeIndex.asJson,
    "holeLine"      -> holeLine.asJson,
    "holeCol"       -> holeCol.asJson,
    "candidateRank" -> candidateRank.asJson,
    "candidate"     -> candidate.asJson,
    "status"        -> status.asJson,
    "elapsedMs"     -> elapsedMs.asJson,
    "rc"            -> rc.asJson,
    "logPath"       -> logPath.asJson,
    "schemaVersion" -> "eval-proof-completion.v0".asJson
  )
}

/** What one fixture's single step concluded, for the report. */
final case class FixtureOutcome(
  fixtureId:      String,
  difficulty:     String,
  goal:           String,
  module:         String,
  closers:        Vector[String],
  bestCandidate:  Option[String],
  bestStatus:     Option[String],
  committed:      Boolean,
  obligationsAfterCommit: Option[Int],
  solved:         Boolean,
  anomaly:        Option[String]
) {
  def toJson: Json = Json.obj(
    "fixtureId"     -> fixtureId.asJson,
    "difficulty"    -> difficulty.asJson,
    "goal"          -> goal.asJson,
    "module"        -> module.asJson,
    "closers"       -> closers.asJson,
    "bestCandidate" -> bestCandidate.asJson,
    "bestStatus"    -> bestStatus.asJson,
    "committed"     -> committed.asJson,
    "obligationsAfterCommit" -> obligationsAfterCommit.asJson,
    "solved"        -> solved.asJson,
    "anomaly"       -> anomaly.asJson
  ).dropNullValues
}

object SingleStepHarness extends IOApp {

  private val usage: String =
    """usage: runMain struxdriver.search.SingleStepHarness
      |    --index PATH           benchmark-index.jsonl
      |    (--ids id1,id2 | --all)
      |    --out-dir PATH         run roots land here
      |    --server-bin PATH      the agda-mcp binary
      |    --project-root PATH    repo root: server cwd; index paths resolve here
      |    [--run-id STR]         default: epoch millis
      |    [--agda-flags STR]     default: the committed .mcp.json flag set
      |    [--server-timeout N]   per-Agda-call bound, seconds (default 600)
      |    [--passes N]           sweep repetitions against one server (default 1)
      |""".stripMargin

  private val defaultAgdaFlags =
    "-i agda-dojang/agda --library-file=agda/libraries -l agda-dojang -l standard-library"

  def run(args: List[String]): IO[ExitCode] =
    parseArgs(args) match {
      case Left(err)  => IO.println(s"error: $err\n\n$usage").as(ExitCode.Error)
      case Right(cfg) => runHarness(cfg).as(ExitCode.Success)
    }

  // --------------------------------------------------------------------------
  // Argument parsing (the EvalBenchmark list-recursion style)
  // --------------------------------------------------------------------------

  private def parseArgs(args: List[String]): Either[String, HarnessConfig] = {
    @annotation.tailrec
    def go(rest: List[String], m: Map[String, String]): Either[String, Map[String, String]] =
      rest match {
        case Nil                              => Right(m)
        case "--all" :: xs                    => go(xs, m + ("all" -> "true"))
        case flag :: v :: xs if flag.startsWith("--") => go(xs, m + (flag.drop(2) -> v))
        case other :: _                       => Left(s"unrecognized argument: $other")
      }
    for {
      m    <- go(args, Map.empty)
      ix   <- m.get("index").toRight("missing --index")
      out  <- m.get("out-dir").toRight("missing --out-dir")
      bin  <- m.get("server-bin").toRight("missing --server-bin")
      root <- m.get("project-root").toRight("missing --project-root")
      ids   = m.get("ids").map(_.split(",").map(_.trim).filter(_.nonEmpty).toSet)
      _    <- if (ids.isEmpty && !m.contains("all")) Left("pass --ids or --all") else Right(())
      passes <- m.get("passes").fold[Either[String, Int]](Right(1))(s =>
                  s.toIntOption.filter(_ >= 1).toRight(s"bad --passes: $s"))
      tmo    <- m.get("server-timeout").fold[Either[String, Int]](Right(600))(s =>
                  s.toIntOption.filter(_ >= 1).toRight(s"bad --server-timeout: $s"))
    } yield HarnessConfig(
      index         = Paths.get(ix),
      ids           = ids,
      outDir        = Paths.get(out),
      runId         = m.getOrElse("run-id", s"run-${System.currentTimeMillis()}"),
      serverBin     = Paths.get(bin),
      agdaFlags     = m.getOrElse("agda-flags", defaultAgdaFlags),
      serverTimeout = tmo,
      projectRoot   = Paths.get(root).toAbsolutePath.normalize,
      passes        = passes
    )
  }

  // --------------------------------------------------------------------------
  // The run
  // --------------------------------------------------------------------------

  private def runHarness(cfg: HarnessConfig): IO[Unit] = {
    val serverCfg = ServerConfig(
      bin        = cfg.serverBin,
      agdaFlags  = cfg.agdaFlags,
      timeoutSec = cfg.serverTimeout,
      cwd        = cfg.projectRoot,
      stderrLog  = cfg.runRoot.resolve("server-stderr.log")
    )
    for {
      entries <- readIndex(cfg)
      _       <- IO.raiseWhen(entries.isEmpty)(new RuntimeException("no obligations matched"))
      _       <- IO.blocking(Files.createDirectories(cfg.runRoot))
      _       <- IO.println(s">> proof-search single-step: ${entries.size} obligation(s), k=${Actions.stubActionSpace.size}, passes=${cfg.passes}")
      _       <- IO.println(s">> run root: ${cfg.runRoot}")
      result  <- McpClient.resource(serverCfg).use { client =>
                   (1 to cfg.passes).toVector.flatTraverse { pass =>
                     for {
                       oracle   <- Oracle.create(client) // fresh memo per pass: a shared one would cache away the warm measurement
                       outcomes <- entries.traverse(e => runFixture(cfg, oracle, pass, e))
                       ledger   <- oracle.timings.get
                     } yield Vector((pass, outcomes, ledger))
                   }
                 }
      _       <- writeOutputs(cfg, entries, result)
    } yield ()
  }

  private def readIndex(cfg: HarnessConfig): IO[Vector[IndexEntry]] =
    IO.blocking(Files.readAllLines(cfg.index, StandardCharsets.UTF_8).asScala.toVector)
      .flatMap(_.filter(_.trim.nonEmpty).traverse(l =>
        IO.fromEither(io.circe.parser.decode[IndexEntry](l).leftMap(e =>
          new RuntimeException(s"bad index row: ${e.getMessage}")))))
      .map(all => cfg.ids.fold(all)(want => all.filter(e => want(e.id))))

  /** Drive one fixture through one pass; anomalies (a fixture that does not
    * present exactly one obligation, or whose goal cannot be read) are
    * reported, not thrown, so one bad fixture cannot abort a sweep.
    */
  private def runFixture(cfg: HarnessConfig, oracle: Oracle, pass: Int, entry: IndexEntry): IO[(FixtureOutcome, Vector[AttemptRow])] = {
    val fixtureId = entry.id
    val workDir   = cfg.runRoot.resolve(s"work/pass-$pass/$fixtureId")
    val logsDir   = cfg.runRoot.resolve(s"logs/pass-$pass/$fixtureId")
    val source    = cfg.projectRoot.resolve(entry.obligationPath)
    val workFile  = workDir.resolve(source.getFileName)

    def anomaly(msg: String): (FixtureOutcome, Vector[AttemptRow]) =
      (FixtureOutcome(fixtureId, entry.difficulty.tag, entry.typeSig, "", Vector.empty,
        None, None, committed = false, None, solved = false, Some(msg)), Vector.empty)

    val step: IO[(FixtureOutcome, Vector[AttemptRow])] = for {
      _       <- IO.blocking { Files.createDirectories(workDir); Files.createDirectories(logsDir) }
      _       <- IO.blocking(Files.copy(source, workFile, StandardCopyOption.REPLACE_EXISTING))
      content <- IO.blocking(new String(Files.readAllBytes(workFile), StandardCharsets.UTF_8))
      check   <- oracle.checkFile(CallCtx(pass, fixtureId, "check_file", None), workFile)
      result  <- check.body.holes match {
                   case Vector(h) =>
                     val ob    = WireHole.toObligation(h)
                     val state = SearchState.initial(content, Vector(ob))
                     probeAndCommit(cfg, oracle, pass, entry, workFile, logsDir, state, ob)
                   case hs =>
                     IO.pure(anomaly(s"expected exactly 1 hole, check_file reported ${hs.size}"))
                 }
      _       <- IO.println(f">> [pass $pass] $fixtureId%-34s ${result._1.bestStatus.getOrElse("-")}%-11s closers=${result._1.closers.size} solved=${result._1.solved}")
    } yield result

    step.handleErrorWith(e => IO.println(s">> [pass $pass] $fixtureId FAILED: ${e.getMessage}").as(anomaly(e.getMessage)))
  }

  private def probeAndCommit(
    cfg: HarnessConfig, oracle: Oracle, pass: Int, entry: IndexEntry,
    workFile: Path, logsDir: Path, state: SearchState, ob: Obligation
  ): IO[(FixtureOutcome, Vector[AttemptRow])] =
    for {
      goal   <- oracle.getGoal(CallCtx(pass, entry.id, "get_goal", None), workFile, ob)
      // The stub is cheap by design; timing it anyway establishes the ledger
      // slot the retrieval/policy proposers of P2/P3 will fill.
      t0     <- IO.monotonic
      cands   = Actions.stubActionSpace
      t1     <- IO.monotonic
      _      <- oracle.recordProposal(CallCtx(pass, entry.id, "proposal", None), (t1 - t0).toNanos)
      fp      = Fingerprint.of(state.content)
      probed <- cands.zipWithIndex.traverse { case (cand, i) =>
                  oracle.probe(CallCtx(pass, entry.id, "fill_hole", Some(i)), workFile, fp, ob, cand)
                    .flatMap { ans =>
                      val logPath = logsDir.resolve(s"cand-$i.json")
                      IO.blocking(Files.write(logPath, (ans.raw + "\n").getBytes(StandardCharsets.UTF_8)))
                        .as((i, cand, ans))
                    }
                }
      rows    = probed.map { case (i, cand, ans) =>
                  AttemptRow(
                    fixtureId     = entry.id,
                    module        = goal.body.module.getOrElse(""),
                    fixturePath   = entry.obligationPath.toString,
                    holeIndex     = 0,
                    holeLine      = ob.line,
                    holeCol       = ob.col,
                    candidateRank = i,
                    candidate     = cand,
                    status        = ans.body.status.wire,
                    elapsedMs     = extractElapsed(ans.raw),
                    rc            = oracle.exitCodeOf(ans.raw).getOrElse(-1),
                    logPath       = cfg.runRoot.relativize(logsDir.resolve(s"cand-$i.json")).toString
                  )
                }
      ranked  = Rank.order(probed.map(_._3.body))
      best    = ranked.headOption
      // Commit the best Ok candidate: the one place a probe becomes a Move.
      committed <- best.filter(_.status == ProbeStatus.Ok) match {
                     case None    => IO.pure(Option.empty[SearchState])
                     case Some(b) =>
                       IO.fromEither(state.commit(ob, b).leftMap(new RuntimeException(_)))
                         .flatTap(s2 => IO.blocking(Files.write(workFile, s2.content.getBytes(StandardCharsets.UTF_8))))
                         .map(Option(_))
                   }
      solved  <- committed match {
                   case Some(s2) if s2.allDischarged =>
                     oracle.checkFile(CallCtx(pass, entry.id, "final_check", None), workFile).map { fin =>
                       SolvedClaim.fromFinalCheck(s2, fin.body.success, fin.body.exitCode.getOrElse(-1)).isRight
                     }
                   case _ => IO.pure(false)
                 }
    } yield (
      FixtureOutcome(
        fixtureId     = entry.id,
        difficulty    = entry.difficulty.tag,
        goal          = goal.body.goal,
        module        = goal.body.module.getOrElse(""),
        closers       = probed.collect { case (_, cand, ans) if ans.body.closesAll => cand },
        bestCandidate = best.map(_.candidate),
        bestStatus    = best.map(_.status.wire),
        committed     = committed.isDefined,
        obligationsAfterCommit = committed.map(_.obligations.size),
        solved        = solved,
        anomaly       = None
      ),
      rows
    )

  private def extractElapsed(raw: String): Long =
    io.circe.parser.parse(raw).toOption
      .flatMap(_.hcursor.get[Long]("elapsedMs").toOption)
      .getOrElse(0L)

  // --------------------------------------------------------------------------
  // Outputs
  // --------------------------------------------------------------------------

  private def writeOutputs(
    cfg: HarnessConfig,
    entries: Vector[IndexEntry],
    result: Vector[(Int, Vector[(FixtureOutcome, Vector[AttemptRow])], Vector[TimingRow])]
  ): IO[Unit] = {
    val tierOf   = entries.map(e => e.id -> e.difficulty.tag).toMap
    val ledger   = result.flatMap(_._3)
    val lastPass = result.map(_._1).max
    // results.jsonl carries the LAST pass only: the eval attempt shape has no
    // pass field, and two passes of the same rows would read as double
    // attempts to a schema consumer.  timing.jsonl keeps every pass.
    val attempts = result.filter(_._1 == lastPass).flatMap(_._2.flatMap(_._2))

    def writeJsonl(path: Path, rows: Vector[Json]): IO[Unit] =
      IO.blocking {
        Files.write(path, rows.map(_.noSpaces).mkString("", "\n", "\n").getBytes(StandardCharsets.UTF_8)); ()
      }

    val oraclePhases = Set("check_file", "get_goal", "fill_hole", "final_check")

    def aggregate(rows: Vector[TimingRow]): Json = {
      val oracle   = rows.filter(r => oraclePhases(r.phase) && !r.cached)
      val proposal = rows.filter(_.phase == "proposal")
      val hits     = rows.count(_.cached)
      val clientMs = oracle.map(_.clientMs).sum
      val serverMs = oracle.flatMap(_.serverElapsedMs).sum
      val overhead = oracle.flatMap(_.overheadMs).sum
      val propMs   = proposal.map(_.clientMs).sum
      val byPhase  = oraclePhases.toVector.sorted.map { ph =>
        val sel = oracle.filter(_.phase == ph)
        ph -> Json.obj(
          "calls"           -> sel.size.asJson,
          "clientMs"        -> round3(sel.map(_.clientMs).sum).asJson,
          "serverElapsedMs" -> sel.flatMap(_.serverElapsedMs).sum.asJson
        )
      }
      Json.obj(
        "oracle" -> Json.obj(
          "calls"            -> oracle.size.asJson,
          "cacheHits"        -> hits.asJson,
          "clientMs"         -> round3(clientMs).asJson,
          "serverElapsedMs"  -> serverMs.asJson,
          "overheadMs"       -> round3(overhead).asJson,
          "overheadPctOfOracle" -> pct(overhead, clientMs).asJson,
          "byPhase"          -> Json.obj(byPhase: _*)
        ),
        "proposal" -> Json.obj(
          "calls"    -> proposal.size.asJson,
          "clientMs" -> round3(propMs).asJson
        ),
        "oraclePctOfTotal"   -> pct(clientMs, clientMs + propMs).asJson,
        "proposalPctOfTotal" -> pct(propMs, clientMs + propMs).asJson
      )
    }

    val perPass = result.map { case (pass, _, _) =>
      Json.obj("pass" -> pass.asJson, "split" -> aggregate(ledger.filter(_.pass == pass)))
    }

    val warmRows = ledger.filter(_.pass == lastPass)
    val perTier = warmRows.groupBy(r => tierOf.getOrElse(r.fixtureId, "?")).toVector.sortBy(_._1).map {
      case (tier, rows) => tier -> aggregate(rows)
    }

    val outcomes = result.filter(_._1 == lastPass).flatMap(_._2.map(_._1))

    val report = Json.obj(
      "schemaVersion" -> "proof-search-report.v0".asJson,
      "runId"         -> cfg.runId.asJson,
      "k"             -> Actions.stubActionSpace.size.asJson,
      "actionSpace"   -> Actions.stubActionSpace.asJson,
      "passes"        -> cfg.passes.asJson,
      "obligations"   -> entries.size.asJson,
      "timestamp"     -> java.time.Instant.now().toString.asJson,
      "perPass"       -> Json.arr(perPass: _*),
      "perTierWarm"   -> Json.obj(perTier: _*),
      "outcomes"      -> Json.arr(outcomes.map(_.toJson): _*)
    )

    for {
      _ <- writeJsonl(cfg.runRoot.resolve("results.jsonl"), attempts.map(_.toJson))
      _ <- writeJsonl(cfg.runRoot.resolve("timing.jsonl"), ledger.map(_.asJson))
      _ <- IO.blocking(Files.write(cfg.runRoot.resolve("report.json"),
             report.spaces2.getBytes(StandardCharsets.UTF_8)))
      _ <- IO.println(summarize(lastPass, ledger, outcomes))
      _ <- IO.println(s">> wrote ${cfg.runRoot.resolve("report.json")}")
    } yield ()
  }

  private def summarize(lastPass: Int, ledger: Vector[TimingRow], outcomes: Vector[FixtureOutcome]): String = {
    val oraclePhases = Set("check_file", "get_goal", "fill_hole", "final_check")
    val warm     = ledger.filter(_.pass == lastPass)
    val oracle   = warm.filter(r => oraclePhases(r.phase) && !r.cached)
    val proposal = warm.filter(_.phase == "proposal")
    val clientMs = oracle.map(_.clientMs).sum
    val serverMs = oracle.flatMap(_.serverElapsedMs).sum.toDouble
    val overhead = oracle.flatMap(_.overheadMs).sum
    val propMs   = proposal.map(_.clientMs).sum
    val solved   = outcomes.count(_.solved)
    val withCloser = outcomes.count(_.closers.nonEmpty)
    f"""
       |== oracle vs proposal split (pass $lastPass${if (lastPass > 1) ", warm" else ""}) ==
       |oracle:   ${oracle.size}%4d calls  ${clientMs}%12.1f ms client-observed
       |          agda subprocess (serverElapsedMs): ${serverMs}%12.1f ms  (${pct(serverMs, clientMs)}%% of oracle)
       |          transport + server handling:       ${overhead}%12.1f ms  (${pct(overhead, clientMs)}%% of oracle)
       |proposal: ${proposal.size}%4d calls  ${propMs}%12.3f ms
       |split:    oracle ${pct(clientMs, clientMs + propMs)}%% / proposal ${pct(propMs, clientMs + propMs)}%%
       |outcomes: ${outcomes.size} obligations, $withCloser with a closer among k=${Actions.stubActionSpace.size}, $solved solved end-to-end
       |""".stripMargin
  }

  private def round3(d: Double): BigDecimal = BigDecimal(d).setScale(3, BigDecimal.RoundingMode.HALF_UP)
  private def pct(part: Double, whole: Double): BigDecimal =
    if (whole <= 0) BigDecimal(0) else BigDecimal(part / whole * 100).setScale(2, BigDecimal.RoundingMode.HALF_UP)
}
