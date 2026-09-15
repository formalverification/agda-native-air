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
  *  the resume rule names every field on which two protocols differ.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import io.circe.Json
import io.circe.syntax._
import java.nio.file.Paths
import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

final class ProtocolSpec extends AnyFunSuite with Matchers {

  private val base = List("--index", "i.jsonl", "--out-dir", "out", "--run-id", "r", "--project-root", ".", "--all",
    "--server-bin", "bin", "--agda-json-bin", "j", "--corpus-stdlib", "s.jsonl", "--corpus-algebras", "a.jsonl", "--agda-flags", "-l x")

  private def cfg(extra: String*): AgentBenchConfig =
    Cli.parse(base ++ List("--model", "claude-sonnet-5") ++ extra.toList).getOrElse(fail("parse"))

  test("the record holds the knobs a subject sees and the judge applies, the prompts by digest, and the servers' flags with --safe") {
    val p = Protocol.of(cfg(), "2.1.261 (Claude Code)", "system", "user {{path}} {{hole}}")
    p.hcursor.get[String]("model").toOption shouldBe Some("claude-sonnet-5")
    p.hcursor.get[String]("agdaFlags").toOption shouldBe Some("-l x")
    p.hcursor.get[String]("subjectAgdaFlags").toOption shouldBe Some("-l x --safe")
    p.hcursor.get[Boolean]("safe").toOption shouldBe Some(true)
    p.hcursor.get[Int]("maxTurns").toOption shouldBe Some(30)
    p.hcursor.get[String]("claudeVersion").toOption shouldBe Some("2.1.261 (Claude Code)")
    p.hcursor.downField("prompts").downField("system").get[String]("sha256").toOption shouldBe Some(struxdriver.io.TextIO.sha256("system"))
    p.hcursor.get[Vector[String]]("tools").toOption.map(_.size) shouldBe Some(15)
    p.hcursor.get[Vector[String]]("claudeFlags").toOption.exists(_.contains("--restricted")) shouldBe true
    p.hcursor.get[String]("index").toOption.exists(_.endsWith("/i.jsonl")) shouldBe true
    p.hcursor.get[String]("corpusAlgebras").toOption.exists(_.endsWith("/a.jsonl")) shouldBe true
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
    val a = Protocol.of(cfg(), "v1", "system", "user")
    val b = Protocol.of(cfg("--max-turns", "40", "--safe", "off"), "v2", "system", "user")
    Protocol.differences(a, a) shouldBe Vector.empty
    val ds = Protocol.differences(a, b)
    ds.exists(_.startsWith("maxTurns: 30 -> 40")) shouldBe true
    ds.exists(_.startsWith("safe: true -> false")) shouldBe true
    ds.exists(_.startsWith("subjectAgdaFlags: ")) shouldBe true
    ds.exists(_.startsWith("claudeVersion: ")) shouldBe true
    ds.exists(_.startsWith("model")) shouldBe false
    Protocol.differences(Json.obj("model" -> "m".asJson), Json.obj()) shouldBe Vector("model: \"m\" -> absent")
    Protocol.differences(a, Protocol.of(cfg(), "v1", "system", "user 2")).map(_.takeWhile(_ != ':')) shouldBe Vector("prompts")
  }

  test("admit records a fresh run, resumes the same protocol, and refuses a changed one or subjects without a record") {
    import cats.effect.unsafe.implicits.global
    import java.nio.file.Files
    val root   = Files.createTempDirectory("agentbench-protocol")
    val layout = RunLayout(root.resolve("r"))
    val a      = Protocol.of(cfg(), "v1", "system", "user")
    val b      = Protocol.of(cfg("--max-turns", "40"), "v1", "system", "user")
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
}
