/** ============================================================================
  *  Outcomes.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Outcomes.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  What one obligation earned (issue #154), and how that is derived from a
  *  subject's archive alone: read the final file, the transcript, the
  *  process record, and the server config (for the work directory the
  *  subject had); audit the transcript (Audit.scala); run the gates
  *  (Judge.scala); assemble the outcome, the eval-proof-completion.v0
  *  fixture row, and the attempt rows; write the verdict beside the archive.
  *  Because this step reads only what the runner archived, `--rejudge` can
  *  redo it for a finished run without a model call.
  *
  *  The arm (issue #162) is read from the subject's own record, not from the
  *  harness's current `--arm`, so a re-judge audits a run under the arm and the
  *  roots it was run with; the `via` and `verdictVia` columns say which
  *  instrument the subject actually used, and which it took its last verdict
  *  from, which is the whole result of the `both` arm.
  *
  *  Anomaly rules
  *  -------------
  *  A row is an anomaly, not a result, when the subject never had the
  *  instrument as the protocol fixes it: no init record (the client never
  *  started), the agda server not connected or one of the required tools
  *  missing (an arm with the server), the tools presented as deferred
  *  names, a tool presented beyond the arm's set (used or not), the
  *  account's rate limit refusing service, a client error that is not one of
  *  the stated caps, or a process that ended with no result record at all
  *  (a crash; a wall-cap kill is a stated cap, not an anomaly); and when the
  *  final file leaves the judge without an answer it should have, which is a
  *  configuration fact, not a fact about the proof: a `check_file` answer
  *  that is not usable at all (it timed out, or carries no exit code, or
  *  contradicts itself), the two batch verdicts (the gold verifier's agda
  *  and the server's check_file) disagreeing, or a file Agda checked that
  *  the extractor could not read.  An anomalous row is never counted a solve
  *  or a restatement, whatever its file earned: it is not a measured row.  The rules are
  *  `anomalyOf`, first that applies.  The gates still run on the file, so the
  *  anomaly keeps its diagnostics, and the run exits non-zero.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.IO
import io.circe.Json
import io.circe.syntax._
import java.nio.file.{Files, StandardCopyOption}
import scala.concurrent.duration._

import struxdriver.benchmark.{Obligation => IndexEntry}
import struxdriver.io.TextIO
import struxdriver.search.{AttemptRow, FixtureRow, LoopOutcome, Scaffold}

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
  via:               String,
  verdictVia:        String,
  agdaExit:          Option[Int],
  agdaMs:            Option[Long],
  agdaTail:          Option[String],
  checkExit:         Option[Int],
  checkCodes:        Vector[String],
  statement:         Option[StatementCheck],
  evidenceSource:    String,
  anomaly:           Option[String],
  finalPath:         Option[String],
  transcriptPath:    Option[String],
  lastWords:         String,
  rateLimit:         Option[Json] = None
) {
  def stratum: String = LoopOutcome.stratumOf(entry.source, entry.tags)
  def toolCallsTotal: Int = toolCalls.map(_._2).sum
  def toJson: Json = Json.obj(
    "benchmarkId"         -> entry.id.asJson,
    "difficulty"          -> entry.difficulty.tag.asJson,
    "source"              -> entry.source.asJson,
    "tags"                -> entry.tags.asJson,
    "stratum"             -> stratum.asJson,
    "hole"                -> entry.hole.asJson,
    "goal"                -> entry.typeSig.asJson,
    "solved"              -> solved.asJson,
    "restated"            -> restated.asJson,
    "gate"                -> gate.map(_.gate).asJson,
    "gateDetail"          -> gate.map(_.detail).asJson,
    "restatementEvidence" -> evidence.asJson,
    "addedImports"        -> addedImports.asJson,
    "terminal"            -> terminal.asJson,
    "turns"               -> turns.asJson,
    "toolCalls"           -> Json.obj(toolCalls.map { case (n, k) => n -> k.asJson }: _*),
    "toolCallsTotal"      -> toolCallsTotal.asJson,
    "wallMs"              -> wallMs.asJson,
    "costUsd"             -> costUsd.asJson,
    "tokens"              -> tokens,
    "permissionDenials"   -> permissionDenials.asJson,
    "isolation"           -> isolation.map(_.toJson).asJson,
    "via"                 -> via.asJson,
    "verdictVia"          -> verdictVia.asJson,
    "agdaExit"            -> agdaExit.asJson,
    "agdaMs"              -> agdaMs.asJson,
    "agdaTail"            -> agdaTail.asJson,
    "checkExit"           -> checkExit.asJson,
    "checkCodes"          -> checkCodes.asJson,
    "statement"           -> statement.map(sc => Json.obj(
                               "gold" -> sc.gold.asJson, "final" -> sc.finalFile.asJson, "equal" -> sc.equal.asJson)).asJson,
    "evidenceSource"      -> evidenceSource.asJson,
    "anomaly"             -> anomaly.asJson,
    "finalPath"           -> finalPath.asJson,
    "transcriptPath"      -> transcriptPath.asJson,
    "lastWords"           -> lastWords.asJson,
    "rateLimit"           -> rateLimit.asJson
  ).dropNullValues
}

object Outcome {
  def anomaly(entry: IndexEntry, msg: String, wallMs: Long): Outcome =
    Outcome(entry, solved = false, restated = false, None, Vector.empty, Vector.empty, "anomaly", 0, Vector.empty,
      wallMs, 0.0, Json.obj(), 0, None, "none", "none", None, None, None, None, Vector.empty, None,
      "unavailable: anomaly", Some(msg), None, None, "")
}

/** One obligation's three outputs: the report outcome, the fixtures.jsonl row, the results.jsonl rows. */
final case class Judged(outcome: Outcome, fixtureRow: Json, attempts: Vector[AttemptRow])

