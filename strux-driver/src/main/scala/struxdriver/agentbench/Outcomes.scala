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
  *  subject's archive alone: read the final file, the transcript, and the
  *  process record; audit the transcript (Audit.scala); run the gates
  *  (Judge.scala); assemble the outcome, the eval-proof-completion.v0
  *  fixture row, and the attempt rows; write the verdict beside the archive.
  *  Because this step reads only what the runner archived, `--rejudge` can
  *  redo it for a finished run without a model call.
  *
  *  Anomaly rules
  *  -------------
  *  A row is an anomaly, not a result, when the subject never had the
  *  instrument: no init record (the client never started), the agda server
  *  not connected, the tools presented as deferred names, a tool missing, the
  *  account's rate limit refusing service, or a client error that is not one
  *  of the stated caps; and when the two batch verdicts on the final file
  *  (the gold verifier's agda and the server's check_file) disagree, which is
  *  a configuration fact, not a fact about the proof.  The gates still run on
  *  the file, so the anomaly keeps its diagnostics, and the run exits
  *  non-zero.
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
      wallMs, 0.0, Json.obj(), 0, None, None, None, None, None, Vector.empty, None, "unavailable: anomaly", Some(msg), None, None, "")
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

  /** Judge one archived subject: transcript, isolation, gates, outcome. */
  def judgeOne(cfg: AgentBenchConfig, entry: IndexEntry, agda: Agda): IO[Judged] = {
    val layout    = cfg.layout
    val subj      = layout.subject(entry.id)
    val stem      = Scaffold.fixtureStem(entry)
    val finalFile = subj.finalFile(stem)
    val workDir   = layout.workDir(entry.id)
    val obFile    = cfg.projectRoot.resolve(entry.obligationPath)
    val goldFile  = cfg.projectRoot.resolve(entry.goldPath)
    for {
      obligation <- TextIO.read(obFile)
      finalText  <- TextIO.read(finalFile)
      stream     <- TextIO.read(subj.transcript).handleError(_ => "")
      record     <- TextIO.readJson(subj.runRecord).map(_.flatMap(SubjectRun.fromJson))
      t           = Transcript.parse(stream)
      killed      = record.exists(_.killed)
      wallMs      = record.map(_.wallMs).getOrElse(t.result.map(_.durationMs).getOrElse(0L))
      iso         = Audit.isolation(t, workDir)
      verdict    <- Judge.judge(entry, obligation, finalText, goldFile, finalFile, agda, cfg.projectRoot, cfg.safe, cfg.serverTimeout.seconds)
      gate        = if (!iso.confined) Some(GateFailure("isolation", (iso.foreignToolUses.map(n => s"tool $n") ++ iso.violations).mkString("; ")))
                    else verdict.gate
      capped      = t.result.exists(r => r.subtype.contains("max_turns") || r.subtype.contains("budget"))
      anomaly     = if (t.init.isEmpty) Some("no init record: the subject never started (see stderr.log)")
                    else if (!iso.mcpConnected) Some("agda server not connected in the subject's session")
                    else if (iso.toolsDeferred) Some("agda tools were presented as deferred names")
                    else if (iso.missingAgdaTools.nonEmpty) Some(s"agda tools missing from the session: ${iso.missingAgdaTools.mkString(",")}")
                    else if (t.rateLimitRejected) Some(s"rate limited: ${t.rateLimits.map(_._1).distinct.mkString(",")}")
                    else if (t.result.exists(_.isError) && !capped) Some(s"client error (${t.result.map(_.subtype).getOrElse("?")}): ${t.result.map(_.text.take(200)).getOrElse("")}")
                    else if (verdict.verdictsDisagree) Some(s"the gold verifier's agda (exit ${verdict.agdaExit.getOrElse(-1)}) and check_file (exit ${verdict.checkExit.getOrElse(-1)}) disagree on the final file")
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
        terminal          = Audit.terminalOf(killed, t.result),
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
      _          <- IO.println(f">> ${entry.id}%-36s ${if (solved) "SOLVED" else if (restated) "RESTATED" else gate.map(g => s"gate:${g.gate}").getOrElse("unsolved")}%-20s turns=${outcome.turns}%3d calls=${outcome.toolCallsTotal}%3d cost=$$${outcome.costUsd}%.3f terminal=${outcome.terminal}${t.rateLimitMax.fold("")(u => f" window=$u%.2f")}${anomaly.fold("")(a => s"  ANOMALY: $a")}")
    } yield judged(layout, outcome, Audit.attemptRows(entry, workDir.resolve(s"$stem.agda"), t, subj.transcriptRel))
  }
}
