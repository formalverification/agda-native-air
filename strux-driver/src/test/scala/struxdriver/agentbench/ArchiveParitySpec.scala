/** ============================================================================
  *  ArchiveParitySpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/ArchiveParitySpec.scala
  *
  *  Purpose
  *  -------
  *  Guards the archive against the harness's own changes (issue #239): for
  *  every archived subject under `reports/agent-bench/`, the transcript
  *  reading the judge makes today (the isolation audit, the `via` columns,
  *  how the session ended, the turns, the calls per tool, the client's cost
  *  and tokens, the permission denials, the rate-limit block, the last
  *  words) is recomputed from the archived transcript and the subject's own
  *  records and compared with its archived `outcome.json`, field for field.
  *  A change to Transcript, Audit, Outcomes, or Pricing that would move a
  *  Claude row on a re-judge fails here, with no Agda and no model call.
  *
  *  The few subjects whose archived reading predates a later, deliberate
  *  change to the audit are listed in `known`, each with the reason, so the
  *  list can only shrink.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import io.circe.Json
import io.circe.syntax._
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths}
import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import scala.jdk.CollectionConverters._

final class ArchiveParitySpec extends AnyFunSuite with Matchers {

  /** The archive, from the test's working directory (strux-driver/) or the repository root. */
  private val archive: Option[Path] =
    Vector(Paths.get("../reports/agent-bench"), Paths.get("reports/agent-bench")).find(Files.isDirectory(_))

  private def read(p: Path): Option[String] =
    if (Files.isRegularFile(p)) Some(new String(Files.readAllBytes(p), StandardCharsets.UTF_8)) else None
  private def json(p: Path): Option[Json] = read(p).flatMap(io.circe.parser.parse(_).toOption)

  private def subjects(root: Path): Vector[Path] = {
    val runs = Files.list(root)
    try runs.iterator.asScala.toVector.map(_.resolve("subjects")).filter(Files.isDirectory(_)).sortBy(_.toString).flatMap { s =>
      val ds = Files.list(s)
      try ds.iterator.asScala.toVector.filter(Files.isDirectory(_)).sortBy(_.toString) finally ds.close()
    } finally runs.close()
  }

  /** The fields recomputed for one subject, as its outcome.json names them. */
  private def reading(dir: Path): Option[Vector[(String, Json)]] =
    read(dir.resolve("transcript.jsonl")).map { stream =>
      val t          = Transcript.parse(stream)
      val rec        = json(dir.resolve("subject.json")).flatMap(SubjectRecord.fromJson)
      val legacyWork = json(dir.resolve("mcp.json")).flatMap(Audit.workDirOf).getOrElse(dir)
      val arm        = rec.map(_.arm).getOrElse(Arm.default)
      val expose     = rec.flatMap(_.expose)
      val roots      = rec.map(_.roots).getOrElse(ShellRoots(legacyWork, Vector.empty, Vector.empty))
      val run        = json(dir.resolve("run.json")).flatMap(SubjectRun.fromJson)
      // A Codex subject is audited and costed under its harness, as judgeOne does (#239).
      val harness    = rec.map(_.harness).getOrElse(Harness.Claude)
      val iso        = Audit.isolation(t, arm, roots, expose, harness)
      Vector(
        "isolation"         -> iso.toJson,
        "via"               -> Outcomes.viaOf(t).asJson,
        "verdictVia"        -> Outcomes.verdictViaOf(t, roots).asJson,
        "terminal"          -> Audit.terminalOf(run.exists(_.killed), t.result).asJson,
        "turns"             -> t.result.map(_.numTurns).getOrElse(0).asJson,
        "toolCalls"         -> Json.obj(t.toolCounts.map { case (n, k) => n -> k.asJson }: _*),
        "costUsd"           -> t.result.map(_.costUsd).getOrElse(if (harness == Harness.Claude) Some(0.0) else None).asJson,
        "tokens"            -> t.result.map(_.tokens).getOrElse(Json.obj()),
        "permissionDenials" -> t.result.map(_.permissionDenials).getOrElse(0).asJson,
        "rateLimit"         -> t.rateLimitMax.map(u => Json.obj(
                                 "maxUtilization" -> u.asJson,
                                 "statuses"       -> t.rateLimits.map(_._1).distinct.asJson)).asJson,
        "lastWords"         -> t.result.map(_.text.take(600)).getOrElse("").asJson)
    }

  /** Subjects whose archived reading predates a deliberate change, by
    * `run/subjects/id field`, with the reason (measured 2026-10-13 against
    * the judge at f9fab0d0, before issue #239 touched it).
    */
  private val known: Map[String, String] = {
    val beforeArm = "the archived isolation block predates the arm's fields (arm, agdaToolsPresented, shellClasses); never re-judged"
    val window    = "the archived rate-limit block predates reading the five-hour window under unifiedWindows; never re-judged"
    Map(
      "arm184-both-1/subjects/algebras-kernels-ker-con isolation" ->
        "judged 2026-09-25, before the audit read a call's own literal bindings (0f040501, 2026-09-27): two violations it no longer reports",
      "cost-opus-1/subjects/algebras-homs-mon-to-hom isolation"       -> beforeArm,
      "cost-opus-1/subjects/stdlib-nat-plus-comm isolation"           -> beforeArm,
      "cost-sonnet-1/subjects/algebras-homs-mon-to-hom isolation"     -> beforeArm,
      "cost-sonnet-1/subjects/stdlib-nat-plus-comm isolation"         -> beforeArm,
      "smoke-haiku-1/subjects/stdlib-nat-plus-identity-l isolation"   -> beforeArm,
      "cost-sonnet-1/subjects/algebras-homs-mon-to-hom rateLimit"     -> window,
      "cost-sonnet-1/subjects/stdlib-nat-plus-comm rateLimit"         -> window)
  }

  test("every archived subject's transcript reading is its archived outcome's, field for field") {
    val root = archive.getOrElse(cancel("no reports/agent-bench archive in reach"))
    val all  = subjects(root)
    all.size should be > 1000
    val diffs = all.flatMap { dir =>
      val outcome = json(dir.resolve("outcome.json"))
      (reading(dir), outcome) match {
        case (Some(fields), Some(o)) =>
          // An archived outcome without a field (made before it existed) is not compared on it.
          fields.collect { case (k, v) if o.hcursor.downField(k).succeeded && o.hcursor.downField(k).focus.exists(_ != v) &&
                                          !(v.isNull && o.hcursor.downField(k).focus.exists(_.isNull)) =>
            s"${root.relativize(dir)} $k"
          }
        case _ => Vector.empty
      }
    }
    val unexplained = diffs.filterNot(known.contains)
    withClue(unexplained.take(40).mkString("\n", "\n", s"\n(${unexplained.size} in all)\n")) { unexplained shouldBe Vector.empty }
    // The list can only shrink: an entry that no longer differs is removed.
    known.keys.toVector.sorted.filterNot(diffs.contains) shouldBe Vector.empty
  }
}
