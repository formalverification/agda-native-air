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
  *  once the session is over: whether the instrument was in its hands (for an
  *  arm with the server, that it connected and the required tools arrived
  *  eagerly), whether it stayed inside the protocol (no tool beyond the arm's
  *  set; no Read outside the arm's read roots and no Edit outside the work
  *  directory that succeeded, with refused attempts counted apart; and, for an
  *  arm with a shell, no Bash command naming a path outside those roots), how
  *  the session ended, and the `fill_hole` probes it made as
  *  eval-proof-completion.v0 attempt rows.
  *
  *  The arm decides what "inside the protocol" means (issue #162), so every
  *  expectation below is read off it rather than fixed: a shell arm has no
  *  server to connect and no agda tools to miss, and its Bash calls are
  *  audited by ShellAudit, which is the only confinement Bash has.  A run
  *  with `--expose` (issue #191) narrows the agda half of the expectation to
  *  the exposed tools, both ways: each must arrive, and no other may.
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
  arm:                Arm,
  mcpConnected:       Boolean,
  agdaToolsPresented: Vector[String],
  missingAgdaTools:   Vector[String],
  extraTools:         Vector[String],
  toolsDeferred:      Boolean,
  foreignToolUses:    Vector[String],
  violations:         Vector[String],
  deniedPaths:        Vector[String],
  shellClasses:       Vector[(String, Int)] = Vector.empty,
  exposed:            Option[Vector[String]] = None
) {
  /** The instrument was in the subject's hands: for an arm with the server,
    * that it connected and every required tool arrived eagerly; for a shell
    * arm, that the tools arrived eagerly at all.
    */
  def instrumentOk: Boolean =
    (!arm.hasServer || (mcpConnected && missingAgdaTools.isEmpty)) && !toolsDeferred

  /** Nothing outside the protocol was done: no foreign tool, no successful
    * escape by a file tool, no shell command outside the arm's roots.
    */
  def confined: Boolean = foreignToolUses.isEmpty && violations.isEmpty

  def toJson: Json = Json.obj(
    "arm"                -> arm.name.asJson,
    "mcpConnected"       -> mcpConnected.asJson,
    "agdaToolsPresented" -> agdaToolsPresented.asJson,
    "missingAgdaTools"   -> missingAgdaTools.asJson,
    "extraTools"         -> extraTools.asJson,
    "toolsDeferred"      -> toolsDeferred.asJson,
    "foreignToolUses"    -> foreignToolUses.asJson,
    "violations"         -> violations.asJson,
    "deniedPaths"        -> deniedPaths.asJson,
    "shellClasses"       -> Json.obj(shellClasses.map { case (c, k) => c -> k.asJson }: _*),
    // Only under --expose, so the audit of a full-surface run keeps its shape.
    "exposed"            -> exposed.asJson
  ).dropNullValues
}

/** What a run gave one subject: the arm, the roots its tools and commands
  * were allowed (issue #162), and the server tools it was shown when the run
  * exposed a subset (issue #191).  Written beside the subject before it spawns and
  * read back by the judge, so a re-judge audits a run under the arm and the
  * roots it actually had -- not the operator's current `--arm`, and not
  * today's nix store paths, which a toolchain bump would move.  An archive
  * without one is the server-only arm confined to its work directory, which is
  * what the runs made before this record existed were.
  */
final case class SubjectRecord(arm: Arm, roots: ShellRoots, expose: Option[Vector[String]] = None) {
  def toJson: Json = Json.obj(
    "arm"       -> arm.name.asJson,
    "workDir"   -> roots.workDir.toString.asJson,
    "readRoots" -> roots.readRoots.map(_.toString).asJson,
    "corpora"   -> roots.corpora.map(_.toString).asJson,
    "expose"    -> expose.asJson
  ).dropNullValues
}

object SubjectRecord {
  def fromJson(j: Json): Option[SubjectRecord] = {
    val c = j.hcursor
    for {
      arm  <- c.get[String]("arm").toOption.flatMap(s => Arm.parse(s).toOption)
      work <- c.get[String]("workDir").toOption.map(Paths.get(_))
    } yield SubjectRecord(arm, ShellRoots(
      workDir   = work,
      readRoots = c.get[Vector[String]]("readRoots").getOrElse(Vector.empty).map(Paths.get(_)),
      corpora   = c.get[Vector[String]]("corpora").getOrElse(Vector.empty).map(Paths.get(_))),
      expose    = c.get[Vector[String]]("expose").toOption)
  }
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

  /** The audit of one transcript under one arm, against the roots the run gave
    * that subject.  A Read may name any of the arm's read roots (the work
    * directory, the libraries' sources, the row's corpus); an Edit only the
    * work directory, since the libraries are not the subject's to change.
    * Under `expose` (issue #191) the exposed agda tools are both the floor
    * and the ceiling.
    */
  def isolation(t: Transcript, arm: Arm, roots: ShellRoots, expose: Option[Vector[String]] = None): Isolation = {
    val init  = t.init
    val tools = init.map(_.tools).getOrElse(Vector.empty)
    val work  = roots.workDir.toAbsolutePath.normalize
    def resolved(p: String): Path = {
      val q = Paths.get(p)
      (if (q.isAbsolute) q else work.resolve(q)).normalize
    }
    val outside = t.filePaths(Subject.fileTools).filter { case (u, _, p) =>
      val q = resolved(p)
      if (u.name == "Edit") !q.startsWith(work) else !roots.canRead(q)
    }
    val (shellViolations, shellClasses) =
      if (arm.hasShell) ShellAudit.auditCalls(t, roots) else (Vector.empty[String], Vector.empty[(String, Int)])
    Isolation(
      arm                = arm,
      mcpConnected       = init.exists(_.mcpServers.contains(("agda", "connected"))),
      agdaToolsPresented = tools.filter(_.startsWith(Arm.agdaPrefix)),
      missingAgdaTools   = if (arm.hasServer) Subject.requiredAgdaTools(expose).filterNot(tools.contains) else Vector.empty,
      extraTools         = tools.filterNot(arm.presents(_, expose)),
      toolsDeferred      = t.toolsDeferred,
      foreignToolUses    = t.uses.map(_.name).filterNot(arm.presents(_, expose)).distinct,
      violations         = outside.collect { case (u, r, p) if !r.exists(_.isError) => s"${u.name} $p" } ++ shellViolations,
      deniedPaths        = outside.collect { case (u, r, p) if r.exists(_.isError) => s"${u.name} $p" },
      shellClasses       = shellClasses,
      exposed            = expose
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
