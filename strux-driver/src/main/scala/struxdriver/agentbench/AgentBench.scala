/** ============================================================================
  *  AgentBench.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/AgentBench.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  The entry point of the agent-in-the-loop evaluation (issue #154, [M1-10]):
  *  a frontier model driving agda-mcp over the benchmark, one fresh
  *  `claude -p` session per obligation, judged by the gold verifier's own
  *  invocation plus the statement gates, and reported in the loop's shape so
  *  the two instruments read side by side.
  *
  *  Flow, per obligation
  *  --------------------
  *    1. Stage (Scaffold.stage, through the harness's own corpus-less server):
  *       work copy under work/<id>/, baseline check_file, the exactly-one-hole
  *       gate.  The work directory holds nothing else; the gold is never in
  *       the subject's view.
  *    2. Write the subject's MCP config and prompt under subjects/<id>/, then
  *       spawn the subject (Subject.run) with cwd work/<id>/, its stream-json
  *       to subjects/<id>/transcript.jsonl, under the turn, cost, and wall caps.
  *    3. Copy the file as the subject left it to subjects/<id>/final/<Stem>.agda
  *       and record how the process ended (run.json).
  *    4. Judge (judgeOne): read the transcript (init record, tool calls,
  *       result), audit isolation (server connected, tools presented eagerly,
  *       no tool outside Read/Edit/agda used, no Read or Edit outside the work
  *       directory that succeeded), run the four gates on the final file
  *       (Judge.judge), and derive the per-tool counts, the fill_hole attempt
  *       rows, and the outcome.  This step reads only what step 3 archived,
  *       so `--rejudge` can redo it without a model call.
  *
  *  Output, under --out-dir/--run-id
  *  --------------------------------
  *    report.json     — the loop's shape: runId, timestamp, config (every cap
  *                      and flag, the prompts' digests, the client version),
  *                      corpora (path and digest), obligations, perTier,
  *                      perStratum, perTool, totals, outcomes (one per row:
  *                      solved, restated, gate, terminal, turns, toolCalls,
  *                      wallMs, costUsd, tokens, isolation, evidence).
  *    results.jsonl   — one eval-proof-completion.v0 attempt row per fill_hole
  *                      the subject probed.
  *    fixtures.jsonl  — one eval-proof-completion.v0 fixture row per obligation
  *                      (plus additive restated/gate/terminal fields).
  *    prompts/        — the fixed system prompt and user template, verbatim.
  *    subjects/<id>/  — mcp.json, prompt.txt, transcript.jsonl, stderr.log,
  *                      run.json, final/<Stem>.agda, outcome.json.
  *    work/<id>/      — the staged working copy (the subject's cwd).
  *    solved/         — the solved files.
  *
  *  Exit code: like the loop, an anomaly (a subject whose server never
  *  connected, whose tools arrived deferred, or whose staging failed) never
  *  aborts the sweep and always makes the run exit non-zero.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.{ExitCode, IO, IOApp, Ref}
import cats.effect.syntax.all._
import cats.syntax.all._
import io.circe.Json
import io.circe.syntax._
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths, StandardCopyOption}
import scala.concurrent.duration._

import struxdriver.benchmark.{Obligation => IndexEntry}
import struxdriver.search.{AttemptRow, CallCtx, FixtureRow, LoopOutcome, McpClient, Oracle, ProofSearchLoop, Scaffold, ServerConfig, TimingRow}

final case class AgentBenchConfig(
  index:           Path,
  ids:             Option[Set[String]],
  outDir:          Path,
  runId:           String,
  projectRoot:     Path,
  serverBin:       Option[Path],
  serverTimeout:   Int,
  agdaFlags:       String,
  model:           Option[String],
  maxTurns:        Int,
  wallCapSec:      Int,
  maxBudgetUsd:    BigDecimal,
  parallelism:     Int,
  safe:            Boolean,
  persistSessions: Boolean,
  claudeBin:       String,
  corpusStdlib:    Option[Path],
  corpusAlgebras:  Option[Path],
  rejudge:         Boolean,
  resume:          Boolean
) {
  def runRoot: Path = outDir.resolve(runId)
}

/** The isolation audit of one subject, from its transcript. */
final case class Isolation(
  mcpConnected:     Boolean,
  missingAgdaTools: Vector[String],
  extraTools:       Vector[String],
  toolsDeferred:    Boolean,
  foreignToolUses:  Vector[String],
  violations:       Vector[String],
  deniedPaths:      Vector[String]
) {
  /** The instrument was in the subject's hands: server up, thirteen tools eager. */
  def instrumentOk: Boolean = mcpConnected && missingAgdaTools.isEmpty && !toolsDeferred
  /** Nothing outside the protocol was done: no foreign tool, no successful escape. */
  def confined: Boolean = foreignToolUses.isEmpty && violations.isEmpty

  def toJson: Json = Json.obj(
    "mcpConnected"     -> mcpConnected.asJson,
    "missingAgdaTools" -> missingAgdaTools.asJson,
    "extraTools"       -> extraTools.asJson,
    "toolsDeferred"    -> toolsDeferred.asJson,
    "foreignToolUses"  -> foreignToolUses.asJson,
    "violations"       -> violations.asJson,
    "deniedPaths"      -> deniedPaths.asJson
  )
}

