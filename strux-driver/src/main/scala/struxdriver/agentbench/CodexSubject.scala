/** ============================================================================
  *  CodexSubject.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/CodexSubject.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  The second kind of subject (issue #239): one `codex exec --json` session
  *  per obligation, for OpenAI's models, which have no Anthropic-compatible
  *  endpoint and so cannot be a `claude -p` subject.  It is given the `mcp`
  *  arm's instrument and nothing more (the agda server, a Read, an Edit), the
  *  same work directory, server, prompt rules, and caps as a Claude subject,
  *  and it ends in the same `SubjectRun`; what it writes is read by the
  *  adapter (CodexTranscript.scala) into the transcript the judge reads.
  *
  *  Isolation, and how each part of it is obtained (Codex CLI 0.162.1)
  *  ------------------------------------------------------------------
  *  - A CODEX_HOME of its own, made fresh for every launch outside the run
  *    directory (so no run directory ever holds a login), holding the
  *    configuration the harness wrote and `auth.json` as a symbolic link to
  *    the operator's login.  Codex writes a refreshed token by opening that
  *    file, which follows the link, so the operator's login stays current
  *    and no token is copied; the store is pinned to the file
  *    (`cli_auth_credentials_store`), so a refresh never lands in a keyring
  *    under the subject's home.  The operator's own configuration, global
  *    AGENTS.md, skills, rules, hooks, and history are not in it.
  *  - `--strict-config`, so a switch Codex does not know refuses the subject
  *    at start instead of leaving a leak open.
  *  - No shell: `features.shell_tool = false`.  A shell can search the
  *    libraries, which is the instrument the `mcp` arm withholds (issue
  *    #162 found it is what separates the shell arm from the server).  The
  *    file is read through `files`, a second MCP server with one tool,
  *    `read`, confined to the work directory and the libraries' source
  *    roots (scripts/python/bench_read_server.py), the Read a Claude subject
  *    has; it is edited with Codex's `apply_patch`, the Edit, whose writes
  *    the sandbox confines to the work directory.  Code mode's JavaScript
  *    has no file system.
  *  - Both servers' tools are top-level function tools
  *    (`omit_tools_from = ["deferred", "code_mode"]`): presented eagerly
  *    with their full JSON schemas, one model step per call, as Claude's
  *    are; `required = true`, so exec waits for them and a server that fails
  *    to start fails the session; `default_tools_approval_mode = "approve"`,
  *    since agda-mcp declares no tool annotations and exec's approval policy
  *    is `never`.  The agda server is the Claude subject's, byte for byte
  *    (Subject.server), plus a marker variable by which its processes are
  *    found and ended after the subject.
  *  - Codex's own context blocks are off (environment, permissions, and
  *    collaboration mode), so the model's instructions are Codex's base
  *    instructions (kept: Codex's documentation strongly discourages
  *    replacing them, and the row measures the harness with the model), the
  *    system prompt as `developer_instructions`, and the user prompt.  AGENTS.md
  *    discovery, skills, plugins, apps, web search, image generation, goals,
  *    hooks, memories, collaboration agents, the ask tool, the sleep tool,
  *    view_image, and the shell snapshot are off; the model catalog is the
  *    run's pinned copy (`model_catalog_json`), never fetched; and the
  *    checkout's trust entry is written beforehand, so Codex does not add one.
  *  - The sandbox is a named permission profile: `:minimal` (the system
  *    directories), the work directory writable, Codex's own package
  *    readable (its sandbox helper runs from there), network off.
  *  - The environment of the Codex process is the harness's, less every
  *    CLAUDE*, OPENAI*, CODEX*, and ANTHROPIC* variable, RUST_LOG (at `info`
  *    Codex logs the account's e-mail address), and LD_LIBRARY_PATH, plus
  *    CODEX_HOME, TMPDIR, and CODEX_ROLLOUT_TRACE_ROOT, whose request trace
  *    is the only record of what the model was presented (`surfaceOf`).
  *  - The caps: Codex has none, so the harness reads the rollout as it is
  *    written and stops the subject (INT, which exec turns into an
  *    interrupted turn) once it has made `maxTurns` responses, or once their
  *    tokens (a compaction's included) cost `maxBudgetUsd` at the run's
  *    price table; the wall cap is the same kill as a Claude subject's.  As
  *    Claude Code's `--max-turns` does, a stop waits for the last response's
  *    calls to return (an agda tool that edits the work file in place
  *    restores it only when it returns), and a response that called nothing
  *    is the turn ending on its own, which no stop interrupts.  A stop can
  *    lag its cap by a response when the poll misses the window.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.IO
import io.circe.Json
import io.circe.syntax._
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, LinkOption, Path, Paths}
import scala.jdk.CollectionConverters._

import struxdriver.io.TextIO

/** A subject's own CODEX_HOME and what Codex and the harness keep in it. */
final case class CodexHome(dir: Path) {
  def auth:     Path = dir.resolve("auth.json")
  def config:   Path = dir.resolve("config.toml")
  def tmp:      Path = dir.resolve("tmp-subject")
  def trace:    Path = dir.resolve("trace")
  def sessions: Path = dir.resolve("sessions")
}

