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
  *  work copy through the harness's own corpus-less `--safe` server
  *  (Scaffold.stage, the exactly-one-hole gate; the same server answers the
  *  judge afterwards), write the subject's record (its arm and the roots its
  *  tools and commands may touch), its server config where the arm has a
  *  server, and its rendered prompts, spawn the subject (Subject.run) under
  *  the caps, archive the file it left and how its process ended, and hand the
  *  archive to the judge
  *  (Outcomes.judgeOne).  Subjects run `parallelism` at a time; the staging
  *  server serializes its own calls.  Under `--resume` a subject already
  *  archived with no anomaly is kept and re-judged, once the run id's
  *  recorded protocol (Protocol.scala) has been found to be this run's;
  *  `--rejudge` re-judges every archived subject and spawns nothing.  A
  *  failure inside one drive is that row's anomaly, never the sweep's.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.{IO, Ref}
import cats.effect.syntax.all._
import cats.syntax.all._
import java.nio.file.{Files, StandardCopyOption}

import java.nio.file.{Path, Paths}

import struxdriver.benchmark.{GoldVerifier, Obligation => IndexEntry}
import struxdriver.io.TextIO
import struxdriver.search.{CallCtx, McpClient, Oracle, Scaffold, TimingRow}

object Run {

  /** Every obligation of the arm, `cfg.parallelism` subjects at a time, over
    * one harness-owned server (`client`, corpus-less, `--safe` in its flags)
    * that stages the work copies and answers the judge.
    */
  def driveAll(cfg: AgentBenchConfig, entries: Vector[IndexEntry], client: McpClient, extractor: Extractor,
               sysP: String, userT: String, addDirs: Vector[Path]): IO[Vector[Judged]] = {
    val layout  = cfg.layout
    val subject = SubjectConfig.of(cfg, sysP, userT, addDirs)
    for {
      _       <- IO.println(s">> agent-bench: ${entries.size} obligation(s), arm=${cfg.arm.name} model=${subject.model} turns=${cfg.maxTurns} wall=${cfg.wallCapSec}s budget=${cfg.maxBudgetUsd} parallelism=${cfg.parallelism} safe=${cfg.safe}")
      _       <- IO.println(s">> run root: ${layout.runRoot}")
      timings <- Ref.of[IO, Vector[TimingRow]](Vector.empty)
      driven  <- entries.parTraverseN(cfg.parallelism) { e =>
                   Oracle.create(client, timings).flatMap { oracle =>
                     val agda = new ServerAgda(oracle, extractor, e.id)
                     archivedClean(cfg, e).flatMap {
                       case true  => IO.println(s">> ${e.id} resume: archived subject kept, re-judged") *> Outcomes.judgeOne(cfg, e, agda, addDirs)
                       case false => driveOne(cfg, subject, oracle, agda, e)
                     }
                   }.handleErrorWith { err =>
                     IO.println(s">> ${e.id} FAILED: ${err.getMessage}") *>
                       IO.pure(Outcomes.anomaly(layout, e, err.getMessage))
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

  /** The `agda` command a shell subject is given: the judge's own, on the
    * staged file, so the arm's verdict and the judge's are one invocation
    * (GoldVerifier.agdaCommand, `--safe` when the judge is safe).
    */
  private[agentbench] def judgeCommand(cfg: AgentBenchConfig, entry: IndexEntry, workFile: Path): String = {
    val agdaDir = GoldVerifier.agdaDirOf(cfg.projectRoot)
    val libs    = Paths.get(agdaDir).resolve("libraries").toString
    GoldVerifier.agdaCommand(entry.source, workFile, libs, if (cfg.safe) Vector("--safe") else Vector.empty).mkString(" ")
  }

  /** Where this subject's tools and commands may reach: its own directory, the
    * registered libraries' sources, and the row's corpus (by the path the run
    * uses and by the file it resolves to, since the corpora are symlinked
    * between worktrees).
    */
  private[agentbench] def rootsOf(workDir: Path, addDirs: Vector[Path], corpus: Path): ShellRoots = {
    val real = scala.util.Try(corpus.toRealPath()).toOption.filter(_ != corpus).toVector
    ShellRoots(workDir, addDirs, corpus +: real)
  }

  /** Stage, spawn, archive, judge: one subject. */
  private def driveOne(cfg: AgentBenchConfig, subject: SubjectConfig, oracle: Oracle, agda: Agda, entry: IndexEntry): IO[Judged] = {
    val layout  = cfg.layout
    val workDir = layout.workDir(entry.id)
    val subj    = layout.subject(entry.id)
    val source  = cfg.projectRoot.resolve(entry.obligationPath)
    val stem    = Scaffold.fixtureStem(entry)
    val corpus  = (if (entry.source == "agda-algebras") cfg.corpusAlgebras else cfg.corpusStdlib)
                    .getOrElse(throw new IllegalStateException("corpus required"))
    for {
      staged <- Scaffold.stage(source, workDir, subj.dir, oracle, CallCtx(1, entry.id, "check_file", None))
      out    <- staged match {
        case Left(msg) =>
          IO.println(s">> ${entry.id} staging anomaly: $msg") *>
            IO.pure(Outcomes.anomaly(layout, entry, s"staging: $msg"))
        case Right(st) =>
          val judgeCmd  = judgeCommand(cfg, entry, st.workFile)
          val prompt    = Subject.render(subject.userTemplate, st.workFile, entry.hole, judgeCmd, corpus)
          val sysPrompt = Subject.render(subject.systemPrompt,  st.workFile, entry.hole, judgeCmd, corpus)
          val perRow    = subject.copy(systemPrompt = sysPrompt)
          val roots     = rootsOf(workDir, subject.addDirs, corpus)
          val finalFile = subj.finalFile(stem)
          val mcpCfg    = if (cfg.arm.hasServer) Some(subj.mcpConfig) else None
          for {
            _   <- TextIO.write(subj.record, SubjectRecord(cfg.arm, roots).toJson.spaces2)
            _   <- mcpCfg.fold(IO.unit)(p => TextIO.write(p, Subject.mcpConfig(perRow, workDir, st.workFile, corpus).spaces2))
            _   <- TextIO.write(subj.prompt, prompt + "\n")
            _   <- TextIO.write(subj.sysPrompt, sysPrompt + "\n")
            _   <- IO.println(s">> ${entry.id} launch (${entry.difficulty.tag}, ${struxdriver.search.LoopOutcome.stratumOf(entry.source, entry.tags)})")
            run <- Subject.run(perRow, workDir, mcpCfg, prompt, subj.transcript, subj.stderr)
            _   <- IO.blocking { Files.createDirectories(finalFile.getParent); Files.copy(st.workFile, finalFile, StandardCopyOption.REPLACE_EXISTING); () }
            _   <- TextIO.write(subj.runRecord, run.toJson.spaces2)
            _   <- IO.println(f">> ${entry.id}%-36s subject exit=${run.exitCode.map(_.toString).getOrElse("killed")} wall=${run.wallMs / 1000}s")
            j   <- Outcomes.judgeOne(cfg, entry, agda, subject.addDirs)
          } yield j
      }
    } yield out
  }

  /** Every archived subject judged again, `cfg.parallelism` at a time; a
    * missing archive is that row's anomaly.  `libraryRoots` are the harness's
    * read roots, which an archive made before subjects recorded their own is
    * read under (Outcomes.judgeOne).
    */
  def rejudgeAll(cfg: AgentBenchConfig, entries: Vector[IndexEntry], client: McpClient, extractor: Extractor,
                 libraryRoots: Vector[Path]): IO[Vector[Judged]] =
    IO.println(s">> agent-bench: re-judging ${entries.size} obligation(s) under ${cfg.layout.runRoot}") *>
      Ref.of[IO, Vector[TimingRow]](Vector.empty).flatMap { timings =>
        entries.parTraverseN(cfg.parallelism) { e =>
          IO.blocking(Files.isRegularFile(cfg.layout.subject(e.id).finalFile(Scaffold.fixtureStem(e)))).flatMap {
            case true  => Oracle.create(client, timings).flatMap(o => Outcomes.judgeOne(cfg, e, new ServerAgda(o, extractor, e.id), libraryRoots))
            case false => IO.pure(Outcomes.anomaly(cfg.layout, e, "no archived subject to judge"))
          }.handleErrorWith { err =>
            IO.println(s">> ${e.id} FAILED: ${err.getMessage}") *> IO.pure(Outcomes.anomaly(cfg.layout, e, err.getMessage))
          }
        }
      }
}
