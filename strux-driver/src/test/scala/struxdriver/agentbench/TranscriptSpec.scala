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
  *  The arm cases (issue #162) are at the end: the same audit read under each
  *  arm, so that a shell arm is not failed for having no server, an mcp arm is
  *  still failed for being handed Bash, and the `via` columns say which
  *  instrument a row used and which gave it its last verdict; and that under
  *  `--expose` (issue #191) the exposed tools are the whole agda expectation,
  *  both the floor and the ceiling.
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

  /** The roots of an archived mcp subject: its work directory and nothing else,
    * which is what the runs made before `--add-dir` had.
    */
  private def onlyWork(dir: java.nio.file.Path) = ShellRoots(dir, Vector.empty, Vector.empty)

  private val workDir = Paths.get("/home/williamdemeo/git/formalverification/agda-native-air/worktrees/154-m1-10-agent-in-the-loop/data/benchmarks/reports/agent-bench/smoke-haiku-1/work/stdlib-nat-plus-identity-l")

  test("captured transcript: init record, eager tools, connected server, tool counts, result") {
    val t = Transcript.parse(resource("transcript-smoke-haiku.jsonl"))
    val init = t.init.getOrElse(fail("no init record"))
    init.tools.size shouldBe 15
    Subject.agdaToolsRequired.forall(t => init.tools.contains(t)) shouldBe true
    init.tools.filterNot(n => Subject.fileTools(n) || Subject.agdaToolsRequired.contains(n)) shouldBe Vector.empty
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
    // Every call and result keeps its stream record: calls in order, each result after its call (issue #188).
    t.uses.map(_.record) shouldBe t.uses.map(_.record).sorted
    t.uses.forall(u => t.resultOf(u).exists(_.record > u.record)) shouldBe true
    t.uses.map(_.record).last should be < t.records
  }

  test("captured transcript: the audit finds the instrument in hand and nothing outside the protocol") {
    val t   = Transcript.parse(resource("transcript-smoke-haiku.jsonl"))
    val iso = Audit.isolation(t, Arm.Mcp, onlyWork(workDir))
    iso.instrumentOk shouldBe true
    iso.confined shouldBe true
    iso.extraTools shouldBe Vector.empty
    iso.deniedPaths shouldBe Vector.empty
    Audit.terminalOf(killed = false, t.result) shouldBe "completed"
  }

  private val cleanVerdict = Verdict(None, Vector.empty, Vector.empty, "bodyRefs", None, Vector.empty, Some(0), checkUnusable = false, Some(0), Some(1L), None)

  test("a tool presented beyond the protocol is an anomaly, used or not") {
    val t   = Transcript.parse(resource("transcript-smoke-haiku.jsonl"))
    val iso = Audit.isolation(t, Arm.Mcp, onlyWork(workDir))
    Outcomes.anomalyOf(t, iso, cleanVerdict, "completed") shouldBe None
    Outcomes.anomalyOf(t, iso.copy(extraTools = Vector("Bash")), cleanVerdict, "completed") shouldBe Some("tools presented beyond the protocol: Bash")
    Outcomes.anomalyOf(t, iso, cleanVerdict.copy(checkExit = Some(1)), "completed").exists(_.contains("disagree")) shouldBe true
  }

  test("a subject that emitted no result record is an anomaly; a wall-cap kill is not") {
    val full    = Transcript.parse(resource("transcript-smoke-haiku.jsonl"))
    val iso     = Audit.isolation(full, Arm.Mcp, onlyWork(workDir))
    val noResult = Transcript.parse(resource("transcript-smoke-haiku.jsonl").linesIterator.filterNot(_.contains("\"type\":\"result\"")).mkString("\n"))
    noResult.result shouldBe None
    noResult.init should not be None
    Audit.terminalOf(killed = false, noResult.result) shouldBe "crash"
    Audit.terminalOf(killed = true, noResult.result) shouldBe "wall_cap"
    Outcomes.anomalyOf(noResult, iso, cleanVerdict, "crash").exists(_.startsWith("no result record")) shouldBe true
    Outcomes.anomalyOf(noResult, iso, cleanVerdict, "wall_cap") shouldBe None
  }

  test("a check_file answer that is not usable at all is an anomaly: the escape and hole gates read nothing") {
    val t   = Transcript.parse(resource("transcript-smoke-haiku.jsonl"))
    val iso = Audit.isolation(t, Arm.Mcp, onlyWork(workDir))
    Outcomes.anomalyOf(t, iso, cleanVerdict.copy(checkUnusable = true), "completed")
      .exists(_.startsWith("check_file gave no usable verdict")) shouldBe true
    // What makes an answer usable, by the server's own fields.
    def checked(success: Boolean, timedOut: Boolean, exit: Option[Int]) =
      Checked(success, timedOut, exit, 0, Vector.empty, Map.empty, 1L)
    checked(true,  false, Some(0)).usable  shouldBe true
    checked(false, false, Some(1)).usable  shouldBe true      // a plain failure is an answer
    checked(true,  true,  Some(0)).usable  shouldBe false     // the server's agda timed out
    checked(true,  false, None).usable     shouldBe false     // no verdict at all
    checked(true,  false, Some(1)).usable  shouldBe false     // the answer contradicts itself
    checked(false, false, Some(0)).usable  shouldBe false
  }

  test("a file Agda checked that the extractor could not read is an anomaly, never a quiet solve") {
    val t   = Transcript.parse(resource("transcript-smoke-haiku.jsonl"))
    val iso = Audit.isolation(t, Arm.Mcp, onlyWork(workDir))
    val unreadable = cleanVerdict.copy(evidenceSource = "unavailable: agda-json exit 1")
    Outcomes.anomalyOf(t, iso, unreadable, "completed") shouldBe Some("the final file type-checks but the extractor could not read it: agda-json exit 1")
    // A file that does not type-check is named by the verdict, not by this rule.
    Outcomes.anomalyOf(t, iso, unreadable.copy(agdaExit = Some(1), checkExit = Some(1)), "completed") shouldBe None
  }

  private val entry = IndexEntry("x-id", "agda-stdlib", "M", Paths.get("data/x/X.agda"), Paths.get("data/g/X.agda"),
    "refl", "x", "T", Difficulty.Routine, "d", "s", Vector.empty)

  test("synthetic transcript: probes become attempt rows, escapes are audited, deferral and rejection are seen") {
    val t = Transcript.parse(resource("transcript-synthetic.jsonl"))
    t.toolsDeferred shouldBe true
    t.rateLimitRejected shouldBe true
    t.rateLimitMax shouldBe Some(1.0)
    t.toolCounts shouldBe Vector("mcp__agda__fill_hole" -> 2, "Read" -> 2, "Bash" -> 1)

    val rows = Audit.attemptRows(entry, Paths.get("/w/work/x/X.agda"), t, "subjects/x-id/transcript.jsonl")
    rows.map(_.candidate) shouldBe Vector("refl", "tt")
    rows.map(_.status) shouldBe Vector("type_error", "crash")
    rows.head.holeLine shouldBe 18
    rows.head.holeCol shouldBe 16
    rows.head.rc shouldBe 1
    rows.head.elapsedMs shouldBe 2500L
    rows.head.candidateRank shouldBe 1
    rows(1).holeIndex shouldBe 0
    rows(1).rc shouldBe -1

    val iso = Audit.isolation(t, Arm.Mcp, onlyWork(Paths.get("/w/work/x")))
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
    Audit.terminalOf(killed = false, t.result) shouldBe "max_turns"
    Audit.terminalOf(killed = true, t.result) shouldBe "wall_cap"
    Audit.terminalOf(killed = false, None) shouldBe "crash"
  }

  // -------------------------------------------------------------- the arms

  private val synthetic = Transcript.parse(resource("transcript-synthetic.jsonl"))
  private val synthWork = Paths.get("/w/work/x")

  test("a shell arm has no server to connect and no agda tools to miss, so neither is its anomaly") {
    val iso = Audit.isolation(synthetic, Arm.Shell, onlyWork(synthWork))
    iso.mcpConnected shouldBe false                      // the fact is still recorded
    iso.missingAgdaTools shouldBe Vector.empty            // but it is not an expectation of this arm
    // The three agda tools the synthetic init lists are beyond a shell arm's set.
    iso.extraTools should contain ("mcp__agda__check_file")
    Outcomes.anomalyOf(synthetic, iso.copy(extraTools = Vector.empty), cleanVerdict, "completed")
      .exists(_.contains("not connected")) shouldBe false
    // An mcp arm, by contrast, is an anomaly on the very same transcript.
    Outcomes.anomalyOf(synthetic, Audit.isolation(synthetic, Arm.Mcp, onlyWork(synthWork)), cleanVerdict, "completed")
      .exists(_.contains("not connected")) shouldBe true
  }

  test("Bash is a foreign tool on the mcp arm and the arm's own tool on the shell and both arms") {
    Audit.isolation(synthetic, Arm.Mcp,   onlyWork(synthWork)).foreignToolUses should contain (Arm.bash)
    Audit.isolation(synthetic, Arm.Shell, onlyWork(synthWork)).foreignToolUses should not contain Arm.bash
    Audit.isolation(synthetic, Arm.Both,  onlyWork(synthWork)).foreignToolUses shouldBe Vector.empty
    Audit.isolation(synthetic, Arm.Both,  onlyWork(synthWork)).extraTools shouldBe Vector.empty
  }

  test("an arm with a shell has its Bash calls classed, and an escape by one fails the gate") {
    val iso = Audit.isolation(synthetic, Arm.Both, onlyWork(synthWork))
    iso.shellClasses shouldBe Vector("other" -> 1)        // the synthetic call is `ls`
    iso.violations shouldBe Vector("Read /w/gold/X.agda") // the file tool's escape, and only it
    iso.confined shouldBe false
    // An mcp arm reads no shell classes at all, whatever the transcript holds.
    Audit.isolation(synthetic, Arm.Mcp, onlyWork(synthWork)).shellClasses shouldBe Vector.empty
  }

  test("a read the arm's roots allow is no longer an escape, which is the symmetric --add-dir change") {
    val withLib = ShellRoots(synthWork, Vector(Paths.get("/w/gold")), Vector.empty)
    val iso     = Audit.isolation(synthetic, Arm.Mcp, withLib)
    iso.violations shouldBe Vector.empty                  // /w/gold/X.agda is inside a read root now
    iso.deniedPaths shouldBe Vector("Read /etc/hostname") // and the refused read is still counted apart
    // An Edit is confined to the work directory even when a read root would allow it.
    val edited = Transcript.parse(resource("transcript-synthetic.jsonl").replace("\"Read\"", "\"Edit\""))
    Audit.isolation(edited, Arm.Mcp, withLib).violations shouldBe Vector("Edit /w/gold/X.agda")
  }

  // ------------------------------------------------------------ --expose (#191)

  private val verdictSubset = Vector("check_file", "fill_hole", "get_goal", "type_of")

  /** A subject shown Read, Edit, and the four exposed tools, which calls the
    * given agda tools once each.
    */
  private def subsetRun(calls: String*): Transcript = Transcript.parse(
    (s"""{"type":"system","subtype":"init","tools":["Edit","Read",${verdictSubset.map(t => s"\"mcp__agda__$t\"").mkString(",")}],"mcp_servers":[{"name":"agda","status":"connected"}]}""" +:
      calls.zipWithIndex.map { case (c, i) =>
        s"""{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t$i","name":"mcp__agda__$c","input":{}}]}}""" }
    ).mkString("\n"))

  test("under --expose the exposed tools are the floor: a subset subject is complete, and would not be without the flag") {
    val t   = subsetRun("check_file", "type_of")
    val iso = Audit.isolation(t, Arm.Mcp, onlyWork(synthWork), Some(verdictSubset))
    iso.missingAgdaTools shouldBe Vector.empty
    iso.extraTools shouldBe Vector.empty
    iso.foreignToolUses shouldBe Vector.empty
    iso.instrumentOk shouldBe true
    iso.exposed shouldBe Some(verdictSubset)
    iso.toJson.hcursor.get[Vector[String]]("exposed").toOption shouldBe Some(verdictSubset)
    // Audited as a full-surface run, the same subject misses nine tools.
    Audit.isolation(t, Arm.Mcp, onlyWork(synthWork)).missingAgdaTools.size shouldBe 9
    // A full-surface audit keeps its old shape: no exposed key at all.
    Audit.isolation(t, Arm.Mcp, onlyWork(synthWork)).toJson.hcursor.downField("exposed").focus shouldBe None
  }

  test("under --expose the exposed tools are the ceiling: a tool beyond them presented or used is outside the protocol") {
    val haiku = Transcript.parse(resource("transcript-smoke-haiku.jsonl"))    // all thirteen presented
    val iso   = Audit.isolation(haiku, Arm.Mcp, onlyWork(workDir), Some(verdictSubset))
    iso.extraTools.size shouldBe 9
    iso.extraTools should contain ("mcp__agda__search_by_name")
    iso.extraTools should not contain ("mcp__agda__check_file")
    // A use of an unexposed tool is foreign, and fails the isolation gate.
    val used = Audit.isolation(subsetRun("check_file", "normalize"), Arm.Mcp, onlyWork(synthWork), Some(verdictSubset))
    used.foreignToolUses shouldBe Vector("mcp__agda__normalize")
    used.confined shouldBe false
  }

  test("via says which instruments a row used; verdictVia says which gave it its last verdict") {
    Outcomes.viaOf(synthetic) shouldBe "both"             // two fill_hole calls and one Bash
    val haiku = Transcript.parse(resource("transcript-smoke-haiku.jsonl"))
    Outcomes.viaOf(haiku) shouldBe "mcp"
    Outcomes.verdictViaOf(haiku, onlyWork(workDir)) shouldBe "mcp"
    Outcomes.verdictViaOf(synthetic, onlyWork(synthWork)) shouldBe "none"   // no check_file, no agda run
    // A shell subject whose last verdict is its own agda run reads `shell`.
    val shellRun = Transcript.parse(
      """{"type":"system","subtype":"init","tools":["Bash","Read","Edit"],"mcp_servers":[]}""" + "\n" +
      """{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"agda --safe -i . M.agda"}}]}}""")
    Outcomes.viaOf(shellRun) shouldBe "shell"
    Outcomes.verdictViaOf(shellRun, onlyWork(synthWork)) shouldBe "shell"
    Audit.isolation(shellRun, Arm.Shell, onlyWork(synthWork)).shellClasses shouldBe Vector("agda-batch" -> 1)
  }
}