/** What a Codex subject is given beyond a Claude subject's configuration:
  * the Codex binary, the effort, the pinned catalog, the read server's
  * command, Codex's package directory, the checkout's root for the trust
  * entry, and the price that turns its tokens into a budget.
  */
final case class CodexSetup(
  codexBin:     String,
  effort:       String,
  catalog:      Path,
  readServer:   Vector[String],
  packageRoot:  Option[Path],
  trustRoots:   Vector[Path],
  price:        Option[ModelPrice]
)

object CodexSubject {

  /** The features switched off, in the order they are written; each key is
    * one Codex 0.162.1 knows (`--strict-config` refuses any other).
    */
  val featuresOff: Vector[String] = Vector(
    "apps", "plugins", "tool_suggest", "goals", "hooks", "image_generation", "sleep_tool", "skill_search",
    "view_image", "multi_agent", "memories", "shell_tool", "shell_snapshot", "unbounded_connection_retries")

  /** The prefixes and names of the variables a Codex subject does not inherit. */
  val envRemovedPrefixes: Vector[String] = Vector("CLAUDE", "OPENAI", "CODEX", "ANTHROPIC")
  val envRemovedNames: Vector[String]    = Vector("RUST_LOG", "LD_LIBRARY_PATH")

  /** How long Codex waits for each server's handshake before it refuses the
    * session.  The agda server enters the dev shell and loads its corpus
    * first, which took 63 s on a loaded machine (load 33 on 20 cores,
    * 2026-10-13) and over 120 s beside the harness's own server; the wait
    * precedes the first model request, so the subject sees none of it, but
    * it counts against the wall cap, as a Claude subject's does.
    */
  val agdaStartupSec: Int  = 600
  val filesStartupSec: Int = 120

  /** The variable by which a subject's server processes are found afterwards. */
  val marker: String = "AGENT_BENCH_SUBJECT"

  /** The variables the harness adds, by name, for the protocol. */
  val envAdded: Vector[String] = Vector("CODEX_HOME", "TMPDIR", "CODEX_ROLLOUT_TRACE_ROOT")

  /** The per-subject environment: the harness's, less the removed
    * variables, plus the subject's own Codex home, temporary directory, and
    * request trace.
    */
  def environment(base: Map[String, String], home: CodexHome): Map[String, String] =
    base.filterNot { case (k, _) => envRemovedPrefixes.exists(k.startsWith) || envRemovedNames.contains(k) } ++ Map(
      "CODEX_HOME"               -> home.dir.toString,
      "TMPDIR"                   -> home.tmp.toString,
      "CODEX_ROLLOUT_TRACE_ROOT" -> home.trace.toString)

  /** The fixed part of the argument vector, for the protocol. */
  val argvFixed: Vector[String] = Vector("--strict-config", "exec", "--json")

