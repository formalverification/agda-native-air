/** ============================================================================
  *  Protocol.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Protocol.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  The protocol of a run (issue #154): every knob that decides what a
  *  subject sees and how its file is judged (the model, the caps, the
  *  client's flags and version, the tools, the servers' Agda flags, the
  *  prompts by digest, the index and the corpora by path).  A fresh run
  *  writes it to `protocol.json` before any subject spawns, and the report's
  *  config block is this record plus the run's own knobs.  A run id is one
  *  protocol: `--resume` keeps an archived subject only when the protocol on
  *  record is the current one, field for field, so a report never labels
  *  subjects of two protocols with one config.  A run made before the record
  *  existed has archived subjects and no `protocol.json`; it is not resumed.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.IO
import io.circe.Json
import io.circe.syntax._
import java.nio.file.{Files, Path}

import struxdriver.io.TextIO

object Protocol {

  private def abs(p: Path): String = p.toAbsolutePath.normalize.toString

  /** The protocol as JSON: null-valued knobs (an unset model) are dropped, so
    * the record and the comparison see the same keys.
    */
  def of(cfg: AgentBenchConfig, version: String, sysP: String, userT: String): Json = {
    val subject = SubjectConfig.of(cfg, sysP, userT)
    Json.obj(
      "index"            -> abs(cfg.index).asJson,
      "model"            -> cfg.model.asJson,
      "maxTurns"         -> cfg.maxTurns.asJson,
      "wallCapSec"       -> cfg.wallCapSec.asJson,
      "maxBudgetUsd"     -> cfg.maxBudgetUsd.asJson,
      "safe"             -> cfg.safe.asJson,
      "serverTimeout"    -> cfg.serverTimeout.asJson,
      "agdaFlags"        -> cfg.agdaFlags.asJson,
      "subjectAgdaFlags" -> subject.agdaFlags.asJson,
      "claudeVersion"    -> version.asJson,
      "claudeFlags"      -> Subject.fixedFlags(subject).asJson,
      "envAdded"         -> Subject.envAdded.asJson,
      "envRemovedPrefix" -> Subject.envRemovedPrefix.asJson,
      "tools"            -> (Subject.fileTools.toVector.sorted ++ Subject.agdaTools).asJson,
      "persistSessions"  -> cfg.persistSessions.asJson,
      "corpusStdlib"     -> cfg.corpusStdlib.map(abs).asJson,
      "corpusAlgebras"   -> cfg.corpusAlgebras.map(abs).asJson,
      "prompts" -> Json.obj(
        "system" -> Json.obj("path" -> "prompts/system-prompt.md".asJson, "sha256" -> TextIO.sha256(sysP).asJson),
        "user"   -> Json.obj("path" -> "prompts/user-prompt.md".asJson,   "sha256" -> TextIO.sha256(userT).asJson))
    ).dropNullValues
  }

  /** The fields on which two protocols differ, `name: recorded -> current`,
    * over the union of their keys (a key one side lacks reads `absent`).
    */
  def differences(recorded: Json, current: Json): Vector[String] = {
    def field(j: Json, k: String): String = j.hcursor.downField(k).focus.map(_.noSpaces).getOrElse("absent")
    val keys = (recorded.asObject.map(_.keys.toVector).getOrElse(Vector.empty) ++
                current.asObject.map(_.keys.toVector).getOrElse(Vector.empty)).distinct.sorted
    keys.collect { case k if field(recorded, k) != field(current, k) => s"$k: ${field(recorded, k)} -> ${field(current, k)}" }
  }

  /** Admit the run: record a fresh run's protocol; under `--resume`, refuse a
    * run id whose record differs or whose subjects predate the record.
    */
  def admit(layout: RunLayout, current: Json, resume: Boolean): IO[Unit] = {
    val runId = layout.runRoot.getFileName
    def refuse(why: String): IO[Unit] =
      IO.raiseError(new RuntimeException(s"resume refused: run $runId $why; pass a new --run-id"))
    def record: IO[Unit] = TextIO.write(layout.protocol, current.spaces2)
    TextIO.readJson(layout.protocol).flatMap {
      case Some(recorded) if resume =>
        differences(recorded, current) match {
          case Vector() => IO.unit
          case ds       => refuse(s"was made under a different protocol (${ds.mkString("; ")})")
        }
      case None if resume =>
        IO.blocking(Files.isDirectory(layout.runRoot.resolve("subjects"))).flatMap {
          case true  => refuse("has archived subjects but no protocol.json (made before the protocol was recorded)")
          case false => record
        }
      case _ => record
    }
  }
}