/** What one obligation earned, for report.json. */
final case class Outcome(
  entry:             IndexEntry,
  solved:            Boolean,
  restated:          Boolean,
  gate:              Option[GateFailure],
  evidence:          Vector[String],
  addedImports:      Vector[String],
  terminal:          String,
  turns:             Int,
  toolCalls:         Vector[(String, Int)],
  wallMs:            Long,
  costUsd:           Double,
  tokens:            Json,
  permissionDenials: Int,
  isolation:         Option[Isolation],
  agdaExit:          Option[Int],
  agdaMs:            Option[Long],
  agdaTail:          Option[String],
  anomaly:           Option[String],
  finalPath:         Option[String],
  transcriptPath:    Option[String],
  lastWords:         String,
  rateLimit:         Option[Json] = None
) {
  def stratum: String = LoopOutcome.stratumOf(entry.source, entry.tags)
  def toolCallsTotal: Int = toolCalls.map(_._2).sum
  def toJson: Json = Json.obj(
    "benchmarkId"       -> entry.id.asJson,
    "difficulty"        -> entry.difficulty.tag.asJson,
    "source"            -> entry.source.asJson,
    "tags"              -> entry.tags.asJson,
    "stratum"           -> stratum.asJson,
    "hole"              -> entry.hole.asJson,
    "goal"              -> entry.typeSig.asJson,
    "solved"            -> solved.asJson,
    "restated"          -> restated.asJson,
    "gate"              -> gate.map(_.gate).asJson,
    "gateDetail"        -> gate.map(_.detail).asJson,
    "restatementEvidence" -> evidence.asJson,
    "addedImports"      -> addedImports.asJson,
    "terminal"          -> terminal.asJson,
    "turns"             -> turns.asJson,
    "toolCalls"         -> Json.obj(toolCalls.map { case (n, k) => n -> k.asJson }: _*),
    "toolCallsTotal"    -> toolCallsTotal.asJson,
    "wallMs"            -> wallMs.asJson,
    "costUsd"           -> costUsd.asJson,
    "tokens"            -> tokens,
    "permissionDenials" -> permissionDenials.asJson,
    "isolation"         -> isolation.map(_.toJson).asJson,
    "agdaExit"          -> agdaExit.asJson,
    "agdaMs"            -> agdaMs.asJson,
    "agdaTail"          -> agdaTail.asJson,
    "anomaly"           -> anomaly.asJson,
    "finalPath"         -> finalPath.asJson,
    "transcriptPath"    -> transcriptPath.asJson,
    "lastWords"         -> lastWords.asJson,
    "rateLimit"         -> rateLimit.asJson
  ).dropNullValues
}

object Outcome {
  def anomaly(entry: IndexEntry, msg: String, wallMs: Long): Outcome =
    Outcome(entry, solved = false, restated = false, None, Vector.empty, Vector.empty, "anomaly", 0, Vector.empty,
      wallMs, 0.0, Json.obj(), 0, None, None, None, None, Some(msg), None, None, "")
}

object AgentBench extends IOApp {

  private val usage: String =
    """usage: runMain struxdriver.agentbench.AgentBench
      |    --index PATH              benchmark-index.jsonl
      |    (--ids id1,id2 | --all)
      |    --out-dir PATH            run roots land here
      |    --run-id STR              the run directory name (a new protocol is a new run id)
      |    --project-root PATH       repo root: the server's cwd; index paths resolve here
      |    --server-bin PATH         the agda-mcp binary (the subjects' servers and the staging server)
      |    --model STR               the subject model, e.g. claude-sonnet-5
      |    --corpus-stdlib PATH      the agda-stdlib corpus, served to agda-stdlib rows
      |    --corpus-algebras PATH    the agda-algebras corpus, served to agda-algebras rows
      |    [--max-turns N]           per-subject turn cap (default 30)
      |    [--wall-cap N]            per-subject wall cap, seconds (default 900)
      |    [--max-budget-usd D]      per-subject cost cap (default 3.00)
      |    [--parallelism N]         subjects at once (default 1; wall clocks are indicative only above 1)
      |    [--safe on|off]           judge with --safe (default on: every committed gold passes under it)
      |    [--persist-sessions on|off]  let the client write its session to disk (default off)
      |    [--claude-bin PATH]       the claude CLI (default: claude on PATH)
      |    [--agda-flags STR]        default: the committed .mcp.json flag set
      |    [--server-timeout N]      per-Agda-call bound, seconds (default 600)
      |    [--rejudge]               re-judge an existing run root from subjects/; no model call
      |    [--resume on|off]         keep the archived, non-anomalous subjects of this run id and run only the rest (default off)
      |""".stripMargin

  def run(args: List[String]): IO[ExitCode] =
    parseArgs(args) match {
      case Left(err)  => IO.println(s"error: $err\n\n$usage").as(ExitCode.Error)
      case Right(cfg) => runHarness(cfg)
    }

  // --------------------------------------------------------------------------
  // Arguments
  // --------------------------------------------------------------------------

