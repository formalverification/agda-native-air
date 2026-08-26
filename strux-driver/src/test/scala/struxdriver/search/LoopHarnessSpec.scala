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
      loop          = LoopConfig.default
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
}
