/** ============================================================================
  *  CodexArchive.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/CodexArchive.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  A Codex subject's archive (issue #239): what is kept of a session once it
  *  ends (`keep`), and the transcript derived from what was kept (`derive`),
  *  the one place the adapter (CodexTranscript.scala) is run, in a fresh run
  *  and a re-judge alike, so an archived run re-reads under a fixed adapter
  *  with no model call.
  *
  *  What is kept, in this order
  *  ---------------------------
  *  1.  The rollout, found by the thread the stream announced and filtered
  *      (CodexSubject.archivable: the account's ids and the repository's git
  *      block dropped, the base instructions and the encrypted reasoning
  *      reduced to digests); Codex's base instructions once per run, by
  *      digest, under `prompts/`.
  *  2.  The surface of the first request (CodexSubject.surfaceOf), with the
  *      number of requests the trace holds and whether Codex rewrote the
  *      configuration the harness wrote.
  *  3.  The credential scrub over everything the subject and Codex wrote:
  *      the events, the rollout, the surface, the client's stderr, then the
  *      final file, with the values of the subject's environment and of the
  *      operator's Codex login, read again after the session, since a
  *      refresh replaces them.
  *  4.  The processes still carrying the subject's marker, ended; then the
  *      subject's CODEX_HOME removed (kept under `--persist-sessions on`);
  *      both as soon as the home has been read, and again if any step
  *      fails, so no failure leaves a server running or a home behind.
  *  5.  The final file, copied and scrubbed, and the process record.  A
  *      subject that deleted or moved its work file fails the copy, as a
  *      Claude subject does (Run.keep), after its process record is written.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.IO
import io.circe.Json
import io.circe.syntax._
import java.nio.file.{Files, Path, StandardCopyOption}

import struxdriver.io.TextIO

/** What a Codex run gives every subject: the setup, the operator's login
  * (linked, never copied), and the endpoint block its records carry.
  */
final case class CodexContext(setup: CodexSetup, authPath: Path, endpoint: Json)

/** The account's usage windows after a subject, from its rollout's last
  * limits: the five-hour and the weekly use in percent, when the five-hour
  * window resets (epoch seconds), and whether the account holds credits.
  */
final case class Limits(fiveHour: Option[Double], weekly: Option[Double], resetsAt: Option[Long], credits: Boolean, reached: Option[String]) {
  def show: String =
    s"window 5h=${fiveHour.fold("?")(p => f"$p%.0f%%")} wk=${weekly.fold("?")(p => f"$p%.0f%%")}" +
      resetsAt.fold("")(r => s" (5h resets ${java.time.Instant.ofEpochSecond(r)})")
}

/** The circuit breaker of a Codex sweep: why it stopped, if it has, how
  * many subjects in a row did not start (a required server that failed, or
  * Codex itself), the last windows read, and how many subjects in a row the
  * harness failed on after launching them (each of which spent the account's
  * window for nothing).
  */
final case class Breaker(stop: Option[String], serverFailures: Int, windows: Option[String] = None, harnessFailures: Int = 0) {

  /** The breaker after a subject the harness failed on (Run.driveAll's handler). */
  def failed(why: String): Breaker = {
    val n = harnessFailures + 1
    copy(harnessFailures = n,
         stop = stop.orElse(if (n >= 2) Some(s"the harness failed on two subjects in a row (the last: ${why.take(200)})") else None))
  }


  /** The breaker after one judged subject and the windows it left. */
  def after(o: Outcome, lim: Option[Limits], allowCredits: Boolean): Breaker = {
    val anomaly  = o.anomaly.getOrElse("")
    val failures = if (anomaly.contains("required MCP server failed to start") || anomaly.startsWith("no init record")) serverFailures + 1 else 0
    val why = stop.orElse(Vector(
      if (anomaly.contains("login failed")) Some("the Codex login failed; log in again") else None,
      lim.flatMap(_.reached).map(r => s"Codex reports a usage limit reached ($r)"),
      if (o.rateLimit.exists(_.hcursor.get[Vector[String]]("statuses").getOrElse(Vector.empty).contains("rejected")))
        Some("a usage window refused service") else None,
      if (failures >= 2) Some("two subjects in a row did not start (a required server failed, or Codex itself; see their stderr.log)") else None,
      lim.flatMap(_.fiveHour).filter(_ >= Breaker.fiveHourStop).map(p => f"the five-hour window is at $p%.0f%%${lim.flatMap(_.resetsAt).fold("")(r => s", resets ${java.time.Instant.ofEpochSecond(r)}")}"),
      lim.flatMap(_.weekly).filter(_ >= Breaker.weeklyStop).map(p => f"the weekly window is at $p%.0f%%"),
      if (lim.exists(_.credits) && !allowCredits) Some("the account holds ChatGPT credits, which a run spends only under --allow-credits on") else None
    ).flatten.headOption)
    Breaker(why, failures, lim.map(_.show).orElse(windows), 0)
  }
}

object Breaker {
  /** The windows' thresholds, in percent: past them no subject is launched. */
  val fiveHourStop: Double = 95.0
  val weeklyStop: Double   = 97.0
}

object CodexArchive {

  /** The last usage windows a subject's archived rollout records. */
  def lastLimits(subj: SubjectLayout): IO[Option[Limits]] =
    TextIO.read(subj.codexRollout).map { r =>
      r.linesIterator.flatMap(l => io.circe.parser.parse(l).toOption).map(_.hcursor)
        .filter(c => c.get[String]("type").toOption.contains("event_msg") && c.downField("payload").get[String]("type").toOption.contains("token_count"))
        .map(_.downField("payload").downField("rate_limits")).filter(_.focus.exists(!_.isNull)).toVector.lastOption.map { l =>
          Limits(
            fiveHour = l.downField("primary").get[Double]("used_percent").toOption,
            weekly   = l.downField("secondary").get[Double]("used_percent").toOption,
            resetsAt = l.downField("primary").get[Long]("resets_at").toOption,
            credits  = l.downField("credits").get[Boolean]("has_credits").getOrElse(false) || l.downField("credits").get[Boolean]("unlimited").getOrElse(false),
            reached  = l.get[String]("rate_limit_reached_type").toOption.filter(_.nonEmpty))
        }
    }.handleError(_ => None)