object Outcomes {

  /** The eval-proof-completion.v0 fixture row for an outcome, plus the
    * additive `restated`, `gate`, and `terminal` fields.
    */
  def fixtureRow(layout: RunLayout, o: Outcome): Json = {
    val stem = Scaffold.fixtureStem(o.entry)
    FixtureRow(
      fixtureId    = stem,
      module       = stem,
      fixturePath  = layout.workDir(o.entry.id).resolve(s"$stem.agda").toString,
      holesTotal   = 1,
      holesSolved  = if (o.solved) 1 else 0,
      fullySolved  = o.solved,
      finalStatus  = if (o.solved) "ok" else if (o.anomaly.isDefined) "crash" else "unsolved",
      elapsedMs    = o.wallMs,
      solvedPath   = if (o.solved) Some(layout.solved.resolve(s"$stem.agda").toString) else None,
      benchmarkId  = o.entry.id,
      searchStatus = o.terminal
    ).toJson.deepMerge(Json.obj(
      "restated" -> o.restated.asJson,
      "gate"     -> o.gate.map(_.gate).asJson,
      "terminal" -> o.terminal.asJson
    ).dropNullValues)
  }

  def judged(layout: RunLayout, o: Outcome, rows: Vector[AttemptRow]): Judged =
    Judged(o, fixtureRow(layout, o), rows)

  def anomaly(layout: RunLayout, entry: IndexEntry, msg: String): Judged =
    judged(layout, Outcome.anomaly(entry, msg, 0L), Vector.empty)

