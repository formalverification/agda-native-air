/** ============================================================================
  *  Subject.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Subject.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  Spawn one subject of the agent-in-the-loop evaluation (issue #154): a
  *  fresh, non-interactive `claude -p` session whose only tools are the
  *  thirteen agda-mcp tools (its own server, started through the committed
  *  launcher with the row's corpus) and Read and Edit on the one staged file,
  *  under a turn cap, a cost cap, and a wall cap enforced from outside.
  *
  *  Isolation, and how each part of it is obtained
  *  -----------------------------------------------
  *  - `--setting-sources ""` loads no user, project, or local settings, and
  *    with them no CLAUDE.md (verified 2026-09-15: the default configuration
  *    delivers both an ancestor CLAUDE.md and the global one; with this flag
  *    neither reaches the model).  `--disable-slash-commands` drops skills;
  *    `--no-session-persistence` writes no session to disk (switchable, so a
  *    verification run can inspect the on-disk transcript for the deferred
  *    tool list).
  *  - `--mcp-config` plus `--strict-mcp-config` makes the per-subject config
  *    the only MCP source; `"alwaysLoad": true` on the server entry and
  *    ENABLE_TOOL_SEARCH=false in the environment present the tools eagerly,
  *    with their descriptions, rather than as deferred names (the #83 run-1
  *    lesson).
  *  - `--tools Read,Edit` is the whole built-in set; `--restricted` confines
  *    those to the working directory and refuses the code-running tools;
  *    `--permission-mode acceptEdits --permission-prompts none` lets edits of
  *    the staged file and the allowed server through and denies anything that
  *    would have asked.  The transcript audit is still run on every row.
  *  - The environment loses every CLAUDE* variable, so a subject launched from
  *    inside a Claude Code session is not that session's child (no inherited
  *    session id, messaging socket, or effort level), and MCP_TIMEOUT covers
  *    the launcher's shell entry plus the corpus load.
  *  - `setsid` puts the subject in its own process group, so a wall-cap kill
  *    reaches the server and its agda children too.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.IO
import io.circe.Json
import io.circe.syntax._
import java.io.File
import java.lang.ProcessBuilder.Redirect
import java.nio.file.Path
import java.util.concurrent.TimeUnit
import scala.concurrent.duration._
import scala.jdk.CollectionConverters._

/** Everything fixed across the subjects of one arm. */
final case class SubjectConfig(
  claudeBin:       String,
  model:           String,
  maxTurns:        Int,
  wallCap:         FiniteDuration,
  maxBudgetUsd:    BigDecimal,
  projectRoot:     Path,
  serverBin:       Path,
  agdaFlags:       String,
  serverTimeout:   Int,
  persistSessions: Boolean,
  systemPrompt:    String,
  userTemplate:    String
) {
  def runServer: Path = projectRoot.resolve("scripts/run-server.sh")
}

/** How a subject process ended: its exit code (None when the wall cap killed it) and its wall clock. */
final case class SubjectRun(exitCode: Option[Int], wallMs: Long, killed: Boolean) {
  def toJson: Json = Json.obj("exitCode" -> exitCode.asJson, "wallMs" -> wallMs.asJson, "killed" -> killed.asJson)
}
object SubjectRun {
  def fromJson(j: Json): Option[SubjectRun] =
    for {
      wallMs <- j.hcursor.get[Long]("wallMs").toOption
      killed <- j.hcursor.get[Boolean]("killed").toOption
    } yield SubjectRun(j.hcursor.get[Option[Int]]("exitCode").toOption.flatten, wallMs, killed)
}

object Subject {

  /** The thirteen tools, as the client names them. */
  val agdaTools: Vector[String] = Vector(
    "get_goal", "fill_hole", "check_file", "get_diagnostics", "check_project",
    "type_of", "normalize", "resolve_name", "definition_of", "exports_of",
    "search_by_name", "search_by_type", "get_dependencies"
  ).map(t => s"mcp__agda__$t")

  /** The built-in tools a subject is given. */
  val fileTools: Set[String] = Set("Read", "Edit")

  /** The per-subject MCP config: the committed launcher, anchored at the
    * repository root, with the committed flag set, the row's corpus, and a
    * `check_project` gate that is the batch check of the one staged file (so
    * the whole-project tool cannot run this repository's own gate).
    */
  def mcpConfig(cfg: SubjectConfig, workDir: Path, workFile: Path, corpus: Path): Json =
    Json.obj("mcpServers" -> Json.obj("agda" -> Json.obj(
      "command" -> cfg.runServer.toString.asJson,
      "args" -> Vector(
        "--cwd", cfg.projectRoot.toString,
        "--agda-flags", cfg.agdaFlags,
        "--timeout", cfg.serverTimeout.toString,
        "--corpus", corpus.toString,
        "--check-command", s"agda ${cfg.agdaFlags} -i $workDir $workFile"
      ).asJson,
      "env" -> Json.obj("AGDA_MCP_BIN" -> cfg.serverBin.toString.asJson),
      "alwaysLoad" -> Json.True
    )))

