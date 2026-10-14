/** ============================================================================
  *  CodexTranscript.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/CodexTranscript.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  The adapter (issue #239): what a Codex subject did, read from what Codex
  *  wrote, into the records of the `claude -p --output-format stream-json`
  *  transcript that the judge, the audit, and every reader of an archived
  *  run already read (Transcript.scala).  The judge does not change.  A
  *  Codex subject's `transcript.jsonl` is this adapter's output, derived
  *  from Codex's own records, which are archived beside it, every time the
  *  subject is judged, so a fix here re-reads an archive with no model call.
  *
  *  Sources
  *  -------
  *  - The session's rollout (Codex's record of the thread, filtered for the
  *    archive by CodexSubject.archivable): every call the model made, in
  *    order, as `item_completed` events with their results, one
  *    `token_usage_record` per model response, the account's usage windows
  *    (`token_count`), the turn's model and effort (`turn_context`), and the
  *    end (`task_complete`).  It is the primary source: the `--json` stream
  *    has no per-response record, and an item can be dropped from it.
  *  - The `--json` stream: the thread id, a failed turn's message (the
  *    rollout keeps no error), and the items per kind, checked against the
  *    rollout's.
  *  - The surface (CodexSubject.surfaceOf, from the first request the
  *    session sent): the tools, their parameters, the instruction blocks,
  *    the model, and the effort the model was given, and whether Codex
  *    rewrote the configuration.
  *  - The subject's process record (`run.json`): a cap stop or a kill.
  *
  *  The mapping
  *  -----------
  *  - Records are grouped by model response: one assistant record per
  *    `token_usage_record`, carrying the response's text, a `tool_use` for
  *    every call it made, and its usage in the Claude field names; then one
  *    user record with every call's result.  A result is therefore in view
  *    only from the next response on, as with a Claude subject's parallel
  *    calls, which is what "seen before the last edit" compares
  *    (OriginalInView.scala).  A compaction is no response: its tokens are
  *    in the totals and its call in no turn.
  *  - The confined read tool (`mcp__files__read`) is `Read`, with Claude's
  *    input names; a file change is one `Edit` per hunk (`old_string`,
  *    `new_string`, and the hunk's diff), a whole-file add or delete one
  *    `Edit` with an empty side, and a move one more `Edit` on the
  *    destination, every `Edit` of one change tagged with its item
  *    (`codex_call`), so the change counts as one call
  *    (Transcript.toolCounts); a patch Codex refused before applying it
  *    leaves no file change, so the cell's error output becomes one failed
  *    `Edit`, as a Claude subject's refused Edit is one.  A server call is
  *    `mcp__<server>__<tool>`, the name the model itself used, with the
  *    result text the model was shown (the call's output record, cut to the
  *    model's budget, rather than the item, which keeps up to 64 KiB); a
  *    server call Codex never completed (a stop, a kill, arguments that were
  *    no JSON) is still a call, failed, with Codex's output or "aborted".
  *    Codex's own resource tools keep their bare names, which the harness's
  *    fixed surface admits.  Anything else keeps Codex's name (a shell
  *    command is `exec_command`), so the audit sees it as the tool it is.
  *  - A nested call is owned by the cell it ran in: the cell open when it
  *    completed, a cell that yielded staying open (through its `notify`
  *    outputs) until a `wait` reports it ended.  A nested call completed
  *    while cells of different responses were open has no known owner, which
  *    is an anomaly.  Within a response, calls are in the order it issued
  *    them, a nested call at its cell's place.
  *  - The init record names the harness, the version, the model and effort
  *    the turn ran with, the tools the first request presented (Read and
  *    Edit for the mapped ones), the two servers (connected when their tools
  *    were presented), whether the agda tools were deferred, the adapter's
  *    version with the digests of its inputs, and `adapterAnomaly`, the
  *    first thing that makes the row not a measurement (`anomalies`).
  *  - The result record exists when the turn ended on its own (`success`,
  *    which a stop that came too late does not change), failed
  *    (`error_turn_failed`), or was stopped at a cap (`error_max_turns`,
  *    `error_max_budget_usd`); a wall-cap kill leaves none, as with a Claude
  *    subject.  It carries `modelUsage` in the four
  *    priced classes with `costBasis` "none" and no client figure, since
  *    Codex reports no cost.
  *  - Every `token_count` with limits is a `rate_limit_event`: the five-hour
  *    window's use as the utilization, the weekly window's beside it, and
  *    status `rejected` when Codex says a limit was reached or the turn
  *    failed for the plan's usage limit.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import io.circe.{ACursor, Json}
import io.circe.syntax._

import struxdriver.io.TextIO

object CodexTranscript {

  /** The adapter's version, stamped into every derived init record; raised
    * whenever the derivation changes what a transcript says.
    */
  val version: Int = 2

  /** The read tool's server, and the transcript's names for what it maps. */
  val filesServer: String = "files"
  val readName: String    = "Read"
  val editName: String    = "Edit"

  /** Codex's names for the tools a Codex subject is given, as the
    * transcript names them.
    */
  def mapName(codex: String): String = codex match {
    case "mcp__files__read" => readName
    case "apply_patch"      => editName
    case other              => other
  }

  /** What the `--json` stream says: the thread, whether the turn ended or
    * failed and with what message, the error lines, the completed items per
    * kind, and the messages of its `error` items (a rerouted model, a
    * configuration warning), which the rollout does not keep.
    */
  final case class Stream(threadId: Option[String], completed: Boolean, failure: Option[String],
                          errors: Vector[String], items: Map[String, Int], itemErrors: Vector[String])

  def stream(events: String): Stream =
    events.linesIterator.flatMap(l => io.circe.parser.parse(l).toOption).foldLeft(Stream(None, false, None, Vector.empty, Map.empty, Vector.empty)) { (s, j) =>
      val c = j.hcursor
      c.get[String]("type").getOrElse("") match {
        case "thread.started" => s.copy(threadId = c.get[String]("thread_id").toOption)
        case "turn.completed" => s.copy(completed = true)
        case "turn.failed"    => s.copy(failure = Some(c.downField("error").get[String]("message").getOrElse("turn failed")))
        case "error"          => s.copy(errors = s.errors :+ c.get[String]("message").getOrElse(""))
        case "item.completed" =>
          val k = c.downField("item").get[String]("type").getOrElse("?")
          val e = if (k == "error") c.downField("item").get[String]("message").toOption.toVector else Vector.empty
          s.copy(items = s.items.updated(k, s.items.getOrElse(k, 0) + 1), itemErrors = s.itemErrors ++ e)
        case _ => s
      }
    }

  /** The stream's item kind of each rollout kind that maps to a call. */
  private val streamKind: Vector[(String, String)] = Vector(
    "CommandExecution" -> "command_execution", "FileChange" -> "file_change", "McpToolCall" -> "mcp_tool_call")

  /** Rollout items that are no call: the user's prompt, the model's text
    * and reasoning, its plan, a hook's prompt, a top-level call's output
    * (the call itself is a response item), and a compaction.
    */
  private val noCall: Set[String] = Set(
    "UserMessage", "AgentMessage", "Reasoning", "Plan", "HookPrompt", "FunctionCallOutput", "ContextCompaction")

  /** Rollout items that are calls of a tool the protocol does not give a
    * Codex subject: kept under their own names, so the audit finds them.
    */
  private val foreignKinds: Set[String] = Set(
    "CommandExecution", "WebSearch", "ImageView", "ImageGeneration", "CollabAgentToolCall", "DynamicToolCall",
    "Extension", "SubAgentActivity", "EnteredReviewMode", "ExitedReviewMode")

  /** Is this message the ChatGPT plan's usage limit ("You’ve hit your
    * usage limit", with U+2019) or a quota refusal?  The fallback when
    * Codex's structured `rate_limit_reached_type` did not come back.
    */
  def usageLimit(message: String): Boolean = {
    val m = message.toLowerCase
    m.contains("usage limit") || m.contains("quota exceeded")
  }

  /** A login failure Codex cannot recover from: the sweep stops on one. */
  def loginFailure(text: String): Boolean = {
    val m = text.toLowerCase
    m.contains("sign in again") || m.contains("logged out") || m.contains("could not be refreshed") || m.contains("not logged in")
  }

  /** One response's token counts, in Codex's names. */
  final case class CodexUsage(input: Long, cached: Long, written: Long, output: Long, reasoning: Long) {
    def +(o: CodexUsage): CodexUsage = CodexUsage(input + o.input, cached + o.cached, written + o.written, output + o.output, reasoning + o.reasoning)
    /** The four priced classes: uncached input excludes the cached and the
      * written tokens; output includes the reasoning tokens, as billed.
      */
    def tokens: Tokens = Tokens(input = math.max(0L, input - cached - written), output = output, cacheRead = cached, cacheCreation = written)
    def claudeUsage: Vector[(String, Json)] = Vector(
      "input_tokens"                -> tokens.input.asJson,
      "cache_creation_input_tokens" -> tokens.cacheCreation.asJson,
      "cache_read_input_tokens"     -> tokens.cacheRead.asJson,
      "output_tokens"               -> tokens.output.asJson,
      "reasoning_output_tokens"     -> reasoning.asJson)
  }
  object CodexUsage {
    val zero: CodexUsage = CodexUsage(0, 0, 0, 0, 0)
    def of(j: ACursor): CodexUsage = {
      def n(k: String): Long = j.get[Long](k).getOrElse(0L)
      CodexUsage(n("input_tokens"), n("cached_input_tokens"), n("cache_write_input_tokens"), n("output_tokens"), n("reasoning_output_tokens"))
    }
  }

  /** The script a shell call ran: the last element of `[shell, -c|-lc, script]`, else the vector joined. */
  def scriptOf(argv: Vector[String]): String =
    argv match {
      case Vector(_, flag, script) if flag == "-c" || flag == "-lc" => script
      case other                                                    => other.mkString(" ")
    }

  /** The hunks of a unified diff, each as the text it replaced and the text
    * it wrote (context lines in both), so the hunk reads as Claude's Edit.
    */
  def hunks(diff: String): Vector[(String, String)] = {
    val lines = diff.split("\n", -1).toVector
    val starts = lines.indices.filter(i => lines(i).startsWith("@@")).toVector
    starts.zipWithIndex.map { case (s, k) =>
      val body = lines.slice(s + 1, if (k + 1 < starts.size) starts(k + 1) else lines.size)
                   .filterNot(_.startsWith("\\ No newline"))
      val old  = body.collect { case l if l.startsWith(" ") || l.startsWith("-") => l.drop(1) }
      val nu   = body.collect { case l if l.startsWith(" ") || l.startsWith("+") => l.drop(1) }
      (old.mkString("\n"), nu.mkString("\n"))
    }
  }

  private def text(s: String): Json = Json.obj("type" -> "text".asJson, "text" -> s.asJson)

  private def toolUse(id: String, name: String, input: Json): Json =
    Json.obj("type" -> "tool_use".asJson, "id" -> id.asJson, "name" -> name.asJson, "input" -> input)

  private def toolResult(id: String, isError: Boolean, content: String): Json =
    Json.obj("type" -> "tool_result".asJson, "tool_use_id" -> id.asJson, "is_error" -> isError.asJson, "content" -> content.asJson)

  /** One call: its `tool_use` block and its `tool_result` block, and
    * whether the client refused it (a permission denial).
    */
  final case class Call(use: Json, result: Json, denied: Boolean)

  /** The text of an MCP result's content blocks, joined, as Transcript.textOf joins Claude's. */
  private def contentText(content: Json): String =
    content.asArray.getOrElse(Vector.empty).flatMap(b => b.hcursor.get[String]("text").toOption.orElse(b.asString)).mkString("\n")

  /** Codex's own MCP-resource tools, which it records as server calls (on
    * the server the model named, "codex" when it named none): kept under
    * their bare names, as the harness's fixed surface admits them.
    */
  val resourceTools: Set[String] = Set("list_mcp_resources", "list_mcp_resource_templates", "read_mcp_resource")

  /** One server call as the transcript names it. */
  private def serverCall(id: String, server: String, tool: String, args: Json, isError: Boolean, body: String, denied: Boolean): Call = {
    val (name, input) =
      if (server == filesServer && tool == "read") (readName, Json.fromFields(Vector("file_path", "offset", "limit")
        .map(k => k -> args.hcursor.downField(k).focus) collect { case (k, Some(v)) => k -> v }))
      else if (resourceTools(tool)) (tool, args)
      else (s"mcp__${server}__$tool", args)
    Call(toolUse(id, name, input), toolResult(id, isError, body), denied)
  }

  /** The text items of an output record, in order (a string body is one). */
  def outputItems(output: ACursor): Vector[String] =
    output.focus match {
      case Some(j) if j.isString => j.asString.toVector
      case Some(j)               => j.asArray.getOrElse(Vector.empty).flatMap(_.hcursor.get[String]("text").toOption)
      case None                  => Vector.empty
    }

  private val wallTime = "^Wall time: [0-9.]+ seconds\nOutput:\n?".r

  /** What the model was shown of a top-level call's result: its output
    * record's text without the wall-time line Codex puts first.
    */
  def shown(items: Vector[String]): String =
    items match {
      case h +: rest => wallTime.findPrefixOf(h) match {
        case Some(p) => (if (h.length == p.length) rest else h.drop(p.length) +: rest).mkString("\n")
        case None    => items.mkString("\n")
      }
      case _ => ""
    }

  /** The status line of a code-mode cell's output ("Script completed",
    * "Script running with cell ID 3", ...).
    */
  def cellStatus(items: Vector[String]): String = items.headOption.flatMap(_.linesIterator.toVector.headOption).getOrElse("")

  /** A status that ends a cell; "Script running ..." leaves it running, and an
    * output with no status (a `notify`, an error before the cell ran) says
    * nothing of its end.
    */
  def cellEnded(status: String): Boolean =
    status == "Script completed" || status == "Script failed" || status == "Script terminated"

  /** The messages by which Codex refuses a patch before applying it (its
    * handler's, and code mode's for a call that is no patch), and the ones of
    * those that are a refusal of the write itself.
    */
  private val patchRefusals: Vector[String] = Vector("apply_patch verification failed", "apply_patch handler received",
    "patch rejected:", "failed to prepare patch permissions", "failed to check patch permissions",
    "tool `apply_patch` expects", "apply_patch is unavailable", "apply_patch environment selection is unavailable")
  def patchFailures(output: String): Vector[String] = output.linesIterator.map(_.trim).filter(l => patchRefusals.exists(l.contains)).toVector
  def patchFailure(output: String): Option[String] = patchFailures(output).headOption
  private def patchDenied(message: String): Boolean = message.contains("patch rejected:") || message.contains("rejected by user approval settings")
  /** A patch's file line, inside the cell's JavaScript: the patch is a
    * string literal there, so the path ends at a newline, an escape, or a
    * quote.
    */
  private val patchPath = """\*\*\* (?:Update|Add|Delete) File: ([^\n\r\\"'`\u0000]+)""".r

  /** A path a patch names, absolute (a relative one is the work directory's);
    * text that is no path is kept as written.
    */
  private def absolute(p: String, cwd: Option[String]): String =
    scala.util.Try {
      val path = java.nio.file.Paths.get(p)
      if (path.isAbsolute) p else cwd.fold(p)(c => java.nio.file.Paths.get(c).resolve(path).normalize.toString)
    }.getOrElse(p)

  /** Every file the patches of a cell name, in order, absolute. */
  def patchTargets(patch: String, cwd: Option[String]): Vector[String] =
    patchPath.findAllMatchIn(patch).map(_.group(1).trim).filter(_.nonEmpty).map(absolute(_, cwd)).toVector.distinct

  /** The file a patch names first. */
  def patchTarget(patch: String, cwd: Option[String]): Option[String] = patchTargets(patch, cwd).headOption

  /** The calls one rollout item maps to, or None when the item is of a
    * kind the adapter does not know, which is an anomaly, not a skip.
    */
  def callsOf(item: ACursor): Option[Vector[Call]] = {
    val kind   = item.get[String]("type").getOrElse("?")
    val id     = item.get[String]("id").getOrElse("codex-item")
    val status = item.get[String]("status").getOrElse("?")
    kind match {
      case k if noCall(k) => Some(Vector.empty)
      case "McpToolCall" =>
        val server  = item.get[String]("server").getOrElse("?")
        val tool    = item.get[String]("tool").getOrElse("?")
        val args    = item.downField("arguments").focus.filterNot(_.isNull).getOrElse(Json.obj())
        val error   = item.downField("error").get[String]("message").toOption
        val body    = item.downField("result").downField("content").focus.map(contentText).orElse(error).getOrElse("")
        val isError = status == "failed" || item.downField("result").get[Boolean]("isError").getOrElse(false) ||
                      item.downField("result").get[Boolean]("is_error").getOrElse(false)
        val denied  = error.exists(_.toLowerCase.contains("requires approval"))
        Some(Vector(serverCall(id, server, tool, args, isError, body, denied)))
      case "FileChange" =>
        val changes = item.downField("changes").focus.flatMap(_.asObject).toVector.flatMap(_.toVector).sortBy(_._1)
        val out     = (item.get[String]("stdout").getOrElse("") + item.get[String]("stderr").getOrElse("")).trim
        val failed  = status != "completed"
        val denied  = failed && out.toLowerCase.contains("rejected")
        Some(changes.zipWithIndex.flatMap { case ((path, change), i) =>
          val c    = change.hcursor
          val kind = c.get[String]("type").getOrElse("update")
          val edits: Vector[(String, Json)] = kind match {
            case "add"    => Vector(path -> Json.obj("file_path" -> path.asJson, "old_string" -> "".asJson,
                               "new_string" -> c.get[String]("content").getOrElse("").asJson, "kind" -> "add".asJson))
            case "delete" => Vector(path -> Json.obj("file_path" -> path.asJson, "old_string" -> c.get[String]("content").getOrElse("").asJson,
                               "new_string" -> "".asJson, "kind" -> "delete".asJson))
            case _ =>
              val diff  = c.get[String]("unified_diff").getOrElse("")
              val parts = hunks(diff)
              val main  = (if (parts.isEmpty) Vector(("", "")) else parts).map { case (o, n) =>
                path -> Json.obj("file_path" -> path.asJson, "old_string" -> o.asJson, "new_string" -> n.asJson, "kind" -> "update".asJson,
                                 "unified_diff" -> diff.asJson)
              }
              // A move writes the destination too, which the path audit must see.
              main ++ c.get[String]("move_path").toOption.filter(_.nonEmpty).map(dest =>
                dest -> Json.obj("file_path" -> dest.asJson, "old_string" -> "".asJson, "new_string" -> "".asJson,
                                 "kind" -> "move".asJson, "moved_from" -> path.asJson)).toVector
          }
          edits.zipWithIndex.map { case ((_, input), j) =>
            val cid = s"$id-$i-$j"
            Call(toolUse(cid, editName, input.deepMerge(Json.obj("codex_call" -> id.asJson))), toolResult(cid, failed, out), denied)
          }
        })
      case "CommandExecution" =>
        val argv = item.get[Vector[String]]("command").getOrElse(Vector.empty)
        Some(Vector(Call(
          toolUse(id, "exec_command", Json.obj("command" -> scriptOf(argv).asJson, "argv" -> argv.asJson,
            "cwd" -> item.get[String]("cwd").toOption.asJson)),
          toolResult(id, status != "completed", item.get[String]("aggregated_output").getOrElse("")),
          status == "declined")))
      case k if foreignKinds(k) =>
        Some(Vector(Call(toolUse(id, k, item.focus.getOrElse(Json.obj())), toolResult(id, status == "failed", ""), false)))
      case _ => None
    }
  }

  /** A model response as the transcript groups it. */
  private final case class Response(id: Option[String], texts: Vector[String], usage: Option[CodexUsage],
                                    calls: Vector[Call], rates: Vector[Json])

  /** A rate-limit record from a `token_count`'s limits. */
  def rateLimit(limits: ACursor): Option[Json] = {
    val five = limits.downField("primary").get[Double]("used_percent").toOption
    val week = limits.downField("secondary").get[Double]("used_percent").toOption
    val hit  = limits.get[String]("rate_limit_reached_type").toOption.filter(_.nonEmpty)
    if (five.isEmpty && week.isEmpty && hit.isEmpty) None
    else Some(Json.obj("type" -> "rate_limit_event".asJson, "rate_limit_info" -> Json.obj(
      "status"         -> (if (hit.isDefined) "rejected" else "allowed").asJson,
      "utilization"    -> five.map(_ / 100).getOrElse(0.0).asJson,
      "unifiedWindows" -> Json.obj(
        "five_hour" -> Json.obj("utilization" -> five.map(_ / 100).asJson,
                                "resetsAt" -> limits.downField("primary").get[Long]("resets_at").toOption.asJson),
        "seven_day" -> Json.obj("utilization" -> week.map(_ / 100).asJson,
                                "resetsAt" -> limits.downField("secondary").get[Long]("resets_at").toOption.asJson)),
      "reachedType"    -> hit.asJson,
      "planType"       -> limits.get[String]("plan_type").toOption.asJson,
      "credits"        -> limits.downField("credits").focus.asJson)))
  }

  /** What the run expected of every subject, from its protocol: the model,
    * the effort, Codex's version string, and the digest of the subject's own
    * rendered system prompt.
    */
  final case class Expected(model: Option[String], effort: Option[String], version: Option[String], systemPromptSha256: Option[String])

  /** How the subject's process ended, from its `run.json`. */
  final case class Ended(killed: Boolean, stopped: Option[String])

  /** The derivation: the stream-json records of one Codex subject.  Pure
    * and deterministic: ids are Codex's item ids, and nothing reads a
    * clock.
    */
  def derive(rollout: String, events: String, surface: Option[Json], stderr: String, expected: Expected, ended: Ended): Vector[Json] = {
    val s        = stream(events)
    val records  = rollout.linesIterator.flatMap(l => io.circe.parser.parse(l).toOption).toVector
    def payloads(tpe: String): Vector[ACursor] = records.filter(_.hcursor.get[String]("type").toOption.contains(tpe)).map(_.hcursor.downField("payload"))
    val meta     = payloads("session_meta").headOption
    val context  = payloads("turn_context").headOption
    val compacts = payloads("compacted").flatMap(_.get[String]("compaction_response_id").toOption).toSet
    val sc       = surface.map(_.hcursor)
    val model    = context.flatMap(_.get[String]("model").toOption).orElse(sc.flatMap(_.get[String]("model").toOption))
    val effort   = context.flatMap(_.get[String]("effort").toOption).orElse(sc.flatMap(_.get[String]("effort").toOption))
    val cliVer   = meta.flatMap(_.get[String]("cli_version").toOption)
    val top      = sc.flatMap(_.get[Vector[String]]("topLevelTools").toOption).getOrElse(Vector.empty)
    val nested   = sc.flatMap(_.get[Vector[String]]("nestedTools").toOption).getOrElse(Vector.empty)
    val presented = (top ++ nested).map(mapName).distinct
    val agdaTop  = top.filter(_.startsWith(Arm.agdaPrefix))
    val readTop  = top.contains("mcp__files__read")
    val itemKinds = payloads("event_msg").filter(_.get[String]("type").toOption.contains("item_completed"))
                      .map(_.downField("item")).map(i => (i, i.get[String]("type").getOrElse("?")))

    val cwd      = meta.flatMap(_.get[String]("cwd").toOption)

    // Walk the rollout, owning every text and call by the response that
    // issued it.  Response k is the one its k-th usage record closes; a text
    // and a call's issuing item (a `function_call`, or the `exec` cell a
    // nested call runs in) come before that record, while the call itself
    // may complete before it (a top-level tool runs as soon as the response
    // has streamed the call) or after it (a cell runs once the response is
    // done).  So a call is owned by the response of the item that issued it,
    // matched by call id, or by the cell still open when it completed; a
    // cell that yielded stays open until a `wait` on it reports it ended.
    // Within a response, calls are in the order they were issued (a nested
    // call at its cell's place), as a Claude transcript has them, not in the
    // order they completed.
    final case class Acc(id: Option[String], texts: Vector[String], calls: Vector[(Int, Call)], rates: Vector[Json], usage: Option[CodexUsage])
    final case class Pending(owner: Int, server: String, tool: String, args: String)
    final case class Walk(resp: Int, owners: Map[String, Int], open: Vector[(String, Int)], acc: Map[Int, Acc],
                          unknown: Vector[String], cells: Int, waits: Int, servers: Map[String, Pending], answered: Set[String],
                          outputs: Map[String, Vector[String]], cellInputs: Map[String, String], cellIds: Map[String, String],
                          waitCells: Map[String, String], ambiguous: Int, issued: Map[String, Int]) {
      def at(k: Int): Acc = acc.getOrElse(k, Acc(None, Vector.empty, Vector.empty, Vector.empty, None))
      def put(k: Int, f: Acc => Acc): Walk = copy(acc = acc.updated(k, f(at(k))))
      def add(k: Int, order: Int, calls: Vector[Call]): Walk =
        if (calls.isEmpty) this else put(k, a => a.copy(calls = a.calls ++ calls.map(order -> _)))
      /** A call issued now: its place in the order, and its response. */
      def issue(id: String): Walk = copy(issued = issued.updated(id, issued.size), owners = owners.updated(id, resp))
      /** The response a completed item belongs to, its place, and whether that is a guess. */
      def ownerOf(id: Option[String]): (Int, Int, Boolean) =
        id.filter(owners.contains).map(i => (owners(i), issued.getOrElse(i, Int.MaxValue), false)).getOrElse {
          val cand = open.map(_._2).distinct
          open.lastOption.fold((math.max(resp - 1, 0), Int.MaxValue, false)) { case (cell, owner) =>
            (owner, issued.getOrElse(cell, Int.MaxValue), cand.size > 1) }
        }
      def close(cell: String): Walk = copy(open = open.filterNot(_._1 == cell))
      /** A cell's output (or a `wait`'s on it): each patch Codex refused is
        * one failed Edit of the cell's response, of the files its message
        * names, else of every file the cell's patches name.
        */
      def refusedPatches(cell: String, out: Vector[String]): Walk =
        cellInputs.get(cell).filter(_.contains("apply_patch")).fold(this) { input =>
          val files = patchTargets(input, cwd)
          patchFailures(out.mkString("\n")).zipWithIndex.foldLeft(this) { case (w, (why, k)) =>
            val cid    = s"$cell-refused-${outputs.size}-$k"
            val named  = files.filter(why.contains)
            val paths  = if (named.nonEmpty) named else files
            val edits  = (if (paths.isEmpty) Vector(None) else paths.map(Some(_))).zipWithIndex.map { case (f, j) =>
              val id = s"$cid-$j"
              Call(toolUse(id, editName, Json.fromFields(f.map(x => "file_path" -> x.asJson).toVector ++ Vector(
                "old_string" -> "".asJson, "new_string" -> "".asJson, "kind" -> "refused".asJson, "codex_call" -> cid.asJson))),
                toolResult(id, true, why), patchDenied(why))
            }
            w.add(owners.getOrElse(cell, math.max(resp - 1, 0)), issued.getOrElse(cell, Int.MaxValue), edits)
          }
        }
    }
    val walk = records.foldLeft(Walk(0, Map.empty, Vector.empty, Map.empty, Vector.empty, 0, 0, Map.empty, Set.empty,
                                      Map.empty, Map.empty, Map.empty, Map.empty, 0, Map.empty)) { (w, r) =>
      val c = r.hcursor
      val p = c.downField("payload")
      (c.get[String]("type").getOrElse(""), p.get[String]("type").getOrElse("")) match {
        case ("event_msg", "item_completed") =>
          val item = p.downField("item")
          item.get[String]("type").getOrElse("?") match {
            case "AgentMessage" =>
              val text = item.downField("content").focus.flatMap(_.asArray).getOrElse(Vector.empty)
                           .flatMap(b => b.hcursor.get[String]("text").toOption).mkString("\n")
              if (text.isEmpty) w else w.put(w.resp, a => a.copy(texts = a.texts :+ text))
            case k => callsOf(item) match {
              case Some(calls) if calls.isEmpty => w
              case Some(calls) =>
                val id                 = item.get[String]("id").toOption
                val (owner, order, ag) = w.ownerOf(id)
                w.add(owner, order, calls).copy(answered = w.answered ++ id.filter(_ => k == "McpToolCall"),
                                                ambiguous = w.ambiguous + (if (ag) 1 else 0))
              case None => w.copy(unknown = w.unknown :+ k)
            }
          }
        case ("event_msg", "token_count") =>
          rateLimit(p.downField("rate_limits")).fold(w)(j => w.put(math.max(w.resp - 1, 0), a => a.copy(rates = a.rates :+ j)))
        case ("token_usage_record", _) if !p.get[String]("response_id").toOption.exists(compacts) =>
          w.put(w.resp, a => a.copy(id = p.get[String]("response_id").toOption, usage = Some(CodexUsage.of(p.downField("usage"))))).copy(resp = w.resp + 1)
        case ("response_item", "custom_tool_call") =>
          val id = p.get[String]("call_id").getOrElse(s"codex-cell-${w.cells}")
          w.issue(id).copy(open = w.open :+ (id -> w.resp),
                           cellInputs = w.cellInputs.updated(id, p.get[String]("input").getOrElse("")),
                           cells = w.cells + (if (p.get[String]("name").toOption.contains("exec")) 1 else 0))
        case ("response_item", "custom_tool_call_output") =>
          // A cell ends on an ending status, or on an output with none (an
          // error before it ran) unless it had yielded, whose later outputs
          // with none are its `notify` calls.
          val id      = p.get[String]("call_id").getOrElse("")
          val out     = outputItems(p.downField("output"))
          val status  = cellStatus(out)
          val running = "Script running with cell ID "
          val yielded = w.cellIds.values.exists(_ == id)
          val w1 =
            if (status.startsWith(running)) w.copy(cellIds = w.cellIds.updated(status.stripPrefix(running).trim, id))
            else if (cellEnded(status) || !yielded) w.close(id)
            else w
          w1.refusedPatches(id, out).copy(outputs = w1.outputs.updated(id, out))
        case ("response_item", "function_call_output") =>
          val id   = p.get[String]("call_id").getOrElse("")
          val out  = outputItems(p.downField("output"))
          val cell = w.waitCells.get(id).flatMap(w.cellIds.get)
          val w1   = cell.fold(w)(x => if (cellEnded(cellStatus(out))) w.close(x) else w)
          cell.fold(w1)(x => w1.refusedPatches(x, out)).copy(outputs = w1.outputs.updated(id, out))
        case ("response_item", "function_call") =>
          val name = p.get[String]("name").getOrElse("?")
          val id   = p.get[String]("call_id").getOrElse(s"codex-call-${w.resp}")
          val raw  = p.get[String]("arguments").getOrElse("")
          val w1   = w.issue(id)
          // A server's call is its own item, once Codex completes it; any
          // other top-level call (`wait`, the asynchronous question) is
          // recorded here.
          p.get[String]("namespace").toOption.filter(_.startsWith("mcp__")) match {
            case Some(ns) => w1.copy(servers = w1.servers.updated(id, Pending(w.resp, ns.stripPrefix("mcp__"), name, raw)))
            case None =>
              val args = io.circe.parser.parse(raw).toOption.getOrElse(Json.obj())
              val cell = args.hcursor.downField("cell_id").focus.flatMap(j => j.asString.orElse(j.asNumber.map(_.toString)))
              val call = Call(toolUse(id, name, args), toolResult(id, false, ""), false)
              w1.add(w.resp, w1.issued(id), Vector(call)).copy(waits = w.waits + (if (name == "wait") 1 else 0),
                                               waitCells = cell.filter(_ => name == "wait").fold(w1.waitCells)(x => w1.waitCells.updated(id, x)))
          }
        case _ => w
      }
    }
    // A server call Codex never completed (stopped, killed, or arguments it
    // could not parse) is still a call: failed, with Codex's output or
    // "aborted", in the response that issued it.
    val unanswered = walk.servers.filterNot { case (id, _) => walk.answered(id) }.toVector.sortBy(_._1)
    val completed  = unanswered.foldLeft(walk) { case (w, (id, u)) =>
      val args = io.circe.parser.parse(u.args).toOption.filter(_.isObject).getOrElse(Json.obj("arguments" -> u.args.asJson))
      w.add(u.owner, walk.issued.getOrElse(id, Int.MaxValue),
            Vector(serverCall(id, u.server, u.tool, args, true, walk.outputs.get(id).map(shown).getOrElse("aborted"), false)))
    }
    // A top-level call's result is the text of its output record, which is
    // what the model was shown.
    def asShown(call: Call): Call = {
      val id = call.use.hcursor.get[String]("id").getOrElse("")
      walk.outputs.get(id).filter(_ => walk.owners.contains(id))
        .fold(call)(out => call.copy(result = call.result.mapObject(_.add("content", shown(out).asJson))))
    }
    val responses = completed.acc.toVector.sortBy(_._1).map { case (_, a) =>
      Response(a.id, a.texts, a.usage, a.calls.sortBy(_._1).map(c => asShown(c._2)), a.rates) }
    val usages    = responses.flatMap(_.usage)
    val compacted = payloads("token_usage_record").filter(_.get[String]("response_id").toOption.exists(compacts)).map(u => CodexUsage.of(u.downField("usage")))
    val total     = (usages ++ compacted).foldLeft(CodexUsage.zero)(_ + _)
    // An agda tool that edits the work file in place, still running when the
    // subject was ended: no output, or Codex's answer for an aborted call (a
    // call refused at once, for arguments that were no JSON, ran nothing).
    val patching  = unanswered.collect { case (id, u) if u.server == "agda" && (u.tool == "fill_hole" || u.tool == "get_goal") &&
                      walk.outputs.get(id).forall(o => shown(o).startsWith("aborted")) => u.tool }.distinct
    val mapped    = streamKind.map { case (r, k) => (k, itemKinds.count(_._2 == r), s.items.getOrElse(k, 0)) }
    val started   = s.threadId.isDefined || meta.isDefined
    val failText  = (s.failure.toVector ++ s.errors :+ stderr).mkString("\n")
    val blocks    = sc.flatMap(_.downField("inputBlocks").focus.flatMap(_.asArray)).getOrElse(Vector.empty)
    val devDigests = blocks.filter(_.hcursor.get[String]("role").toOption.contains("developer")).flatMap(_.hcursor.get[String]("sha256").toOption)
    val params    = sc.flatMap(_.downField("toolParams").focus.flatMap(_.asObject)).map(_.toMap).getOrElse(Map.empty[String, Json])

    // The first thing that makes the row not a measurement.
    val anomaly: Option[String] = Vector(
      if (loginFailure(failText)) Some("the Codex login failed (see stderr.log); the sweep stops") else None,
      failText.linesIterator.find(_.contains("required MCP servers failed to initialize"))
        .map(l => s"a required MCP server failed to start: ${l.trim.take(300)}"),
      for { t <- s.threadId; m <- meta; id = m.get[String]("id").getOrElse("?") if id != t } yield s"the rollout is thread $id, the stream's $t",
      if (s.threadId.isDefined && meta.isEmpty) Some("the session started and no rollout was kept") else None,
      if (walk.unknown.nonEmpty) Some(s"Codex recorded items the adapter does not know: ${walk.unknown.distinct.mkString(", ")}") else None,
      Some(patching).filter(_.nonEmpty && (ended.killed || ended.stopped.isDefined)).map(ts =>
        s"the subject was ended during agda's ${ts.mkString(" and ")}, which edits the work file in place and restores it after; the final file is not known to be the subject's"),
      s.itemErrors.find(_.startsWith("model rerouted")).map(m => s"Codex reports the backend rerouted the model: ${m.take(300)}"),
      s.itemErrors.find(_.contains("event stream lagged")).map(m => s"the --json stream dropped events, so a rerouted model could go unseen: ${m.take(200)}"),
      Some(walk.ambiguous).filter(_ > 0).map(n => s"$n nested call(s) completed while cells of different responses were open, so their response is not known"),
      mapped.collectFirst { case (k, inRollout, inStream) if !ended.killed && inRollout < inStream =>
        s"the rollout holds $inRollout $k items and the stream $inStream" },
      if (started && surface.isEmpty) Some("no surface: the first request was not read") else None,
      for { e <- expected.version; v <- cliVer if !e.contains(v) } yield s"Codex $v ran, the protocol's is $e",
      for { e <- expected.model; m <- model if m != e } yield s"the turn ran $m, the protocol's model is $e",
      for { e <- expected.effort; f <- effort if f != e } yield s"the turn ran at effort $f, the protocol's is $e",
      Some(nested.filter(_.startsWith("mcp__"))).filter(_.nonEmpty).map(ns => s"server tools presented inside code mode: ${ns.mkString(", ")}"),
      for { e <- expected.systemPromptSha256 if surface.isDefined && !devDigests.contains(e) } yield "the system prompt is not among the request's developer blocks",
      Some(blocks.size).filter(n => surface.isDefined && n != 3).map(n => s"the first request carried $n instruction blocks, not the base instructions, the system prompt, and the user prompt"),
      Some(agdaTop.filter(t => params.get(t).flatMap(_.asArray).forall(_.isEmpty))).filter(_.nonEmpty)
        .map(ts => s"agda tools presented with no named parameter: ${ts.mkString(", ")}"),
      if (sc.flatMap(_.get[Boolean]("configChanged").toOption).contains(true)) Some("Codex rewrote the subject's config.toml") else None
    ).flatten.headOption

    val init = Json.obj(
      "type"           -> "system".asJson,
      "subtype"        -> "init".asJson,
      "harness"        -> "codex".asJson,
      "codex_version"  -> cliVer.asJson,
      "model"          -> model.asJson,
      "effort"         -> effort.asJson,
      "cwd"            -> meta.flatMap(_.get[String]("cwd").toOption).asJson,
      "permissionMode" -> context.flatMap(_.get[String]("approval_policy").toOption).asJson,
      "tools"          -> presented.asJson,
      "mcp_servers"    -> Json.arr(
                            Json.obj("name" -> "agda".asJson, "status" -> (if (agdaTop.nonEmpty) "connected" else "failed").asJson),
                            Json.obj("name" -> filesServer.asJson, "status" -> (if (readTop) "connected" else "failed").asJson)),
      "deferred"       -> (if (surface.isEmpty) Json.Null else (agdaTop.isEmpty).asJson),
      "adapter"        -> Json.obj("version" -> version.asJson, "inputs" -> Json.obj(
                            "rollout" -> TextIO.sha256(rollout).asJson, "events" -> TextIO.sha256(events).asJson,
                            "surface" -> surface.map(j => TextIO.sha256(j.noSpaces)).asJson)),
      "adapterAnomaly" -> anomaly.asJson
    ).dropNullValues

    val body = responses.flatMap { r =>
      val assistant = Json.obj("type" -> "assistant".asJson, "message" -> Json.fromFields(
        r.id.map(i => "id" -> i.asJson).toVector ++ Vector(
          "role"    -> "assistant".asJson,
          "content" -> Json.arr((r.texts.map(text) ++ r.calls.map(_.use)): _*)) ++
        r.usage.map(u => "usage" -> Json.fromFields(u.claudeUsage)).toVector))
      val results = if (r.calls.isEmpty) Vector.empty
                    else Vector(Json.obj("type" -> "user".asJson, "message" -> Json.obj(
                      "role" -> "user".asJson, "content" -> Json.arr(r.calls.map(_.result): _*))))
      (assistant +: results) ++ r.rates
    }

    val refused = s.failure.filter(usageLimit).orElse(s.errors.find(usageLimit)).map { m =>
      Json.obj("type" -> "rate_limit_event".asJson, "rate_limit_info" -> Json.obj(
        "status" -> "rejected".asJson, "utilization" -> 1.0.asJson, "message" -> m.asJson))
    }
    val done  = payloads("event_msg").find(_.get[String]("type").toOption.contains("task_complete"))
    val words = done.flatMap(_.get[String]("last_agent_message").toOption).orElse(responses.flatMap(_.texts).lastOption).getOrElse("")
    // A turn the stream reports completed ended on its own, whatever stop
    // was sent after it (an interrupted turn emits no `turn.completed`).
    val endedAs: Option[(String, Boolean, String)] =
      ended.stopped match {
        case _ if s.completed  => Some(("success", false, words))
        case Some("max_turns") => Some(("error_max_turns", true, words))
        case Some("budget")    => Some(("error_max_budget_usd", true, words))
        case _ if s.failure.isDefined => Some(("error_turn_failed", true, s.failure.getOrElse("")))
        case _                 => None
      }
    val result = endedAs.map { case (subtype, isError, last) =>
      Json.obj(
        "type"               -> "result".asJson,
        "subtype"            -> subtype.asJson,
        "is_error"           -> isError.asJson,
        "num_turns"          -> usages.size.asJson,
        "duration_ms"        -> done.flatMap(_.get[Long]("duration_ms").toOption).asJson,
        "usage"              -> Json.fromFields(total.claudeUsage ++ Vector(
                                  "service_tier"           -> sc.flatMap(_.get[String]("serviceTier").toOption).asJson,
                                  "long_context_responses" -> usages.count(_.input > 272000L).asJson)).dropNullValues,
        "modelUsage"         -> Json.obj(model.toVector.map(m => m -> Json.obj(
                                  "inputTokens"              -> total.tokens.input.asJson,
                                  "outputTokens"             -> total.tokens.output.asJson,
                                  "cacheReadInputTokens"     -> total.tokens.cacheRead.asJson,
                                  "cacheCreationInputTokens" -> total.tokens.cacheCreation.asJson,
                                  "reasoningOutputTokens"    -> total.reasoning.asJson,
                                  "provider"                 -> "openai".asJson,
                                  "costBasis"                -> ModelUsage.noFigure.asJson)): _*),
        "permission_denials" -> Json.arr(responses.flatMap(_.calls).filter(_.denied).map(_.use): _*),
        "result"             -> last.asJson,
        "codex"              -> Json.obj(
                                  "execCells"    -> walk.cells.asJson,
                                  "waits"        -> walk.waits.asJson,
                                  "compactions"  -> compacts.size.asJson,
                                  "streamErrors" -> s.errors.size.asJson,
                                  "itemErrors"   -> s.itemErrors.size.asJson)
      ).dropNullValues
    }
    (if (started || anomaly.isDefined) Vector(init) else Vector.empty) ++ body ++ refused.toVector ++ result.toVector
  }

  /** The derived transcript as the file holds it, one record per line. */
  def render(records: Vector[Json]): String = records.map(_.noSpaces).mkString("", "\n", if (records.isEmpty) "" else "\n")
}