  /** The anomaly rules of the header, first that applies. */
  def anomalyOf(t: Transcript, iso: Isolation, verdict: Verdict, terminal: String): Option[String] = {
    val capped = t.result.exists(r => r.subtype.contains("max_turns") || r.subtype.contains("budget"))
    if (t.init.isEmpty) Some("no init record: the subject never started (see stderr.log)")
    else if (iso.arm.hasServer && !iso.mcpConnected) Some("agda server not connected in the subject's session")
    else if (iso.toolsDeferred) Some("agda tools were presented as deferred names")
    else if (iso.arm.hasServer && iso.missingAgdaTools.nonEmpty) Some(s"agda tools missing from the session: ${iso.missingAgdaTools.mkString(",")}")
    else if (iso.extraTools.nonEmpty) Some(s"tools presented beyond the protocol: ${iso.extraTools.mkString(",")}")
    else if (t.rateLimitRejected) Some(s"rate limited: ${t.rateLimits.map(_._1).distinct.mkString(",")}")
    else if (t.result.exists(_.isError) && !capped) Some(s"client error (${t.result.map(_.subtype).getOrElse("?")}): ${t.result.map(_.text.take(200)).getOrElse("")}")
    else if (terminal == "crash") Some("no result record: the subject's process ended without one (see stderr.log)")
    else if (verdict.agdaExit.contains(0) && verdict.evidenceSource.startsWith("unavailable"))
      Some(s"the final file type-checks but the extractor could not read it: ${verdict.evidenceSource.stripPrefix("unavailable: ")}")
    else if (verdict.checkUnusable) Some(s"check_file gave no usable verdict for the final file (exit ${verdict.checkExit.map(_.toString).getOrElse("none")}), so the escape and hole gates had nothing to read")
    else if (verdict.verdictsDisagree) Some(s"the gold verifier's agda (exit ${verdict.agdaExit.getOrElse(-1)}) and check_file (exit ${verdict.checkExit.getOrElse(-1)}) disagree on the final file")
    else None
  }

  /** Which instruments the subject used at all, from its calls. */
  def viaOf(t: Transcript): String =
    (t.uses.exists(_.name.startsWith(Arm.agdaPrefix)), t.uses.exists(_.name == Arm.bash)) match {
      case (true, true)  => "both"
      case (true, false) => "mcp"
      case (false, true) => "shell"
      case _             => "none"
    }

  /** Which instrument the subject took its LAST verdict from: the server's
    * `check_file` / `check_project`, or an `agda` run on the shell (batch or
    * interaction, both of which are Agda's own answer).  This is the column
    * the `both` arm exists for.
    */
  def verdictViaOf(t: Transcript, roots: ShellRoots): String = {
    def isShellAgda(u: ToolUse) =
      u.name == Arm.bash && ShellAudit.inspect(u.str("command").getOrElse(""), roots).commandClass.startsWith("agda-")
    t.uses.filter(u => u.name == "mcp__agda__check_file" || u.name == "mcp__agda__check_project" || isShellAgda(u))
      .lastOption.fold("none")(u => if (u.name == Arm.bash) "shell" else "mcp")
  }

