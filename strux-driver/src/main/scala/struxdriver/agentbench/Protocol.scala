/** ============================================================================
  *  Protocol.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Protocol.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  The protocol of a run (issue #154): every knob that decides what a subject
  *  sees and how its file is judged (the arm, the model, the caps, the
  *  client's flags and version, the tools, the subset of the server's tools
  *  the subjects are shown (`expose`, issue #191, absent when they see all),
  *  the directories the file tools may read, the servers' Agda flags, the
  *  prompts by digest, the index and the corpora by path).  A run id is one
  *  arm (issue #162): the three attribution arms are three run ids, and `arm`
  *  is the field that says which.  A fresh run writes it to `protocol.json`
  *  before any subject spawns, and the report's config block is this record
  *  plus the run's own knobs.  A run id is one protocol: `--resume` keeps an
  *  archived subject only when the protocol on record is the current one,
  *  field for field, so a report never labels subjects of two protocols with
  *  one config.  Every input the run reads is identified by content, not by
  *  path (`inputs`): the index, the two corpora, the server binary, and the
  *  extractor binary are recorded with their SHA-256, so regenerating one in
  *  place, or rebuilding a binary, refuses the resume instead of mixing two
  *  environments in one report.  A run made before the record existed has
  *  archived subjects and no `protocol.json`; it is not resumed.
  *
  *  The endpoint (issue #237).  `endpoint` is the endpoint the subjects are
  *  served by, read from the environment they are given (`Endpoint`: the base
  *  URL or `absent`, and the client's model variables when set, never a
  *  credential), so a run on another provider names it, and a resume under a
  *  changed endpoint is refused naming the field, as a changed model is.  The
  *  price table the report prices tokens at (`--prices`) is an input like the
  *  corpora, by digest, under the name of the run's own copy (`prices.json`,
  *  which a resume prices at), so a resume under a changed table is refused,
  *  and an edit to the committed one is not a change.  A protocol recorded
  *  before issue #237 has neither the endpoint nor the table, and reads as the
  *  client's default endpoint and the current table (`differences`), as one
  *  recorded before `--expose` reads as the full surface, so a run in flight
  *  across the change can still be resumed.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.IO
import cats.syntax.all._
import io.circe.Json
import io.circe.syntax._
import java.nio.file.{Files, Path}

import struxdriver.io.TextIO
import struxdriver.search.Digest

object Protocol {

  private def abs(p: Path): String = p.toAbsolutePath.normalize.toString

  /** One input file, by path and by content. */
  private def fileId(p: Path): IO[Json] =
    Digest.sha256Hex(p).map(d => Json.obj("path" -> abs(p).asJson, "sha256" -> d.asJson))

  /** What the run reads, by content: the index, the binaries, the corpora
    * (whose provenance block already carries a digest and the assembly's own
    * provenance), and the price table (issue #237).  The project root is a
    * path: it is where everything else is resolved from, and its content is
    * the repository.
    */
  def inputs(cfg: AgentBenchConfig, corpora: Json, prices: PriceTable): IO[Json] =
    for {
      index  <- fileId(cfg.index)
      server <- cfg.serverBin.traverse(fileId)
      extr   <- cfg.agdaJsonBin.traverse(fileId)
    } yield Json.obj(
      "projectRoot" -> abs(cfg.projectRoot).asJson,
      "index"       -> index,
      "serverBin"   -> server.asJson,
      "agdaJsonBin" -> extr.asJson,
      "corpora"     -> corpora,
      // The table the run prices at is its own copy, `prices.json` in the
      // run root, by digest: the same record whether a fresh run copied it
      // there or a resume reads it back.
      "prices"      -> Json.obj("path" -> Layout.pricesFile.asJson, "sha256" -> prices.sha256.asJson)
    ).dropNullValues

  /** The protocol as JSON: null-valued knobs (an unset model) are dropped, so
    * the record and the comparison see the same keys.
    */
  def of(cfg: AgentBenchConfig, version: String, sysP: String, userT: String, inputs: Json, addDirs: Vector[Path] = Vector.empty): Json = {
    val subject = SubjectConfig.of(cfg, sysP, userT, addDirs)
    Json.obj(
      "arm"              -> cfg.arm.name.asJson,
      "model"            -> cfg.model.asJson,
      // Which endpoint served the model: the base URL or `absent`, plus the
      // client's model variables when set (issue #237).
      "endpoint"         -> cfg.endpoint.toJson,
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
      // The tools a subject of this arm is given: its built-ins, and the agda
      // tools an arm with the server must have (exactly the exposed ones under
      // --expose, issue #191).  What the server actually presented is recorded
      // per subject (Isolation.agdaToolsPresented), because the full surface
      // grows between runs.
      "tools"            -> (cfg.arm.builtinTools.toVector.sorted ++
                             (if (cfg.arm.hasServer) Subject.requiredAgdaTools(cfg.expose) else Vector.empty)).asJson,
      // Absent (null, dropped below) when the server presents every tool, so
      // a protocol recorded before --expose existed is still this one.
      "expose"           -> cfg.expose.asJson,
      "addDirs"          -> addDirs.map(_.toString).asJson,
      "persistSessions"  -> cfg.persistSessions.asJson,
      "inputs"           -> inputs,
      "prompts" -> Json.obj(
        "system" -> Json.obj("path" -> "prompts/system-prompt.md".asJson, "sha256" -> TextIO.sha256(sysP).asJson),
        "user"   -> Json.obj("path" -> "prompts/user-prompt.md".asJson,   "sha256" -> TextIO.sha256(userT).asJson))
    ).dropNullValues
  }

  /** A protocol recorded before issue #237, read as one recorded after it:
    * no `endpoint` is the client's default, and no price table is the
    * current one.  A record that has them is unchanged.
    */
  private def since237(recorded: Json, current: Json): Json = {
    val c        = recorded.hcursor
    val endpoint = if (c.downField("endpoint").succeeded || !current.hcursor.downField("endpoint").succeeded) recorded
                   else recorded.mapObject(_.add("endpoint", Endpoint(Vector(Endpoint.baseUrlVar -> Endpoint.absent)).toJson))
    (endpoint.hcursor.downField("inputs").focus, current.hcursor.downField("inputs").downField("prices").focus) match {
      case (Some(in), Some(p)) if !in.hcursor.downField("prices").succeeded =>
        endpoint.mapObject(_.add("inputs", in.mapObject(_.add("prices", p))))
      case _ => endpoint
    }
  }

  /** The fields on which two protocols differ, `name: recorded -> current`,
    * over the union of their keys (a key one side lacks reads `absent`).
    */
  def differences(recorded: Json, current: Json): Vector[String] = {
    val was = since237(recorded, current)
    def field(j: Json, k: String): String = j.hcursor.downField(k).focus.map(_.noSpaces).getOrElse("absent")
    val keys = (was.asObject.map(_.keys.toVector).getOrElse(Vector.empty) ++
                current.asObject.map(_.keys.toVector).getOrElse(Vector.empty)).distinct.sorted
    keys.collect { case k if field(was, k) != field(current, k) => s"$k: ${field(was, k)} -> ${field(current, k)}" }
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
