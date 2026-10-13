/** ============================================================================
  *  ProtocolSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/ProtocolSpec.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  Pins the protocol record (issue #154): what a run's `protocol.json`
  *  holds, that the subjects' servers carry the judge's `--safe`, and that
  *  the resume rule names every field on which two protocols differ.  The
  *  endpoint (issue #237): the base URL the subjects are given, or `absent`,
  *  in the protocol and in each subject's record, never a credential (a
  *  search of the two records written with one in the environment; the
  *  live spec searches a whole run directory), and a resume under a changed
  *  endpoint refused naming the field.  The price
  *  table is an input by path and digest, like the corpora.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.unsafe.implicits.global
import io.circe.Json
import io.circe.syntax._
import java.nio.file.{Files, Paths}
import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

final class ProtocolSpec extends AnyFunSuite with Matchers {

  /** The harness's parser under an environment the test names: none unless
    * it says, so no test reads the endpoint of the machine it runs on.
    */
  private def cliParse(args: List[String], env: Map[String, String] = Map.empty): Either[String, AgentBenchConfig] = Cli.parse(args, env)

  private val base = List("--index", "i.jsonl", "--out-dir", "out", "--run-id", "r", "--project-root", ".", "--all",
    "--server-bin", "bin", "--agda-json-bin", "j", "--corpus-stdlib", "s.jsonl", "--corpus-algebras", "a.jsonl", "--agda-flags", "-l x")

  /** A config whose subjects inherit `env`: empty unless a test names one,
    * so no test reads the endpoint of the machine it runs on.
    */
  private def cfg(extra: String*): AgentBenchConfig = cfgIn(Map.empty, extra: _*)
  private def cfgIn(env: Map[String, String], extra: String*): AgentBenchConfig =
    cliParse(base ++ List("--model", "claude-sonnet-5", "--prices", "p.json") ++ extra.toList, env).getOrElse(fail("parse"))

  /** A value no real credential has, standing for one. */
  private val credential = "sk-test-not-a-credential-237"
  private val moonshot   = Map(
    "PATH"                          -> "/usr/bin",
    "ANTHROPIC_BASE_URL"            -> "https://api.moonshot.ai/anthropic",
    "ANTHROPIC_AUTH_TOKEN"          -> credential,
    "ANTHROPIC_DEFAULT_HAIKU_MODEL" -> "kimi-k3",
    "CLAUDE_CODE_ENTRYPOINT"        -> "cli")

  /** A stand-in for the content-addressed inputs block. */
  private def someInputs(indexSha: String = "aa", corpusSha: String = "cc"): Json = Json.obj(
    "projectRoot" -> "/repo".asJson,
    "index"       -> Json.obj("path" -> "/repo/i.jsonl".asJson, "sha256" -> indexSha.asJson),
    "serverBin"   -> Json.obj("path" -> "/repo/bin".asJson, "sha256" -> "bb".asJson),
    "corpora"     -> Json.obj("agda-stdlib" -> Json.obj("path" -> "/repo/s.jsonl".asJson, "sha256" -> corpusSha.asJson)))

  test("the record holds the knobs a subject sees and the judge applies, the prompts by digest, and the servers' flags with --safe") {
    val p = Protocol.of(cfg(), "2.1.261 (Claude Code)", "system", "user {{path}} {{hole}}", someInputs())
    p.hcursor.get[String]("model").toOption shouldBe Some("claude-sonnet-5")
    p.hcursor.get[String]("agdaFlags").toOption shouldBe Some("-l x")
    p.hcursor.get[String]("subjectAgdaFlags").toOption shouldBe Some("-l x --safe")
    p.hcursor.get[Boolean]("safe").toOption shouldBe Some(true)
    p.hcursor.get[Int]("maxTurns").toOption shouldBe Some(30)
    p.hcursor.get[String]("claudeVersion").toOption shouldBe Some("2.1.261 (Claude Code)")
    p.hcursor.downField("prompts").downField("system").get[String]("sha256").toOption shouldBe Some(struxdriver.io.TextIO.sha256("system"))
    p.hcursor.get[Vector[String]]("tools").toOption.map(_.size) shouldBe Some(15)
    p.hcursor.get[Vector[String]]("claudeFlags").toOption.exists(_.contains("--restricted")) shouldBe true
    p.hcursor.downField("inputs").downField("index").get[String]("sha256").toOption shouldBe Some("aa")
    p.hcursor.downField("inputs").downField("corpora").downField("agda-stdlib").get[String]("sha256").toOption shouldBe Some("cc")
  }

  test("inputs identify the index, the binaries, the corpora, and the price table by content, so a file regenerated in place differs") {
    val dir    = Files.createTempDirectory("agentbench-inputs")
    val index  = dir.resolve("i.jsonl"); val bin = dir.resolve("bin"); val js = dir.resolve("j")
    val corp   = dir.resolve("s.jsonl"); val alg = dir.resolve("a.jsonl"); val prices = dir.resolve("p.json")
    val row    = """{"input": 3, "cacheWrite": 3, "cacheRead": 0.3, "output": 15}"""
    Vector(index -> "one\n", bin -> "server", js -> "extractor", corp -> "rows", alg -> "rows",
      prices -> s"""{"schemaVersion": "agent-bench-prices.v0", "asOf": "2026-10-13", "models": {"kimi-k3": $row}}""")
      .foreach { case (p, s) => Files.write(p, s.getBytes("UTF-8")) }
    val table  = Pricing.load(prices).unsafeRunSync()
    val real = cliParse(List("--index", index.toString, "--out-dir", "out", "--run-id", "r", "--project-root", ".", "--all",
      "--server-bin", bin.toString, "--agda-json-bin", js.toString, "--corpus-stdlib", corp.toString,
      "--corpus-algebras", alg.toString, "--model", "m", "--prices", prices.toString), Map.empty).getOrElse(fail("parse"))
    val before = Protocol.inputs(real, Json.obj("agda-stdlib" -> Json.obj("sha256" -> "digest-of-rows".asJson)), table).unsafeRunSync()
    before.hcursor.downField("index").get[String]("path").toOption shouldBe Some(index.toAbsolutePath.toString)
    val indexSha = before.hcursor.downField("index").get[String]("sha256").getOrElse(fail("no index digest"))
    indexSha.length shouldBe 64
    before.hcursor.downField("agdaJsonBin").get[String]("sha256").toOption should not be None
    before.hcursor.downField("corpora").downField("agda-stdlib").get[String]("sha256").toOption shouldBe Some("digest-of-rows")

    Files.write(index, "one\ntwo\n".getBytes("UTF-8"))          // regenerated in place, same path
    val after = Protocol.inputs(real, Json.obj(), table).unsafeRunSync()
    after.hcursor.downField("index").get[String]("sha256").toOption should not be Some(indexSha)
    val ds = Protocol.differences(
      Protocol.of(real, "v1", "system", "user", before),
      Protocol.of(real, "v1", "system", "user", after))
    ds.map(_.takeWhile(_ != ':')) shouldBe Vector("inputs")

    // The price table likewise (issue #237): by path and digest, so a table
    // edited in place is a different protocol.
    after.hcursor.downField("prices").get[String]("path").toOption shouldBe Some("prices.json")   // the run's own copy, which a resume reads
    val pricesSha = after.hcursor.downField("prices").get[String]("sha256").getOrElse(fail("no price-table digest"))
    Files.write(prices, new String(Files.readAllBytes(prices), "UTF-8").replace("15}", "15.5}").getBytes("UTF-8"))
    val repriced = Protocol.inputs(real, Json.obj(), Pricing.load(prices).unsafeRunSync()).unsafeRunSync()
    repriced.hcursor.downField("prices").get[String]("sha256").toOption should not be Some(pricesSha)
    Protocol.differences(Protocol.of(real, "v1", "system", "user", after), Protocol.of(real, "v1", "system", "user", repriced))
      .map(_.takeWhile(_ != ':')) shouldBe Vector("inputs")
  }

  test("the subject's server config carries the judge's --safe in its flags and in the check_project command") {
    val subject = SubjectConfig.of(cfg(), "system", "user")
    val mcp     = Subject.mcpConfig(subject, Paths.get("/w"), Paths.get("/w/M.agda"), Paths.get("/c.jsonl"))
    val args    = mcp.hcursor.downField("mcpServers").downField("agda").get[Vector[String]]("args").getOrElse(fail("args"))
    args.sliding(2).collectFirst { case Vector("--agda-flags", f) => f } shouldBe Some("-l x --safe")
    args.sliding(2).collectFirst { case Vector("--check-command", c) => c } shouldBe Some("agda -l x --safe -i /w /w/M.agda")
    SubjectConfig.of(cfg("--safe", "off"), "system", "user").agdaFlags shouldBe "-l x"
    Audit.workDirOf(mcp) shouldBe Some(Paths.get("/w"))                        // the audit's root, from the config itself
    Audit.workDirOf(Json.obj()) shouldBe None
  }

  test("differences names every field that changed, absent keys included, and nothing when equal") {
    val a = Protocol.of(cfg(), "v1", "system", "user", someInputs())
    val b = Protocol.of(cfg("--max-turns", "40", "--safe", "off"), "v2", "system", "user", someInputs())
    Protocol.differences(a, a) shouldBe Vector.empty
    val ds = Protocol.differences(a, b)
    ds.exists(_.startsWith("maxTurns: 30 -> 40")) shouldBe true
    ds.exists(_.startsWith("safe: true -> false")) shouldBe true
    ds.exists(_.startsWith("subjectAgdaFlags: ")) shouldBe true
    ds.exists(_.startsWith("claudeVersion: ")) shouldBe true
    ds.exists(_.startsWith("model")) shouldBe false
    Protocol.differences(Json.obj("model" -> "m".asJson), Json.obj()) shouldBe Vector("model: \"m\" -> absent")
    Protocol.differences(a, Protocol.of(cfg(), "v1", "system", "user 2", someInputs())).map(_.takeWhile(_ != ':')) shouldBe Vector("prompts")
    // A corpus regenerated at the same path is a different protocol.
    Protocol.differences(a, Protocol.of(cfg(), "v1", "system", "user", someInputs(corpusSha = "dd")))
      .map(_.takeWhile(_ != ':')) shouldBe Vector("inputs")
  }

  test("the record names the arm, its tools, and its read roots, so two arms are two protocols") {
    def armed(a: String, dirs: Vector[java.nio.file.Path] = Vector.empty) = {
      val c = cliParse(base ++ List("--model", "claude-sonnet-5", "--arm", a)).getOrElse(fail("parse"))
      Protocol.of(c, "2.1.261", "system", "user", someInputs(), dirs)
    }
    armed("mcp").hcursor.get[String]("arm").toOption   shouldBe Some("mcp")
    armed("shell").hcursor.get[String]("arm").toOption shouldBe Some("shell")
    // The shell arm's tool list is its three built-ins and no agda tool; the
    // mcp arm's is Read, Edit and the thirteen an arm with the server must have.
    armed("shell").hcursor.get[Vector[String]]("tools").toOption shouldBe Some(Vector("Bash", "Edit", "Read"))
    armed("mcp").hcursor.get[Vector[String]]("tools").toOption.map(_.size)  shouldBe Some(15)
    armed("both").hcursor.get[Vector[String]]("tools").toOption.map(_.size) shouldBe Some(16)
    // Two arms differ as protocols, named by the fields that carry the arm.
    val ds = Protocol.differences(armed("mcp"), armed("shell")).map(_.takeWhile(_ != ':'))
    ds should contain ("arm")
    ds should contain ("tools")
    ds should contain ("claudeFlags")
    // The libraries' roots are part of the protocol, so a toolchain that moves
    // them refuses a resume instead of mixing two environments.
    Protocol.differences(armed("mcp"), armed("mcp", Vector(java.nio.file.Paths.get("/nix/store/x/src"))))
      .map(_.takeWhile(_ != ':')) should contain ("addDirs")
  }

  test("--expose is recorded: the subset, and the tools a subject must be shown; a run without it has no expose key") {
    val sub = Protocol.of(cfg("--expose", "check_file,fill_hole,get_goal,type_of"), "v", "s", "u", someInputs())
    sub.hcursor.get[Vector[String]]("expose").toOption shouldBe Some(Vector("check_file", "fill_hole", "get_goal", "type_of"))
    sub.hcursor.get[Vector[String]]("tools").toOption shouldBe
      Some(Vector("Edit", "Read", "mcp__agda__check_file", "mcp__agda__fill_hole", "mcp__agda__get_goal", "mcp__agda__type_of"))
    val all = Protocol.of(cfg(), "v", "s", "u", someInputs())
    all.hcursor.downField("expose").focus shouldBe None
    // So a subset run and a full one are two protocols, named by the field.
    Protocol.differences(all, sub).map(_.takeWhile(_ != ':')) should contain allOf ("expose", "tools")
  }

  test("a re-judge keeps the run's own arm in the report's config; only an archive with none takes the operator's") {
    val rejudge = cliParse(base ++ List("--rejudge")).getOrElse(fail("parse"))   // --arm left at its default, mcp
    val shellRun = Json.obj("arm" -> "shell".asJson, "safe" -> Json.True, "model" -> "claude-sonnet-5".asJson)
    val kept     = Report.rejudgedConfig(shellRun, rejudge, "2026-09-25T00:00:00Z")
    kept.hcursor.get[String]("arm").toOption shouldBe Some("shell")
    kept.hcursor.get[String]("rejudgedAt").toOption shouldBe Some("2026-09-25T00:00:00Z")
    kept.hcursor.get[String]("model").toOption shouldBe Some("claude-sonnet-5")
    // An archive made before the arm existed records none, and was the mcp arm.
    Report.rejudgedConfig(Json.obj("model" -> "claude-opus-5".asJson), rejudge, "t").hcursor.get[String]("arm").toOption shouldBe Some("mcp")
  }

  test("a subject's own record carries the arm and the roots, and survives the round trip") {
    val roots = ShellRoots(Paths.get("/w/work/x"), Vector(Paths.get("/nix/store/x/src")), Vector(Paths.get("/c/corpus.jsonl")))
    val rec   = SubjectRecord(Arm.Both, roots)
    SubjectRecord.fromJson(rec.toJson) shouldBe Some(rec)
    // The exposed subset rides along when a run has one (issue #191), and a
    // record without it (every archive before #191) reads as the full surface.
    val subset = SubjectRecord(Arm.Mcp, roots, Some(Vector("check_file", "type_of")))
    SubjectRecord.fromJson(subset.toJson) shouldBe Some(subset)
    rec.toJson.hcursor.downField("expose").focus shouldBe None
    SubjectRecord.fromJson(Json.obj()) shouldBe None
    SubjectRecord.fromJson(Json.obj("arm" -> "nope".asJson, "workDir" -> "/w".asJson)) shouldBe None
    // An archive written before the record existed has none, and the judge
    // falls back to the mcp arm confined to its work directory.
    Arm.default shouldBe Arm.Mcp
  }

  test("admit records a fresh run, resumes the same protocol, and refuses a changed one or subjects without a record") {
    val root   = Files.createTempDirectory("agentbench-protocol")
    val layout = RunLayout(root.resolve("r"))
    val a      = Protocol.of(cfg(), "v1", "system", "user", someInputs())
    val b      = Protocol.of(cfg("--max-turns", "40"), "v1", "system", "user", someInputs())
    Files.createDirectories(layout.runRoot)
    Protocol.admit(layout, a, resume = false).unsafeRunSync()
    io.circe.parser.parse(new String(Files.readAllBytes(layout.protocol), "UTF-8")).toOption shouldBe Some(a)
    Protocol.admit(layout, a, resume = true).unsafeRunSync()                       // the same protocol resumes
    val refused = intercept[RuntimeException](Protocol.admit(layout, b, resume = true).unsafeRunSync())
    refused.getMessage should startWith ("resume refused: run r was made under a different protocol (")
    refused.getMessage should include ("maxTurns: 30 -> 40")                    // and claudeFlags, which carry the cap
    refused.getMessage should endWith ("; pass a new --run-id")
    Protocol.admit(layout, b, resume = false).unsafeRunSync()                      // a fresh run re-records
    io.circe.parser.parse(new String(Files.readAllBytes(layout.protocol), "UTF-8")).toOption shouldBe Some(b)
    val old = RunLayout(root.resolve("old"))                                        // subjects archived before the record existed
    Files.createDirectories(old.runRoot.resolve("subjects"))
    intercept[RuntimeException](Protocol.admit(old, a, resume = true).unsafeRunSync()).getMessage should include ("no protocol.json")
    Files.exists(old.protocol) shouldBe false
    val fresh = RunLayout(root.resolve("fresh"))                                    // resume on an empty run id is a fresh run
    Files.createDirectories(fresh.runRoot)
    Protocol.admit(fresh, a, resume = true).unsafeRunSync()
    Files.exists(fresh.protocol) shouldBe true
  }

  test("the endpoint is the base URL the subjects are given, or absent, with the client's model variables and never a credential (#237)") {
    // The subject inherits the endpoint and its credential: the client needs both.
    val inherited = Subject.environment(moonshot)
    inherited.get("ANTHROPIC_BASE_URL") shouldBe Some("https://api.moonshot.ai/anthropic")
    inherited.get("ANTHROPIC_AUTH_TOKEN") shouldBe Some(credential)
    inherited.keySet should not contain ("CLAUDE_CODE_ENTRYPOINT")
    inherited.get("ENABLE_TOOL_SEARCH") shouldBe Some("false")
    // The record carries the allowlist alone.
    val p = Protocol.of(cfgIn(moonshot, "--model", "kimi-k3"), "v", "s", "u", someInputs())
    p.hcursor.downField("endpoint").focus shouldBe Some(Json.obj(
      "ANTHROPIC_BASE_URL"            -> "https://api.moonshot.ai/anthropic".asJson,
      "ANTHROPIC_DEFAULT_HAIKU_MODEL" -> "kimi-k3".asJson,
      "ANTHROPIC_AUTH_TOKEN"          -> "set".asJson))
    p.spaces2 should not include (credential)
    // Every credential variable the client reads is named, never valued.
    val all = cfgIn(moonshot ++ Map("ANTHROPIC_API_KEY" -> credential, "ANTHROPIC_CUSTOM_HEADERS" -> s"Authorization: Bearer $credential",
      "ANTHROPIC_BASE_URL" -> "https://api.anthropic.com")).endpoint
    all.toJson.noSpaces should not include (credential)
    all.vars.filter(_._2 == "set").map(_._1) shouldBe Vector("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_CUSTOM_HEADERS")
    // The config, printed, prints no credential either.
    cfgIn(moonshot).toString should not include (credential)
    // No base URL is the client's default, Anthropic's API, recorded as such.
    Protocol.of(cfg(), "v", "s", "u", someInputs()).hcursor.downField("endpoint").focus shouldBe
      Some(Json.obj("ANTHROPIC_BASE_URL" -> "absent".asJson))
    // A CLAUDE* variable never reaches the subject.
    cfgIn(Map("CLAUDE_CODE_USE_BEDROCK" -> "1", "PATH" -> "/bin")).env.vars.keySet shouldBe Set("PATH", "MCP_TIMEOUT", "ENABLE_TOOL_SEARCH")
    // An exported empty value is no value, for the client and for the record:
    // Ollama's setup clears ANTHROPIC_API_KEY so, and an emptied base URL is
    // the default.
    val ollama = Map("ANTHROPIC_BASE_URL" -> "http://localhost:11434", "ANTHROPIC_AUTH_TOKEN" -> "ollama", "ANTHROPIC_API_KEY" -> "")
    cfgIn(ollama).endpoint.toJson shouldBe Json.obj("ANTHROPIC_BASE_URL" -> "http://localhost:11434".asJson, "ANTHROPIC_AUTH_TOKEN" -> "set".asJson)
    cfgIn(Map("ANTHROPIC_BASE_URL" -> " ")).endpoint shouldBe Endpoint(Vector("ANTHROPIC_BASE_URL" -> "absent"))
  }

  test("a base URL is recorded without its userinfo, query, and fragment, and a value that is no URL is not recorded at all (#237)") {
    Endpoint.redact(s"https://user:$credential@api.example.com:8443/anthropic/?key=$credential#frag") shouldBe
      "https://api.example.com:8443/anthropic/"
    Endpoint.redact("http://orin.local:11434") shouldBe "http://orin.local:11434"
    Endpoint.redact(" https://api.moonshot.ai/anthropic ") shouldBe "https://api.moonshot.ai/anthropic"
    Endpoint.redact("localhost:11434") shouldBe "unparsed"
    Endpoint.redact(credential) shouldBe "unparsed"
    Endpoint.of(Map("ANTHROPIC_BASE_URL" -> s"https://$credential@h/p")).toJson.noSpaces should not include (credential)
  }

  test("a changed endpoint is a different protocol, and a resume under it is refused naming the field (#237)") {
    val anthropic = Protocol.of(cfg(), "v1", "system", "user", someInputs())
    val moon      = Protocol.of(cfgIn(moonshot), "v1", "system", "user", someInputs())
    Protocol.differences(anthropic, moon).map(_.takeWhile(_ != ':')) shouldBe Vector("endpoint")
    val layout = RunLayout(Files.createTempDirectory("agentbench-endpoint").resolve("r"))
    Files.createDirectories(layout.runRoot)
    Protocol.admit(layout, anthropic, resume = false).unsafeRunSync()
    val refused = intercept[RuntimeException](Protocol.admit(layout, moon, resume = true).unsafeRunSync())
    refused.getMessage should include ("""endpoint: {"ANTHROPIC_BASE_URL":"absent"} -> {"ANTHROPIC_BASE_URL":"https://api.moonshot.ai/anthropic","ANTHROPIC_DEFAULT_HAIKU_MODEL":"kimi-k3","ANTHROPIC_AUTH_TOKEN":"set"}""")
    refused.getMessage should not include (credential)
  }

  test("a subject's record carries the endpoint; a record made before #237 has none") {
    val roots = ShellRoots(Paths.get("/w/work/x"), Vector.empty, Vector.empty)
    val rec   = SubjectRecord(Arm.Mcp, roots, None, Some(cfgIn(moonshot).endpoint))
    SubjectRecord.fromJson(rec.toJson) shouldBe Some(rec)
    rec.toJson.hcursor.downField("endpoint").get[String]("ANTHROPIC_BASE_URL").toOption shouldBe Some("https://api.moonshot.ai/anthropic")
    SubjectRecord.fromJson(Json.obj("arm" -> "mcp".asJson, "workDir" -> "/w".asJson)).map(_.endpoint) shouldBe Some(None)
  }

  test("the protocol and a subject record written under a credential hold none of it (#237)") {
    val c      = cfgIn(moonshot)
    val layout = RunLayout(Files.createTempDirectory("agentbench-credential").resolve("r"))
    Files.createDirectories(layout.runRoot)
    Protocol.admit(layout, Protocol.of(c, "v1", "system", "user", someInputs()), resume = false).unsafeRunSync()
    struxdriver.io.TextIO.write(layout.subject("x").record,
      SubjectRecord(c.arm, ShellRoots(layout.workDir("x"), Vector.empty, Vector.empty), c.expose, Some(c.endpoint)).toJson.spaces2).unsafeRunSync()
    val files = Files.walk(layout.runRoot).filter(Files.isRegularFile(_)).toArray.toVector.map(_.asInstanceOf[java.nio.file.Path])
    files.map(_.getFileName.toString).sorted shouldBe Vector("protocol.json", "subject.json")
    files.foreach(f => withClue(f.toString)(new String(Files.readAllBytes(f), "UTF-8") should not include (credential)))
  }

  test("a run that would send another host both an API key and an auth token is refused at parse time; a re-judge, which spawns nothing, is not (#237)") {
    val both = moonshot + ("ANTHROPIC_API_KEY" -> credential)
    val refused = cliParse(base ++ List("--model", "kimi-k3", "--prices", "p.json"), both)
    refused.left.map(_.startsWith("ANTHROPIC_BASE_URL names another host than Anthropic's and both")) shouldBe Left(true)
    refused.left.map(_.contains(credential)) shouldBe Left(false)
    cliParse(base ++ List("--model", "kimi-k3", "--prices", "p.json"), moonshot).isRight shouldBe true              // one credential
    cliParse(base ++ List("--model", "m"), both + ("ANTHROPIC_BASE_URL" -> "https://api.anthropic.com")).isRight shouldBe true  // Anthropic's own host
    cliParse(base ++ List("--model", "m"), both - "ANTHROPIC_BASE_URL").isRight shouldBe true                        // the client's default
    cliParse(base ++ List("--model", "m", "--prices", "p.json"), both + ("ANTHROPIC_API_KEY" -> "")).isRight shouldBe true  // an emptied key is no key
    cliParse(List("--rejudge", "--index", "i", "--out-dir", "o", "--run-id", "r", "--project-root", ".", "--all",
      "--server-bin", "b", "--agda-json-bin", "j"), both).isRight shouldBe true
  }

  test("a protocol recorded before #237 reads as the client's default endpoint and the current table, so a run in flight resumes") {
    val table  = Json.obj("path" -> "prices.json".asJson, "sha256" -> "pp".asJson)
    val now    = Protocol.of(cfg(), "v1", "system", "user", someInputs().mapObject(_.add("prices", table)))
    val before = now.mapObject(_.remove("endpoint")).hcursor.downField("inputs").withFocus(_.mapObject(_.remove("prices"))).top.get
    before.hcursor.downField("endpoint").focus shouldBe None
    Protocol.differences(before, now) shouldBe Vector.empty
    // It is still the client's default it reads as: under another endpoint
    // the resume is refused.
    val moon = Protocol.of(cfgIn(moonshot), "v1", "system", "user", someInputs().mapObject(_.add("prices", table)))
    Protocol.differences(before, moon).map(_.takeWhile(_ != ':')) shouldBe Vector("endpoint")
    // And a record that has a table keeps it: a changed table is a change.
    val repriced = now.hcursor.downField("inputs").downField("prices").withFocus(_.mapObject(_.add("sha256", "qq".asJson))).top.get
    Protocol.differences(now, repriced).map(_.takeWhile(_ != ':')) shouldBe Vector("inputs")
  }
}