  /** The operator's Codex login values, read now, in memory only. */
  def loginCredentials(authPath: Path): IO[Credentials] =
    TextIO.read(authPath).map(Credentials.ofCodexLogin).handleError(_ => Credentials.of(Map.empty))

  /** Keep what a finished Codex subject left (the header's order), and
    * return its process record with what was replaced and what was ended.
    */
  def keep(layout: RunLayout, subj: SubjectLayout, home: CodexHome, configSha: String, envCreds: Credentials, authPath: Path,
           workFile: Path, finalFile: Path, run: SubjectRun, mark: String, persist: Boolean): IO[SubjectRun] = {
    val cleanup: IO[Int] =
      CodexSubject.reapMarked(mark).handleError(_ => 0) <* (if (persist) IO.unit else CodexSubject.remove(home.dir).handleError(_ => ()))
    val kept = for {
      events   <- TextIO.read(subj.codexEvents).handleError(_ => "")
      thread    = CodexTranscript.stream(events).threadId
      rollout  <- CodexSubject.rolloutOf(home, thread).flatMap(_.fold(IO.pure(Option.empty[String]))(p => TextIO.read(p).map(Some(_))))
      _        <- rollout.fold(IO.unit)(r => TextIO.write(subj.codexRollout, CodexSubject.archivable(r)))
      _        <- rollout.flatMap(CodexSubject.baseInstructions).fold(IO.unit) { b =>
                    val p = layout.prompts.resolve(s"codex-base-instructions-${TextIO.sha256(b).take(12)}.md")
                    IO.blocking(Files.exists(p)).flatMap(e => if (e) IO.unit else TextIO.write(p, b))
                  }
      request  <- CodexSubject.firstRequest(home)
      written  <- TextIO.read(home.config).map(TextIO.sha256).handleError(_ => "")
      _        <- request.fold(IO.unit) { case (req, n) =>
                    TextIO.write(subj.codexSurface, CodexSubject.surfaceOf(req).deepMerge(Json.obj(
                      "requests" -> n.asJson, "configSha256" -> configSha.asJson, "configChanged" -> (written != configSha).asJson)).spaces2)
                  }
      login    <- loginCredentials(authPath)
      creds     = envCreds ++ login
      logs     <- Credentials.scrub(creds, Vector(subj.codexEvents, subj.codexRollout, subj.codexSurface, subj.stderr))
      orphans  <- cleanup
      copied   <- IO.blocking { Files.createDirectories(finalFile.getParent); Files.copy(workFile, finalFile, StandardCopyOption.REPLACE_EXISTING); () }.attempt
      file     <- copied.fold(_ => IO.pure(Vector.empty[String]), _ => Credentials.scrub(creds, Vector(finalFile)))
      done      = run.copy(redacted = (logs ++ file).distinct.sorted, orphansKilled = orphans)
      _        <- TextIO.write(subj.runRecord, done.toJson.spaces2)
      _        <- IO.fromEither(copied)
    } yield done
    kept.onError { case _ => cleanup.void }.onCancel(cleanup.void)
  }

  /** What the run expected of its subjects, from its protocol and the
    * subject's own rendered system prompt.
    */
  private def expected(layout: RunLayout, subj: SubjectLayout): IO[CodexTranscript.Expected] =
    for {
      protocol <- TextIO.readJson(layout.protocol)
      sysP     <- TextIO.read(subj.sysPrompt).map(s => Some(s.stripSuffix("\n"))).handleError(_ => None)
    } yield {
      val c = protocol.map(_.hcursor)
      CodexTranscript.Expected(
        model              = c.flatMap(_.get[String]("model").toOption),
        effort             = c.flatMap(_.get[String]("effort").toOption),
        version            = c.flatMap(_.get[String]("harnessVersion").toOption),
        systemPromptSha256 = sysP.map(CodexSubject.promptDigest))
    }

  /** Derive the subject's `transcript.jsonl` from its archived records, and
    * write it only when its bytes change.  A subject with no archived events
    * at all gets an init record that says so, which the anomaly rules read.
    */
  def derive(layout: RunLayout, subj: SubjectLayout, record: Option[SubjectRun]): IO[Unit] =
    for {
      events  <- TextIO.read(subj.codexEvents).map(Some(_)).handleError(_ => None)
      rollout <- TextIO.read(subj.codexRollout).handleError(_ => "")
      surface <- TextIO.readJson(subj.codexSurface)
      stderr  <- TextIO.read(subj.stderr).handleError(_ => "")
      exp     <- expected(layout, subj)
      ended    = CodexTranscript.Ended(record.exists(_.killed), record.flatMap(_.stopped))
      records  = events.fold(Vector(Json.obj(
                   "type" -> "system".asJson, "subtype" -> "init".asJson, "harness" -> "codex".asJson,
                   "adapterAnomaly" -> "no archived Codex event stream to derive the transcript from".asJson)))(e =>
                   CodexTranscript.derive(rollout, e, surface, stderr, exp, ended))
      text     = CodexTranscript.render(records)
      now     <- TextIO.read(subj.transcript).map(Some(_)).handleError(_ => None)
      _       <- if (now.contains(text)) IO.unit else TextIO.write(subj.transcript, text)
    } yield ()
}