  private def parseArgs(args: List[String]): Either[String, AgentBenchConfig] = {
    val known = Set("index", "ids", "out-dir", "run-id", "project-root", "server-bin", "model", "corpus-stdlib",
      "corpus-algebras", "max-turns", "wall-cap", "max-budget-usd", "parallelism", "safe", "persist-sessions",
      "claude-bin", "agda-flags", "server-timeout", "resume")
    @annotation.tailrec
    def go(rest: List[String], m: Map[String, String]): Either[String, Map[String, String]] =
      rest match {
        case Nil                                       => Right(m)
        case "--all" :: xs                             => go(xs, m + ("all" -> "true"))
        case "--rejudge" :: xs                         => go(xs, m + ("rejudge" -> "true"))
        case flag :: v :: xs if flag.startsWith("--") && known(flag.drop(2)) => go(xs, m + (flag.drop(2) -> v))
        case other :: _                                => Left(s"unrecognized argument: $other")
      }
    def intOf(m: Map[String, String], key: String, dflt: Int, min: Int): Either[String, Int] =
      m.get(key).fold[Either[String, Int]](Right(dflt))(s => s.toIntOption.filter(_ >= min).toRight(s"bad --$key: $s"))
    def onOff(m: Map[String, String], key: String, dflt: Boolean): Either[String, Boolean] =
      m.get(key).fold[Either[String, Boolean]](Right(dflt)) {
        case "on"  => Right(true)
        case "off" => Right(false)
        case other => Left(s"bad --$key: $other (on|off)")
      }
    for {
      m       <- go(args, Map.empty)
      rejudge  = m.contains("rejudge")
      ix      <- m.get("index").toRight("missing --index")
      out     <- m.get("out-dir").toRight("missing --out-dir")
      runId   <- m.get("run-id").toRight("missing --run-id")
      root    <- m.get("project-root").toRight("missing --project-root")
      ids      = m.get("ids").map(_.split(",").map(_.trim).filter(_.nonEmpty).toSet)
      _       <- if (ids.isEmpty && !m.contains("all")) Left("pass --ids or --all") else Right(())
      rootAbs  = Paths.get(root).toAbsolutePath.normalize
      abs      = (p: String) => { val q = Paths.get(p); if (q.isAbsolute) q else rootAbs.resolve(q).normalize }
      bin     <- if (rejudge) Right(m.get("server-bin").map(abs)) else m.get("server-bin").map(abs).map(Option(_)).toRight("missing --server-bin")
      model   <- if (rejudge) Right(m.get("model")) else m.get("model").map(Option(_)).toRight("missing --model")
      cs      <- if (rejudge) Right(m.get("corpus-stdlib").map(abs)) else m.get("corpus-stdlib").map(abs).map(Option(_)).toRight("missing --corpus-stdlib")
      ca      <- if (rejudge) Right(m.get("corpus-algebras").map(abs)) else m.get("corpus-algebras").map(abs).map(Option(_)).toRight("missing --corpus-algebras")
      turns   <- intOf(m, "max-turns", 30, 1)
      wall    <- intOf(m, "wall-cap", 900, 1)
      par     <- intOf(m, "parallelism", 1, 1)
      tmo     <- intOf(m, "server-timeout", 600, 1)
      budget  <- m.get("max-budget-usd").fold[Either[String, BigDecimal]](Right(BigDecimal("3.00")))(s =>
                   scala.util.Try(BigDecimal(s)).toOption.filter(_ > 0).toRight(s"bad --max-budget-usd: $s"))
      safe    <- onOff(m, "safe", true)
      persist <- onOff(m, "persist-sessions", false)
      resume  <- onOff(m, "resume", false)
    } yield AgentBenchConfig(
      index           = Paths.get(ix),
      ids             = ids,
      outDir          = Paths.get(out).toAbsolutePath.normalize,
      runId           = runId,
      projectRoot     = rootAbs,
      serverBin       = bin,
      serverTimeout   = tmo,
      agdaFlags       = m.getOrElse("agda-flags", Scaffold.defaultAgdaFlags),
      model           = model,
      maxTurns        = turns,
      wallCapSec      = wall,
      maxBudgetUsd    = budget,
      parallelism     = par,
      safe            = safe,
      persistSessions = persist,
      claudeBin       = m.getOrElse("claude-bin", "claude"),
      corpusStdlib    = cs,
      corpusAlgebras  = ca,
      rejudge         = rejudge,
      resume          = resume
    )
  }

  // --------------------------------------------------------------------------
  // Small helpers
  // --------------------------------------------------------------------------

  private def readText(p: Path): IO[String] =
    IO.blocking(new String(Files.readAllBytes(p), StandardCharsets.UTF_8))

  private def writeText(p: Path, s: String): IO[Unit] =
    IO.blocking { Files.createDirectories(p.getParent); Files.write(p, s.getBytes(StandardCharsets.UTF_8)); () }

  private def resource(name: String): IO[String] =
    IO.blocking {
      val in = Option(getClass.getClassLoader.getResourceAsStream(s"agentbench/$name"))
        .getOrElse(throw new RuntimeException(s"missing classpath resource agentbench/$name"))
      try new String(in.readAllBytes(), StandardCharsets.UTF_8) finally in.close()
    }

