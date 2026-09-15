/** ============================================================================
  *  Run.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Run.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  Drive the subjects of one arm (issue #154).  Per obligation: stage the
  *  work copy through the harness's own corpus-less server (Scaffold.stage,
  *  the exactly-one-hole gate), write the subject's server config and
  *  prompt, spawn the subject (Subject.run) under the caps, archive the file
  *  it left and how its process ended, and hand the archive to the judge
  *  (Outcomes.judgeOne).  Subjects run `parallelism` at a time; the staging
  *  server serializes its own calls.  Under `--resume` a subject already
  *  archived with no anomaly is kept and re-judged; `--rejudge` re-judges
  *  every archived subject and spawns nothing.  A failure inside one drive is
  *  that row's anomaly, never the sweep's.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.{IO, Ref}
import cats.effect.syntax.all._
import cats.syntax.all._
import java.nio.file.{Files, StandardCopyOption}
import scala.concurrent.duration._

import struxdriver.benchmark.{Obligation => IndexEntry}
import struxdriver.io.TextIO
import struxdriver.search.{CallCtx, McpClient, Oracle, Scaffold, ServerConfig, TimingRow}

object Run {

  /** Every obligation of the arm, `cfg.parallelism` subjects at a time. */
  def driveAll(cfg: AgentBenchConfig, entries: Vector[IndexEntry], sysP: String, userT: String): IO[Vector[Judged]] = {
    val layout  = cfg.layout
    val bin     = cfg.serverBin.getOrElse(throw new IllegalStateException("server-bin required"))
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
      stderrLog  = layout.stagingLog,
      corpus     = None
    )
    for {
      _       <- IO.println(s">> agent-bench: ${entries.size} obligation(s), model=${subject.model} turns=${cfg.maxTurns} wall=${cfg.wallCapSec}s budget=${cfg.maxBudgetUsd} parallelism=${cfg.parallelism} safe=${cfg.safe}")
      _       <- IO.println(s">> run root: ${layout.runRoot}")
      timings <- Ref.of[IO, Vector[TimingRow]](Vector.empty)
      driven  <- McpClient.resource(staging).use { client =>
                   entries.parTraverseN(cfg.parallelism) { e =>
                     archivedClean(cfg, e).flatMap {
                       case true  => IO.println(s">> ${e.id} resume: archived subject kept, re-judged") *> Outcomes.judgeOne(cfg, e)
                       case false => driveOne(cfg, subject, client, timings, e)
                     }.handleErrorWith { err =>
                       IO.println(s">> ${e.id} FAILED: ${err.getMessage}") *>
                         IO.pure(Outcomes.anomaly(layout, e, err.getMessage))
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
    else {
      val subj = cfg.layout.subject(e.id)
      IO.blocking(Files.isRegularFile(subj.finalFile(Scaffold.fixtureStem(e)))).flatMap {
        case false => IO.pure(false)
        case true  => TextIO.readJson(subj.outcome).map(_.exists(_.hcursor.get[String]("anomaly").toOption.isEmpty))
      }
    }

  /** Stage, spawn, archive, judge: one subject. */
  private def driveOne(cfg: AgentBenchConfig, subject: SubjectConfig, client: McpClient, timings: Ref[IO, Vector[TimingRow]], entry: IndexEntry): IO[Judged] = {
    val layout  = cfg.layout
    val workDir = layout.workDir(entry.id)
    val subj    = layout.subject(entry.id)
    val source  = cfg.projectRoot.resolve(entry.obligationPath)
    val stem    = Scaffold.fixtureStem(entry)
    val corpus  = (if (entry.source == "agda-algebras") cfg.corpusAlgebras else cfg.corpusStdlib)
                    .getOrElse(throw new IllegalStateException("corpus required"))
    for {
      oracle <- Oracle.create(client, timings)
      staged <- Scaffold.stage(source, workDir, subj.dir, oracle, CallCtx(1, entry.id, "check_file", None))
      out    <- staged match {
        case Left(msg) =>
          IO.println(s">> ${entry.id} staging anomaly: $msg") *>
            IO.pure(Outcomes.anomaly(layout, entry, s"staging: $msg"))
        case Right(st) =>
          val prompt    = Subject.userPrompt(subject.userTemplate, st.workFile, entry.hole)
          val finalFile = subj.finalFile(stem)
          for {
            _   <- TextIO.write(subj.mcpConfig, Subject.mcpConfig(subject, workDir, st.workFile, corpus).spaces2)
            _   <- TextIO.write(subj.prompt, prompt + "\n")
            _   <- IO.println(s">> ${entry.id} launch (${entry.difficulty.tag}, ${struxdriver.search.LoopOutcome.stratumOf(entry.source, entry.tags)})")
            run <- Subject.run(subject, workDir, subj.mcpConfig, prompt, subj.transcript, subj.stderr)
            _   <- IO.blocking { Files.createDirectories(finalFile.getParent); Files.copy(st.workFile, finalFile, StandardCopyOption.REPLACE_EXISTING); () }
            _   <- TextIO.write(subj.runRecord, run.toJson.spaces2)
            _   <- IO.println(f">> ${entry.id}%-36s subject exit=${run.exitCode.map(_.toString).getOrElse("killed")} wall=${run.wallMs / 1000}s")
            j   <- Outcomes.judgeOne(cfg, entry)
          } yield j
      }
    } yield out
  }

  /** Every archived subject judged again; a missing archive is that row's anomaly. */
  def rejudgeAll(cfg: AgentBenchConfig, entries: Vector[IndexEntry]): IO[Vector[Judged]] =
    IO.println(s">> agent-bench: re-judging ${entries.size} obligation(s) under ${cfg.layout.runRoot}") *>
      entries.traverse { e =>
        IO.blocking(Files.isRegularFile(cfg.layout.subject(e.id).finalFile(Scaffold.fixtureStem(e)))).flatMap {
          case true  => Outcomes.judgeOne(cfg, e)
          case false => IO.pure(Outcomes.anomaly(cfg.layout, e, "no archived subject to judge"))
        }
      }
}
