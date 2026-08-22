/** ============================================================================
  *  LoopHarness.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/search/LoopHarness.scala
  *  Package: struxdriver.search
  *
  *  Purpose
  *  -------
  *  The P1 entry point of issue #113 (sub-issue #122): drive the M1-5
  *  benchmark through the beam loop (BeamLoop.scala) with the fixed action
  *  space (Propose.scala), one fixture at a time against one agda-mcp server,
  *  and report on the shared eval schema — the per-tier solve counts that are
  *  the phase's headline number.
  *
  *  Flow, per fixture
  *  -----------------
  *    1. Stage (Scaffold.stage): work copy, baseline check_file, the
  *       exactly-one-hole gate.
  *    2. Build the fixed proposer from the fixture's own source (its `using`
  *       imports) with binder counts from lane type_of, and run the beam
  *       loop under the configured beam width, depth bound, probe budget,
  *       dedup policy, and peek flag.
  *    3. Every probe becomes one results.jsonl attempt row (schema
  *       eval-proof-completion.v0: fixtureId is the module STEM, benchmarkId
  *       the additive join key, elapsedMs the client-observed wall clock,
  *       candidateRank the 1-based rank in that expansion's proposal list —
  *       peek-rejected candidates were never judged, so they have no row) and
  *       one raw-reply log file.
  *    4. The fixture lands one fixtures.jsonl row (same schema version:
  *       holesTotal is 1 per benchmark obligation; holesSolved counts the
  *       committed moves of the winning script, the fills-performed reading
  *       eval_fixtures.py implements; fullySolved iff the final strict gate
  *       passed; solvedPath names the artifact under the run's solved/
  *       directory) plus a report outcome with the search status
  *       (solved / exhausted / budget_exceeded) and the loop counters.
  *
  *  Exit code: P0's discipline unchanged — anomalies never abort the sweep
  *  and never stop artifact writing, but any anomaly (or any fixture whose
  *  search raised) makes the run exit non-zero.
  *
  *  Output, under --out-dir/--run-id
  *  --------------------------------
  *    results.jsonl  — per-probe attempt rows (eval-proof-completion.v0).
  *    fixtures.jsonl — per-fixture summary rows (eval-proof-completion.v0).
  *    timing.jsonl   — the proof-search-timing.v0 ledger, with the new
  *                     type_of and peek phases beside P0's.
  *    report.json    — config, per-tier solve counts, per-fixture outcomes,
  *                     and the oracle split (batch vs knowledge vs proposal).
  *    work/, logs/, solved/ — working copies, raw replies, solved artifacts.
  *
  *  Invocation (see the proof-search-loop Make target)
  *  ---------------------------------------------------
  *    sbt "runMain struxdriver.search.ProofSearchLoop
  *          --index data/benchmarks/benchmark-index.jsonl --all
  *          --out-dir data/benchmarks/reports/proof-search --run-id beam1
  *          --server-bin /path/to/agda-mcp --project-root /path/to/repo
  *          [--beam 4] [--max-depth 6] [--probe-budget 60]
  *          [--dedup script|content] [--peek on|off]"
  *
  *  ============================================================================
  */
package struxdriver.search

import cats.effect.{ExitCode, IO, IOApp, Ref}
import cats.syntax.all._
import io.circe.Json
import io.circe.syntax._
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths}

import struxdriver.benchmark.{Obligation => IndexEntry}

/** Loop-harness configuration, parsed from argv. */
final case class LoopHarnessConfig(
  index:         Path,
  ids:           Option[Set[String]], // None = --all
  outDir:        Path,
  runId:         String,
  serverBin:     Path,
  agdaFlags:     String,
  serverTimeout: Int,
  projectRoot:   Path,
  loop:          LoopConfig
) {
  def runRoot: Path = outDir.resolve(runId)
}

/** One fixtures.jsonl row: the eval-proof-completion.v0 per-fixture summary
  * (agda-dojang/README.md "Result schema (v0)"), plus the additive fields P1
  * adds — `benchmarkId` (the join key, P0's precedent) and `searchStatus`
  * (the loop's distinct termination status; `anomaly` for a fixture whose
  * drive failed).
  */
