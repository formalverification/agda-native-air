/** ============================================================================
  *  CodexTranscriptSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/CodexTranscriptSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins the adapter (issue #239) against what Codex CLI 0.162.1 wrote for
  *  real subjects, kept VERBATIM under test/resources/agentbench/codex/ but
  *  for the archive's filter (CodexSubject.archivable: the account's ids and
  *  the repository's git block dropped, the base instructions and the
  *  encrypted reasoning reduced to digests):
  *
  *    + `smoke/`: the persisted smoke subject `smoke239-sol-1` (GPT-6.1 Sol,
  *      effort low, stdlib-nat-plus-comm, 2026-10-13): one read, one patch,
  *      one check_file, solved in four responses.  Its derived transcript is
  *      re-derived byte for byte.
  *    + `turncap/`: the same row under `--max-turns 1`, stopped by the
  *      harness after its first response.
  *    + `s3/`: a spike subject of the design's first protocol, before the
  *      shell was switched off, whose read is a shell command run inside a
  *      code-mode cell together with the edit and the check: the shell is a
  *      foreign tool to the audit, and the cell's calls are one response's.
  *
  *  Synthetic rollouts add what the subjects did not exhibit: parallel
  *  top-level calls, a call that completes before its response's usage
  *  record, a moved and an added file, a usage-limit refusal (worded and
  *  structured), a kill, a compaction, an unknown item, a stream with more
  *  items than the rollout, and a rollout of another thread.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import io.circe.Json
import io.circe.syntax._
import java.nio.file.Paths
import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import scala.io.Source

import struxdriver.io.TextIO

final class CodexTranscriptSpec extends AnyFunSuite with Matchers {

  private def resource(name: String): String = {
    val src = Source.fromResource(s"agentbench/codex/$name")
    try src.mkString finally src.close()
  }
  private def json(name: String): Json = io.circe.parser.parse(resource(name)).getOrElse(fail(s"$name is not JSON"))

  private def expectedOf(dir: String): CodexTranscript.Expected =
    CodexTranscript.Expected(Some("gpt-6.1-sol"), Some("low"), Some("codex-cli 0.162.1"),
      Some(CodexSubject.promptDigest(resource(s"$dir/system-prompt.txt").stripSuffix("\n"))))

  private def derived(dir: String, ended: CodexTranscript.Ended): Vector[Json] =
    CodexTranscript.derive(resource(s"$dir/codex-rollout.jsonl"), resource(s"$dir/codex-events.jsonl"),
      Some(json(s"$dir/codex-surface.json")), "", expectedOf(dir), ended)

  private val notKilled = CodexTranscript.Ended(killed = false, stopped = None)

  private val workDir = Paths.get("/home/williamdemeo/git/formalverification/agda-native-air/worktrees/239-m1-47-agent-bench-codex-subject-gpt-sol-astra/data/benchmarks/reports/agent-bench/smoke239-sol-1/work/stdlib-nat-plus-comm")
  private val roots   = ShellRoots(workDir, Vector.empty, Vector.empty)

  test("the smoke subject's transcript re-derives byte for byte, and twice the same") {
    val text = CodexTranscript.render(derived("smoke", notKilled))
    text shouldBe resource("smoke/transcript.jsonl")
    CodexTranscript.render(derived("smoke", notKilled)) shouldBe text
  }

  test("the smoke subject reads as a Claude subject of the mcp arm: init, tools, usage per response, a result with no client cost") {
    val t    = Transcript.parse(resource("smoke/transcript.jsonl"))
    val init = t.init.getOrElse(fail("no init record"))
    init.harness shouldBe Some("codex")
    init.version shouldBe Some("0.162.1")
    init.model shouldBe Some("gpt-6.1-sol")
    init.deferred shouldBe Some(false)
    init.adapterAnomaly shouldBe None
    init.mcpServers shouldBe Vector(("agda", "connected"), ("files", "connected"))
    Subject.agdaToolsRequired.forall(init.tools.contains) shouldBe true
    init.tools should contain allOf ("Read", "Edit")
    init.tools should not contain "exec_command"
    t.toolCounts shouldBe Vector("Read" -> 1, "Edit" -> 1, "mcp__agda__check_file" -> 1)
    t.toolsDeferred shouldBe false
    val r = t.result.getOrElse(fail("no result record"))
    r.subtype shouldBe "success"
    r.numTurns shouldBe 4
    r.costUsd shouldBe None
    r.modelUsage.map(u => (u.model, u.costUsd, u.costBasis)) shouldBe Vector(("gpt-6.1-sol", None, Some("none")))
    // Every assistant record that closes a response carries its usage.
    val firstAssistant = resource("smoke/transcript.jsonl").linesIterator.flatMap(io.circe.parser.parse(_).toOption)
      .find(_.hcursor.get[String]("type").toOption.contains("assistant")).getOrElse(fail("no assistant record"))
    firstAssistant.hcursor.downField("message").downField("usage").get[Long]("input_tokens").toOption.isDefined shouldBe true
    // A call's result comes back in the record after its response.
    t.uses.forall(u => t.resultOf(u).exists(_.record == u.record + 1)) shouldBe true
    val iso = Audit.isolation(t, Arm.Mcp, roots, None, Harness.Codex)
    iso.instrumentOk shouldBe true
    iso.extraTools shouldBe Vector.empty
    iso.confined shouldBe true
    Audit.terminalOf(killed = false, t.result) shouldBe "completed"
    Outcomes.viaOf(t) shouldBe "mcp"
  }

  test("the same subject under the Claude harness's surface fails the audit: Codex's own tools are extra") {
    val t = Transcript.parse(resource("smoke/transcript.jsonl"))
    Audit.isolation(t, Arm.Mcp, roots, None, Harness.Claude).extraTools should contain ("exec")
  }

  test("a subject stopped at the turn cap ends max_turns, priced, with no anomaly") {
    val recs = derived("turncap", CodexTranscript.Ended(killed = false, stopped = Some("max_turns")))
    CodexTranscript.render(recs) shouldBe resource("turncap/transcript.jsonl")
    val t = Transcript.parse(CodexTranscript.render(recs))
    val r = t.result.getOrElse(fail("no result record"))
    r.subtype shouldBe "error_max_turns"
    r.numTurns shouldBe 1
    Audit.terminalOf(killed = false, t.result) shouldBe "max_turns"
    t.init.flatMap(_.adapterAnomaly) shouldBe None
    Pricing.ofResult(t.result, table).usd.isDefined shouldBe true
  }

  test("the code-mode spike: a cell's shell read, patch, and check are one response's calls, and the shell is a foreign tool") {
    val recs = CodexTranscript.derive(resource("s3/codex-rollout.jsonl"), resource("s3/codex-events.jsonl"), None, "",
                 CodexTranscript.Expected(None, None, None, None), notKilled)
    val t = Transcript.parse(CodexTranscript.render(recs))
    t.toolCounts.toMap.keySet shouldBe Set("exec_command", "Edit", "mcp__agda__check_file")
    val edit  = t.usesOf("Edit").head
    val check = t.usesOf("mcp__agda__check_file").head
    edit.record shouldBe check.record
    edit.str("old_string").exists(_.contains("{!!}")) shouldBe true
    edit.str("new_string").exists(_.contains("+-comm zero n")) shouldBe true
    // No surface was read for the spike: the row is not a measurement.
    t.init.flatMap(_.adapterAnomaly) shouldBe Some("no surface: the first request was not read")
    Audit.isolation(t, Arm.Mcp, roots, None, Harness.Codex).foreignToolUses shouldBe Vector("exec_command")
  }

  test("archivable is idempotent on an archived rollout and keeps no account field") {
    Vector("smoke", "turncap", "s3").foreach { d =>
      val r = resource(s"$d/codex-rollout.jsonl")
      CodexSubject.archivable(r) shouldBe r
      r should not include "creator_account_id"
      r should not include "creator_user_id"
    }
  }

  // ---- synthetic rollouts ----------------------------------------------------

  private def line(tpe: String, payload: Json): String = Json.obj("type" -> tpe.asJson, "payload" -> payload).noSpaces
  private val meta    = line("session_meta", Json.obj("id" -> "T1".asJson, "cli_version" -> "0.162.1".asJson, "cwd" -> "/w".asJson))
  private val context = line("turn_context", Json.obj("model" -> "gpt-6.1-sol".asJson, "effort" -> "low".asJson, "approval_policy" -> "never".asJson))
  private def usage(id: String, input: Long, cached: Long = 0, output: Long = 10): String =
    line("token_usage_record", Json.obj("response_id" -> id.asJson, "usage" -> Json.obj(
      "input_tokens" -> input.asJson, "cached_input_tokens" -> cached.asJson, "cache_write_input_tokens" -> 0.asJson,
      "output_tokens" -> output.asJson, "reasoning_output_tokens" -> 3.asJson)))
  private def call(id: String, ns: String, name: String): String =
    line("response_item", Json.obj("type" -> "function_call".asJson, "call_id" -> id.asJson, "namespace" -> ns.asJson, "name" -> name.asJson))
  private def mcp(id: String, server: String, tool: String, args: Json, text: String, status: String = "completed"): String =
    line("event_msg", Json.obj("type" -> "item_completed".asJson, "item" -> Json.obj(
      "type" -> "McpToolCall".asJson, "id" -> id.asJson, "server" -> server.asJson, "tool" -> tool.asJson, "arguments" -> args,
      "status" -> status.asJson, "result" -> Json.obj("content" -> Json.arr(Json.obj("type" -> "text".asJson, "text" -> text.asJson))))))
  private def agentText(text: String): String =
    line("event_msg", Json.obj("type" -> "item_completed".asJson, "item" -> Json.obj(
      "type" -> "AgentMessage".asJson, "id" -> "m".asJson, "content" -> Json.arr(Json.obj("type" -> "Text".asJson, "text" -> text.asJson)))))
  private def done(last: String): String = line("event_msg", Json.obj("type" -> "task_complete".asJson, "last_agent_message" -> last.asJson, "duration_ms" -> 1000.asJson))
  private def events(items: Vector[String], end: String = """{"type":"turn.completed","usage":{}}"""): String =
    (Vector("""{"type":"thread.started","thread_id":"T1"}""", """{"type":"turn.started"}""") ++
      items.map(k => s"""{"type":"item.completed","item":{"id":"x","type":"$k"}}""") :+ end).mkString("\n")
  private val surface = Json.obj(
    "model" -> "gpt-6.1-sol".asJson, "effort" -> "low".asJson,
    "topLevelTools" -> (Vector("exec", "wait", "mcp__files__read") ++ Subject.agdaToolsRequired).asJson,
    "toolParams" -> Json.obj((Subject.agdaToolsRequired :+ "mcp__files__read").map(_ -> Vector("filePath").asJson): _*),
    "nestedTools" -> Vector("apply_patch").asJson,
    "inputBlocks" -> Vector(Json.obj("role" -> "developer".asJson, "sha256" -> "base".asJson),
                            Json.obj("role" -> "developer".asJson, "sha256" -> TextIO.sha256("SYS").asJson),
                            Json.obj("role" -> "user".asJson, "sha256" -> "u".asJson)).asJson,
    "configChanged" -> false.asJson)
  private val expected = CodexTranscript.Expected(Some("gpt-6.1-sol"), Some("low"), Some("codex-cli 0.162.1"), Some(TextIO.sha256("SYS")))
  private def parse(rollout: Vector[String], ev: String, ended: CodexTranscript.Ended = notKilled, s: Option[Json] = Some(surface), stderr: String = ""): Transcript =
    Transcript.parse(CodexTranscript.render(CodexTranscript.derive(rollout.mkString("\n"), ev, s, stderr, expected, ended)))

  private val table = PriceTable(Paths.get("p.json"), "x", "2026-10-13", None,
    Map("gpt-6.1-sol" -> ModelPrice(BigDecimal(2), BigDecimal("2.5"), BigDecimal("0.1"), BigDecimal(10))))

  test("parallel calls of one response, one completing before the response's usage record, are that response's") {
    val rollout = Vector(meta, context, agentText("reading"),
      call("c1", "mcp__files", "read"), mcp("c1", "files", "read", Json.obj("file_path" -> "/w/F.agda".asJson), "1\tmodule F where"),
      call("c2", "mcp__agda", "get_goal"), usage("r1", 100, 40),
      mcp("c2", "agda", "get_goal", Json.obj("filePath" -> "/w/F.agda".asJson), "{\"goal\":\"x\"}"),
      call("c3", "mcp__agda", "check_file"), usage("r2", 200, 150),
      mcp("c3", "agda", "check_file", Json.obj("filePath" -> "/w/F.agda".asJson), "{\"success\":false}", "failed"),
      agentText("done"), usage("r3", 300, 250), done("done"))
    val t = parse(rollout, events(Vector("mcp_tool_call", "mcp_tool_call", "mcp_tool_call")))
    val read = t.usesOf("Read").head
    read.str("file_path") shouldBe Some("/w/F.agda")
    t.usesOf("mcp__agda__get_goal").head.record shouldBe read.record
    t.usesOf("mcp__agda__check_file").head.record should be > read.record
    t.resultOf(t.usesOf("mcp__agda__check_file").head).exists(_.isError) shouldBe true
    val r = t.result.getOrElse(fail("no result"))
    r.numTurns shouldBe 3
    r.usageTokens shouldBe Tokens(input = 160, output = 30, cacheRead = 440, cacheCreation = 0)
    Pricing.ofResult(t.result, table).usd shouldBe Some((BigDecimal(160) * 2 + BigDecimal(440) * BigDecimal("0.1") + BigDecimal(30) * 10) / Pricing.perMillion)
    t.init.flatMap(_.adapterAnomaly) shouldBe None
  }

  test("a file change is one Edit per hunk, a whole-file add an Edit with an empty old side, and a move an Edit of the destination") {
    val change = line("event_msg", Json.obj("type" -> "item_completed".asJson, "item" -> Json.obj(
      "type" -> "FileChange".asJson, "id" -> "fc".asJson, "status" -> "completed".asJson, "stdout" -> "Success.".asJson,
      "changes" -> Json.obj(
        "/w/F.agda" -> Json.obj("type" -> "update".asJson, "move_path" -> "/elsewhere/G.agda".asJson,
          "unified_diff" -> "@@ -1,2 +1,2 @@\n a\n-b\n+c\n@@ -9 +9 @@\n-y\n+z\n".asJson),
        "/w/New.agda" -> Json.obj("type" -> "add".asJson, "content" -> "module New where\n".asJson)))))
    val cell = line("response_item", Json.obj("type" -> "custom_tool_call".asJson, "call_id" -> "cell".asJson, "name" -> "exec".asJson))
    val out  = line("response_item", Json.obj("type" -> "custom_tool_call_output".asJson, "call_id" -> "cell".asJson))
    val t = parse(Vector(meta, context, cell, usage("r1", 10), change, out, usage("r2", 20), done("ok")), events(Vector("file_change")))
    val edits = t.usesOf("Edit")
    edits.flatMap(_.str("file_path")) shouldBe Vector("/w/F.agda", "/w/F.agda", "/elsewhere/G.agda", "/w/New.agda")
    edits.flatMap(_.str("old_string")).take(2) shouldBe Vector("a\nb", "y")
    edits.flatMap(_.str("new_string")).take(2) shouldBe Vector("a\nc", "z")
    edits.last.str("old_string") shouldBe Some("")
    edits.map(_.record).distinct.size shouldBe 1
    // One change is one call, however many hunks it has.
    t.toolCounts.toMap.get("Edit") shouldBe Some(1)
    // The move leaves the work directory, which the path audit sees.
    Audit.isolation(t, Arm.Mcp, ShellRoots(Paths.get("/w"), Vector.empty, Vector.empty), None, Harness.Codex).violations shouldBe
      Vector("Edit /elsewhere/G.agda")
  }

  test("a usage-limit refusal, worded or structured, is a rejected rate limit; a failed turn is a client error with its message") {
    val worded = parse(Vector(meta, context, usage("r1", 10)),
      events(Vector.empty, """{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Try again at 6:12 PM."}}"""))
    worded.rateLimitRejected shouldBe true
    worded.result.map(r => (r.subtype, r.isError)) shouldBe Some(("error_turn_failed", true))
    worded.result.map(_.text).exists(_.contains("usage limit")) shouldBe true
    val limits = line("event_msg", Json.obj("type" -> "token_count".asJson, "rate_limits" -> Json.obj(
      "primary" -> Json.obj("used_percent" -> 100.0.asJson), "secondary" -> Json.obj("used_percent" -> 41.0.asJson),
      "rate_limit_reached_type" -> "rate_limit_reached".asJson)))
    val structured = parse(Vector(meta, context, usage("r1", 10), limits), events(Vector.empty))
    structured.rateLimitRejected shouldBe true
    structured.rateLimitMax shouldBe Some(1.0)
  }

  test("a killed subject has no result record; a compaction is not a turn; Codex's windows are read in both units") {
    val compaction = line("compacted", Json.obj("compaction_response_id" -> "rc".asJson))
    val limits = line("event_msg", Json.obj("type" -> "token_count".asJson, "rate_limits" -> Json.obj(
      "primary" -> Json.obj("used_percent" -> 12.0.asJson, "resets_at" -> 1791936924L.asJson),
      "secondary" -> Json.obj("used_percent" -> 3.0.asJson))))
    val rollout = Vector(meta, context, usage("r1", 10), compaction, usage("rc", 999), usage("r2", 20), limits)
    val killed = parse(rollout, events(Vector.empty, ""), CodexTranscript.Ended(killed = true, stopped = None))
    killed.result shouldBe None
    Audit.terminalOf(killed = true, killed.result) shouldBe "wall_cap"
    val ended = parse(rollout :+ done("x"), events(Vector.empty))
    ended.result.map(_.numTurns) shouldBe Some(2)
    // The compaction is no turn, but its tokens were spent and are priced.
    ended.result.map(_.usageTokens.input) shouldBe Some(10L + 999L + 20L)
    ended.rateLimits shouldBe Vector(("allowed", 0.12))
  }

  test("what makes a Codex row not a measurement is named in the init record") {
    def anomaly(rollout: Vector[String], ev: String, ended: CodexTranscript.Ended = notKilled, s: Option[Json] = Some(surface), stderr: String = "") =
      parse(rollout, ev, ended, s, stderr).init.flatMap(_.adapterAnomaly)
    val ok = Vector(meta, context, usage("r1", 10), done("x"))
    anomaly(ok, events(Vector.empty)) shouldBe None
    anomaly(ok :+ line("event_msg", Json.obj("type" -> "item_completed".asJson, "item" -> Json.obj("type" -> "Telepathy".asJson))),
      events(Vector.empty)).exists(_.contains("Telepathy")) shouldBe true
    anomaly(ok, events(Vector("mcp_tool_call"))).exists(_.contains("mcp_tool_call items")) shouldBe true
    anomaly(ok, events(Vector("mcp_tool_call")), CodexTranscript.Ended(killed = true, stopped = None)) shouldBe None
    anomaly(ok, events(Vector.empty).replace("T1", "T2")).exists(_.contains("the rollout is thread T1")) shouldBe true
    anomaly(Vector.empty, events(Vector.empty)) shouldBe Some("the session started and no rollout was kept")
    anomaly(ok, events(Vector.empty), s = Some(surface.mapObject(_.add("effort", "xhigh".asJson)))) shouldBe None
    anomaly(Vector(meta, line("turn_context", Json.obj("model" -> "gpt-6.1-sol".asJson, "effort" -> "high".asJson)), done("x")),
      events(Vector.empty)).exists(_.contains("effort high")) shouldBe true
    anomaly(ok, events(Vector.empty), s = Some(surface.mapObject(_.add("nestedTools", Vector("mcp__agda__get_goal").asJson))))
      .exists(_.contains("inside code mode")) shouldBe true
    anomaly(ok, events(Vector.empty), s = Some(surface.mapObject(_.add("configChanged", true.asJson)))) shouldBe Some("Codex rewrote the subject's config.toml")
    anomaly(ok, events(Vector.empty), s = Some(surface.mapObject(_.add("inputBlocks", Vector(Json.obj("role" -> "developer".asJson, "sha256" -> "zz".asJson)).asJson))))
      .exists(_.contains("system prompt")) shouldBe true
    anomaly(Vector.empty, "", stderr = "Error: required MCP servers failed to initialize: agda")
      .exists(_.contains("a required MCP server failed to start")) shouldBe true
    anomaly(ok, events(Vector.empty), stderr = "Your access token could not be refreshed; please sign in again.")
      .exists(_.contains("login failed")) shouldBe true
  }

  private def cell(id: String, input: String): String =
    line("response_item", Json.obj("type" -> "custom_tool_call".asJson, "call_id" -> id.asJson, "name" -> "exec".asJson, "input" -> input.asJson))
  private def cellOut(id: String, texts: String*): String =
    line("response_item", Json.obj("type" -> "custom_tool_call_output".asJson, "call_id" -> id.asJson,
      "output" -> Json.arr(texts.map(t => Json.obj("type" -> "input_text".asJson, "text" -> t.asJson)): _*)))
  private def callOut(id: String, texts: String*): String =
    line("response_item", Json.obj("type" -> "function_call_output".asJson, "call_id" -> id.asJson,
      "output" -> Json.arr(texts.map(t => Json.obj("type" -> "input_text".asJson, "text" -> t.asJson)): _*)))
  private def fileChange(id: String, path: String): String =
    line("event_msg", Json.obj("type" -> "item_completed".asJson, "item" -> Json.obj(
      "type" -> "FileChange".asJson, "id" -> id.asJson, "status" -> "completed".asJson, "stdout" -> "Success.".asJson,
      "changes" -> Json.obj(path -> Json.obj("type" -> "update".asJson, "unified_diff" -> "@@ -1 +1 @@\n-a\n+b\n".asJson)))))
  private def resourceCall(server: String, tool: String): String =
    line("event_msg", Json.obj("type" -> "item_completed".asJson, "item" -> Json.obj(
      "type" -> "McpToolCall".asJson, "id" -> s"exec-$server-$tool".asJson, "server" -> server.asJson, "tool" -> tool.asJson,
      "arguments" -> Json.obj(), "status" -> "completed".asJson, "result" -> Json.obj("content" -> Json.arr()))))
  private val work = ShellRoots(Paths.get("/w"), Vector.empty, Vector.empty)

  test("Codex's resource tools keep their bare names on any server, which the Codex surface admits (#239 review)") {
    val rollout = Vector(meta, context, cell("x", "await tools.list_mcp_resources({})"), usage("r1", 10),
      resourceCall("codex", "list_mcp_resources"), resourceCall("agda", "list_mcp_resource_templates"),
      resourceCall("files", "read_mcp_resource"), cellOut("x", "Script completed\nWall time 0.1 seconds\nOutput:\n"),
      usage("r2", 10), done("x"))
    val t = parse(rollout, events(Vector("mcp_tool_call", "mcp_tool_call", "mcp_tool_call")))
    t.uses.map(_.name) shouldBe Vector("list_mcp_resources", "list_mcp_resource_templates", "read_mcp_resource")
    val iso = Audit.isolation(t, Arm.Mcp, work, None, Harness.Codex)
    iso.foreignToolUses shouldBe Vector.empty
    iso.confined shouldBe true
    Outcomes.viaOf(t) shouldBe "none"
  }

  test("a server call Codex never completed is a failed call of its response; ended during fill_hole, the row is an anomaly (#239 review)") {
    val rollout = Vector(meta, context, call("c1", "mcp__agda", "fill_hole"), usage("r1", 10),
      callOut("c1", "aborted by user after 0.4s"))
    val stopped = parse(rollout, events(Vector.empty, ""), CodexTranscript.Ended(killed = false, stopped = Some("max_turns")))
    val use = stopped.usesOf("mcp__agda__fill_hole").headOption.getOrElse(fail("the call vanished"))
    stopped.resultOf(use).map(r => (r.isError, r.text)) shouldBe Some((true, "aborted by user after 0.4s"))
    stopped.init.flatMap(_.adapterAnomaly).exists(_.contains("fill_hole")) shouldBe true
    // A call whose arguments were no JSON, in a session that ended on its own, is a failed call and no anomaly.
    val bad = parse(Vector(meta, context, call("c2", "mcp__agda", "check_file"), usage("r1", 10), callOut("c2", "failed to parse"),
      usage("r2", 10), done("x")), events(Vector.empty))
    bad.usesOf("mcp__agda__check_file").size shouldBe 1
    bad.init.flatMap(_.adapterAnomaly) shouldBe None
    Outcomes.verdictViaOf(bad, work) shouldBe "mcp"
    // A fill_hole refused at once (its arguments no JSON) ran nothing, so a later stop is no anomaly.
    val refusedAtOnce = parse(Vector(meta, context, call("c3", "mcp__agda", "fill_hole"), usage("r1", 10), callOut("c3", "err: EOF while parsing"),
      call("c4", "mcp__agda", "check_file"), usage("r2", 10), mcp("c4", "agda", "check_file", Json.obj(), "{}"), callOut("c4", "{}")),
      events(Vector("mcp_tool_call"), ""), CodexTranscript.Ended(killed = false, stopped = Some("max_turns")))
    refusedAtOnce.init.flatMap(_.adapterAnomaly) shouldBe None
    refusedAtOnce.usesOf("mcp__agda__fill_hole").size shouldBe 1
  }

  test("calls are in the order the response issued them, not the order they completed (#239 review)") {
    val rollout = Vector(meta, context, call("c1", "mcp__agda", "fill_hole"), call("c2", "mcp__agda", "fill_hole"), usage("r1", 10),
      mcp("c2", "agda", "fill_hole", Json.obj("candidate" -> "b".asJson), "{}"), mcp("c1", "agda", "fill_hole", Json.obj("candidate" -> "a".asJson), "{}"),
      usage("r2", 10), done("x"))
    val t = parse(rollout, events(Vector("mcp_tool_call", "mcp_tool_call")))
    t.usesOf("mcp__agda__fill_hole").map(_.id) shouldBe Vector("c1", "c2")
  }

  test("a top-level call's result is the text the model was shown, not the item's (#239 review)") {
    val whole = (1 to 5).map(i => s"$i\tline").mkString("\n")
    val cut   = "1\tline\n…3 tokens truncated…\n5\tline"
    val rollout = Vector(meta, context, call("c1", "mcp__files", "read"),
      mcp("c1", "files", "read", Json.obj("file_path" -> "/w/F.agda".asJson), whole),
      usage("r1", 10), callOut("c1", "Wall time: 0.0019 seconds\nOutput:", cut), usage("r2", 10), done("x"))
    val t = parse(rollout, events(Vector("mcp_tool_call")))
    t.resultOf(t.usesOf("Read").head).map(_.text) shouldBe Some(cut)
  }

  test("a turn the stream reports completed is a success whatever stop came after it (#239 review)") {
    val rollout = Vector(meta, context, agentText("done"), usage("r1", 10), done("done"))
    val t = parse(rollout, events(Vector.empty), CodexTranscript.Ended(killed = false, stopped = Some("max_turns")))
    t.result.map(r => (r.subtype, r.isError)) shouldBe Some(("success", false))
  }

  test("a cell that yielded owns its later edit until a wait reports it done; two open cells make the owner unknown (#239 review)") {
    val patch = "await tools.apply_patch(\"*** Begin Patch\\n*** Update File: F.agda\\n@@\\n-a\\n+b\\n*** End Patch\")"
    val waitCall = line("response_item", Json.obj("type" -> "function_call".asJson, "call_id" -> "w1".asJson, "name" -> "wait".asJson,
      "arguments" -> """{"cell_id":"1"}""".asJson))
    val rollout = Vector(meta, context, cell("x", patch), usage("r1", 10), cellOut("x", "Script running with cell ID 1\nWall time 10 seconds\nOutput:\n"),
      call("c1", "mcp__files", "read"), usage("r2", 10),
      mcp("c1", "files", "read", Json.obj("file_path" -> "/w/F.agda".asJson), "1\ta"), callOut("c1", "Wall time: 0.001 seconds\nOutput:", "1\ta"),
      waitCall, usage("r3", 10), fileChange("exec-1", "/w/F.agda"), callOut("w1", "Script completed\nWall time 1 seconds\nOutput:\n"),
      usage("r4", 10), done("x"))
    val t = parse(rollout, events(Vector("mcp_tool_call", "file_change")))
    val edit = t.usesOf("Edit").headOption.getOrElse(fail("no edit"))
    edit.record should be < t.usesOf("Read").head.record
    t.init.flatMap(_.adapterAnomaly) shouldBe None
    // Two cells of two responses open when a nested call completes: whose it is cannot be read.
    val two = Vector(meta, context, cell("x", patch), usage("r1", 10), cellOut("x", "Script running with cell ID 1\nWall time 10 seconds\nOutput:\n"),
      cell("y", "1"), usage("r2", 10), fileChange("exec-1", "/w/F.agda"), cellOut("y", "Script completed\nWall time 1 seconds\nOutput:\n"),
      usage("r3", 10), done("x"))
    parse(two, events(Vector("file_change"))).init.flatMap(_.adapterAnomaly).exists(_.contains("response is not known")) shouldBe true
    // A yielded cell's notify (an output with no status) does not end it; its edit is still its own.
    val notified = Vector(meta, context, cell("x", patch), usage("r1", 10), cellOut("x", "Script running with cell ID 1\nWall time 10 seconds\nOutput:\n"),
      cellOut("x", "halfway"), call("c1", "mcp__files", "read"), usage("r2", 10),
      mcp("c1", "files", "read", Json.obj("file_path" -> "/w/F.agda".asJson), "1\ta"), callOut("c1", "Wall time: 0.001 seconds\nOutput:", "1\ta"),
      cell("y", "1"), usage("r3", 10), fileChange("exec-1", "/w/F.agda"), cellOut("y", "Script completed\nWall time 1 seconds\nOutput:\n"),
      usage("r4", 10), done("x"))
    parse(notified, events(Vector("mcp_tool_call", "file_change"))).init.flatMap(_.adapterAnomaly).exists(_.contains("response is not known")) shouldBe true
  }

  test("a rerouted model is an anomaly; other error items are counted (#239 review)") {
    val ok = Vector(meta, context, usage("r1", 10), done("x"))
    val ev = events(Vector.empty).replace("""{"type":"turn.completed""",
      """{"type":"item.completed","item":{"id":"e","type":"error","message":"model rerouted: gpt-6.1-sol -> gpt-6-mini (HighRiskCyberActivity)"}}""" + "\n" + """{"type":"turn.completed""")
    val t = parse(ok, ev)
    t.init.flatMap(_.adapterAnomaly).exists(_.contains("rerouted")) shouldBe true
    val lagged = parse(ok, events(Vector.empty).replace("""{"type":"turn.completed""",
      """{"type":"item.completed","item":{"id":"e","type":"error","message":"in-process app-server event stream lagged; dropped 7 events"}}""" + "\n" + """{"type":"turn.completed"""))
    lagged.init.flatMap(_.adapterAnomaly).exists(_.contains("dropped events")) shouldBe true
    val warned = parse(ok, events(Vector.empty).replace("""{"type":"turn.completed""",
      """{"type":"item.completed","item":{"id":"e","type":"error","message":"deprecated config key"}}""" + "\n" + """{"type":"turn.completed"""))
    warned.init.flatMap(_.adapterAnomaly) shouldBe None
  }

  test("a patch Codex refused before applying it is one failed Edit of the cell's response, a write refusal a denial (#239 review)") {
    val patch = "await tools.apply_patch(\"*** Begin Patch\\n*** Update File: F.agda\\n@@\\n-zz\\n+b\\n*** End Patch\")"
    val rollout = Vector(meta, context, cell("x", patch), usage("r1", 10),
      cellOut("x", "Script failed\nWall time 0.1 seconds\nOutput:\n", "Script error:\napply_patch verification failed: Failed to find expected lines in /w/F.agda"),
      cell("y", patch.replace("F.agda", "/etc/passwd")), usage("r2", 10),
      cellOut("y", "Script failed\nWall time 0.1 seconds\nOutput:\n", "Script error:\npatch rejected: writing outside of the project; rejected by user approval settings"),
      usage("r3", 10), done("x"))
    val t = parse(rollout, events(Vector.empty))
    val edits = t.usesOf("Edit")
    edits.flatMap(_.str("file_path")) shouldBe Vector("/w/F.agda", "/etc/passwd")
    edits.flatMap(e => t.resultOf(e)).forall(_.isError) shouldBe true
    t.toolCounts.toMap.get("Edit") shouldBe Some(2)
    t.result.map(_.permissionDenials) shouldBe Some(1)
    Audit.isolation(t, Arm.Mcp, work, None, Harness.Codex).violations shouldBe Vector.empty
    // A cell whose second patch was refused, the message naming no file: the refusal is of every file the cell's patches name,
    // and a call that is no patch at all (an object, not a string) is refused by code mode, one more failed Edit.
    val two = Vector(meta, context, cell("x", patch + "; " + patch.replace("F.agda", "/etc/passwd")), usage("r1", 10), fileChange("exec-1", "/w/F.agda"),
      cellOut("x", "Script failed\nWall time 0.1 seconds\nOutput:\n", "Script error:\npatch rejected: writing outside of the project; rejected by user approval settings"),
      cell("y", "await tools.apply_patch({patch: 1})"), usage("r2", 10),
      cellOut("y", "Script failed\nWall time 0.1 seconds\nOutput:\n", "Script error:\nError: tool `apply_patch` expects a string input"),
      usage("r3", 10), done("x"))
    val t2 = parse(two, events(Vector("file_change")))
    t2.usesOf("Edit").filter(_.str("kind").contains("refused")).flatMap(_.str("file_path")) shouldBe Vector("/w/F.agda", "/etc/passwd")
    t2.toolCounts.toMap.get("Edit") shouldBe Some(3)
    Audit.isolation(t2, Arm.Mcp, work, None, Harness.Codex).deniedPaths should contain ("Edit /etc/passwd")
  }

  test("a unified diff reads as the hunks Claude's Edit would carry") {
    CodexTranscript.hunks("@@ -1 +1 @@\n-x = {!!}\n+x = refl\n\\ No newline at end of file\n") shouldBe Vector(("x = {!!}", "x = refl"))
    CodexTranscript.hunks("") shouldBe Vector.empty
    // A patch's file, as a cell's JavaScript carries it: a template literal or an escaped string.
    CodexTranscript.patchTarget("tools.apply_patch(`*** Begin Patch\n*** Update File: F.agda\n@@`)", Some("/w")) shouldBe Some("/w/F.agda")
    CodexTranscript.patchTarget("tools.apply_patch(\"*** Begin Patch\\n*** Add File: /w/G.agda\\n+x\")", Some("/w")) shouldBe Some("/w/G.agda")
    CodexTranscript.patchTarget("no patch here", Some("/w")) shouldBe None
  }
}
