/** ============================================================================
  *  Audit.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Audit.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  What a subject's transcript says about the subject (issue #154), read
  *  once the session is over: whether the instrument was in its hands (the
  *  server connected, the thirteen tools presented and not deferred), whether
  *  it stayed inside the protocol (no tool beyond Read, Edit, and the
  *  thirteen; no Read or Edit outside the work directory that succeeded, with
  *  refused attempts counted apart), how the session ended, and the
  *  `fill_hole` probes it made as eval-proof-completion.v0 attempt rows.
  *
  *  Design notes
  *  ------------
  *  - The probe rows decode each `fill_hole` reply with the same strict
  *    decoder the search loop uses (`FillHoleBody` in Wire.scala), so the
  *    two instruments read one wire contract; a refused call, or a reply the
  *    decoder does not recognize, is a `crash` row, exactly as Oracle.probe
  *    files an `isError` reply.
  *  - Pure functions over a parsed transcript; TranscriptSpec pins them on a
  *    captured stream and on a synthetic one that exhibits every branch.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import io.circe.Json
import io.circe.syntax._
import java.nio.file.{Path, Paths}

import struxdriver.benchmark.{Obligation => IndexEntry}
import struxdriver.search.{AttemptRow, FillHoleBody, Scaffold}

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

object Audit {

  /** How the session ended, in the report's vocabulary: `completed`,
    * `max_turns`, `budget`, `wall_cap` (killed from outside), `crash` (no
    * result record), or the client's own subtype otherwise.
    */
  def terminalOf(killed: Boolean, result: Option[ResultRecord]): String =
    if (killed) "wall_cap"
    else result match {
      case None    => "crash"
      case Some(r) => r.subtype match {
        case "success"                    => "completed"
        case s if s.contains("max_turns") => "max_turns"
        case s if s.contains("budget")    => "budget"
        case s                            => s
      }
    }

  /** The work directory the subject's own server config names: the parent
    * of the staged file its check command ends with.  A re-judge of an
    * archive copied elsewhere audits the transcript's paths against the
    * directory the subject had, not the copy's.
    */
  def workDirOf(mcpConfig: Json): Option[Path] = {
    val args = mcpConfig.hcursor.downField("mcpServers").downField("agda").get[Vector[String]]("args").toOption.getOrElse(Vector.empty)
    args.sliding(2).collectFirst { case Vector("--check-command", cmd) => cmd }
      .flatMap(cmd => cmd.trim.split("\\s+").lastOption)
      .map(Paths.get(_)).filter(_.isAbsolute).flatMap(f => Option(f.getParent))
  }

  def isolation(t: Transcript, workDir: Path): Isolation = {
    val init    = t.init
    val tools   = init.map(_.tools).getOrElse(Vector.empty)
    val allowed = Subject.fileTools ++ Subject.agdaTools
    val root    = workDir.toAbsolutePath.normalize
    val outside = t.filePaths(Subject.fileTools).filter { case (_, _, p) =>
      val q = Paths.get(p)
      !(if (q.isAbsolute) q else workDir.resolve(q)).normalize.startsWith(root)
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

  /** One attempt row per `fill_hole` the subject probed, in call order. */
  def attemptRows(entry: IndexEntry, workFile: Path, t: Transcript, transcriptRel: String): Vector[AttemptRow] = {
    val stem = Scaffold.fixtureStem(entry)
    t.usesOf("mcp__agda__fill_hole").zipWithIndex.map { case (u, i) =>
      val body = t.resultOf(u).map(_.reply).filterNot(_.isError).flatMap(_.decodeAs[FillHoleBody].toOption)
      AttemptRow(
        fixtureId     = stem,
        benchmarkId   = entry.id,
        module        = stem,
        fixturePath   = workFile.toString,
        holeIndex     = u.int("holeIndex").getOrElse(0),
        holeLine      = u.int("line").getOrElse(-1),
        holeCol       = u.int("column").orElse(u.int("col")).getOrElse(-1),
        candidateRank = i + 1,
        candidate     = u.str("candidate").getOrElse(""),
        status        = body.map(_.status).getOrElse("crash"),
        elapsedMs     = body.map(_.elapsedMs).getOrElse(0L),
        rc            = body.flatMap(_.exitCode).getOrElse(-1),
        logPath       = transcriptRel
      )
    }
  }
}