  private def sha256(s: String): String = {
    val md = java.security.MessageDigest.getInstance("SHA-256")
    md.digest(s.getBytes(StandardCharsets.UTF_8)).map(b => f"$b%02x").mkString
  }

  private def claudeVersion(bin: String): IO[String] =
    IO.blocking {
      val p = new ProcessBuilder(bin, "--version").redirectErrorStream(true).start()
      val out = new String(p.getInputStream.readAllBytes(), StandardCharsets.UTF_8).trim
      p.waitFor()
      out
    }.handleError(e => s"unknown (${e.getMessage})")

  private def subjectsDir(cfg: AgentBenchConfig, id: String): Path = cfg.runRoot.resolve(s"subjects/$id")
  private def workDirOf(cfg: AgentBenchConfig, id: String): Path   = cfg.runRoot.resolve(s"work/$id")

  // --------------------------------------------------------------------------
  // The run
  // --------------------------------------------------------------------------

  private def runHarness(cfg: AgentBenchConfig): IO[ExitCode] =
    for {
      entries  <- Scaffold.readIndex(cfg.index, cfg.ids)
      _        <- IO.raiseWhen(entries.isEmpty)(new RuntimeException("no obligations matched"))
      _        <- IO.blocking(Files.createDirectories(cfg.runRoot))
      sysP     <- resource("system-prompt.md")
      userT    <- resource("user-prompt.md")
      _        <- writeText(cfg.runRoot.resolve("prompts/system-prompt.md"), sysP)
      _        <- writeText(cfg.runRoot.resolve("prompts/user-prompt.md"), userT)
      // A re-judge keeps the run's own record of how its subjects were run:
      // the previous report's config and corpora blocks are carried over
      // verbatim (the judge's own knob and the re-judge time are added), since
      // the harness is not told the model or the corpora a second time.
      previous <- if (cfg.rejudge)
                    readText(cfg.runRoot.resolve("report.json")).map(io.circe.parser.parse(_).toOption).handleError(_ => None)
                  else IO.pure(Option.empty[Json])
      driven   <- if (cfg.rejudge) rejudgeAll(cfg, entries) else driveAll(cfg, entries, sysP, userT)
      corpora  <- previous.flatMap(_.hcursor.downField("corpora").focus).map(IO.pure).getOrElse(
                    Vector(cfg.corpusStdlib.map("agda-stdlib" -> _), cfg.corpusAlgebras.map("agda-algebras" -> _)).flatten
                      .traverse { case (k, p) => ProofSearchLoop.corpusProvenance(p).map(k -> _) }.map(v => Json.obj(v: _*)))
      version  <- if (cfg.rejudge) IO.pure("n/a (rejudge)") else claudeVersion(cfg.claudeBin)
      _        <- writeOutputs(cfg, entries, driven, corpora, version, sysP, userT, previous.flatMap(_.hcursor.downField("config").focus))
      anomalies = driven.map(_._1).filter(_.anomaly.isDefined)
      _        <- anomalies.traverse_(o => IO.println(s"!! ${o.entry.id} anomaly: ${o.anomaly.getOrElse("")}"))
    } yield if (anomalies.isEmpty) ExitCode.Success else ExitCode.Error

  private def driveAll(cfg: AgentBenchConfig, entries: Vector[IndexEntry], sysP: String, userT: String): IO[Vector[(Outcome, Json, Vector[AttemptRow])]] = {
    val bin = cfg.serverBin.getOrElse(throw new IllegalStateException("server-bin required"))
    val subject = SubjectConfig(
      claudeBin       = cfg.claudeBin,
      model           = cfg.model.getOrElse(""),
      maxTurns        = cfg.maxTurns,
      wallCap         = cfg.wallCapSec.seconds,
      maxBudgetUsd    = cfg.maxBudgetUsd,
      projectRoot     = cfg.projectRoot,
      serverBin       = bin,
      agdaFlags       = cfg.agdaFlags,
      serverTimeout   = cfg.serverTimeout,
      persistSessions = cfg.persistSessions,
      systemPrompt    = sysP.trim,
      userTemplate    = userT
    )
    val staging = ServerConfig(
      bin        = bin,
      agdaFlags  = cfg.agdaFlags,
      timeoutSec = cfg.serverTimeout,
      cwd        = cfg.projectRoot,
      stderrLog  = cfg.runRoot.resolve("server-stderr.log"),
      corpus     = None
    )
    for {
      _       <- IO.println(s">> agent-bench: ${entries.size} obligation(s), model=${subject.model} turns=${cfg.maxTurns} wall=${cfg.wallCapSec}s budget=${cfg.maxBudgetUsd} parallelism=${cfg.parallelism} safe=${cfg.safe}")
      _       <- IO.println(s">> run root: ${cfg.runRoot}")
      timings <- Ref.of[IO, Vector[TimingRow]](Vector.empty)
      driven  <- McpClient.resource(staging).use { client =>
                   entries.parTraverseN(cfg.parallelism) { e =>
                     archivedClean(cfg, e).flatMap {
                       case true  => IO.println(s">> ${e.id} resume: archived subject kept, re-judged") *> judgeOne(cfg, e, subjectsDir(cfg, e.id))
                       case false => driveOne(cfg, subject, client, timings, e)
                     }.handleErrorWith { err =>
                       IO.println(s">> ${e.id} FAILED: ${err.getMessage}") *>
                         IO.pure(judgedTriple(cfg, Outcome.anomaly(e, err.getMessage, 0L), Vector.empty))
                     }
                   }
                 }
    } yield driven
  }