  /** The argument vector: the configuration is the subject's CODEX_HOME's,
    * read strictly; the prompt is the user prompt, the system part being in
    * the configuration.
    */
  def argv(codexBin: String, prompt: String): Vector[String] =
    (("setsid" +: codexBin +: argvFixed) :+ prompt)

  /** The tables of a subject's `config.toml` (the header's list), for a
    * subject whose work directory is `workDir`, whose agda server is
    * `server`, and whose read server reads `readRoots` besides the work
    * directory.
    */
  def tables(model: String, setup: CodexSetup, systemPrompt: String, workDir: Path, readRoots: Vector[Path],
             server: (String, Vector[String], Map[String, String]), subjectMark: String, toolTimeoutSec: Int): Vector[TomlTable] = {
    val readArgs = setup.readServer.tail ++ (workDir +: readRoots).flatMap(r => Vector("--root", r.toString))
    Vector(
      TomlTable(Vector.empty, Vector(
        "model"                                   -> Toml.str(model),
        "model_reasoning_effort"                  -> Toml.str(setup.effort),
        "model_catalog_json"                      -> Toml.str(setup.catalog.toString),
        "approval_policy"                         -> Toml.str("never"),
        "default_permissions"                     -> Toml.str("subject"),
        "allow_login_shell"                       -> Toml.bool(false),
        "cli_auth_credentials_store"              -> Toml.str("file"),
        "project_doc_max_bytes"                   -> Toml.int(0),
        "project_root_markers"                    -> Toml.strs(Vector.empty),
        "web_search"                              -> Toml.str("disabled"),
        "include_environment_context"             -> Toml.bool(false),
        "include_permissions_instructions"        -> Toml.bool(false),
        "include_collaboration_mode_instructions" -> Toml.bool(false),
        "developer_instructions"                  -> Toml.str(systemPrompt))),
      TomlTable(Vector("analytics"), Vector("enabled" -> Toml.bool(false))),
      TomlTable(Vector("agents"), Vector("enabled" -> Toml.bool(false))),
      TomlTable(Vector("tools", "experimental_request_user_input"), Vector("enabled" -> Toml.bool(false))),
      TomlTable(Vector("skills"), Vector("include_instructions" -> Toml.bool(false))),
      TomlTable(Vector("skills", "bundled"), Vector("enabled" -> Toml.bool(false))),
      TomlTable(Vector("features"), featuresOff.map(_ -> Toml.bool(false)))
    ) ++ setup.trustRoots.map(r => TomlTable(Vector("projects", r.toString), Vector("trust_level" -> Toml.str("untrusted")))) ++ Vector(
      TomlTable(Vector("permissions", "subject", "filesystem"),
        Vector(":minimal" -> Toml.str("read"), workDir.toString -> Toml.str("write")) ++
          setup.packageRoot.toVector.map(_.toString -> Toml.str("read"))),
      TomlTable(Vector("permissions", "subject", "network"), Vector("enabled" -> Toml.bool(false))),
      TomlTable(Vector("mcp_servers", "agda"), Vector(
        "command"                     -> Toml.str(server._1),
        "args"                        -> Toml.strs(server._2),
        "required"                    -> Toml.bool(true),
        "startup_timeout_sec"         -> Toml.int(agdaStartupSec),
        "tool_timeout_sec"            -> Toml.int(toolTimeoutSec),
        "default_tools_approval_mode" -> Toml.str("approve"),
        "omit_tools_from"             -> Toml.strs(Vector("deferred", "code_mode")))),
      TomlTable(Vector("mcp_servers", "agda", "env"), (server._3 + (marker -> subjectMark)).toVector.sorted.map { case (k, v) => k -> Toml.str(v) }),
      TomlTable(Vector("mcp_servers", CodexTranscript.filesServer), Vector(
        "command"                     -> Toml.str(setup.readServer.head),
        "args"                        -> Toml.strs(readArgs),
        "required"                    -> Toml.bool(true),
        "startup_timeout_sec"         -> Toml.int(filesStartupSec),
        "tool_timeout_sec"            -> Toml.int(60),
        "enabled_tools"               -> Toml.strs(Vector("read")),
        "default_tools_approval_mode" -> Toml.str("approve"),
        "omit_tools_from"             -> Toml.strs(Vector("deferred", "code_mode")))),
      TomlTable(Vector("mcp_servers", CodexTranscript.filesServer, "env"), Vector(marker -> Toml.str(subjectMark)))
    )
  }

