/** ============================================================================
  *  LoopHarnessSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/search/LoopHarnessSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins the loop harness's anomaly-recovery contract (Copilot round 1 on
  *  PR #126): when a fixture's search dies mid-flight, the attempt rows
  *  already written, the fixture's real wall clock, and the probe/hit counts
  *  the hooks observed all survive into the fixture's outputs — an anomaly
  *  must never strip results.jsonl of exactly the evidence that explains it.
  *
  *  Pure: a scripted ToolCaller whose transport dies on the second probe; no
  *  server, no Agda.
  *
  *  Also pins the report's stratum label (issue #129): an outcome carries its
  *  index row's `source` and `tags` on every path, anomaly included, and the
  *  label under which it reports is the source extended by the `stratum:`
  *  tag when there is one.
  *
  *  ============================================================================
  */
package struxdriver.search

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import cats.effect.IO
import cats.effect.unsafe.implicits.global
import io.circe.Json
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Paths}

import struxdriver.benchmark.{Difficulty, Obligation => IndexEntry}

final class LoopHarnessSpec extends AnyFunSuite with Matchers {

  private val checkOneHole: String =
    Json.obj(
      "success"    -> Json.False,
      "holes"      -> Json.arr(Json.obj(
        "index" -> Json.fromInt(0), "line" -> Json.fromInt(3),
        "col"   -> Json.fromInt(8), "goal" -> Json.fromString("?"))),
      "holesCount" -> Json.fromInt(1),
      "timedOut"   -> Json.False,
      "elapsedMs"  -> Json.fromInt(7)
    ).noSpaces

  private val goalReply: String =
    Json.obj(
      "goal"      -> Json.fromString("T"),
      "context"   -> Json.arr(),
      "module"    -> Json.fromString("Test"),
      "source"    -> Json.fromString("interaction-lane"),
      "elapsedMs" -> Json.fromInt(1)
    ).noSpaces

  private val reflTypeError: String =
    Json.obj(
      "status"         -> Json.fromString("type_error"),
      "candidate"      -> Json.fromString("refl"),
      "message"        -> Json.fromString("no"),
      "holes"          -> Json.arr(Json.obj(
        "index" -> Json.fromInt(0), "line" -> Json.fromInt(3),
        "col"   -> Json.fromInt(8), "goal" -> Json.fromString("?"))),
      "remainingHoles" -> Json.fromInt(1),
      "elapsedMs"      -> Json.fromInt(5)
    ).noSpaces

  /** Answers the staging check and the first probe, then the transport dies
    * on the second probe — the mid-fixture failure whose diagnostics the
    * recovery path must keep.
    */
  private val dyingCaller: ToolCaller = new ToolCaller {
    def callTool(tool: String, args: Json): IO[Timed[ToolReply]] = tool match {
      case "check_file" => IO.pure(Timed(ToolReply(isError = false, checkOneHole), 1000000L))
      case "get_goal"   => IO.pure(Timed(ToolReply(isError = false, goalReply), 1000000L))
      case "fill_hole"  =>
        args.hcursor.get[String]("candidate").toOption.get match {
          case "refl" => IO.pure(Timed(ToolReply(isError = false, reflTypeError), 1000000L))
          case other  => IO.raiseError(new RuntimeException(s"transport died probing $other"))
        }
      case other => IO.raiseError(new RuntimeException(s"unexpected tool: $other"))
    }
  }