  /** Under --resume, a subject already archived under this run id with no
    * anomaly is kept (and re-judged); an anomalous or missing one is run.
    */
  private def archivedClean(cfg: AgentBenchConfig, e: IndexEntry): IO[Boolean] =
    if (!cfg.resume) IO.pure(false)
    else IO.blocking {
      val dir = subjectsDir(cfg, e.id)
      val out = dir.resolve("outcome.json")
      Files.isRegularFile(out) && Files.isRegularFile(dir.resolve(s"final/${Scaffold.fixtureStem(e)}.agda")) && {
        val j = io.circe.parser.parse(new String(Files.readAllBytes(out), StandardCharsets.UTF_8)).getOrElse(Json.obj())
        j.hcursor.get[String]("anomaly").toOption.isEmpty
      }
    }

  /** Stage, spawn, archive, judge: one subject. */
  private def driveOne(cfg: AgentBenchConfig, subject: SubjectConfig, client: McpClient, timings: Ref[IO, Vector[TimingRow]], entry: IndexEntry): IO[(Outcome, Json, Vector[AttemptRow])] = {
    val workDir = workDirOf(cfg, entry.id)
    val subjDir = subjectsDir(cfg, entry.id)
    val source  = cfg.projectRoot.resolve(entry.obligationPath)
    val stem    = Scaffold.fixtureStem(entry)
    val corpus  = (if (entry.source == "agda-algebras") cfg.corpusAlgebras else cfg.corpusStdlib)
                    .getOrElse(throw new IllegalStateException("corpus required"))
    for {
      oracle <- Oracle.create(client, timings)
      staged <- Scaffold.stage(source, workDir, subjDir, oracle, CallCtx(1, entry.id, "check_file", None))
      out    <- staged match {
        case Left(msg) =>
          IO.println(s">> ${entry.id} staging anomaly: $msg") *>
            IO.pure(judgedTriple(cfg, Outcome.anomaly(entry, s"staging: $msg", 0L), Vector.empty))
        case Right(st) =>
          val mcpPath   = subjDir.resolve("mcp.json")
          val prompt    = Subject.userPrompt(subject.userTemplate, st.workFile, entry.hole)
          val transcript = subjDir.resolve("transcript.jsonl")
          val finalFile = subjDir.resolve(s"final/$stem.agda")
          for {
            _   <- writeText(mcpPath, Subject.mcpConfig(subject, workDir, st.workFile, corpus).spaces2)
            _   <- writeText(subjDir.resolve("prompt.txt"), prompt + "\n")
            _   <- IO.println(s">> ${entry.id} launch (${entry.difficulty.tag}, ${LoopOutcome.stratumOf(entry.source, entry.tags)})")
            run <- Subject.run(subject, workDir, mcpPath, prompt, transcript, subjDir.resolve("stderr.log"))
            _   <- IO.blocking { Files.createDirectories(finalFile.getParent); Files.copy(st.workFile, finalFile, StandardCopyOption.REPLACE_EXISTING); () }
            _   <- writeText(subjDir.resolve("run.json"), Json.obj(
                     "exitCode" -> run.exitCode.asJson, "wallMs" -> run.wallMs.asJson, "killed" -> run.killed.asJson).spaces2)
            _   <- IO.println(f">> ${entry.id}%-36s subject exit=${run.exitCode.map(_.toString).getOrElse("killed")} wall=${run.wallMs / 1000}s")
            j   <- judgeOne(cfg, entry, subjDir)
          } yield j
      }
    } yield out
  }

  private def rejudgeAll(cfg: AgentBenchConfig, entries: Vector[IndexEntry]): IO[Vector[(Outcome, Json, Vector[AttemptRow])]] =
    IO.println(s">> agent-bench: re-judging ${entries.size} obligation(s) under ${cfg.runRoot}") *>
      entries.traverse { e =>
        val subjDir = subjectsDir(cfg, e.id)
        IO.blocking(Files.isRegularFile(subjDir.resolve(s"final/${Scaffold.fixtureStem(e)}.agda"))).flatMap {
          case true  => judgeOne(cfg, e, subjDir)
          case false => IO.pure(judgedTriple(cfg, Outcome.anomaly(e, "no archived subject to judge", 0L), Vector.empty))
        }
      }

  // --------------------------------------------------------------------------
  // The judge step, over what subjects/<id>/ archived
  // --------------------------------------------------------------------------

  private[agentbench] def terminalOf(killed: Boolean, result: Option[ResultRecord]): String =
    if (killed) "wall_cap"
    else result match {
      case None    => "crash"
      case Some(r) => r.subtype match {
        case "success"                     => "completed"
        case s if s.contains("max_turns")  => "max_turns"
        case s if s.contains("budget")     => "budget"
        case s                             => s
      }
    }

