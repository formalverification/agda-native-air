/** ============================================================================
  *  Transcript.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Transcript.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  Read what a subject did from the `claude -p --output-format stream-json
  *  --verbose` stream it wrote (issue #154): the init record (which tools the
  *  client presented, whether the agda server connected), every tool call the
  *  model made with the result it got back, the text it wrote, and the final
  *  result record (turns, wall, cost, tokens, how the session ended).  From
  *  those the harness derives the per-tool call counts, the fill_hole attempt
  *  rows, the Read/Edit path audit, and the isolation verdict.
  *
  *  Design notes
  *  ------------
  *  - Lenient by design: every field is optional and a line that is not JSON
  *    is skipped, because the stream is another program's output and a
  *    parser that raised on an unknown record would lose the whole subject.
  *    The one thing that must be present for a row to count is the init
  *    record; its absence is reported as such.
  *  - A tool result's `content` is a string or a list of text blocks; both are
  *    flattened to one text.  The MCP tools' bodies are JSON inside that text
  *    (the same double encoding McpClient unwraps), read here with cursors
  *    rather than the strict Wire decoders, since a refused call's text is
  *    prose and must still be counted.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import io.circe.{ACursor, Json}
import io.circe.parser.parse

/** A tool call the model made: the block id (pairs it with its result), the tool name, the arguments. */
final case class ToolUse(id: String, name: String, input: Json) {
  def str(field: String): Option[String] = input.hcursor.get[String](field).toOption
  def int(field: String): Option[Int]    = input.hcursor.get[Int](field).toOption
}

/** What came back for one tool call. */
final case class ToolResult(toolUseId: String, isError: Boolean, text: String) {
  /** The MCP body as JSON, when the text is JSON. */
  def body: Option[Json] = parse(text).toOption
}

/** The `system/init` record: the client's view of the session at start. */
final case class InitRecord(
  tools:          Vector[String],
  mcpServers:     Vector[(String, String)], // (name, status)
  model:          Option[String],
  version:        Option[String],
  permissionMode: Option[String]
)

/** The `result` record: how the session ended and what it cost. */
final case class ResultRecord(
  subtype:           String,
  isError:           Boolean,
  numTurns:          Int,
  durationMs:        Long,
  durationApiMs:     Option[Long],
  costUsd:           Double,
  usage:             Json,
  permissionDenials: Int,
  text:              String
) {
  private def usageInt(field: String): Long = usage.hcursor.get[Long](field).getOrElse(0L)
  def tokens: Json = Json.obj(
    "input"         -> Json.fromLong(usageInt("input_tokens")),
    "output"        -> Json.fromLong(usageInt("output_tokens")),
    "cacheRead"     -> Json.fromLong(usageInt("cache_read_input_tokens")),
    "cacheCreation" -> Json.fromLong(usageInt("cache_creation_input_tokens"))
  )
}

final case class Transcript(
  init:           Option[InitRecord],
  uses:           Vector[ToolUse],
  results:        Map[String, ToolResult],
  result:         Option[ResultRecord],
  userTexts:      Vector[String],
  assistantTexts: Vector[String],
  rateLimits:     Vector[(String, Double)], // (status, utilization) of every rate_limit_event, in order
  records:        Int
) {
  /** The account's usage window is a real constraint on a sweep: the client
    * reports it as `rate_limit_event` records.  Anything but `allowed` or
    * `allowed_warning` means the subject was refused service, which is a
    * fact about the account, never about the obligation.
    */
  def rateLimitRejected: Boolean = rateLimits.exists { case (s, _) => s != "allowed" && s != "allowed_warning" }
  def rateLimitMax: Option[Double] = rateLimits.map(_._2).maxOption

  def resultOf(u: ToolUse): Option[ToolResult] = results.get(u.id)

  /** Calls per tool name, in first-seen order of the names. */
  def toolCounts: Vector[(String, Int)] =
    uses.map(_.name).distinct.map(n => n -> uses.count(_.name == n))

  def usesOf(name: String): Vector[ToolUse] = uses.filter(_.name == name)

  /** Every file-tool call with the path it named. */
  def filePaths(tools: Set[String]): Vector[(ToolUse, Option[ToolResult], String)] =
    uses.filter(u => tools(u.name)).flatMap(u =>
      u.str("file_path").orElse(u.str("path")).orElse(u.str("filePath")).map(p => (u, resultOf(u), p)))

  /** Did the client hand the model the agda tools as deferred names?  Eager
    * definitions live in the system prompt and never appear in the stream; a
    * deferred presentation lists the names in a user-side reminder.
    */
  def toolsDeferred: Boolean =
    userTexts.exists(t => t.contains("deferred") && t.contains("mcp__agda__"))
}