  test("an anomalous RETRIEVAL fixture keeps its accumulated ledger (#130 round 3)") {
    // The corpus queries answer and the ledger accumulates (hits, inScope,
    // proposedLemmas); then the transport dies on a probe.  The recovered
    // outcome must carry the retrieval snapshot — the honesty ledger matters
    // most precisely on failed runs.
    val searchHit: String =
      """[{"prettyQname":"TestLib.helper","type":"U → T","defKind":"function","module":"TestLib","hasBody":true}]"""
    // Per-expression lane answers: the target ("goal") and the lemma
    // ("helper") must print DIFFERENT types, or the lane-form statement
    // exclusion (correctly) removes the lemma as a target alias.
    def typeOfReply(expr: String): String =
      if (expr == "helper") """{"type":"U → T","elapsedMs":1}"""
      else """{"type":"T","elapsedMs":1}"""
    val retrievalDyingCaller: ToolCaller = new ToolCaller {
      def callTool(tool: String, args: Json): IO[Timed[ToolReply]] = tool match {
        case "check_file"     => IO.pure(Timed(ToolReply(isError = false, checkOneHole), 1000000L))
        case "get_goal"       => IO.pure(Timed(ToolReply(isError = false, goalReply), 1000000L))
        case "type_of"        =>
          val expr = args.hcursor.get[String]("expr").toOption.getOrElse("")
          IO.pure(Timed(ToolReply(isError = false, typeOfReply(expr)), 1000000L))
        case "search_by_name" => IO.pure(Timed(ToolReply(isError = false, searchHit), 1000000L))
        case "search_by_type" => IO.pure(Timed(ToolReply(isError = false, "[]"), 1000000L))
        case "fill_hole"      => IO.raiseError(new RuntimeException("transport died on the first probe"))
        case other            => IO.raiseError(new RuntimeException(s"unexpected tool: $other"))
      }
    }
    val root = Files.createTempDirectory(
      Files.createDirectories(Paths.get(sys.props("user.dir"), "target", "loop-harness-spec")), "root-")
    val oblDir = Files.createDirectories(root.resolve("obl"))
    Files.write(oblDir.resolve("Test.agda"),
      "module Test where\nopen import TestLib using ( helper )\ngoal : T\ngoal = {!!}\n".getBytes(StandardCharsets.UTF_8))
    val cfg = LoopHarnessConfig(
      index         = root.resolve("unused.jsonl"),
      ids           = None,
      outDir        = root.resolve("out"),
      runId         = "t-retr",
      serverBin     = root.resolve("unused-bin"),
      agdaFlags     = "",
      serverTimeout = 1,
      projectRoot   = root,
      loop          = LoopConfig.default.copy(peek = false),
      proposerKind  = "retrieval",
      corpus        = Some(root.resolve("unused-corpus.jsonl")),
      retrieval     = RetrievalConfig.default
    )
    val entry = IndexEntry(
      id             = "test-retr-anomaly",
      source         = "test",
      module         = "Test",
      obligationPath = Paths.get("obl/Test.agda"),
      goldPath       = Paths.get("obl/Test.agda"),
      goldTerm       = "",
      hole           = "goal",
      typeSig        = "T",
      difficulty     = Difficulty.Routine,
      domain         = "",
      proofStrategy  = "",
      tags           = Vector.empty
    )

    val (outcome, row, attempts) = (for {
      oracle <- Oracle.create(retrievalDyingCaller)
      out    <- ProofSearchLoop.runFixture(cfg, oracle, entry)
    } yield out).unsafeRunSync()

    outcome.searchStatus shouldBe "anomaly"
    outcome.anomaly.getOrElse("") should include ("transport died")
    outcome.source shouldBe "test"
    outcome.tags shouldBe Vector.empty
    outcome.stratum shouldBe "test"
    row.searchStatus shouldBe "anomaly"
    attempts shouldBe empty // the transport died on the FIRST probe
    val retr = outcome.retrieval.getOrElse(fail("retrieval ledger lost on the anomaly path"))
    retr.hcursor.get[Int]("hits").toOption.getOrElse(0) should be >= 1
    retr.hcursor.get[Vector[String]]("proposedLemmas").toOption.getOrElse(Vector.empty) should contain ("helper")
  }

  test("an anomalous fixture keeps its rows, wall clock, and hook-observed counts") {
    val root = Files.createTempDirectory(
      Files.createDirectories(Paths.get(sys.props("user.dir"), "target", "loop-harness-spec")), "root-")
    val oblDir = Files.createDirectories(root.resolve("obl"))
    // No `using` imports, so the fixed space is the two closers: refl (a
    // type_error the world answers) then tt (where the transport dies).
    Files.write(oblDir.resolve("Test.agda"),
      "module Test where\ngoal : T\ngoal = {!!}\n".getBytes(StandardCharsets.UTF_8))

    val cfg = LoopHarnessConfig(
      index         = root.resolve("unused.jsonl"),
      ids           = None,
      outDir        = root.resolve("out"),
      runId         = "t",
      serverBin     = root.resolve("unused-bin"),
      agdaFlags     = "",
      serverTimeout = 1,
      projectRoot   = root,
      loop          = LoopConfig.default.copy(peek = false), // fakes no lane; see BeamLoopSpec.noPeek
      proposerKind  = "fixed",
      corpus        = None,
      retrieval     = RetrievalConfig.default
    )
    val entry = IndexEntry(
      id             = "test-anomaly",
      source         = "test",
      module         = "Test",
      obligationPath = Paths.get("obl/Test.agda"),
      goldPath       = Paths.get("obl/Test.agda"),
      goldTerm       = "",
      hole           = "goal",
      typeSig        = "T",
      difficulty     = Difficulty.Routine,
      domain         = "",
      proofStrategy  = "",
      tags           = Vector.empty
    )

    val (outcome, row, attempts) = (for {
      oracle <- Oracle.create(dyingCaller)
      out    <- ProofSearchLoop.runFixture(cfg, oracle, entry)
    } yield out).unsafeRunSync()

    outcome.searchStatus shouldBe "anomaly"
    outcome.anomaly.getOrElse("") should include ("transport died")
    // The evidence survives: the refl attempt row, and the hook-observed
    // probe count — not the zeros the pre-fix recovery reported.
    attempts should have size 1
    attempts.head.candidate shouldBe "refl"
    attempts.head.status shouldBe "type_error"
    outcome.stats.probes shouldBe 1
    outcome.stats.memoHits shouldBe 0
    row.searchStatus shouldBe "anomaly"
    row.finalStatus shouldBe "crash"
    // The raw reply log the hook wrote is also on disk, beside the row.
    Files.exists(cfg.runRoot.resolve("logs/test-anomaly/probe-001.json")) shouldBe true
  }

  test("the stratum label is the source, extended by the stratum tag when present (#129)") {
    LoopOutcome.stratumOf("agda-stdlib", Vector.empty) shouldBe "agda-stdlib"
    LoopOutcome.stratumOf("agda-stdlib", Vector("stratum:haystack")) shouldBe "agda-stdlib/haystack"
    LoopOutcome.stratumOf("agda-algebras", Vector("universe-polymorphic", "stratum:wholesale")) shouldBe
      "agda-algebras/wholesale"
    // Other tags never make a stratum; the first stratum tag wins.
    LoopOutcome.stratumOf("agda-algebras", Vector("universe-polymorphic")) shouldBe "agda-algebras"
    LoopOutcome.stratumOf("x", Vector("stratum:a", "stratum:b")) shouldBe "x/a"
  }
}
