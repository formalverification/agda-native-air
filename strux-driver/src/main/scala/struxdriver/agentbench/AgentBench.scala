/** ============================================================================
  *  AgentBench.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/AgentBench.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  The entry point of the agent-in-the-loop evaluation (issue #154,
  *  [M1-10]): a frontier model driving agda-mcp over the benchmark, one fresh
  *  `claude -p` session per obligation, judged by the gold verifier's own
  *  invocation plus the statement gates, and reported in the loop's shape.
  *  `--arm` (issue #162) decides which instrument the subjects get -- the
  *  server, a shell with the pinned `agda`, or both -- and the arm chooses the
  *  prompts; the libraries' source roots come from the Agda registry and are
  *  given to the file tools on every arm, so the arms differ in their
  *  instrument and in nothing else.
  *  This file only wires the parts together: Cli (the arguments), Layout
  *  (where a run keeps things), Run (stage, spawn, archive), Outcomes (the
  *  judge step over the archive), Report (the outputs).  Like the loop, an
  *  anomaly never aborts the sweep and always makes the run exit non-zero.
  *
  *  Invocation: see the `agent-bench` Make targets, or `Cli.usage`.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.{ExitCode, IO, IOApp}
import cats.syntax.all._
import io.circe.Json
import io.circe.syntax._
import java.nio.file.Files

import struxdriver.benchmark.GoldVerifier
import struxdriver.io.TextIO
import struxdriver.search.{McpClient, ProofSearchLoop, Scaffold, ServerConfig}
import scala.concurrent.duration._

object AgentBench extends IOApp {

  def run(args: List[String]): IO[ExitCode] =
    Cli.parse(args) match {
      case Left(err)  => IO.println(s"error: $err\n\n${Cli.usage}").as(ExitCode.Error)
      case Right(cfg) => runHarness(cfg)
    }

  private def runHarness(cfg: AgentBenchConfig): IO[ExitCode] = {
    val layout = cfg.layout
    for {
      entries  <- Scaffold.readIndex(cfg.index, cfg.ids)
      _        <- IO.raiseWhen(entries.isEmpty)(new RuntimeException("no obligations matched"))
      _        <- IO.blocking(Files.createDirectories(layout.runRoot))
      // The prompts: a fresh run packages them into the archive; a re-judge
      // reads the archive's own, so the record of what the subjects saw is
      // never rewritten by a later resource.
      sysP     <- if (cfg.rejudge) archived(layout.prompts.resolve("system-prompt.md")) else TextIO.resource(s"agentbench/system-prompt-${cfg.arm.name}.md")
      userT    <- if (cfg.rejudge) archived(layout.prompts.resolve("user-prompt.md")) else TextIO.resource(s"agentbench/user-prompt-${cfg.arm.name}.md")
      version  <- if (cfg.rejudge) IO.pure("n/a (rejudge)") else Subject.version(cfg.claudeBin)
      // The corpora by content, before anything runs: the same block the
      // report carries, and the corpus half of the protocol's inputs.
      fresh    <- if (cfg.rejudge) IO.pure(Json.obj())
                  else Vector(cfg.corpusStdlib.map("agda-stdlib" -> _), cfg.corpusAlgebras.map("agda-algebras" -> _)).flatten
                         .traverse { case (k, p) => ProofSearchLoop.corpusProvenance(p).map(k -> _) }.map(v => Json.obj(v: _*))
      inputs   <- if (cfg.rejudge) IO.pure(Json.obj()) else Protocol.inputs(cfg, fresh)
      // The roots outside its own directory that a subject may read: the
      // registered libraries' source roots, and the registry directory itself,
      // whose `libraries` file the judge's `agda` command names, so a shell
      // subject running that command is inside the roots.  One set, given to
      // every arm's file tools (`--add-dir`) and used by the shell audit as
      // its read roots, and recorded in the protocol, so a toolchain bump that
      // moves them is a different protocol.
      agdaDir   = GoldVerifier.agdaDirOf(cfg.projectRoot)
      includes <- Extractor.includesFromRegistry(java.nio.file.Paths.get(agdaDir).resolve("libraries"))
      readRoots = (includes :+ java.nio.file.Paths.get(agdaDir)).map(_.toAbsolutePath.normalize).distinct
      protocol  = if (cfg.rejudge) Json.obj() else Protocol.of(cfg, version, sysP, userT, inputs, readRoots)
      // A run id is one protocol: a fresh run records its own before anything
      // spawns, and a resumed one must be the protocol on record.
      _        <- if (cfg.rejudge) IO.unit else Protocol.admit(layout, protocol, cfg.resume)
      _        <- if (cfg.rejudge) IO.unit
                  else TextIO.write(layout.prompts.resolve("system-prompt.md"), sysP) *> TextIO.write(layout.prompts.resolve("user-prompt.md"), userT)
      // A re-judge keeps the run's own record of how its subjects were run:
      // the previous report's config and corpora blocks are carried over,
      // since the harness is not told the model or the corpora a second time.
      previous <- if (cfg.rejudge) TextIO.readJson(layout.report) else IO.pure(Option.empty[Json])
      // The harness's own server: corpus-less, and `--safe` in its flags when
      // the judge is, so its check_file names Agda's refusals; it stages the
      // work copies and answers the judge for both modes.
      bin       = cfg.serverBin.getOrElse(throw new IllegalStateException("server-bin required"))
      server    = ServerConfig(
                    bin        = bin,
                    agdaFlags  = if (cfg.safe) cfg.agdaFlags + " --safe" else cfg.agdaFlags,
                    timeoutSec = cfg.serverTimeout,
                    cwd        = cfg.projectRoot,
                    stderrLog  = layout.stagingLog,
                    corpus     = None)
      extractor = Extractor(cfg.agdaJsonBin.getOrElse(throw new IllegalStateException("agda-json-bin required")), includes, agdaDir, cfg.serverTimeout.seconds)
      driven   <- McpClient.resource(server).use { client =>
                    if (cfg.rejudge) Run.rejudgeAll(cfg, entries, client, extractor)
                    else Run.driveAll(cfg, entries, client, extractor, sysP, userT, readRoots)
                  }
      corpora   = previous.flatMap(_.hcursor.downField("corpora").focus).getOrElse(fresh)
      _        <- Report.write(cfg, entries, driven, corpora, protocol, previous.flatMap(_.hcursor.downField("config").focus))
      anomalies = driven.map(_.outcome).filter(_.anomaly.isDefined)
      _        <- anomalies.traverse_(o => IO.println(s"!! ${o.entry.id} anomaly: ${o.anomaly.getOrElse("")}"))
    } yield if (anomalies.isEmpty) ExitCode.Success else ExitCode.Error
  }

  /** An archived prompt, named when missing: a re-judge never substitutes the packaged one. */
  private def archived(p: java.nio.file.Path): IO[String] =
    TextIO.read(p).adaptError { case e => new RuntimeException(s"no archived prompt at $p (a re-judge reads the run's own prompts): ${e.getMessage}") }
}