  /** Codex's npm package, two levels above the real path of the `codex` the
    * harness runs (its `bin/codex.js`), whose vendored binary the sandbox
    * runs as its helper.  None when it cannot be found.
    */
  def packageRoot(codexBin: String, pathEnv: Option[String]): Option[Path] =
    resolve(codexBin, pathEnv).flatMap(real => Option(real.getParent).flatMap(b => Option(b.getParent)))

  /** The executable a command name runs: itself when it names a path, else
    * the first match on PATH, with its links resolved.
    */
  def resolve(bin: String, pathEnv: Option[String]): Option[Path] = {
    val candidates =
      if (bin.contains("/")) Vector(Paths.get(bin))
      else pathEnv.toVector.flatMap(_.split(":").toVector).filter(_.nonEmpty).map(d => Paths.get(d).resolve(bin))
    candidates.find(p => Files.isExecutable(p)).flatMap(p => scala.util.Try(p.toRealPath()).toOption)
  }

  /** The native binary the npm wrapper launches, for the protocol's digest:
    * the one executable named `codex` under the package's vendor directory.
    */
  def nativeBinary(pkg: Path): IO[Option[Path]] =
    IO.blocking {
      val vendor = pkg.resolve("node_modules")
      if (!Files.isDirectory(vendor)) None
      else {
        val walk = Files.walk(vendor)
        try walk.iterator.asScala.toVector
          .filter(p => p.getFileName.toString == "codex" && p.getParent.getFileName.toString == "bin" && Files.isRegularFile(p))
          .sortBy(_.toString).headOption
        finally walk.close()
      }
    }

  /** The operator's login: `auth.json` in the harness's CODEX_HOME, else in `~/.codex`. */
  def operatorAuth(env: Map[String, String]): Path =
    env.get("CODEX_HOME").filter(_.nonEmpty).map(Paths.get(_))
      .getOrElse(Paths.get(env.getOrElse("HOME", System.getProperty("user.home")), ".codex"))
      .resolve("auth.json")

  /** How the operator is logged in, by which fields `auth.json` holds,
    * never their values, as Codex decides it: its `auth_mode` when it names
    * one (`chatgpt`, `apikey`, or another kind, named as Codex names it),
    * else an API key before the tokens.
    */
  def authModeOf(authJson: String): String = {
    val c = io.circe.parser.parse(authJson).toOption.map(_.hcursor)
    c.flatMap(_.get[String]("auth_mode").toOption).filter(_.nonEmpty).getOrElse {
      if (c.exists(_.get[String]("OPENAI_API_KEY").toOption.exists(_.nonEmpty))) "apikey"
      else if (c.exists(_.downField("tokens").downField("access_token").focus.exists(_.isString))) "chatgpt"
      else "unknown"
    }
  }

  /** Why a login cannot serve a run, if it cannot: the harness scrubs and
    * searches for the secrets of a ChatGPT login and an API key
    * (Credentials.ofCodexLogin, the archive target), and a login of any
    * other kind (an access token, an agent identity, Bedrock keys) would
    * pass both with nothing searched.
    */
  def loginRefusal(authJson: String): Option[String] = {
    val c       = io.circe.parser.parse(authJson).toOption.map(_.hcursor)
    val foreign = Vector("personal_access_token", "agent_identity", "bedrock_api_key", "bedrock_access_keys")
                    .filter(k => c.exists(_.downField(k).focus.exists(j => !j.isNull)))
    val mode    = authModeOf(authJson)
    if (foreign.nonEmpty) Some(s"the Codex login holds ${foreign.mkString(", ")}, whose values the harness does not scrub; log in with `codex login` (ChatGPT) or an API key")
    else if (mode != "chatgpt" && mode != "apikey") Some(s"the Codex login is of kind $mode, neither a ChatGPT login nor an API key; log in with `codex login`")
    else None
  }

