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
  *  archive to the judge (Outcomes.judgeOne), which prices it at the run's
  *  table (issue #237).  Between the two, every credential value in what the
  *  subject and its client wrote is replaced (`keep`, Credentials.scrub), the
  *  logs before anything that can fail, so nothing judged or archived holds
  *  one.  Subjects run `parallelism` at a time; the staging server serializes
  *  its own calls.  Under `--resume` a subject already archived with no
  *  anomaly is kept and re-judged, once the run id's recorded protocol
  *  (Protocol.scala) has been found to be this run's; `--rejudge` re-judges
  *  every archived subject and spawns nothing.  A failure inside one drive is
  *  that row's anomaly, never the sweep's.
  *
  *  A Codex subject (issue #239) is driven the same way through its own
  *  spawn (CodexSubject.scala) and archive (CodexArchive.scala), one at a
  *  time, behind a circuit breaker: after a usage window refuses service or
  *  passes its threshold, the login fails, two servers fail to start in a
  *  row, or the account holds ChatGPT credits the run did not allow, no
  *  further subject is launched, and each remaining row is the anomaly "not
  *  run: <why>", which `--resume` runs once the cause is gone.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.{IO, Ref}
import cats.effect.syntax.all._
import cats.syntax.all._
import java.nio.file.{Files, StandardCopyOption}

import java.nio.file.{Path, Paths}
import scala.concurrent.duration._

import struxdriver.benchmark.{GoldVerifier, Obligation => IndexEntry}
import struxdriver.io.TextIO
import struxdriver.search.{CallCtx, McpClient, Oracle, Scaffold, TimingRow}

object Run {

  /** Every obligation of the arm, `cfg.parallelism` subjects at a time, over
    * one harness-owned server (`client`, corpus-less, `--safe` in its flags)
    * that stages the work copies and answers the judge.
    */
  def driveAll(cfg: AgentBenchConfig, entries: Vector[IndexEntry], client: McpClient, extractor: Extractor,
               sysP: String, userT: String, addDirs: Vector[Path], sources: String, prices: PriceTable,
               codex: Option[CodexContext] = None): IO[Vector[Judged]] = {
    val layout  = cfg.layout
    val subject = SubjectConfig.of(cfg, sysP, userT, addDirs)
    for {
      breaker <- Ref.of[IO, Breaker](Breaker(None, 0))
      _       <- IO.println(s">> agent-bench: ${entries.size} obligation(s), arm=${cfg.arm.name}${cfg.expose.fold("")(ts => s" expose=${ts.mkString(",")}")} model=${subject.model}${cfg.endpoint.baseUrl.fold("")(u => s" endpoint=$u")} turns=${cfg.maxTurns} wall=${cfg.wallCapSec}s budget=${cfg.maxBudgetUsd} parallelism=${cfg.parallelism} safe=${cfg.safe}")
      _       <- IO.println(s">> run root: ${layout.runRoot}")
      timings <- Ref.of[IO, Vector[TimingRow]](Vector.empty)
      driven  <- entries.parTraverseN(cfg.parallelism) { e =>
                   Oracle.create(client, timings).flatMap { oracle =>
                     val agda = new ServerAgda(oracle, extractor, e.id)
                     archivedClean(cfg, e).flatMap {
                       case true  => IO.println(s">> ${e.id} resume: archived subject kept, re-judged") *> Outcomes.judgeOne(cfg, e, agda, addDirs, prices)
                       case false => codex.fold(driveOne(cfg, subject, oracle, agda, e, sources, prices))(c =>
                                       driveCodex(cfg, subject, oracle, agda, e, prices, c, breaker))
                     }
                   }.handleErrorWith { err =>
                     // A Codex row has no client figure, so its failure has none either, and
                     // two failures in a row stop the sweep, which spends a window (issue #239).
                     IO.println(s">> ${e.id} FAILED: ${err.getMessage}") *>
                       codex.fold(IO.unit)(_ => breaker.update(_.failed(String.valueOf(err.getMessage)))) *>
                       IO.pure(Outcomes.anomaly(layout, e, err.getMessage, Priced.unread("the drive failed, so what the subject spent, if it ran, was not read"),
                                                if (codex.isDefined) None else Some(0.0)))
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
      // A Codex subject is kept only with the records its transcript is derived from (issue #239).
      IO.blocking(Files.isRegularFile(subj.finalFile(Scaffold.fixtureStem(e))) &&
                  (cfg.harness != Harness.Codex || Vector(subj.codexEvents, subj.codexRollout, subj.codexSurface).forall(Files.isRegularFile(_)))).flatMap {
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
  private def driveOne(cfg: AgentBenchConfig, subject: SubjectConfig, oracle: Oracle, agda: Agda, entry: IndexEntry,
                       sources: String, prices: PriceTable): IO[Judged] = {
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
            IO.pure(Outcomes.anomaly(layout, entry, s"staging: $msg", Priced.nothing))
        case Right(st) =>
          val judgeCmd  = judgeCommand(cfg, entry, st.workFile)
          val prompt    = Subject.render(subject.userTemplate, st.workFile, entry.hole, judgeCmd, corpus, sources)
          val sysPrompt = Subject.render(subject.systemPrompt,  st.workFile, entry.hole, judgeCmd, corpus, sources)
          val perRow    = subject.copy(systemPrompt = sysPrompt)
          val roots     = rootsOf(workDir, subject.addDirs, corpus)
          val finalFile = subj.finalFile(stem)
          val mcpCfg    = if (cfg.arm.hasServer) Some(subj.mcpConfig) else None
          for {
            _   <- TextIO.write(subj.record, SubjectRecord(cfg.arm, roots, cfg.expose, Some(cfg.endpoint)).toJson.spaces2)
            _   <- mcpCfg.fold(IO.unit)(p => TextIO.write(p, Subject.mcpConfig(perRow, workDir, st.workFile, corpus).spaces2))
            _   <- TextIO.write(subj.prompt, prompt + "\n")
            _   <- TextIO.write(subj.sysPrompt, sysPrompt + "\n")
            _   <- IO.println(s">> ${entry.id} launch (${entry.difficulty.tag}, ${struxdriver.search.LoopOutcome.stratumOf(entry.source, entry.tags)})")
            run <- Subject.run(perRow, workDir, mcpCfg, prompt, subj.transcript, subj.stderr)
            _   <- keep(cfg.env.credentials, subj, st.workFile, finalFile, run)
            _   <- IO.println(f">> ${entry.id}%-36s subject exit=${run.exitCode.map(_.toString).getOrElse("killed")} wall=${run.wallMs / 1000}s")
            j   <- Outcomes.judgeOne(cfg, entry, agda, subject.addDirs, prices)
          } yield j
      }
    } yield out
  }

  /** Stage, spawn, archive, judge: one Codex subject (issue #239), unless
    * the breaker has stopped the sweep; then read the account's windows and
    * the row's verdict into the breaker.
    */
  private def driveCodex(cfg: AgentBenchConfig, subject: SubjectConfig, oracle: Oracle, agda: Agda, entry: IndexEntry,
                         prices: PriceTable, ctx: CodexContext, breaker: Ref[IO, Breaker]): IO[Judged] = {
    val layout  = cfg.layout
    val workDir = layout.workDir(entry.id)
    val subj    = layout.subject(entry.id)
    val source  = cfg.projectRoot.resolve(entry.obligationPath)
    val stem    = Scaffold.fixtureStem(entry)
    val corpus  = (if (entry.source == "agda-algebras") cfg.corpusAlgebras else cfg.corpusStdlib)
                    .getOrElse(throw new IllegalStateException("corpus required"))
    // What an earlier attempt of the row left, which this attempt replaces.
    val earlier = Vector(subj.record, subj.runRecord, subj.outcome, subj.codexEvents, subj.codexRollout, subj.codexSurface,
                         subj.transcript, subj.finalFile(stem))
    breaker.get.flatMap {
      case Breaker(Some(why), _, _, _) =>
        // The row's directory says what the report says: not launched.
        IO.println(s">> ${entry.id} not run: $why") *>
          IO.blocking(earlier.foreach(Files.deleteIfExists)) *>
          IO.pure(Outcomes.anomaly(layout, entry, s"not run: $why", Priced.nothing, None))
      case _ =>
        Scaffold.stage(source, workDir, subj.dir, oracle, CallCtx(1, entry.id, "check_file", None)).flatMap {
          case Left(msg) =>
            IO.println(s">> ${entry.id} staging anomaly: $msg") *>
              IO.pure(Outcomes.anomaly(layout, entry, s"staging: $msg", Priced.nothing, None))
          case Right(st) =>
            val prompt    = Subject.render(subject.userTemplate, st.workFile, entry.hole, "", corpus, "")
            val sysPrompt = Subject.render(subject.systemPrompt,  st.workFile, entry.hole, "", corpus, "")
            val perRow    = subject.copy(systemPrompt = sysPrompt)
            val roots     = rootsOf(workDir, subject.addDirs, corpus)
            val finalFile = subj.finalFile(stem)
            val home      = layout.codexHome(entry.id)
            val mark      = s"${cfg.runId}/${entry.id}"
            val server    = Subject.server(perRow, workDir, st.workFile, corpus)
            val config    = Toml.render(CodexSubject.tables(subject.model, ctx.setup, sysPrompt, workDir, subject.addDirs, server, mark,
                                                            cfg.serverTimeout + 60))
            val env       = CodexSubject.environment(cfg.env.vars -- Subject.envAdded.keys, home)
            for {
              _    <- TextIO.write(subj.record, SubjectRecord(cfg.arm, roots, cfg.expose, None, Harness.Codex, Some(ctx.endpoint)).toJson.spaces2)
              _    <- TextIO.write(subj.mcpConfig, Subject.mcpConfig(perRow, workDir, st.workFile, corpus).spaces2)
              _    <- TextIO.write(subj.prompt, prompt + "\n")
              _    <- TextIO.write(subj.sysPrompt, sysPrompt + "\n")
              _    <- TextIO.write(subj.codexConfig, config)
              // An earlier attempt's records and final file are never read as this one's.
              _    <- IO.blocking(Vector(subj.codexEvents, subj.codexRollout, subj.codexSurface, subj.transcript, subj.runRecord, finalFile)
                                    .foreach(Files.deleteIfExists))
              sha  <- CodexSubject.prepare(home, ctx.authPath, config)
              b    <- breaker.get
              _    <- IO.println(s">> ${entry.id} launch (${entry.difficulty.tag}, ${struxdriver.search.LoopOutcome.stratumOf(entry.source, entry.tags)})${b.windows.fold("")(w => s" $w")}")
              run  <- CodexSubject.run(ctx.setup, env, home, workDir, prompt, subj.codexEvents, subj.stderr, cfg.wallCapSec.seconds,
                                       cfg.maxTurns, cfg.maxBudgetUsd)
              kept <- CodexArchive.keep(layout, subj, home, sha, cfg.env.credentials, ctx.authPath, st.workFile, finalFile, run, mark, cfg.persistSessions)
              _    <- IO.println(f">> ${entry.id}%-36s subject exit=${kept.exitCode.map(_.toString).getOrElse("killed")} wall=${kept.wallMs / 1000}s${kept.stopped.fold("")(c => s" stopped=$c")}${if (kept.orphansKilled > 0) s" orphans=${kept.orphansKilled}" else ""}")
              j    <- Outcomes.judgeOne(cfg, entry, agda, subject.addDirs, prices)
              lim  <- CodexArchive.lastLimits(subj)
              _    <- breaker.update(_.after(j.outcome, lim, cfg.allowCredits))
              now  <- breaker.get
              _    <- now.stop.fold(IO.unit)(why => IO.println(s"!! codex sweep stopped after ${entry.id}: $why"))
            } yield j
        }
    }
  }

  /** Archive what a finished subject left: its transcript and stderr are
    * scrubbed of every credential value first (issue #237), so a failure
    * after this point (a work file the subject deleted fails the copy)
    * still leaves nothing to archive that holds one; then the final file is
    * copied and scrubbed, and `run.json` names what was replaced.
    */
  private[agentbench] def keep(creds: Credentials, subj: SubjectLayout, workFile: Path, finalFile: Path, run: SubjectRun): IO[SubjectRun] =
    for {
      logs  <- Credentials.scrub(creds, Vector(subj.transcript, subj.stderr))
      _     <- IO.blocking { Files.createDirectories(finalFile.getParent); Files.copy(workFile, finalFile, StandardCopyOption.REPLACE_EXISTING); () }
      file  <- Credentials.scrub(creds, Vector(finalFile))
      done   = run.copy(redacted = (logs ++ file).distinct.sorted)
      _     <- TextIO.write(subj.runRecord, done.toJson.spaces2)
    } yield done

  /** Every archived subject judged again, `cfg.parallelism` at a time; a
    * missing archive is that row's anomaly.  `libraryRoots` are the harness's
    * read roots, which an archive made before subjects recorded their own is
    * read under (Outcomes.judgeOne).
    */
  def rejudgeAll(cfg: AgentBenchConfig, entries: Vector[IndexEntry], client: McpClient, extractor: Extractor,
                 libraryRoots: Vector[Path], prices: PriceTable, codexRun: Boolean = false): IO[Vector[Judged]] = {
    // A Codex run's rows have no client figure, and a row it never launched
    // (the breaker's "not run") spent nothing, as the fresh run recorded
    // (issue #239); a Claude run's rows are judged as they always were.
    val cost: Option[Double] = if (codexRun) None else Some(0.0)
    // A row the run never launched has neither its record nor an event stream (driveCodex writes both before the spawn).
    def missing(e: IndexEntry): IO[Priced] =
      if (!codexRun) IO.pure(Priced.unread("no archived subject"))
      else {
        val subj = cfg.layout.subject(e.id)
        IO.blocking(Files.exists(subj.record) || Files.exists(subj.codexEvents))
          .map(launched => if (launched) Priced.unread("no archived subject") else Priced.nothing)
      }
    IO.println(s">> agent-bench: re-judging ${entries.size} obligation(s) under ${cfg.layout.runRoot}") *>
      Ref.of[IO, Vector[TimingRow]](Vector.empty).flatMap { timings =>
        entries.parTraverseN(cfg.parallelism) { e =>
          IO.blocking(Files.isRegularFile(cfg.layout.subject(e.id).finalFile(Scaffold.fixtureStem(e)))).flatMap {
            case true  => Oracle.create(client, timings).flatMap(o => Outcomes.judgeOne(cfg, e, new ServerAgda(o, extractor, e.id), libraryRoots, prices))
            case false => missing(e).map(p => Outcomes.anomaly(cfg.layout, e, "no archived subject to judge", p, cost))
          }.handleErrorWith { err =>
            IO.println(s">> ${e.id} FAILED: ${err.getMessage}") *>
              IO.pure(Outcomes.anomaly(cfg.layout, e, err.getMessage, Priced.unread("the re-judge failed, so the subject's transcript was not read"), cost))
          }
        }
      }
  }
}
