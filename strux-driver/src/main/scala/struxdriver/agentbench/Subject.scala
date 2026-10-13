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
  *  fresh, non-interactive `claude -p` session whose only tools are the arm's
  *  (issue #162): the agda-mcp server (its own, started through the committed
  *  launcher with the row's corpus), Bash, or both, plus Read and Edit on the
  *  one staged file, under a turn cap, a cost cap, and a wall cap enforced
  *  from outside.
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
  *  - `--tools` is the whole built-in set, and it is the arm's: Read and Edit
  *    everywhere, Bash where the arm has a shell.  `--restricted` is kept on
  *    every arm: measured on client 2.1.261, it removes the code-running tools
  *    only when `--tools` does NOT name them, so a shell arm keeps Bash and
  *    still gets what `--restricted` gives every arm -- the file tools confined
  *    to the working directories, `--add-dir` included, and user, project and
  *    local settings ignored.  `--permission-mode acceptEdits
  *    --permission-prompts none` lets edits of the staged file through and
  *    denies anything that would have asked, so a pre-approval is needed for a
  *    tool that would ask: `--allowedTools` carries the server's namespace and
  *    Bash (verified: without it every Bash call is denied for want of an
  *    approval surface).  Bash is NOT confined by the client, so the shell
  *    arm's confinement is the audit over the paths its commands name
  *    (ShellAudit.scala); the transcript audit is run on every row of every
  *    arm.
  *  - `--add-dir` adds the registered libraries' source roots, on every arm,
  *    so reading the library's own sources is allowed symmetrically: the
  *    archived mcp arm refused eleven such reads for Sonnet and two for Opus
  *    as a confinement side effect, and a shell arm that can `cat` a module
  *    while the server arm cannot would confound the comparison (#162).
  *  - The environment loses every CLAUDE* variable, so a subject launched from
  *    inside a Claude Code session is not that session's child (no inherited
  *    session id, messaging socket, or effort level), and MCP_TIMEOUT covers
  *    the launcher's shell entry plus the corpus load.  Everything else is
  *    inherited, an exported ANTHROPIC_BASE_URL and its credential included,
  *    which is how an arm reaches another provider's Anthropic-compatible
  *    endpoint (issue #237); `environment` is that rule as a function, read
  *    once into `SubjectEnv`, which the launch hands to the child and the
  *    protocol reads the endpoint from (`Endpoint`), so the record is what
  *    the subject was given.
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
import java.nio.file.{Path, Paths}
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
  userTemplate:    String,
  arm:             Arm,
  addDirs:         Vector[Path],
  expose:          Option[Vector[String]],
  env:             SubjectEnv
) {
  def runServer: Path = projectRoot.resolve("scripts/run-server.sh")
}

object SubjectConfig {
  /** The one reading of the harness config into a subject's: the server flags
    * are the protocol's (`--safe` included when the judge is safe).
    */
  def of(cfg: AgentBenchConfig, systemPrompt: String, userTemplate: String, addDirs: Vector[Path] = Vector.empty): SubjectConfig =
    SubjectConfig(
      claudeBin       = cfg.claudeBin,
      model           = cfg.model.getOrElse(""),
      maxTurns        = cfg.maxTurns,
      wallCap         = cfg.wallCapSec.seconds,
      maxBudgetUsd    = cfg.maxBudgetUsd,
      projectRoot     = cfg.projectRoot,
      serverBin       = cfg.serverBin.getOrElse(Paths.get("")),
      agdaFlags       = cfg.serverAgdaFlags,
      serverTimeout   = cfg.serverTimeout,
      persistSessions = cfg.persistSessions,
      systemPrompt    = systemPrompt.trim,
      userTemplate    = userTemplate,
      arm             = cfg.arm,
      addDirs         = addDirs,
      expose          = cfg.expose,
      env             = cfg.env
    )
}

/** The endpoint that serves a run's subjects, as their environment names it
  * (issue #237): `ANTHROPIC_BASE_URL` always, its value or `absent` (the
  * client's default, Anthropic's API); the variables that choose which model
  * ids the client asks that endpoint for, only when they are set; and the
  * credential variables the client sends it, by name only, as `set`, which
  * says how the subjects authenticated (none of them: the client's own
  * login) and never with what.  It is an allowlist, so no token or key can
  * reach the record under a name nobody foresaw; and a base URL keeps only
  * its scheme, host, port, and path, since userinfo and a query string are
  * where a credential inside a URL would sit.  A value that is not an
  * absolute URL is recorded as `unparsed`, never verbatim.
  */
final case class Endpoint(vars: Vector[(String, String)]) {
  /** The base URL when one is set, for the console lines. */
  def baseUrl: Option[String] = vars.collectFirst { case (Endpoint.baseUrlVar, v) if v != Endpoint.absent => v }
  def toJson: Json = Json.obj(vars.map { case (k, v) => k -> v.asJson }: _*)
}

object Endpoint {
  val baseUrlVar: String = "ANTHROPIC_BASE_URL"
  val absent: String     = "absent"
  val unparsed: String   = "unparsed"

  /** The variables besides the base URL that the record carries when set:
    * the client's model aliases and its small fast model, which decide what
    * an endpoint is asked to serve for the calls `--model` does not name.
    */
  val modelVars: Vector[String] = Vector(
    "ANTHROPIC_MODEL", "ANTHROPIC_SMALL_FAST_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL")

  /** The credential variables the client reads, recorded as `set` when present. */
  val credentialVars: Vector[String] = Vector("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_CUSTOM_HEADERS")
  val set: String = "set"

  /** A variable's value when it is set to something: an exported empty
    * value (Ollama's and OpenRouter's setups clear ANTHROPIC_API_KEY so)
    * is no value, for the client and for the record.
    */
  def valueOf(env: Map[String, String], k: String): Option[String] = env.get(k).filter(_.trim.nonEmpty)

  /** A run's endpoint, read from the environment its subjects are given. */
  def of(env: Map[String, String]): Endpoint =
    Endpoint((baseUrlVar -> valueOf(env, baseUrlVar).fold(absent)(redact)) +:
      (modelVars.flatMap(k => valueOf(env, k).map(k -> _)) ++ credentialVars.filter(valueOf(env, _).isDefined).map(_ -> set)))

  /** Is the base URL another host than Anthropic's own?  The client sends
    * every credential it is given to it.
    */
  def foreign(e: Endpoint): Boolean =
    e.baseUrl.exists(u => scala.util.Try(new java.net.URI(u).getHost).toOption.forall(h => h == null || !(h == "anthropic.com" || h.endsWith(".anthropic.com"))))

  /** A base URL without its userinfo, query, and fragment. */
  def redact(url: String): String =
    scala.util.Try(new java.net.URI(url.trim)).toOption
      .filter(u => u.getScheme != null && u.getHost != null)
      .fold(unparsed)(u => s"${u.getScheme}://${u.getHost}${if (u.getPort >= 0) s":${u.getPort}" else ""}${Option(u.getRawPath).getOrElse("")}")

  /** A record's endpoint block; None when it has none (every subject made before issue #237). */
  def fromJson(j: Json): Option[Endpoint] =
    j.asObject.map(o => Endpoint(o.toVector.flatMap { case (k, v) => v.asString.map(k -> _) }))
}

/** The environment a run's subjects are given (`Subject.environment` of
  * the harness's own), read once and threaded to the launch, so the endpoint
  * the protocol records and the environment a subject receives are one value
  * (issue #237).  It holds credentials, so it is a plain class whose
  * rendering names only how many variables it holds: a config that prints
  * itself, in a log or a failed test, prints no secret.
  */
final class SubjectEnv(val vars: Map[String, String]) {
  def endpoint: Endpoint       = Endpoint.of(vars)
  def credentials: Credentials = Credentials.of(vars)
  override def toString: String = s"SubjectEnv(${vars.size} variables)"
  override def equals(o: Any): Boolean = o match {
    case e: SubjectEnv => e.vars == vars
    case _             => false
  }
  override def hashCode: Int = vars.hashCode
}

object SubjectEnv {
  /** The subjects' environment, from the harness's own. */
  def of(harness: Map[String, String]): SubjectEnv = new SubjectEnv(Subject.environment(harness))
}

/** How a subject process ended: its exit code (None when the wall cap killed
  * it), its wall clock, when it started (issue #237: an arm on another
  * endpoint is checked against a usage page that counts by the hour), and
  * the credential variables whose values were found in what it wrote and
  * replaced (Credentials.scala).  The last two are absent from an archive
  * made before issue #237.
  */
final case class SubjectRun(exitCode: Option[Int], wallMs: Long, killed: Boolean, startedAt: Option[String] = None,
                            redacted: Vector[String] = Vector.empty) {
  // The exit code is kept when null (a kill); the two later fields only
  // when they say something.
  def toJson: Json = Json.fromFields(
    Vector("exitCode" -> exitCode.asJson, "wallMs" -> wallMs.asJson, "killed" -> killed.asJson) ++
      startedAt.map(at => "startedAt" -> at.asJson) ++
      (if (redacted.isEmpty) Vector.empty else Vector("redacted" -> redacted.asJson)))
}
object SubjectRun {
  def fromJson(j: Json): Option[SubjectRun] =
    for {
      wallMs <- j.hcursor.get[Long]("wallMs").toOption
      killed <- j.hcursor.get[Boolean]("killed").toOption
    } yield SubjectRun(j.hcursor.get[Option[Int]]("exitCode").toOption.flatten, wallMs, killed,
      j.hcursor.get[String]("startedAt").toOption, j.hcursor.get[Vector[String]]("redacted").getOrElse(Vector.empty))
}

object Subject {

  /** The agda tools an arm with the server must have, as the client names
    * them: the thirteen the archived arms ran with.  It is a floor, not the
    * surface -- the server exposes more since `search_in_scope` landed (PR
    * #161) -- so a run records what was actually presented and the audit
    * admits any `mcp__agda__` tool (Arm.presents).
    */
  val agdaToolsRequired: Vector[String] = Vector(
    "get_goal", "fill_hole", "check_file", "get_diagnostics", "check_project",
    "type_of", "normalize", "resolve_name", "definition_of", "exports_of",
    "search_by_name", "search_by_type", "get_dependencies"
  ).map(t => s"mcp__agda__$t")

  /** Every tool the server registers with a corpus, as it names them, in its
    * own order: the fourteen of issue #191's surface, and what `--expose` may
    * name.  Since issue #203 the server presents thirteen of them by default:
    * `search_in_scope` only when `--expose` names it.
    */
  val serverTools: Vector[String] = Vector(
    "get_goal", "fill_hole", "check_file", "get_diagnostics", "check_project",
    "type_of", "normalize", "resolve_name", "definition_of", "exports_of",
    "search_by_name", "search_by_type", "get_dependencies", "search_in_scope"
  )

  /** The agda tools a subject must be presented, as the client names them:
    * exactly the exposed ones under `--expose` (issue #191), else the
    * thirteen-tool floor.
    */
  def requiredAgdaTools(expose: Option[Vector[String]]): Vector[String] =
    expose.fold(agdaToolsRequired)(_.map(t => s"${Arm.agdaPrefix}$t"))

  /** The file tools every arm is given. */
  val fileTools: Set[String] = Set("Read", "Edit")

  /** The per-subject MCP config: the committed launcher, anchored at the
    * repository root, with the committed flag set, the row's corpus, a
    * `check_project` gate that is the batch check of the one staged file (so
    * the whole-project tool cannot run this repository's own gate), and the
    * run's `--expose` list when it has one (issue #191).
    */
  def mcpConfig(cfg: SubjectConfig, workDir: Path, workFile: Path, corpus: Path): Json =
    Json.obj("mcpServers" -> Json.obj("agda" -> Json.obj(
      "command" -> cfg.runServer.toString.asJson,
      "args" -> (Vector(
        "--cwd", cfg.projectRoot.toString,
        "--agda-flags", cfg.agdaFlags,
        "--timeout", cfg.serverTimeout.toString,
        "--corpus", corpus.toString,
        "--check-command", s"agda ${cfg.agdaFlags} -i $workDir $workFile"
      ) ++ cfg.expose.toVector.flatMap(ts => Vector("--expose", ts.mkString(",")))).asJson,
      "env" -> Json.obj("AGDA_MCP_BIN" -> cfg.serverBin.toString.asJson),
      "alwaysLoad" -> Json.True
    )))

  /** Render a prompt template for one row.  Both prompts go through this, so
    * the shell arms can state the row's own `agda` command and corpus path
    * (issue #162) and the directories their library sources are in (issue
    * #189) while the archive keeps the templates themselves; a placeholder a
    * template does not use is simply not there to replace.
    */
  def render(template: String, workFile: Path, hole: String, agdaCommand: String, corpus: Path, sources: String): String =
    template
      .replace("{{path}}", workFile.toString)
      .replace("{{hole}}", hole)
      .replace("{{agda}}", agdaCommand)
      .replace("{{corpus}}", corpus.toString)
      .replace("{{sources}}", sources)
      .trim

  /** The `{{sources}}` block: one indented line per source root, the library
    * named after it, then Agda's own primitive modules when the run found
    * them.  Every directory listed is one of the run's read roots.
    */
  def sourcesBlock(named: Vector[(String, Path)], prim: Option[Path]): String =
    (named.map { case (name, dir) => s"    $dir   ($name)" } ++
      prim.toVector.map(dir => s"    $dir   (Agda's own Agda.Builtin and Agda.Primitive)")).mkString("\n")

  /** The fixed flag set, in one place, so the report can quote it; the arm
    * decides the built-in tools and the pre-approvals, and nothing else.
    * `--strict-mcp-config` stays on the shell arm, where it is what makes the
    * absent `--mcp-config` mean no MCP server at all rather than the user's.
    */
  def fixedFlags(cfg: SubjectConfig): Vector[String] =
    Vector(
      "--output-format", "stream-json", "--verbose",
      "--max-turns", cfg.maxTurns.toString,
      "--max-budget-usd", cfg.maxBudgetUsd.toString,
      "--strict-mcp-config",
      "--tools", cfg.arm.builtinTools.toVector.sorted.mkString(","),
      "--allowedTools", cfg.arm.allowedTools.mkString(","),
      "--permission-mode", "acceptEdits",
      "--permission-prompts", "none",
      "--setting-sources", "",
      "--disable-slash-commands",
      "--restricted"
    ) ++ (if (cfg.addDirs.isEmpty) Vector.empty else "--add-dir" +: cfg.addDirs.map(_.toString)) ++
      (if (cfg.persistSessions) Vector.empty else Vector("--no-session-persistence"))

  /** The argument vector; a shell arm carries no `--mcp-config`, so with
    * `--strict-mcp-config` it has no MCP server at all.
    */
  def argv(cfg: SubjectConfig, mcpConfig: Option[Path], prompt: String): Vector[String] =
    Vector("setsid", cfg.claudeBin, "-p", prompt, "--model", cfg.model) ++
      mcpConfig.toVector.flatMap(p => Vector("--mcp-config", p.toString)) ++
      fixedFlags(cfg) ++ Vector("--system-prompt", cfg.systemPrompt)

  /** The environment additions, and the prefix of the variables removed. */
  val envAdded: Map[String, String] = Map("MCP_TIMEOUT" -> "120000", "ENABLE_TOOL_SEARCH" -> "false")
  val envRemovedPrefix: String      = "CLAUDE"

  /** The environment a subject is given: the harness's own, less every
    * CLAUDE* variable, plus the additions.  Read once, as `SubjectEnv`: the
    * launch hands it to the child, and the protocol reads the endpoint from
    * it.
    */
  def environment(base: Map[String, String]): Map[String, String] =
    base.filterNot { case (k, _) => k.startsWith(envRemovedPrefix) } ++ envAdded

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
  def run(cfg: SubjectConfig, workDir: Path, mcpConfig: Option[Path], prompt: String, stdout: Path, stderr: Path): IO[SubjectRun] = {
    val start = IO.blocking {
      val pb = new ProcessBuilder(argv(cfg, mcpConfig, prompt).asJava)
      pb.directory(workDir.toFile)
      pb.redirectInput(Redirect.from(new File("/dev/null")))
      pb.redirectOutput(Redirect.to(stdout.toFile))
      pb.redirectError(Redirect.to(stderr.toFile))
      val env = pb.environment()
      env.clear()
      env.putAll(cfg.env.vars.asJava)
      pb.start()
    }
    for {
      at  <- IO.realTimeInstant
      t0  <- IO.monotonic
      res <- start.bracket { proc =>
               await(proc, t0 + cfg.wallCap).map(exited => if (exited) (Some(proc.exitValue()), false) else (Option.empty[Int], true))
             }(killGroup)
      t1  <- IO.monotonic
    } yield SubjectRun(res._1, (t1 - t0).toMillis, res._2, Some(at.toString))
  }
}