  /** The version line of what `codex --version` printed (its standard error
    * merged, where Codex may warn first), or None when there is none: a
    * wrapper that cannot start its runtime is no Codex to record.
    */
  def versionOf(output: String): Option[String] =
    output.linesIterator.map(_.trim).filter(_.matches("codex-cli \\d+\\.\\d+\\.\\d+\\S*")).toVector.lastOption

  /** The endpoint block of a Codex subject: OpenAI, by how the operator is logged in. */
  def endpoint(authMode: String): Json = Json.obj(
    "provider" -> "openai".asJson,
    "authMode" -> authMode.asJson,
    "baseUrl"  -> (if (authMode == "chatgpt") "https://chatgpt.com/backend-api/codex" else "https://api.openai.com/v1").asJson)

  /** Make a subject's CODEX_HOME afresh: an earlier attempt's sessions,
    * state, and memories are removed, the link to the operator's login is
    * made, and the configuration written.  Returns the configuration's
    * digest, against which the file is compared after the session.
    */
  def prepare(home: CodexHome, authTarget: Path, config: String): IO[String] =
    remove(home.dir) *> IO.blocking {
      Files.createDirectories(home.tmp)
      Files.createDirectories(home.trace)
      Files.createSymbolicLink(home.auth, authTarget); ()
    } *> TextIO.write(home.config, config).as(TextIO.sha256(config))

  /** Remove a directory and everything under it, links included, never
    * following one (the login link is removed, not its target).
    */
  def remove(dir: Path): IO[Unit] =
    IO.blocking {
      if (Files.exists(dir, LinkOption.NOFOLLOW_LINKS)) {
        val walk = Files.walk(dir)
        try walk.iterator.asScala.toVector.sortBy(-_.getNameCount).foreach(p => Files.deleteIfExists(p))
        finally walk.close()
      }
    }

  /** The session's rollout, by the thread the stream announced and only by
    * it: the file under `sessions/` named after the thread whose first line
    * is that thread's.  None without a thread id.
    */
  def rolloutOf(home: CodexHome, threadId: Option[String]): IO[Option[Path]] =
    threadId.fold(IO.pure(Option.empty[Path])) { t =>
      IO.blocking {
        if (!Files.isDirectory(home.sessions)) None
        else {
          val walk = Files.walk(home.sessions)
          try walk.iterator.asScala.toVector.find(p => Files.isRegularFile(p) && p.getFileName.toString.endsWith(s"-$t.jsonl"))
          finally walk.close()
        }
      }.map(_.filter(p => threadOf(p).contains(t)))
    }

  /** The thread a rollout's first line (its session record) names. */
  private def threadOf(p: Path): Option[String] =
    scala.util.Using(Files.newBufferedReader(p, StandardCharsets.UTF_8))(_.readLine()).toOption.flatMap(Option(_))
      .flatMap(io.circe.parser.parse(_).toOption).flatMap(_.hcursor.downField("payload").get[String]("id").toOption)