  /** Judge one archived subject: transcript, isolation, gates, outcome. */
  def judgeOne(cfg: AgentBenchConfig, entry: IndexEntry, agda: Agda): IO[Judged] = {
    val layout    = cfg.layout
    val subj      = layout.subject(entry.id)
    val stem      = Scaffold.fixtureStem(entry)
    val finalFile = subj.finalFile(stem)
    val obFile    = cfg.projectRoot.resolve(entry.obligationPath)
    val goldFile  = cfg.projectRoot.resolve(entry.goldPath)
    for {
      obligation <- TextIO.read(obFile)
      finalText  <- TextIO.read(finalFile)
      stream     <- TextIO.read(subj.transcript).handleError(_ => "")
      record     <- TextIO.readJson(subj.runRecord).map(_.flatMap(SubjectRun.fromJson))
      // The arm and the roots are the subject's own record; an archive made
      // before that record existed is the server-only arm confined to the
      // work directory its server config names, so a copy of either re-judges
      // as the original.
      rec        <- TextIO.readJson(subj.record).map(_.flatMap(SubjectRecord.fromJson))
      legacyWork <- TextIO.readJson(subj.mcpConfig).map(_.flatMap(Audit.workDirOf).getOrElse(layout.workDir(entry.id)))
      arm         = rec.map(_.arm).getOrElse(cfg.arm)
      roots       = rec.map(_.roots).getOrElse(ShellRoots(legacyWork, Vector.empty, Vector.empty))
      workDir     = roots.workDir
      t           = Transcript.parse(stream)
      killed      = record.exists(_.killed)
      wallMs      = record.map(_.wallMs).getOrElse(t.result.map(_.durationMs).getOrElse(0L))
      iso         = Audit.isolation(t, arm, roots)
      terminal    = Audit.terminalOf(killed, t.result)
      verdict    <- Judge.judge(entry, obligation, finalText, goldFile, finalFile, agda, cfg.projectRoot, cfg.safe, cfg.serverTimeout.seconds)
      gate        = if (!iso.confined) Some(GateFailure("isolation", (iso.foreignToolUses.map(n => s"tool $n") ++ iso.violations).mkString("; ")))
                    else verdict.gate
      anomaly     = anomalyOf(t, iso, verdict, terminal)
      // An anomaly is not a result: a row the harness could not measure
      // properly is never published as a solve or a restatement, whatever
      // the file itself earned.
      solved      = anomaly.isEmpty && gate.isEmpty && verdict.solved
      restated    = anomaly.isEmpty && gate.isEmpty && verdict.restated
      outcome     = Outcome(
        entry             = entry,
        solved            = solved,
        restated          = restated,
        gate              = gate,
        evidence          = verdict.evidence,
        addedImports      = verdict.addedImports,
        terminal          = terminal,
        turns             = t.result.map(_.numTurns).getOrElse(0),
        toolCalls         = t.toolCounts,
        wallMs            = wallMs,
        costUsd           = t.result.map(_.costUsd).getOrElse(0.0),
        tokens            = t.result.map(_.tokens).getOrElse(Json.obj()),
        permissionDenials = t.result.map(_.permissionDenials).getOrElse(0),
        isolation         = Some(iso),
        via               = viaOf(t),
        verdictVia        = verdictViaOf(t, roots),
        agdaExit          = verdict.agdaExit,
        agdaMs            = verdict.agdaMs,
        agdaTail          = verdict.agdaTail,
        checkExit         = verdict.checkExit,
        checkCodes        = verdict.checkCodes,
        statement         = verdict.statement,
        evidenceSource    = verdict.evidenceSource,
        anomaly           = anomaly,
        finalPath         = Some(layout.relative(finalFile)),
        transcriptPath    = Some(subj.transcriptRel),
        lastWords         = t.result.map(_.text.take(600)).getOrElse(""),
        rateLimit         = t.rateLimitMax.map(u => Json.obj(
                              "maxUtilization" -> u.asJson,
                              "statuses"       -> t.rateLimits.map(_._1).distinct.asJson))
      )
      _          <- if (solved) IO.blocking {
                      Files.createDirectories(layout.solved)
                      Files.copy(finalFile, layout.solved.resolve(s"$stem.agda"), StandardCopyOption.REPLACE_EXISTING); ()
                    } else IO.unit
      _          <- TextIO.write(subj.outcome, outcome.toJson.spaces2)
      _          <- IO.println(f">> ${entry.id}%-36s ${if (solved) "SOLVED" else if (restated) "RESTATED" else gate.map(g => s"gate:${g.gate}").getOrElse("unsolved")}%-20s turns=${outcome.turns}%3d calls=${outcome.toolCallsTotal}%3d via=${outcome.via}%-5s verdict=${outcome.verdictVia}%-5s cost=$$${outcome.costUsd}%.3f terminal=${outcome.terminal}${t.rateLimitMax.fold("")(u => f" window=$u%.2f")}${anomaly.fold("")(a => s"  ANOMALY: $a")}")
    } yield judged(layout, outcome, Audit.attemptRows(entry, workDir.resolve(s"$stem.agda"), t, subj.transcriptRel))
  }
}