  private[agentbench] def audit(t: Transcript, workDir: Path): Isolation = {
    val init     = t.init
    val tools    = init.map(_.tools).getOrElse(Vector.empty)
    val allowed  = Subject.fileTools ++ Subject.agdaTools
    val paths    = t.filePaths(Subject.fileTools)
    val outside  = paths.filter { case (_, _, p) =>
      val q = Paths.get(p)
      !(if (q.isAbsolute) q else workDir.resolve(q)).normalize.startsWith(workDir.toAbsolutePath.normalize)
    }
    Isolation(
      mcpConnected     = init.exists(_.mcpServers.contains(("agda", "connected"))),
      missingAgdaTools = Subject.agdaTools.filterNot(tools.contains),
      extraTools       = tools.filterNot(allowed.contains),
      toolsDeferred    = t.toolsDeferred,
      foreignToolUses  = t.uses.map(_.name).filterNot(allowed.contains).distinct,
      violations       = outside.collect { case (u, r, p) if !r.exists(_.isError) => s"${u.name} $p" },
      deniedPaths      = outside.collect { case (u, r, p) if r.exists(_.isError) => s"${u.name} $p" }
    )
  }

  private[agentbench] def attemptRows(cfg: AgentBenchConfig, entry: IndexEntry, t: Transcript, transcriptRel: String): Vector[AttemptRow] = {
    val stem = Scaffold.fixtureStem(entry)
    t.usesOf("mcp__agda__fill_hole").zipWithIndex.map { case (u, i) =>
      val r    = t.resultOf(u)
      val body = r.flatMap(_.body)
      val status =
        if (r.exists(_.isError) || r.isEmpty) "crash"
        else body.flatMap(_.hcursor.get[String]("status").toOption).getOrElse("crash")
      AttemptRow(
        fixtureId     = stem,
        benchmarkId   = entry.id,
        module        = stem,
        fixturePath   = workDirOf(cfg, entry.id).resolve(s"$stem.agda").toString,
        holeIndex     = u.int("holeIndex").getOrElse(0),
        holeLine      = u.int("line").getOrElse(-1),
        holeCol       = u.int("column").orElse(u.int("col")).getOrElse(-1),
        candidateRank = i + 1,
        candidate     = u.str("candidate").getOrElse(""),
        status        = status,
        elapsedMs     = body.flatMap(_.hcursor.get[Long]("elapsedMs").toOption).getOrElse(0L),
        rc            = body.flatMap(_.hcursor.downField("verdict").get[Int]("exitCode").toOption).getOrElse(-1),
        logPath       = transcriptRel
      )
    }
  }

  private def judgedTriple(cfg: AgentBenchConfig, o: Outcome, rows: Vector[AttemptRow]): (Outcome, Json, Vector[AttemptRow]) = {
    val stem = Scaffold.fixtureStem(o.entry)
    val fixture = FixtureRow(
      fixtureId    = stem,
      module       = stem,
      fixturePath  = workDirOf(cfg, o.entry.id).resolve(s"$stem.agda").toString,
      holesTotal   = 1,
      holesSolved  = if (o.solved) 1 else 0,
      fullySolved  = o.solved,
      finalStatus  = if (o.solved) "ok" else if (o.anomaly.isDefined) "crash" else "unsolved",
      elapsedMs    = o.wallMs,
      solvedPath   = if (o.solved) Some(cfg.runRoot.resolve(s"solved/$stem.agda").toString) else None,
      benchmarkId  = o.entry.id,
      searchStatus = o.terminal
    ).toJson.deepMerge(Json.obj(
      "restated" -> o.restated.asJson,
      "gate"     -> o.gate.map(_.gate).asJson,
      "terminal" -> o.terminal.asJson
    ).dropNullValues)
    (o, fixture, rows)
  }