  /** A rollout as the archive keeps it: line for line the session's, less
    * what is either the account's or no reading's.  The session record's
    * account ids (`creator_user_id`, `creator_account_id`) and the
    * repository's git block are dropped, and its copy of Codex's own base
    * instructions (the same for every subject of a version, archived once
    * per run by digest) and each reasoning item's `encrypted_content`
    * (opaque to every reader) are replaced by their digest and length.  A
    * line that is not JSON is kept as it is; the credential scrub runs over
    * the result like any other file a subject wrote.
    */
  def archivable(rollout: String): String = {
    def digest(s: String): Json = Json.obj("sha256" -> TextIO.sha256(s).asJson, "chars" -> s.length.asJson)
    rollout.linesIterator.map { line =>
      io.circe.parser.parse(line).toOption.fold(line) { j =>
        val c = j.hcursor
        val out = c.get[String]("type").getOrElse("") match {
          case "session_meta" =>
            c.downField("payload").withFocus(_.mapObject { o =>
              val dropped = o.remove("creator_user_id").remove("creator_account_id").remove("git")
              dropped("base_instructions").flatMap(_.hcursor.get[String]("text").toOption)
                .fold(dropped)(t => dropped.add("base_instructions", Json.obj("text" -> digest(t))))
            }).top
          case "response_item" if c.downField("payload").get[String]("type").toOption.contains("reasoning") =>
            c.downField("payload").withFocus(_.mapObject(o =>
              o("encrypted_content").flatMap(_.asString).fold(o)(e => o.add("encrypted_content", digest(e))))).top
          case _ => Some(j)
        }
        out.getOrElse(j).noSpaces
      }
    }.mkString("", "\n", "\n")
  }

  /** Codex's base instructions as a rollout's session record holds them, for
    * the run's one copy per digest.
    */
  def baseInstructions(rollout: String): Option[String] =
    rollout.linesIterator.take(1).flatMap(io.circe.parser.parse(_).toOption)
      .flatMap(_.hcursor.downField("payload").downField("base_instructions").get[String]("text").toOption).toVector.headOption

  /** The first request the session sent, from its trace bundle, and how
    * many requests the trace holds.  None when the session made none.
    */
  def firstRequest(home: CodexHome): IO[Option[(Json, Int)]] =
    IO.blocking {
      if (!Files.isDirectory(home.trace)) None
      else {
        val bundles = Files.list(home.trace)
        val dirs    = try bundles.iterator.asScala.toVector.filter(Files.isDirectory(_)).sortBy(_.toString) finally bundles.close()
        dirs.iterator.flatMap { d =>
          val log = d.resolve("trace.jsonl")
          if (!Files.isRegularFile(log)) None
          else {
            val starts = new String(Files.readAllBytes(log), StandardCharsets.UTF_8).linesIterator
              .flatMap(l => io.circe.parser.parse(l).toOption).map(_.hcursor.downField("payload"))
              .filter(_.get[String]("type").toOption.contains("inference_started")).toVector
            starts.headOption
              .flatMap(_.downField("request_payload").get[String]("path").toOption)
              .map(d.resolve).filter(Files.isRegularFile(_))
              .flatMap(p => io.circe.parser.parse(new String(Files.readAllBytes(p), StandardCharsets.UTF_8)).toOption)
              .map(_ -> starts.size)
          }
        }.nextOption()
      }
    }

