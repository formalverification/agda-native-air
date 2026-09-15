/** ============================================================================
  *  TranscriptSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/TranscriptSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins the stream-json reader (issue #154) against a transcript captured
  *  VERBATIM from a real subject (test/resources/agentbench/transcript-smoke-
  *  haiku.jsonl: Haiku 4.5 solving stdlib-nat-plus-identity-l in four turns,
  *  2026-09-15, Claude Code 2.1.261), and the harness's audit and attempt-row
  *  derivations against a synthetic transcript that mirrors those record
  *  shapes and adds what the smoke run did not exhibit: a fill_hole probe with
  *  a JSON body, a refused fill_hole, a denied Read outside the work
  *  directory, a Read outside it that succeeded, a foreign tool, a deferred
  *  tool list, a rate-limit rejection, and a turn-capped result.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import java.nio.file.Paths
import scala.io.Source

import struxdriver.benchmark.{Difficulty, Obligation => IndexEntry}

final class TranscriptSpec extends AnyFunSuite with Matchers {

  private def resource(name: String): String = {
    val src = Source.fromResource(s"agentbench/$name")
    try src.mkString finally src.close()
  }

  private val workDir = Paths.get("/home/williamdemeo/git/formalverification/agda-native-air/worktrees/154-m1-10-agent-in-the-loop/data/benchmarks/reports/agent-bench/smoke-haiku-1/work/stdlib-nat-plus-identity-l")

  test("captured transcript: init record, eager tools, connected server, tool counts, result") {
    val t = Transcript.parse(resource("transcript-smoke-haiku.jsonl"))
    val init = t.init.getOrElse(fail("no init record"))
    init.tools.size shouldBe 15
    Subject.agdaTools.forall(init.tools.contains) shouldBe true
    init.tools.filterNot(n => Subject.fileTools(n) || Subject.agdaTools.contains(n)) shouldBe Vector.empty
    init.mcpServers shouldBe Vector(("agda", "connected"))
    init.model shouldBe Some("claude-haiku-4-5-20251001")
    init.version shouldBe Some("2.1.261")
    t.toolsDeferred shouldBe false
    t.toolCounts shouldBe Vector("Read" -> 1, "Edit" -> 1, "mcp__agda__check_file" -> 1)
    t.rateLimits shouldBe Vector(("allowed_warning", 0.99))
    t.rateLimitRejected shouldBe false
    val r = t.result.getOrElse(fail("no result record"))
    r.subtype shouldBe "success"
    r.numTurns shouldBe 4
    r.costUsd should be > 0.04
    r.permissionDenials shouldBe 0
    r.tokens.hcursor.get[Long]("cacheRead").toOption shouldBe Some(39316L)
    t.filePaths(Subject.fileTools).map(_._3).forall(_.startsWith(workDir.toString)) shouldBe true
    t.resultOf(t.usesOf("mcp__agda__check_file").head).flatMap(_.body).flatMap(_.hcursor.get[Boolean]("success").toOption) shouldBe Some(true)
  }

  test("captured transcript: the audit finds the instrument in hand and nothing outside the protocol") {
    val t   = Transcript.parse(resource("transcript-smoke-haiku.jsonl"))
    val iso = AgentBench.audit(t, workDir)
    iso.instrumentOk shouldBe true
    iso.confined shouldBe true
    iso.extraTools shouldBe Vector.empty
    iso.deniedPaths shouldBe Vector.empty
    AgentBench.terminalOf(killed = false, t.result) shouldBe "completed"
  }

  private val entry = IndexEntry("x-id", "agda-stdlib", "M", Paths.get("data/x/X.agda"), Paths.get("data/g/X.agda"),
    "refl", "x", "T", Difficulty.Routine, "d", "s", Vector.empty)

  private val cfg = AgentBenchConfig(Paths.get("i"), None, Paths.get("/w/out"), "run", Paths.get("/w"), None, 600, "",
    None, 30, 900, BigDecimal(3), 1, safe = true, persistSessions = false, "claude", None, None, rejudge = false, resume = false)

  test("synthetic transcript: probes become attempt rows, escapes are audited, deferral and rejection are seen") {
    val t = Transcript.parse(resource("transcript-synthetic.jsonl"))
    t.toolsDeferred shouldBe true
    t.rateLimitRejected shouldBe true
    t.rateLimitMax shouldBe Some(1.0)
    t.toolCounts shouldBe Vector("mcp__agda__fill_hole" -> 2, "Read" -> 2, "Bash" -> 1)

    val rows = AgentBench.attemptRows(cfg, entry, t, "subjects/x-id/transcript.jsonl")
    rows.map(_.candidate) shouldBe Vector("refl", "tt")
    rows.map(_.status) shouldBe Vector("type_error", "crash")
    rows.head.holeLine shouldBe 18
    rows.head.holeCol shouldBe 16
    rows.head.rc shouldBe 1
    rows.head.elapsedMs shouldBe 2500L
    rows.head.candidateRank shouldBe 1
    rows(1).holeIndex shouldBe 0
    rows(1).rc shouldBe -1

    val iso = AgentBench.audit(t, Paths.get("/w/work/x"))
    iso.mcpConnected shouldBe false
    iso.missingAgdaTools.size shouldBe 10
    iso.extraTools shouldBe Vector("Bash")
    iso.foreignToolUses shouldBe Vector("Bash")
    iso.deniedPaths shouldBe Vector("Read /etc/hostname")
    iso.violations shouldBe Vector("Read /w/gold/X.agda")
    iso.instrumentOk shouldBe false
    iso.confined shouldBe false

    val r = t.result.get
    r.isError shouldBe true
    r.permissionDenials shouldBe 1
    AgentBench.terminalOf(killed = false, t.result) shouldBe "max_turns"
    AgentBench.terminalOf(killed = true, t.result) shouldBe "wall_cap"
    AgentBench.terminalOf(killed = false, None) shouldBe "crash"
  }
}