  /** Judge one archived subject: transcript, isolation, gates, outcome. */
  private def judgeOne(cfg: AgentBenchConfig, entry: IndexEntry, subjDir: Path): IO[(Outcome, Json, Vector[AttemptRow])] = {
    val stem      = Scaffold.fixtureStem(entry)
    val finalFile = subjDir.resolve(s"final/$stem.agda")
    val workDir   = workDirOf(cfg, entry.id)
    val transcriptRel = cfg.runRoot.relativize(subjDir.resolve("transcript.jsonl")).toString
    for {
      obligation <- readText(cfg.projectRoot.resolve(entry.obligationPath))
      finalText  <- readText(finalFile)
      stream     <- readText(subjDir.resolve("transcript.jsonl")).handleError(_ => "")
      runJson    <- readText(subjDir.resolve("run.json")).map(io.circe.parser.parse(_).getOrElse(Json.obj())).handleError(_ => Json.obj())
      t           = Transcript.parse(stream)
      killed      = runJson.hcursor.get[Boolean]("killed").getOrElse(false)
      wallMs      = runJson.hcursor.get[Long]("wallMs").getOrElse(t.result.map(_.durationMs).getOrElse(0L))
      iso         = audit(t, workDir)
      verdict    <- Judge.judge(entry, obligation, finalText, finalFile, cfg.projectRoot, cfg.safe, cfg.serverTimeout.seconds)
      gate        = if (!iso.confined) Some(GateFailure("isolation", (iso.foreignToolUses.map(n => s"tool $n") ++ iso.violations).mkString("; ")))
                    else verdict.gate
      capped      = t.result.exists(r => r.subtype.contains("max_turns") || r.subtype.contains("budget"))
      anomaly     = if (t.init.isEmpty) Some("no init record: the subject never started (see stderr.log)")
                    else if (!iso.mcpConnected) Some("agda server not connected in the subject's session")
                    else if (iso.toolsDeferred) Some("agda tools were presented as deferred names")
                    else if (iso.missingAgdaTools.nonEmpty) Some(s"agda tools missing from the session: ${iso.missingAgdaTools.mkString(",")}")
                    else if (t.rateLimitRejected) Some(s"rate limited: ${t.rateLimits.map(_._1).distinct.mkString(",")}")
                    else if (t.result.exists(_.isError) && !capped) Some(s"client error (${t.result.map(_.subtype).getOrElse("?")}): ${t.result.map(_.text.take(200)).getOrElse("")}")
                    else None
      solved      = gate.isEmpty && verdict.solved
      restated    = gate.isEmpty && verdict.restated
      outcome     = Outcome(
        entry             = entry,
        solved            = solved,
        restated          = restated,
        gate              = gate,
        evidence          = verdict.evidence,
        addedImports      = verdict.addedImports,
        terminal          = terminalOf(killed, t.result),
        turns             = t.result.map(_.numTurns).getOrElse(0),
        toolCalls         = t.toolCounts,
        wallMs            = wallMs,
        costUsd           = t.result.map(_.costUsd).getOrElse(0.0),
        tokens            = t.result.map(_.tokens).getOrElse(Json.obj()),
        permissionDenials = t.result.map(_.permissionDenials).getOrElse(0),
        isolation         = Some(iso),
        agdaExit          = verdict.agdaExit,
        agdaMs            = verdict.agdaMs,
        agdaTail          = verdict.agdaTail,
        anomaly           = anomaly,
        finalPath         = Some(cfg.runRoot.relativize(finalFile).toString),
        transcriptPath    = Some(transcriptRel),
        lastWords         = t.result.map(_.text.take(600)).getOrElse(""),
        rateLimit         = t.rateLimitMax.map(u => Json.obj(
                              "maxUtilization" -> u.asJson,
                              "statuses"       -> t.rateLimits.map(_._1).distinct.asJson))
      )
      _          <- if (solved) IO.blocking {
                      val dir = cfg.runRoot.resolve("solved"); Files.createDirectories(dir)
                      Files.copy(finalFile, dir.resolve(s"$stem.agda"), StandardCopyOption.REPLACE_EXISTING); ()
                    } else IO.unit
      _          <- writeText(subjDir.resolve("outcome.json"), outcome.toJson.spaces2)
      _          <- IO.println(f">> ${entry.id}%-36s ${if (solved) "SOLVED" else if (restated) "RESTATED" else gate.map(g => s"gate:${g.gate}").getOrElse("unsolved")}%-20s turns=${outcome.turns}%3d calls=${outcome.toolCallsTotal}%3d cost=$$${outcome.costUsd}%.3f terminal=${outcome.terminal}${t.rateLimitMax.fold("")(u => f" window=$u%.2f")}${anomaly.fold("")(a => s"  ANOMALY: $a")}")
    } yield judgedTriple(cfg, outcome, attemptRows(cfg, entry, t, transcriptRel))
  }

  // --------------------------------------------------------------------------
  // Outputs
  // --------------------------------------------------------------------------

  private def block(sel: Vector[Outcome]): Json = {
    val gates = sel.flatMap(_.gate.map(_.gate))
    Json.obj(
      "total"       -> sel.size.asJson,
      "solved"      -> sel.count(_.solved).asJson,
      "restated"    -> sel.count(_.restated).asJson,
      "gates"       -> Json.obj(gates.distinct.sorted.map(g => g -> gates.count(_ == g).asJson): _*),
      "anomalies"   -> sel.count(_.anomaly.isDefined).asJson,
      "turns"       -> sel.map(_.turns).sum.asJson,
      "toolCalls"   -> sel.map(_.toolCallsTotal).sum.asJson,
      "wallMs"      -> sel.map(_.wallMs).sum.asJson,
      "costUsd"     -> Scaffold.round3(sel.map(_.costUsd).sum).asJson
    )
  }

  private def perTool(outcomes: Vector[Outcome]): Json = {
    val all = outcomes.flatMap(_.toolCalls)
    Json.obj(all.map(_._1).distinct.sortBy(n => (-all.filter(_._1 == n).map(_._2).sum, n)).map(n => n -> all.filter(_._1 == n).map(_._2).sum.asJson): _*)
  }