  /** What a request presented: the model, the effort, the service tier, the
    * top-level tools (a namespace's tools as `<namespace>__<tool>`) with
    * their parameter names, the nested tools the code-mode `exec`
    * description declares, and each instruction block of its input by role
    * and digest.  Pure, over the request payload.
    */
  def surfaceOf(request: Json): Json = {
    val c      = request.hcursor
    val input  = c.downField("input").focus.flatMap(_.asArray).getOrElse(Vector.empty)
    val tools  = input.filter(_.hcursor.get[String]("type").toOption.contains("additional_tools"))
                   .flatMap(_.hcursor.downField("tools").focus.flatMap(_.asArray).getOrElse(Vector.empty))
    def flat(t: Json): Vector[(String, Json)] = {
      val tc = t.hcursor
      if (tc.get[String]("type").toOption.contains("namespace")) {
        val ns = tc.get[String]("name").getOrElse("")
        tc.downField("tools").focus.flatMap(_.asArray).getOrElse(Vector.empty).flatMap(flat).map { case (n, j) =>
          (if (ns == "functions" || ns.isEmpty) n else s"${ns}__$n") -> j }
      } else tc.get[String]("name").toOption.map(_ -> t).toVector
    }
    val leaves  = tools.flatMap(flat)
    val execDoc = leaves.collectFirst { case ("exec", j) => j.hcursor.get[String]("description").getOrElse("") }.getOrElse("")
    val nested  = "declare const tools: \\{ ([A-Za-z0-9_]+)\\(".r.findAllMatchIn(execDoc).map(_.group(1)).toVector.distinct
    val params  = leaves.map { case (n, j) =>
      n -> j.hcursor.downField("parameters").downField("properties").focus.flatMap(_.asObject).map(_.keys.toVector.sorted).getOrElse(Vector.empty).asJson }
    val blocks  = input.filter(_.hcursor.get[String]("type").toOption.contains("message")).map { m =>
      val t = m.hcursor.downField("content").focus.flatMap(_.asArray).getOrElse(Vector.empty)
                .flatMap(_.hcursor.get[String]("text").toOption).mkString
      Json.obj("role" -> m.hcursor.get[String]("role").toOption.asJson, "sha256" -> TextIO.sha256(t).asJson, "chars" -> t.length.asJson)
    }
    Json.obj(
      "model"                 -> c.get[String]("model").toOption.asJson,
      "effort"                -> c.downField("reasoning").get[String]("effort").toOption.asJson,
      "serviceTier"           -> c.get[String]("service_tier").toOption.asJson,
      "topLevelTools"         -> leaves.map(_._1).asJson,
      "toolParams"            -> Json.obj(params: _*),
      "nestedTools"           -> nested.asJson,
      "inputBlocks"           -> blocks.asJson,
      "execDescriptionSha256" -> TextIO.sha256(execDoc).asJson)
  }

  /** The digest of a system prompt as Codex sends it: the developer block's text. */
  def promptDigest(systemPrompt: String): String = TextIO.sha256(systemPrompt)

  /** What a rollout records so far, for the caps: every model response's
    * tokens (a compaction is no response, but its tokens are spent), how
    * many calls the last response issued, how many issued calls have no
    * output yet, and whether the turn has ended.
    */
  final case class Progress(responses: Vector[CodexTranscript.CodexUsage], compactions: Vector[CodexTranscript.CodexUsage],
                            lastIssued: Int, open: Int, ended: Boolean)

  def progress(rollout: String): Progress = {
    val recs  = rollout.linesIterator.flatMap(l => io.circe.parser.parse(l).toOption).map(_.hcursor).toVector
    def tpe(c: io.circe.ACursor): String = c.get[String]("type").getOrElse("")
    val comps = recs.filter(c => tpe(c) == "compacted").flatMap(_.downField("payload").get[String]("compaction_response_id").toOption).toSet
    final case class P(rs: Vector[CodexTranscript.CodexUsage], cs: Vector[CodexTranscript.CodexUsage], issued: Int, last: Int,
                       calls: Set[String], outs: Set[String], ended: Boolean)
    val p = recs.foldLeft(P(Vector.empty, Vector.empty, 0, 0, Set.empty, Set.empty, false)) { (p, c) =>
      val pl = c.downField("payload")
      (tpe(c), tpe(pl)) match {
        case ("token_usage_record", _) =>
          val u = CodexTranscript.CodexUsage.of(pl.downField("usage"))
          if (pl.get[String]("response_id").toOption.exists(comps)) p.copy(cs = p.cs :+ u)
          else p.copy(rs = p.rs :+ u, last = p.issued, issued = 0)
        case ("response_item", "function_call" | "custom_tool_call") =>
          p.copy(issued = p.issued + 1, calls = p.calls ++ pl.get[String]("call_id").toOption)
        case ("response_item", "function_call_output" | "custom_tool_call_output") =>
          p.copy(outs = p.outs ++ pl.get[String]("call_id").toOption)
        case ("event_msg", "task_complete") => p.copy(ended = true)
        case _ => p
      }
    }
    Progress(p.rs, p.cs, p.last, (p.calls -- p.outs).size, p.ended)
  }