final case class FixtureRow(
  fixtureId:    String,
  module:       String,
  fixturePath:  String,
  holesTotal:   Int,
  holesSolved:  Int,
  fullySolved:  Boolean,
  finalStatus:  String,
  elapsedMs:    Long,
  solvedPath:   Option[String],
  benchmarkId:  String,
  searchStatus: String
) {
  def toJson: Json = Json.obj(
    "schemaVersion" -> "eval-proof-completion.v0".asJson,
    "fixtureId"     -> fixtureId.asJson,
    "module"        -> module.asJson,
    "fixturePath"   -> fixturePath.asJson,
    "holesTotal"    -> holesTotal.asJson,
    "holesSolved"   -> holesSolved.asJson,
    "fullySolved"   -> fullySolved.asJson,
    "finalStatus"   -> finalStatus.asJson,
    "elapsedMs"     -> elapsedMs.asJson,
    "solvedPath"    -> solvedPath.fold(Json.Null)(_.asJson),
    "benchmarkId"   -> benchmarkId.asJson,
    "searchStatus"  -> searchStatus.asJson
  )
}

/** What one fixture's search concluded, for report.json. */
final case class LoopOutcome(
  benchmarkId:  String,
  difficulty:   String,
  goal:         String,
  module:       String,
  searchStatus: String,
  solved:       Boolean,
  script:       Vector[String],
  stats:        LoopStats,
  wallMs:       Long,
  anomaly:      Option[String]
) {
  def toJson: Json = Json.obj(
    "benchmarkId"  -> benchmarkId.asJson,
    "difficulty"   -> difficulty.asJson,
    "goal"         -> goal.asJson,
    "module"       -> module.asJson,
    "searchStatus" -> searchStatus.asJson,
    "solved"       -> solved.asJson,
    "script"       -> script.asJson,
    "expansions"   -> stats.expansions.asJson,
    "probes"       -> stats.probes.asJson,
    "memoHits"     -> stats.memoHits.asJson,
    "peeks"        -> stats.peeks.asJson,
    "peekRejects"  -> stats.peekRejects.asJson,
    "dedupSkips"   -> stats.dedupSkips.asJson,
    "finalChecks"  -> stats.finalChecks.asJson,
    "depthReached" -> stats.depthReached.asJson,
    "depthCapped"  -> stats.depthCapped.asJson,
    "wallMs"       -> wallMs.asJson,
    "anomaly"      -> anomaly.asJson
  ).dropNullValues
}

object ProofSearchLoop extends IOApp {

  private val usage: String =
    """usage: runMain struxdriver.search.ProofSearchLoop
      |    --index PATH           benchmark-index.jsonl
      |    (--ids id1,id2 | --all)
      |    --out-dir PATH         run roots land here
      |    --server-bin PATH      the agda-mcp binary
      |    --project-root PATH    repo root: server cwd; index paths resolve here
      |    [--run-id STR]         default: epoch millis
      |    [--agda-flags STR]     default: the committed .mcp.json flag set
      |    [--server-timeout N]   per-Agda-call bound, seconds (default 600)
      |    [--beam N]             beam width (default 4)
      |    [--max-depth N]        depth bound: max committed moves (default 6)
      |    [--probe-budget N]     per-fixture budget of memo-missing fill_hole probes (default 60)
      |    [--dedup script|content]  frontier dedup policy (default script)
      |    [--peek on|off]        type_of pre-filter before each probe (default off)
      |""".stripMargin

  def run(args: List[String]): IO[ExitCode] =
    parseArgs(args) match {
      case Left(err)  => IO.println(s"error: $err\n\n$usage").as(ExitCode.Error)
      case Right(cfg) => runHarness(cfg).as(ExitCode.Success)
    }

  // --------------------------------------------------------------------------
  // Argument parsing (the EvalBenchmark list-recursion style)
  // --------------------------------------------------------------------------