  private def writeOutputs(cfg: AgentBenchConfig, entries: Vector[IndexEntry], driven: Vector[(Outcome, Json, Vector[AttemptRow])], corpora: Json, version: String, sysP: String, userT: String, previousConfig: Option[Json]): IO[Unit] = {
    val outcomes = driven.map(_._1)
    val tiers    = Vector("routine", "compositional", "non-obvious")
    val strata   = outcomes.map(_.stratum).distinct
    val subject  = SubjectConfig(cfg.claudeBin, cfg.model.getOrElse(""), cfg.maxTurns, cfg.wallCapSec.seconds, cfg.maxBudgetUsd,
                     cfg.projectRoot, cfg.serverBin.getOrElse(Paths.get("")), cfg.agdaFlags, cfg.serverTimeout, cfg.persistSessions, sysP, userT)
    val builtConfig = Json.obj(
        "model"           -> cfg.model.asJson,
        "maxTurns"        -> cfg.maxTurns.asJson,
        "wallCapSec"      -> cfg.wallCapSec.asJson,
        "maxBudgetUsd"    -> cfg.maxBudgetUsd.asJson,
        "parallelism"     -> cfg.parallelism.asJson,
        "safe"            -> cfg.safe.asJson,
        "serverTimeout"   -> cfg.serverTimeout.asJson,
        "agdaFlags"       -> cfg.agdaFlags.asJson,
        "claudeBin"       -> cfg.claudeBin.asJson,
        "claudeVersion"   -> version.asJson,
        "claudeFlags"     -> Subject.fixedFlags(subject).asJson,
        "envAdded"        -> Subject.envAdded.asJson,
        "envRemovedPrefix" -> Subject.envRemovedPrefix.asJson,
        "tools"           -> (Subject.fileTools.toVector.sorted ++ Subject.agdaTools).asJson,
        "persistSessions" -> cfg.persistSessions.asJson,
        "resume"          -> cfg.resume.asJson,
        "prompts" -> Json.obj(
          "system" -> Json.obj("path" -> "prompts/system-prompt.md".asJson, "sha256" -> sha256(sysP).asJson),
          "user"   -> Json.obj("path" -> "prompts/user-prompt.md".asJson,   "sha256" -> sha256(userT).asJson)),
        "gates"           -> Vector("preservation", "escape", "holes", "typecheck", "isolation").asJson
      )
    val config = previousConfig match {
      case Some(prev) if cfg.rejudge =>
        prev.deepMerge(Json.obj("safe" -> cfg.safe.asJson, "rejudgedAt" -> java.time.Instant.now().toString.asJson))
      case _ => builtConfig
    }
    val report = Json.obj(
      "schemaVersion" -> "agent-bench-report.v0".asJson,
      "runId"         -> cfg.runId.asJson,
      "timestamp"     -> java.time.Instant.now().toString.asJson,
      "rejudged"      -> cfg.rejudge.asJson,
      "config"        -> config,
      "corpora"       -> corpora,
      "obligations" -> entries.size.asJson,
      "totals"      -> block(outcomes),
      "perTier"     -> Json.obj(tiers.map(t => t -> block(outcomes.filter(_.entry.difficulty.tag == t))): _*),
      "perStratum"  -> Json.obj(strata.map(s => s -> block(outcomes.filter(_.stratum == s))): _*),
      "perTool"     -> perTool(outcomes),
      "outcomes"    -> Json.arr(outcomes.map(_.toJson): _*)
    ).dropNullValues
    for {
      _ <- Scaffold.writeJsonl(cfg.runRoot.resolve("results.jsonl"), driven.flatMap(_._3).map(_.toJson))
      _ <- Scaffold.writeJsonl(cfg.runRoot.resolve("fixtures.jsonl"), driven.map(_._2))
      _ <- IO.blocking(Files.write(cfg.runRoot.resolve("report.json"), report.spaces2.getBytes(StandardCharsets.UTF_8)))
      _ <- IO.println(summarize(cfg, outcomes))
      _ <- IO.println(s">> wrote ${cfg.runRoot.resolve("report.json")}")
    } yield ()
  }

  private def summarize(cfg: AgentBenchConfig, outcomes: Vector[Outcome]): String = {
    def line(label: String, sel: Vector[Outcome]) =
      f"$label%-26s ${sel.count(_.solved)}%2d/${sel.size}%-2d solved  ${sel.count(_.restated)}%2d restated  ${sel.count(_.anomaly.isDefined)}%2d anomaly  turns=${sel.map(_.turns).sum}%4d calls=${sel.map(_.toolCallsTotal).sum}%4d cost=$$${sel.map(_.costUsd).sum}%.2f"
    val tiers  = Vector("routine", "compositional", "non-obvious").map(t => line(t, outcomes.filter(_.entry.difficulty.tag == t)))
    val strata = outcomes.map(_.stratum).distinct.map(s => line(s, outcomes.filter(_.stratum == s)))
    val tools  = perTool(outcomes).asObject.map(_.toVector.map { case (n, k) => s"$n=${k.asNumber.flatMap(_.toInt).getOrElse(0)}" }.mkString(" ")).getOrElse("")
    s"""
       |== agent-bench (model=${cfg.model.getOrElse("?")} turns=${cfg.maxTurns} wall=${cfg.wallCapSec}s budget=${cfg.maxBudgetUsd} safe=${cfg.safe}) ==
       |${tiers.mkString("\n")}
       |${strata.mkString("\n")}
       |${line("total", outcomes)}
       |tools: $tools
       |""".stripMargin
  }
}