  /** Is a cap reached?  `max_turns` once the subject has made `maxTurns`
    * responses, `budget` once their tokens cost `maxBudget` at `price`;
    * either only while the turn goes on (the last response called a tool)
    * and once every call has returned, so the stop lands between responses,
    * where a Claude subject's does.  A cell that yielded has returned for
    * this purpose: under this protocol a cell can reach only `apply_patch`
    * and Codex's own resource tools, never an agda tool (their
    * `omit_tools_from` keeps them out of code mode), so no stop can land in
    * agda's in-place edit of the work file.  Two limits remain, both a
    * response late, never early: a response that called nothing but did
    * not end the turn, and a compaction whose summary Codex never recorded,
    * which counts as a response.
    */
  def capReached(rollout: String, price: Option[ModelPrice], maxTurns: Int, maxBudget: BigDecimal): Option[String] = {
    val pr   = progress(rollout)
    val cost = price.map(p => (pr.responses ++ pr.compactions).map(u => p.cost(u.tokens)).sum)
    if (pr.ended || pr.lastIssued == 0 || pr.open > 0) None
    else if (pr.responses.size >= maxTurns) Some("max_turns")
    else if (cost.exists(_ >= maxBudget)) Some("budget")
    else None
  }

  /** Run one subject: the shared spawn (Subject.spawn), with a poll of the
    * rollout for the caps, and INT first on a stop or a kill.
    */
  def run(setup: CodexSetup, env: Map[String, String], home: CodexHome, workDir: Path, prompt: String,
          stdout: Path, stderr: Path, wallCap: scala.concurrent.duration.FiniteDuration, maxTurns: Int, maxBudget: BigDecimal): IO[SubjectRun] = {
    val poll: IO[Option[String]] =
      IO.blocking {
        if (!Files.isDirectory(home.sessions)) None
        else {
          val walk = Files.walk(home.sessions)
          val all  = try walk.iterator.asScala.toVector.filter(p => Files.isRegularFile(p) && p.getFileName.toString.startsWith("rollout-")) finally walk.close()
          all.headOption.filter(_ => all.size == 1).map(p => new String(Files.readAllBytes(p), StandardCharsets.UTF_8))
        }
      }.map(_.flatMap(capReached(_, setup.price, maxTurns, maxBudget)))
    Subject.spawn(argv(setup.codexBin, prompt), env, workDir, stdout, stderr, wallCap, "INT", poll)
  }

  /** End every process still carrying this subject's marker (its servers,
    * which Codex starts in process groups of their own), after the
    * subject, whatever way it ended.  Returns how many were ended.
    */
  def reapMarked(mark: String): IO[Int] =
    IO.blocking {
      val needle = s"$marker=$mark".getBytes(StandardCharsets.UTF_8)
      def has(bytes: Array[Byte]): Boolean =
        new String(bytes, StandardCharsets.ISO_8859_1).split('\u0000').contains(new String(needle, StandardCharsets.ISO_8859_1))
      val procs = Files.list(Paths.get("/proc"))
      val pids  = try procs.iterator.asScala.toVector.map(_.getFileName.toString).filter(_.forall(_.isDigit)) finally procs.close()
      val self  = ProcessHandle.current().pid()
      val hits  = pids.flatMap(_.toLongOption).filter(_ != self).filter { pid =>
        scala.util.Try(Files.readAllBytes(Paths.get(s"/proc/$pid/environ"))).toOption.exists(has)
      }
      hits.flatMap(pid => ProcessHandle.of(pid).toScala).filter(_.isAlive).map { h =>
        h.destroy()
        scala.util.Try(h.onExit().get(5, java.util.concurrent.TimeUnit.SECONDS))
        if (h.isAlive) h.destroyForcibly()
        1
      }.sum
    }

  private implicit final class OptionalOps[A](private val o: java.util.Optional[A]) extends AnyVal {
    def toScala: Option[A] = if (o.isPresent) Some(o.get) else None
  }
}