object Transcript {

  private def textOf(content: ACursor): String =
    content.focus match {
      case Some(j) if j.isString => j.asString.getOrElse("")
      case Some(j) if j.isArray  =>
        j.asArray.getOrElse(Vector.empty).flatMap(b => b.hcursor.get[String]("text").toOption).mkString("\n")
      case _ => ""
    }

  def parse(stream: String): Transcript =
    stream.linesIterator.foldLeft(Transcript(None, Vector.empty, Map.empty, None, Vector.empty, Vector.empty, Vector.empty, 0)) { (acc, line) =>
      io.circe.parser.parse(line).toOption match {
        case None => acc
        case Some(json) =>
          val c = json.hcursor
          val t = c.get[String]("type").getOrElse("")
          val next = t match {
            case "system" if c.get[String]("subtype").toOption.contains("init") =>
              val servers = c.downField("mcp_servers").focus.flatMap(_.asArray).getOrElse(Vector.empty).map { s =>
                (s.hcursor.get[String]("name").getOrElse("?"), s.hcursor.get[String]("status").getOrElse("?"))
              }
              acc.copy(init = Some(InitRecord(
                tools          = c.downField("tools").as[Vector[String]].getOrElse(Vector.empty),
                mcpServers     = servers,
                model          = c.get[String]("model").toOption,
                version        = c.get[String]("claude_code_version").toOption,
                permissionMode = c.get[String]("permissionMode").toOption)))
            case "assistant" =>
              val blocks = c.downField("message").downField("content").focus.flatMap(_.asArray).getOrElse(Vector.empty)
              val uses = blocks.flatMap { b =>
                val bc = b.hcursor
                if (bc.get[String]("type").toOption.contains("tool_use"))
                  for { id <- bc.get[String]("id").toOption; name <- bc.get[String]("name").toOption }
                    yield ToolUse(id, name, bc.downField("input").focus.getOrElse(Json.obj()))
                else None
              }
              val texts = blocks.flatMap(b => if (b.hcursor.get[String]("type").toOption.contains("text")) b.hcursor.get[String]("text").toOption else None)
              acc.copy(uses = acc.uses ++ uses, assistantTexts = acc.assistantTexts ++ texts)
            case "user" =>
              val content = c.downField("message").downField("content")
              val blocks  = content.focus.flatMap(_.asArray).getOrElse(Vector.empty)
              val results = blocks.flatMap { b =>
                val bc = b.hcursor
                if (bc.get[String]("type").toOption.contains("tool_result"))
                  bc.get[String]("tool_use_id").toOption.map(id =>
                    id -> ToolResult(id, bc.get[Boolean]("is_error").getOrElse(false), textOf(bc.downField("content"))))
                else None
              }
              val texts =
                if (content.focus.exists(_.isString)) Vector(textOf(content))
                else blocks.flatMap(b => if (b.hcursor.get[String]("type").toOption.contains("text")) b.hcursor.get[String]("text").toOption else None)
              acc.copy(results = acc.results ++ results, userTexts = acc.userTexts ++ texts)
            case "rate_limit_event" =>
              val info = c.downField("rate_limit_info")
              acc.copy(rateLimits = acc.rateLimits :+ (
                (info.get[String]("status").getOrElse("?"), info.get[Double]("utilization").getOrElse(0.0))))
            case "result" =>
              acc.copy(result = Some(ResultRecord(
                subtype           = c.get[String]("subtype").getOrElse("?"),
                isError           = c.get[Boolean]("is_error").getOrElse(false),
                numTurns          = c.get[Int]("num_turns").getOrElse(0),
                durationMs        = c.get[Long]("duration_ms").getOrElse(0L),
                durationApiMs     = c.get[Long]("duration_api_ms").toOption,
                costUsd           = c.get[Double]("total_cost_usd").getOrElse(0.0),
                usage             = c.downField("usage").focus.getOrElse(Json.obj()),
                permissionDenials = c.downField("permission_denials").focus.flatMap(_.asArray).map(_.size).getOrElse(0),
                text              = c.get[String]("result").getOrElse(""))))
            case _ => acc
          }
          next.copy(records = next.records + 1)
      }
    }
}