  private def parseArgs(args: List[String]): Either[String, LoopHarnessConfig] = {
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
      m      <- go(args, Map.empty)
      ix     <- m.get("index").toRight("missing --index")
      out    <- m.get("out-dir").toRight("missing --out-dir")
      bin    <- m.get("server-bin").toRight("missing --server-bin")
      root   <- m.get("project-root").toRight("missing --project-root")
      ids     = m.get("ids").map(_.split(",").map(_.trim).filter(_.nonEmpty).toSet)
      _      <- if (ids.isEmpty && !m.contains("all")) Left("pass --ids or --all") else Right(())
      tmo    <- intOf(m, "server-timeout", 600, 1)
      beam   <- intOf(m, "beam", LoopConfig.default.beamWidth, 1)
      depth  <- intOf(m, "max-depth", LoopConfig.default.maxDepth, 1)
      budget <- intOf(m, "probe-budget", LoopConfig.default.probeBudget, 1)
      dedup  <- m.get("dedup").fold[Either[String, DedupPolicy]](Right(LoopConfig.default.dedup))(DedupPolicy.parse)
      peek   <- m.get("peek").fold[Either[String, Boolean]](Right(LoopConfig.default.peek)) {
                  case "on"  => Right(true)
                  case "off" => Right(false)
                  case other => Left(s"bad --peek: $other (on|off)")
                }
    } yield LoopHarnessConfig(
      index         = Paths.get(ix),
      ids           = ids,
      outDir        = Paths.get(out),
      runId         = m.getOrElse("run-id", s"run-${System.currentTimeMillis()}"),
      serverBin     = Paths.get(bin),
      agdaFlags     = m.getOrElse("agda-flags", Scaffold.defaultAgdaFlags),
      serverTimeout = tmo,
      projectRoot   = Paths.get(root).toAbsolutePath.normalize,
      loop          = LoopConfig(beam, depth, budget, dedup, peek)
    )
  }

  // --------------------------------------------------------------------------
  // The run
  // --------------------------------------------------------------------------

  private def runHarness(cfg: LoopHarnessConfig): IO[Unit] = {
    val serverCfg = ServerConfig(
      bin        = cfg.serverBin,
      agdaFlags  = cfg.agdaFlags,
      timeoutSec = cfg.serverTimeout,
      cwd        = cfg.projectRoot,
      stderrLog  = cfg.runRoot.resolve("server-stderr.log")
    )
    for {
      entries <- Scaffold.readIndex(cfg.index, cfg.ids)
      _       <- IO.raiseWhen(entries.isEmpty)(new RuntimeException("no obligations matched"))
      _       <- IO.blocking(Files.createDirectories(cfg.runRoot))
      _       <- IO.println(s">> proof-search loop: ${entries.size} obligation(s), beam=${cfg.loop.beamWidth} depth=${cfg.loop.maxDepth} budget=${cfg.loop.probeBudget} dedup=${cfg.loop.dedup.tag} peek=${if (cfg.loop.peek) "on" else "off"}")
      _       <- IO.println(s">> run root: ${cfg.runRoot}")
      result  <- McpClient.resource(serverCfg).use { client =>
                   for {
                     oracle <- Oracle.create(client)
                     driven <- entries.traverse(e => runFixture(cfg, oracle, e))
                     ledger <- oracle.timings.get
                   } yield (driven, ledger)
                 }
      (driven, ledger) = result
      _       <- writeOutputs(cfg, entries, driven, ledger)
      anomalies = driven.collect { case (o, _, _) if o.anomaly.isDefined => o }
      _       <- anomalies.traverse_(o =>
                   IO.println(s"!! ${o.benchmarkId} anomaly: ${o.anomaly.getOrElse("")}"))
      _       <- IO.raiseWhen(anomalies.nonEmpty)(new RuntimeException(
                   s"${anomalies.size} fixture(s) ended in an anomaly; outputs are written but the run is not clean"))
    } yield ()
  }

  /** Drive one fixture through the loop.  Any raise inside the search —
    * oracle failure, wire drift, a commit refusal, a final-check
    * disagreement — is caught here and reported as this fixture's anomaly,
    * so one broken fixture cannot abort the sweep.
    */
  private def runFixture(
    cfg:    LoopHarnessConfig,
    oracle: Oracle,
    entry:  IndexEntry
  ): IO[(LoopOutcome, FixtureRow, Vector[AttemptRow])] = {
    val workDir  = cfg.runRoot.resolve(s"work/${entry.id}")
    val logsDir  = cfg.runRoot.resolve(s"logs/${entry.id}")
    val source   = cfg.projectRoot.resolve(entry.obligationPath)
    val absPath  = source.toString
    val stem     = Scaffold.fixtureStem(entry)
    def mkCtx(phase: String, rank: Option[Int]) = CallCtx(1, entry.id, phase, rank)

    def fixtureRow(module: String, result: Option[FixtureSearchResult], solvedPath: Option[String], wallMs: Long, anomalous: Boolean): FixtureRow =
      FixtureRow(
        fixtureId    = stem,
        module       = module,
        fixturePath  = absPath,
        holesTotal   = 1,
        holesSolved  = result.flatMap(_.solved).map(_.state.script.size).getOrElse(0),
        fullySolved  = result.exists(_.solved.isDefined),
        finalStatus  = if (result.exists(_.solved.isDefined)) "ok"
                       else if (anomalous) "crash" else "unsolved",
        elapsedMs    = wallMs,
        solvedPath   = solvedPath,
        benchmarkId  = entry.id,
        searchStatus = result.map(_.status.tag).getOrElse("anomaly")
      )

    val step: IO[(LoopOutcome, FixtureRow, Vector[AttemptRow])] = for {
      t0     <- IO.monotonic
      staged <- Scaffold.stage(source, workDir, logsDir, oracle, mkCtx("check_file", None))
      out    <- staged match {
        case Left(msg) =>
          for {
            t1 <- IO.monotonic
            wallMs = (t1 - t0).toMillis
          } yield (
            LoopOutcome(entry.id, entry.difficulty.tag, entry.typeSig, "", "anomaly",
              solved = false, Vector.empty, LoopStats(), wallMs, Some(msg)),
            fixtureRow("", None, None, wallMs, anomalous = true),
            Vector.empty[AttemptRow]
          )
        case Right(st) =>
          for {
            rows    <- Ref.of[IO, Vector[AttemptRow]](Vector.empty)
            counter <- Ref.of[IO, Int](0)
            proposer <- FixedProposer.create(st.content, name =>
                          oracle.typeOf(mkCtx("type_of", None), st.workFile, name, None)
                            .map(_.body.map(_.inferred)))
            hooks    = BeamLoop.Hooks { ev =>
                         for {
                           n      <- counter.updateAndGet(_ + 1)
                           logPath = logsDir.resolve(f"probe-$n%03d.json")
                           _      <- IO.blocking(Files.write(logPath, (ev.answer.raw + "\n").getBytes(StandardCharsets.UTF_8)))
                           row     = AttemptRow(
                                       fixtureId     = stem,
                                       benchmarkId   = entry.id,
                                       module        = ev.goal.module.getOrElse(""),
                                       fixturePath   = absPath,
                                       holeIndex     = ev.depth,
                                       holeLine      = ev.target.line,
                                       holeCol       = ev.target.col,
                                       candidateRank = ev.rank,
                                       candidate     = ev.candidate,
                                       status        = ev.answer.body.status.wire,
                                       elapsedMs     = Math.round(ev.answer.clientMs),
                                       rc            = oracle.exitCodeOf(ev.answer.raw).getOrElse(-1),
                                       logPath       = cfg.runRoot.relativize(logPath).toString
                                     )
                           _      <- rows.update(_ :+ row)
                         } yield ()
                       }
            state0   = SearchState.initial(st.content, Vector(st.obligation))
            result  <- BeamLoop.run(oracle, proposer, cfg.loop, mkCtx, st.workFile, state0, hooks)
            t1      <- IO.monotonic
            wallMs   = (t1 - t0).toMillis
            solvedPath <- result.solved.traverse { claim =>
                            val dir  = cfg.runRoot.resolve("solved")
                            val file = dir.resolve(s"$stem.agda")
                            IO.blocking {
                              Files.createDirectories(dir)
                              Files.write(file, claim.state.content.getBytes(StandardCharsets.UTF_8))
                              file.toString
                            }
                          }
            attempts <- rows.get
            module    = result.rootGoal.flatMap(_.module).getOrElse("")
            outcome   = LoopOutcome(
                          benchmarkId  = entry.id,
                          difficulty   = entry.difficulty.tag,
                          goal         = result.rootGoal.map(_.goal).getOrElse(entry.typeSig),
                          module       = module,
                          searchStatus = result.status.tag,
                          solved       = result.solved.isDefined,
                          script       = result.solved.map(_.state.script.map(_.candidate)).getOrElse(Vector.empty),
                          stats        = result.stats,
                          wallMs       = wallMs,
                          anomaly      = None
                        )
          } yield (outcome, fixtureRow(module, Some(result), solvedPath, wallMs, anomalous = false), attempts)
      }
      _ <- IO.println(f">> ${entry.id}%-36s ${out._1.searchStatus}%-16s probes=${out._1.stats.probes}%3d depth=${out._1.stats.depthReached} ${if (out._1.solved) "SOLVED: " + out._1.script.mkString(" ; ") else ""}")
    } yield out

    step.handleErrorWith { e =>
      IO.println(s">> ${entry.id} FAILED: ${e.getMessage}").as((
        LoopOutcome(entry.id, entry.difficulty.tag, entry.typeSig, "", "anomaly",
          solved = false, Vector.empty, LoopStats(), 0L, Some(e.getMessage)),
        fixtureRow("", None, None, 0L, anomalous = true),
        Vector.empty[AttemptRow]
      ))
    }
  }

  // --------------------------------------------------------------------------
  // Outputs
  // --------------------------------------------------------------------------

  private val batchPhases     = Set("check_file", "fill_hole", "final_check")
  private val knowledgePhases = Set("get_goal", "type_of", "peek")

  private def aggregate(rows: Vector[TimingRow]): Json = {
    def phaseObj(phases: Set[String]) = {
      val sel = rows.filter(r => phases(r.phase) && !r.cached)
      Json.obj(
        "calls"           -> sel.size.asJson,
        "clientMs"        -> Scaffold.round3(sel.map(_.clientMs).sum).asJson,
        "serverElapsedMs" -> sel.flatMap(_.serverElapsedMs).sum.asJson,
        "byPhase" -> Json.obj(phases.toVector.sorted.map { ph =>
          val s = sel.filter(_.phase == ph)
          ph -> Json.obj(
            "calls"    -> s.size.asJson,
            "clientMs" -> Scaffold.round3(s.map(_.clientMs).sum).asJson)
        }: _*)
      )
    }
    val proposal = rows.filter(_.phase == "proposal")
    val batchMs  = rows.filter(r => batchPhases(r.phase) && !r.cached).map(_.clientMs).sum
    val knowMs   = rows.filter(r => knowledgePhases(r.phase) && !r.cached).map(_.clientMs).sum
    Json.obj(
      "batch"     -> phaseObj(batchPhases),
      "knowledge" -> phaseObj(knowledgePhases),
      "proposal"  -> Json.obj(
        "calls"    -> proposal.size.asJson,
        "clientMs" -> Scaffold.round3(proposal.map(_.clientMs).sum).asJson),
      "cacheHits"        -> rows.count(_.cached).asJson,
      "batchPctOfOracle" -> Scaffold.pct(batchMs, batchMs + knowMs).asJson
    )
  }

  private def writeOutputs(
    cfg:     LoopHarnessConfig,
    entries: Vector[IndexEntry],
    driven:  Vector[(LoopOutcome, FixtureRow, Vector[AttemptRow])],
    ledger:  Vector[TimingRow]
  ): IO[Unit] = {
    val outcomes = driven.map(_._1)
    val tiers    = Vector("routine", "compositional", "non-obvious")

    def tierBlock(tier: String): Json = {
      val sel = outcomes.filter(_.difficulty == tier)
      Json.obj(
        "total"          -> sel.size.asJson,
        "solved"         -> sel.count(_.solved).asJson,
        "exhausted"      -> sel.count(_.searchStatus == "exhausted").asJson,
        "budgetExceeded" -> sel.count(_.searchStatus == "budget_exceeded").asJson,
        "anomalies"      -> sel.count(_.searchStatus == "anomaly").asJson,
        "probes"         -> sel.map(_.stats.probes).sum.asJson,
        "peeks"          -> sel.map(_.stats.peeks).sum.asJson,
        "peekRejects"    -> sel.map(_.stats.peekRejects).sum.asJson,
        "wallMs"         -> sel.map(_.wallMs).sum.asJson
      )
    }

    val report = Json.obj(
      "schemaVersion" -> "proof-search-loop-report.v0".asJson,
      "runId"         -> cfg.runId.asJson,
      "config" -> Json.obj(
        "beamWidth"   -> cfg.loop.beamWidth.asJson,
        "maxDepth"    -> cfg.loop.maxDepth.asJson,
        "probeBudget" -> cfg.loop.probeBudget.asJson,
        "dedup"       -> cfg.loop.dedup.tag.asJson,
        "peek"        -> cfg.loop.peek.asJson
      ),
      "obligations" -> entries.size.asJson,
      "timestamp"   -> java.time.Instant.now().toString.asJson,
      "perTier"     -> Json.obj(tiers.map(t => t -> tierBlock(t)): _*),
      "split"       -> aggregate(ledger),
      "outcomes"    -> Json.arr(outcomes.map(_.toJson): _*)
    )

    for {
      _ <- Scaffold.writeJsonl(cfg.runRoot.resolve("results.jsonl"), driven.flatMap(_._3).map(_.toJson))
      _ <- Scaffold.writeJsonl(cfg.runRoot.resolve("fixtures.jsonl"), driven.map(_._2.toJson))
      _ <- Scaffold.writeJsonl(cfg.runRoot.resolve("timing.jsonl"), ledger.map(_.asJson))
      _ <- IO.blocking(Files.write(cfg.runRoot.resolve("report.json"),
             report.spaces2.getBytes(StandardCharsets.UTF_8)))
      _ <- IO.println(summarize(cfg, outcomes, ledger))
      _ <- IO.println(s">> wrote ${cfg.runRoot.resolve("report.json")}")
    } yield ()
  }

  private def summarize(cfg: LoopHarnessConfig, outcomes: Vector[LoopOutcome], ledger: Vector[TimingRow]): String = {
    val tiers = Vector("routine", "compositional", "non-obvious")
    val perTier = tiers.map { t =>
      val sel = outcomes.filter(_.difficulty == t)
      f"$t%-14s ${sel.count(_.solved)}%2d/${sel.size}%-2d solved  (${sel.count(_.searchStatus == "exhausted")} exhausted, ${sel.count(_.searchStatus == "budget_exceeded")} budget, ${sel.count(_.searchStatus == "anomaly")} anomaly)"
    }.mkString("\n|")
    val batch  = ledger.filter(r => batchPhases(r.phase) && !r.cached)
    val know   = ledger.filter(r => knowledgePhases(r.phase) && !r.cached)
    val peeks  = outcomes.map(_.stats.peeks).sum
    val prej   = outcomes.map(_.stats.peekRejects).sum
    f"""
       |== proof-search loop (beam=${cfg.loop.beamWidth} depth=${cfg.loop.maxDepth} budget=${cfg.loop.probeBudget} dedup=${cfg.loop.dedup.tag} peek=${if (cfg.loop.peek) "on" else "off"}) ==
       |$perTier
       |solved total: ${outcomes.count(_.solved)}/${outcomes.size}
       |oracle: batch ${batch.size} calls ${batch.map(_.clientMs).sum / 1000.0}%.1f s; knowledge ${know.size} calls ${know.map(_.clientMs).sum / 1000.0}%.1f s; memo hits ${ledger.count(_.cached)}
       |peek:   $peeks peeks, $prej rejected (probes skipped)
       |""".stripMargin
  }
}
