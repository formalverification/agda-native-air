/** ============================================================================
  *  AgentBenchCliSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/AgentBenchCliSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins the harness's argument contract (Copilot on PR #158): exactly one of
  *  `--ids` and `--all`, and an `--ids` that names at least one obligation, so
  *  a mis-selection fails at parse time rather than an hour into a sweep;
  *  and where `--prices` resolves (issue #237).
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

final class AgentBenchCliSpec extends AnyFunSuite with Matchers {

  /** The harness's parser under an environment the test names: none unless
    * it says, so no test reads the endpoint of the machine it runs on.
    */
  private def cliParse(args: List[String], env: Map[String, String] = Map.empty): Either[String, AgentBenchConfig] = Cli.parse(args, env)

  private val base = List("--index", "i.jsonl", "--out-dir", "out", "--run-id", "r", "--project-root", ".",
    "--server-bin", "bin", "--agda-json-bin", "j", "--model", "m", "--corpus-stdlib", "s.jsonl", "--corpus-algebras", "a.jsonl")

  test("--all alone and --ids alone parse; both together, neither, and an empty --ids are refused") {
    cliParse(base ++ List("--all")).map(_.ids) shouldBe Right(None)
    cliParse(base ++ List("--ids", "a, b,")).map(_.ids) shouldBe Right(Some(Set("a", "b")))
    cliParse(base ++ List("--ids", "a", "--all")) shouldBe Left("pass exactly one of --ids and --all")
    cliParse(base) shouldBe Left("pass exactly one of --ids and --all")
    cliParse(base ++ List("--ids", "")) shouldBe Left("--ids names no obligation")
    cliParse(base ++ List("--ids", " , ")) shouldBe Left("--ids names no obligation")
  }

  test("a re-judge needs neither model nor corpora, but still the server and the extractor") {
    val rejudge = List("--rejudge", "--index", "i.jsonl", "--out-dir", "out", "--run-id", "r", "--project-root", ".", "--all")
    cliParse(rejudge ++ List("--server-bin", "bin", "--agda-json-bin", "j")).map(c => (c.model, c.rejudge)) shouldBe Right((None, true))
    cliParse(rejudge ++ List("--agda-json-bin", "j")) shouldBe Left("missing --server-bin")
    cliParse(rejudge ++ List("--server-bin", "bin")) shouldBe Left("missing --agda-json-bin")
  }

  test("the subjects' servers and the judge share one flag set: --safe on adds --safe, off does not") {
    cliParse(base ++ List("--all", "--agda-flags", "-l x")).map(_.serverAgdaFlags) shouldBe Right("-l x --safe")
    cliParse(base ++ List("--all", "--agda-flags", "-l x", "--safe", "off")).map(_.serverAgdaFlags) shouldBe Right("-l x")
  }

  test("every input path resolves from the project root, the index included") {
    val c = cliParse(List("--index", "data/benchmarks/benchmark-index.jsonl", "--out-dir", "out", "--run-id", "r",
      "--project-root", "/repo", "--all", "--server-bin", "bin/agda-mcp", "--agda-json-bin", "/abs/agda-json",
      "--model", "m", "--corpus-stdlib", "data/s.jsonl", "--corpus-algebras", "data/a.jsonl")).getOrElse(fail("parse"))
    c.index.toString        shouldBe "/repo/data/benchmarks/benchmark-index.jsonl"
    c.serverBin.map(_.toString)      shouldBe Some("/repo/bin/agda-mcp")
    c.agdaJsonBin.map(_.toString)    shouldBe Some("/abs/agda-json")     // an absolute path is left alone
    c.corpusStdlib.map(_.toString)   shouldBe Some("/repo/data/s.jsonl")
  }

  test("--expose names server tools on an arm with the server, and is refused by name otherwise (#191)") {
    cliParse(base ++ List("--all")).map(_.expose) shouldBe Right(None)
    cliParse(base ++ List("--all", "--expose", "check_file, type_of,")).map(_.expose) shouldBe Right(Some(Vector("check_file", "type_of")))
    cliParse(base ++ List("--all", "--arm", "both", "--expose", "check_file")).map(_.expose) shouldBe Right(Some(Vector("check_file")))
    cliParse(base ++ List("--all", "--expose", "check_file,chek_file")) shouldBe Left("--expose names tools the server does not have: chek_file")
    cliParse(base ++ List("--all", "--expose", " , ")) shouldBe Left("--expose names no tool")
    cliParse(base ++ List("--all", "--arm", "shell", "--expose", "check_file")) shouldBe Left("--expose needs an arm with the server, not shell")
    // The subjects' server is started with the same list.
    val c    = cliParse(base ++ List("--all", "--expose", "check_file,type_of")).getOrElse(fail("parse"))
    val args = Subject.mcpConfig(SubjectConfig.of(c, "s", "u"), java.nio.file.Paths.get("/w"), java.nio.file.Paths.get("/w/F.agda"), java.nio.file.Paths.get("/c.jsonl"))
      .hcursor.downField("mcpServers").downField("agda").get[Vector[String]]("args").getOrElse(Vector.empty)
    args.sliding(2).collectFirst { case Vector("--expose", v) => v } shouldBe Some("check_file,type_of")
    val none = Subject.mcpConfig(SubjectConfig.of(cliParse(base ++ List("--all")).getOrElse(fail("parse")), "s", "u"),
      java.nio.file.Paths.get("/w"), java.nio.file.Paths.get("/w/F.agda"), java.nio.file.Paths.get("/c.jsonl"))
      .hcursor.downField("mcpServers").downField("agda").get[Vector[String]]("args").getOrElse(Vector.empty)
    none should not contain ("--expose")
  }

  test("--arm names the instrument, defaults to the archived protocol's, and is refused by name otherwise") {
    cliParse(base ++ List("--all")).map(_.arm)                      shouldBe Right(Arm.Mcp)
    cliParse(base ++ List("--all", "--arm", "shell")).map(_.arm)     shouldBe Right(Arm.Shell)
    cliParse(base ++ List("--all", "--arm", "both")).map(_.arm)      shouldBe Right(Arm.Both)
    cliParse(base ++ List("--all", "--arm", "mcp")).map(_.arm)       shouldBe Right(Arm.Mcp)
    cliParse(base ++ List("--all", "--arm", "sh"))                   shouldBe Left("bad --arm: sh (shell|mcp|both)")
  }

  test("an arm decides the built-in tools and the pre-approvals, and nothing else about the flags") {
    def flags(arm: String) = {
      val c = cliParse(base ++ List("--all", "--arm", arm)).getOrElse(fail("parse"))
      Subject.fixedFlags(SubjectConfig.of(c, "system", "user"))
    }
    def valueOf(fs: Vector[String], flag: String) = fs.sliding(2).collectFirst { case Vector(`flag`, v) => v }
    valueOf(flags("mcp"),   "--tools")        shouldBe Some("Edit,Read")
    valueOf(flags("shell"), "--tools")        shouldBe Some("Bash,Edit,Read")
    valueOf(flags("both"),  "--tools")        shouldBe Some("Bash,Edit,Read")
    valueOf(flags("mcp"),   "--allowedTools") shouldBe Some("mcp__agda")
    valueOf(flags("shell"), "--allowedTools") shouldBe Some("Bash")
    valueOf(flags("both"),  "--allowedTools") shouldBe Some("mcp__agda,Bash")
    // --restricted stays on every arm: it confines the file tools and drops the
    // settings files, and it keeps Bash whenever --tools names it (measured on
    // client 2.1.261).
    Arm.all.map(_.name).foreach(a => withClue(a)(flags(a) should contain ("--restricted")))
    // A shell arm carries no --mcp-config, so --strict-mcp-config gives it no server.
    val shell = cliParse(base ++ List("--all", "--arm", "shell")).getOrElse(fail("parse"))
    val argv  = Subject.argv(SubjectConfig.of(shell, "system", "user"), None, "prompt")
    argv should contain ("--strict-mcp-config")
    argv should not contain "--mcp-config"
    Subject.argv(SubjectConfig.of(shell, "system", "user"), Some(java.nio.file.Paths.get("/m.json")), "p") should contain ("--mcp-config")
  }

  test("the arms' read roots reach the file tools through --add-dir, on every arm alike") {
    val dirs = Vector(java.nio.file.Paths.get("/nix/store/x/src"), java.nio.file.Paths.get("/repo/agda-dojang/agda"))
    Arm.all.foreach { arm =>
      val c  = cliParse(base ++ List("--all", "--arm", arm.name)).getOrElse(fail("parse"))
      val fs = Subject.fixedFlags(SubjectConfig.of(c, "system", "user", dirs))
      withClue(arm.name) {
        fs should contain ("--add-dir")
        dirs.map(_.toString).foreach(d => fs should contain (d))
      }
    }
    // No roots, no flag: an empty --add-dir would be an argument error.
    Subject.fixedFlags(SubjectConfig.of(cliParse(base ++ List("--all")).getOrElse(fail("parse")), "s", "u")) should not contain "--add-dir"
  }

  test("--prices resolves from the project root, is optional on Anthropic's endpoint, and is required on another (#237)") {
    val repo = List("--index", "i.jsonl", "--out-dir", "out", "--run-id", "r", "--project-root", "/repo", "--all",
      "--server-bin", "b", "--agda-json-bin", "j", "--model", "m", "--corpus-stdlib", "s", "--corpus-algebras", "a")
    cliParse(repo).map(_.prices) shouldBe Right(None)                       // the harness reads Cli.defaultPrices
    cliParse(repo ++ List("--prices", "data/prices-moonshot.json")).map(_.prices.map(_.toString)) shouldBe Right(Some("/repo/data/prices-moonshot.json"))
    val moonshot = Map("ANTHROPIC_BASE_URL" -> "https://api.moonshot.ai/anthropic")
    cliParse(repo, moonshot).left.map(_.startsWith("ANTHROPIC_BASE_URL names another host than Anthropic's: pass --prices")) shouldBe Left(true)
    cliParse(repo ++ List("--prices", "p.json"), moonshot).isRight shouldBe true
    cliParse(repo, Map("ANTHROPIC_BASE_URL" -> "https://api.anthropic.com/")).isRight shouldBe true
    cliParse(List("--rejudge", "--index", "i", "--out-dir", "o", "--run-id", "r", "--project-root", ".", "--all",
      "--server-bin", "b", "--agda-json-bin", "j"), moonshot).isRight shouldBe true   // a re-judge prices at the run's own table
  }

  test("an unknown flag and a bad on|off value are refused by name") {
    cliParse(base ++ List("--all", "--bogus", "1")) shouldBe Left("unrecognized argument: --bogus")
    cliParse(base ++ List("--all", "--safe", "maybe")) shouldBe Left("bad --safe: maybe (on|off)")
  }
}
