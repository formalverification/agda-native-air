/** ============================================================================
  *  CodexSubjectSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/CodexSubjectSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins the Codex subject's setup (issue #239): the configuration it is
  *  given (every isolation switch, the two servers presented at top level,
  *  the sandbox profile, the trust entries), the environment it inherits,
  *  its argument vector, the caps read from its rollout, the strict lookup
  *  of its rollout by thread, the fresh CODEX_HOME of every launch, the
  *  surface read from its first request, and the login read by kind.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.unsafe.implicits.global
import io.circe.Json
import io.circe.syntax._
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, LinkOption, Path, Paths}
import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

final class CodexSubjectSpec extends AnyFunSuite with Matchers {

  private val setup = CodexSetup(
    codexBin    = "/opt/codex/bin/codex.js",
    effort      = "low",
    catalog     = Paths.get("/run/codex-models.json"),
    readServer  = Vector("/usr/bin/python3", "/repo/scripts/python/bench_read_server.py"),
    packageRoot = Some(Paths.get("/opt/codex")),
    trustRoots  = Vector(Paths.get("/repo"), Paths.get("/main")),
    price       = Some(ModelPrice(BigDecimal(2), BigDecimal("2.5"), BigDecimal("0.1"), BigDecimal(10))))

  private val server = ("/repo/scripts/run-server.sh", Vector("--cwd", "/repo", "--check-command", "agda -i /w /w/F.agda"),
                        Map("AGDA_MCP_BIN" -> "/bin/agda-mcp"))

  private def config: String =
    Toml.render(CodexSubject.tables("gpt-6.1-sol", setup, "SYSTEM \"prompt\"\nline two", Paths.get("/w"),
      Vector(Paths.get("/lib/src")), server, "run/F", 660))

  test("the configuration closes every switch the design names, and presents both servers at top level") {
    val c = config
    Vector(
      "model = \"gpt-6.1-sol\"", "model_reasoning_effort = \"low\"", "model_catalog_json = \"/run/codex-models.json\"",
      "approval_policy = \"never\"", "default_permissions = \"subject\"", "allow_login_shell = false",
      "cli_auth_credentials_store = \"file\"", "project_doc_max_bytes = 0", "project_root_markers = []",
      "web_search = \"disabled\"", "include_environment_context = false", "include_permissions_instructions = false",
      "include_collaboration_mode_instructions = false", "developer_instructions = \"SYSTEM \\\"prompt\\\"\\nline two\"",
      "[agents]\nenabled = false", "[tools.experimental_request_user_input]\nenabled = false",
      "[skills]\ninclude_instructions = false", "[skills.bundled]\nenabled = false",
      "shell_tool = false", "shell_snapshot = false", "unbounded_connection_retries = false", "apps = false", "memories = false",
      "[projects.\"/repo\"]\ntrust_level = \"untrusted\"", "[projects.\"/main\"]\ntrust_level = \"untrusted\"",
      "[permissions.subject.filesystem]\n\":minimal\" = \"read\"\n\"/w\" = \"write\"\n\"/opt/codex\" = \"read\"",
      "[permissions.subject.network]\nenabled = false",
      "[mcp_servers.agda]\ncommand = \"/repo/scripts/run-server.sh\"",
      "required = true", "default_tools_approval_mode = \"approve\"", "omit_tools_from = [\"deferred\", \"code_mode\"]",
      "[mcp_servers.agda.env]\nAGDA_MCP_BIN = \"/bin/agda-mcp\"\nAGENT_BENCH_SUBJECT = \"run/F\"",
      "[mcp_servers.files]\ncommand = \"/usr/bin/python3\"",
      "args = [\"/repo/scripts/python/bench_read_server.py\", \"--root\", \"/w\", \"--root\", \"/lib/src\"]",
      "enabled_tools = [\"read\"]", "[mcp_servers.files.env]\nAGENT_BENCH_SUBJECT = \"run/F\""
    ).foreach(s => withClue(s)(c should include (s)))
    // Codex refuses an unknown key under --strict-config; the root's keys come first.
    c.linesIterator.next() shouldBe "model = \"gpt-6.1-sol\""
    c should not include "sandbox_mode"
    c.endsWith("\n") shouldBe true
  }

  test("a TOML key is bare only when it is letters, digits, _ and -; a string is a JSON string") {
    Toml.key("trust_level") shouldBe "trust_level"
    Toml.key(":minimal") shouldBe "\":minimal\""
    Toml.key("/w") shouldBe "\"/w\""
    Toml.str("a\"b\\c\u0001") shouldBe "\"a\\\"b\\\\c\\u0001\""
  }

  test("the environment drops every Claude, OpenAI, Codex, and Anthropic variable, RUST_LOG, and LD_LIBRARY_PATH, and names the subject's own home") {
    val home = CodexHome(Paths.get("/h"))
    val env  = CodexSubject.environment(Map("PATH" -> "/bin", "CLAUDE_X" -> "1", "OPENAI_API_KEY" -> "k", "CODEX_HOME" -> "/mine",
      "ANTHROPIC_AUTH_TOKEN" -> "t", "RUST_LOG" -> "info", "LD_LIBRARY_PATH" -> "/x", "HOME" -> "/home/u"), home)
    env shouldBe Map("PATH" -> "/bin", "HOME" -> "/home/u", "CODEX_HOME" -> "/h", "TMPDIR" -> "/h/tmp-subject",
      "CODEX_ROLLOUT_TRACE_ROOT" -> "/h/trace")
    CodexSubject.argv("/c", "P") shouldBe Vector("setsid", "/c", "--strict-config", "exec", "--json", "P")
  }

  private def usageLine(n: Int, input: Long): String =
    s"""{"type":"token_usage_record","payload":{"response_id":"r$n","usage":{"input_tokens":$input,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":100,"reasoning_output_tokens":0}}}"""

  private def callLine(id: String): String =
    s"""{"type":"response_item","payload":{"type":"function_call","name":"check_file","namespace":"mcp__agda","call_id":"$id","arguments":"{}"}}"""
  private def outputLine(id: String): String =
    s"""{"type":"response_item","payload":{"type":"function_call_output","call_id":"$id","output":"ok"}}"""
  private def compaction(input: Long): String =
    s"""{"type":"token_usage_record","payload":{"response_id":"c1","usage":{"input_tokens":$input,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":100,"reasoning_output_tokens":0}}}""" +
      "\n" + """{"type":"compacted","payload":{"compaction_response_id":"c1"}}"""

  test("the caps are read from the rollout: the turns once maxTurns responses are in, their calls returned, and the turn not ended, the budget at the price") {
    // Each response calls a tool whose output is in: the turn goes on.
    val three = (1 to 3).map(n => callLine(s"k$n") + "\n" + usageLine(n, 1000) + "\n" + outputLine(s"k$n")).mkString("\n")
    CodexSubject.capReached(three, setup.price, 3, BigDecimal(3)) shouldBe Some("max_turns")
    CodexSubject.capReached(three, setup.price, 4, BigDecimal(3)) shouldBe None
    CodexSubject.capReached(three + "\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}", setup.price, 3, BigDecimal(3)) shouldBe None
    // 3 x (1000 x 2 + 100 x 10) / 1e6 = 0.009 USD
    CodexSubject.capReached(three, setup.price, 30, BigDecimal("0.009")) shouldBe Some("budget")
    CodexSubject.capReached(three, setup.price, 30, BigDecimal("0.0091")) shouldBe None
    CodexSubject.capReached(three, None, 30, BigDecimal("0.001")) shouldBe None
    // A call still running: no stop until its output is in (agda's fill_hole restores the file only when it returns).
    val running = (1 to 2).map(n => callLine(s"k$n") + "\n" + usageLine(n, 1000) + "\n" + outputLine(s"k$n")).mkString("\n") +
                  "\n" + callLine("k3") + "\n" + usageLine(3, 1000)
    CodexSubject.capReached(running, setup.price, 3, BigDecimal(3)) shouldBe None
    CodexSubject.capReached(running + "\n" + outputLine("k3"), setup.price, 3, BigDecimal(3)) shouldBe Some("max_turns")
    // A last response that called nothing is the turn ending on its own, before task_complete is written.
    val answered = (1 to 2).map(n => callLine(s"k$n") + "\n" + usageLine(n, 1000) + "\n" + outputLine(s"k$n")).mkString("\n") + "\n" + usageLine(3, 1000)
    CodexSubject.capReached(answered, setup.price, 3, BigDecimal(3)) shouldBe None
    CodexSubject.capReached(answered, setup.price, 30, BigDecimal("0.001")) shouldBe None
    // A compaction is no response, but its tokens count toward the budget: 0.009 + (100000 x 2 + 100 x 10) / 1e6 = 0.21 USD.
    val compacted = three + "\n" + compaction(100000)
    val fourth    = compacted + "\n" + callLine("k4") + "\n" + usageLine(4, 1000) + "\n" + outputLine("k4")
    CodexSubject.capReached(fourth, setup.price, 4, BigDecimal(3)) shouldBe Some("max_turns")
    CodexSubject.capReached(fourth, setup.price, 5, BigDecimal(3)) shouldBe None
    CodexSubject.capReached(compacted, setup.price, 30, BigDecimal("0.2")) shouldBe Some("budget")
    CodexSubject.progress(compacted).responses.size shouldBe 3
  }

  private def tmp(): Path = Files.createTempDirectory("codex-subject-spec")

  test("a launch makes the subject's CODEX_HOME afresh, links the login without copying it, and returns the config's digest") {
    val home = CodexHome(tmp().resolve("home"))
    val auth = Files.writeString(tmp().resolve("auth.json"), "{\"tokens\":{\"access_token\":\"not-a-real-token-0123456789\"}}")
    Files.createDirectories(home.sessions)
    Files.writeString(home.sessions.resolve("rollout-old-T0.jsonl"), "stale")
    val sha = CodexSubject.prepare(home, auth, "model = \"m\"\n").unsafeRunSync()
    sha shouldBe struxdriver.io.TextIO.sha256("model = \"m\"\n")
    Files.exists(home.sessions) shouldBe false
    Files.isSymbolicLink(home.auth) shouldBe true
    Files.readSymbolicLink(home.auth) shouldBe auth
    Files.isDirectory(home.tmp) && Files.isDirectory(home.trace) shouldBe true
    CodexSubject.remove(home.dir).unsafeRunSync()
    Files.exists(home.dir, LinkOption.NOFOLLOW_LINKS) shouldBe false
    Files.exists(auth) shouldBe true
  }

  test("the rollout is found by the stream's thread and only by it") {
    val home = CodexHome(tmp())
    val day  = Files.createDirectories(home.sessions.resolve("2026/10/13"))
    Files.writeString(day.resolve("rollout-2026-10-13T00-00-00-T1.jsonl"), """{"type":"session_meta","payload":{"id":"T1"}}""" + "\n")
    Files.writeString(day.resolve("rollout-2026-10-13T00-00-01-T2.jsonl"), """{"type":"session_meta","payload":{"id":"T9"}}""" + "\n")
    CodexSubject.rolloutOf(home, Some("T1")).unsafeRunSync().map(_.getFileName.toString) shouldBe Some("rollout-2026-10-13T00-00-00-T1.jsonl")
    CodexSubject.rolloutOf(home, Some("T2")).unsafeRunSync() shouldBe None   // its session record names another thread
    CodexSubject.rolloutOf(home, None).unsafeRunSync() shouldBe None
  }

  test("the archive's filter drops the account's ids and the git block and digests the base instructions and the encrypted reasoning") {
    val raw = Vector(
      """{"type":"session_meta","payload":{"id":"T1","creator_user_id":"user-x","creator_account_id":"acct","git":{"branch":"b"},"base_instructions":{"text":"BASE"}}}""",
      """{"type":"response_item","payload":{"type":"reasoning","encrypted_content":"OPAQUE","summary":[]}}""",
      """not json""").mkString("\n")
    val out = CodexSubject.archivable(raw)
    out should not include "user-x"
    out should not include "acct"
    out should not include "\"git\""
    out should not include "OPAQUE"
    out should include (struxdriver.io.TextIO.sha256("BASE"))
    out should include ("not json")
    CodexSubject.archivable(out) shouldBe out
    CodexSubject.baseInstructions(raw) shouldBe Some("BASE")
  }

  test("the surface of a request: top-level tools under their namespaces with their parameters, nested tools, instruction blocks") {
    val tool = (n: String, props: Vector[String]) => Json.obj("type" -> "function".asJson, "name" -> n.asJson,
      "parameters" -> Json.obj("properties" -> Json.obj(props.map(_ -> Json.obj()): _*)))
    val request = Json.obj(
      "model" -> "gpt-6.1-sol".asJson, "reasoning" -> Json.obj("effort" -> "low".asJson),
      "input" -> Json.arr(
        Json.obj("type" -> "additional_tools".asJson, "tools" -> Json.arr(
          Json.obj("type" -> "namespace".asJson, "name" -> "functions".asJson, "tools" -> Json.arr(
            Json.obj("type" -> "custom".asJson, "name" -> "exec".asJson,
              "description" -> "declare const tools: { apply_patch(input: string): Promise<unknown>; };".asJson),
            tool("wait", Vector("cell_id")))),
          Json.obj("type" -> "namespace".asJson, "name" -> "mcp__agda".asJson, "tools" -> Json.arr(tool("check_file", Vector("filePath")))))),
        Json.obj("type" -> "message".asJson, "role" -> "developer".asJson, "content" -> Json.arr(Json.obj("type" -> "input_text".asJson, "text" -> "SYS".asJson))),
        Json.obj("type" -> "message".asJson, "role" -> "user".asJson, "content" -> Json.arr(Json.obj("type" -> "input_text".asJson, "text" -> "U".asJson)))))
    val s = CodexSubject.surfaceOf(request).hcursor
    s.get[Vector[String]]("topLevelTools") shouldBe Right(Vector("exec", "wait", "mcp__agda__check_file"))
    s.get[Vector[String]]("nestedTools") shouldBe Right(Vector("apply_patch"))
    s.downField("toolParams").get[Vector[String]]("mcp__agda__check_file") shouldBe Right(Vector("filePath"))
    s.get[String]("effort") shouldBe Right("low")
    s.downField("inputBlocks").focus.flatMap(_.asArray).map(_.size) shouldBe Some(2)
    s.downField("inputBlocks").downN(0).get[String]("sha256") shouldBe Right(CodexSubject.promptDigest("SYS"))
  }

  test("the version is the line Codex prints for it, after any warning; a wrapper that cannot run has none") {
    CodexSubject.versionOf("codex-cli 0.162.1\n") shouldBe Some("codex-cli 0.162.1")
    CodexSubject.versionOf("WARNING: proceeding, even though we could not create PATH aliases\ncodex-cli 0.162.1") shouldBe Some("codex-cli 0.162.1")
    CodexSubject.versionOf("/usr/bin/env: 'node': No such file or directory") shouldBe None
    CodexSubject.versionOf("unknown (java.io.IOException)") shouldBe None
  }

  test("the breaker stops after two subjects in a row the harness failed on, and a judged subject resets the count") {
    val once = Breaker(None, 0).failed("copy failed")
    once.stop shouldBe None
    once.failed("copy failed").stop.exists(_.contains("two subjects in a row")) shouldBe true
    once.harnessFailures shouldBe 1
  }

  test("the login is read by kind, never by value; its values are credentials under CODEX_LOGIN_ names") {
    CodexSubject.authModeOf("""{"tokens":{"access_token":"a"}}""") shouldBe "chatgpt"
    CodexSubject.authModeOf("""{"OPENAI_API_KEY":"sk-x"}""") shouldBe "apikey"
    CodexSubject.authModeOf("not json") shouldBe "unknown"
    // Codex's own field first, else an API key before the tokens, as Codex decides it.
    CodexSubject.authModeOf("""{"auth_mode":"chatgpt","OPENAI_API_KEY":null,"tokens":{"access_token":"a"}}""") shouldBe "chatgpt"
    CodexSubject.authModeOf("""{"OPENAI_API_KEY":"sk-x","tokens":{"access_token":"a"}}""") shouldBe "apikey"
    CodexSubject.loginRefusal("""{"auth_mode":"chatgpt","tokens":{"access_token":"a"}}""") shouldBe None
    CodexSubject.loginRefusal("""{"OPENAI_API_KEY":"sk-x"}""") shouldBe None
    CodexSubject.loginRefusal("""{"personal_access_token":"p"}""").exists(_.contains("personal_access_token")) shouldBe true
    CodexSubject.loginRefusal("""{"auth_mode":"agentIdentity","agent_identity":"j"}""").exists(_.contains("agent_identity")) shouldBe true
    CodexSubject.loginRefusal("""{"auth_mode":"headers"}""").exists(_.contains("kind headers")) shouldBe true
    CodexSubject.loginRefusal("{}").isDefined shouldBe true
    val claims = java.util.Base64.getUrlEncoder.withoutPadding.encodeToString(
      """{"email":"someone@example.org","https://api.openai.com/auth":{"chatgpt_user_id":"user-0123456789abcdef"}}""".getBytes(StandardCharsets.UTF_8))
    val creds = Credentials.ofCodexLogin(s"""{"tokens":{"access_token":"tok-0123456789abcdef0123","id_token":"h.$claims.s","account_id":"acct-0123456789abcdef"}}""")
    creds.names should contain allOf ("CODEX_LOGIN_ACCESS_TOKEN", "CODEX_LOGIN_EMAIL", "CODEX_LOGIN_USER_ID", "CODEX_LOGIN_ACCOUNT_ID")
    creds.found("x someone@example.org y") shouldBe Vector("CODEX_LOGIN_EMAIL")
    creds.redact("acct-0123456789abcdef") shouldBe "<redacted:CODEX_LOGIN_ACCOUNT_ID>"
    creds.toString should not include "tok-"
  }
}