  def userPrompt(template: String, workFile: Path, hole: String): String =
    template.replace("{{path}}", workFile.toString).replace("{{hole}}", hole).trim

  /** The fixed flag set, in one place, so the report can quote it. */
  def fixedFlags(cfg: SubjectConfig): Vector[String] =
    Vector(
      "--output-format", "stream-json", "--verbose",
      "--max-turns", cfg.maxTurns.toString,
      "--max-budget-usd", cfg.maxBudgetUsd.toString,
      "--strict-mcp-config",
      "--tools", fileTools.toVector.sorted.mkString(","),
      "--allowedTools", "mcp__agda",
      "--permission-mode", "acceptEdits",
      "--permission-prompts", "none",
      "--setting-sources", "",
      "--disable-slash-commands",
      "--restricted"
    ) ++ (if (cfg.persistSessions) Vector.empty else Vector("--no-session-persistence"))

  def argv(cfg: SubjectConfig, mcpConfig: Path, prompt: String): Vector[String] =
    Vector("setsid", cfg.claudeBin, "-p", prompt, "--model", cfg.model, "--mcp-config", mcpConfig.toString) ++
      fixedFlags(cfg) ++ Vector("--system-prompt", cfg.systemPrompt)

  /** The environment additions, and the prefix of the variables removed. */
  val envAdded: Map[String, String] = Map("MCP_TIMEOUT" -> "120000", "ENABLE_TOOL_SEARCH" -> "false")
  val envRemovedPrefix: String      = "CLAUDE"

  /** The client's own version string, for the report (`unknown` when the binary cannot be run). */
  def version(bin: String): IO[String] =
    IO.blocking {
      val p   = new ProcessBuilder(bin, "--version").redirectErrorStream(true).start()
      val out = new String(p.getInputStream.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8).trim
      p.waitFor()
      out
    }.handleError(e => s"unknown (${e.getMessage})")

  private def killGroup(proc: Process): IO[Unit] =
    IO.blocking {
      if (proc.isAlive) {
        val pgid = proc.pid().toString
        new ProcessBuilder("kill", "-TERM", "--", s"-$pgid").start().waitFor()
        if (!proc.waitFor(10, TimeUnit.SECONDS)) {
          new ProcessBuilder("kill", "-KILL", "--", s"-$pgid").start().waitFor()
          proc.destroyForcibly()
          proc.waitFor(5, TimeUnit.SECONDS)
        }
        ()
      }
    }

  /** Poll for exit until the deadline; true when the process exited. */
  private def await(proc: Process, deadline: FiniteDuration): IO[Boolean] =
    IO.blocking(proc.waitFor(500, TimeUnit.MILLISECONDS)).flatMap { done =>
      if (done) IO.pure(true)
      else IO.monotonic.flatMap(now => if (now >= deadline) IO.pure(false) else await(proc, deadline))
    }

  /** Run one subject: cwd is the work directory, stdin is /dev/null, stdout
    * (the stream-json) and stderr go to the named files.  The process group
    * is killed at the wall cap and on any other exit of this effect.
    */
  def run(cfg: SubjectConfig, workDir: Path, mcpConfig: Path, prompt: String, stdout: Path, stderr: Path): IO[SubjectRun] = {
    val start = IO.blocking {
      val pb = new ProcessBuilder(argv(cfg, mcpConfig, prompt).asJava)
      pb.directory(workDir.toFile)
      pb.redirectInput(Redirect.from(new File("/dev/null")))
      pb.redirectOutput(Redirect.to(stdout.toFile))
      pb.redirectError(Redirect.to(stderr.toFile))
      val env = pb.environment()
      env.keySet().removeIf(k => k.startsWith(envRemovedPrefix))
      envAdded.foreach { case (k, v) => env.put(k, v) }
      pb.start()
    }
    for {
      t0  <- IO.monotonic
      res <- start.bracket { proc =>
               await(proc, t0 + cfg.wallCap).map(exited => if (exited) (Some(proc.exitValue()), false) else (Option.empty[Int], true))
             }(killGroup)
      t1  <- IO.monotonic
    } yield SubjectRun(res._1, (t1 - t0).toMillis, res._2)
  }
}
