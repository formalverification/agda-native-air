/** ============================================================================
  *  AgentBenchIntegrationSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/AgentBenchIntegrationSpec.scala
  *
  *  Purpose
  *  -------
  *  The judge's typecheck gate against the real `agda` (issue #154): the
  *  committed gold of stdlib-nat-plus-comm passes every gate under --safe and
  *  is solved; the same file with a wrong proof body passes the syntactic
  *  gates and fails on typecheck, named.  Needs the Agda-capable dev shell:
  *  set AGDA_NATIVE_AIR_ROOT to the repo root (the agent-bench-it Make target
  *  does), inside `nix develop .#backend`; without it the suite is cancelled.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import cats.effect.unsafe.implicits.global
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Paths}
import scala.concurrent.duration._
import scala.jdk.CollectionConverters._

final class AgentBenchIntegrationSpec extends AnyFunSuite with Matchers {

  private val rootEnv = sys.env.get("AGDA_NATIVE_AIR_ROOT").map(Paths.get(_))

  private def entry(root: java.nio.file.Path, id: String) =
    Files.readAllLines(root.resolve("data/benchmarks/benchmark-index.jsonl"), StandardCharsets.UTF_8).asScala
      .map(l => io.circe.parser.decode[struxdriver.benchmark.Obligation](l).toOption.get)
      .find(_.id == id).get

  test("the judge solves the committed gold under --safe and names typecheck on a wrong proof") {
    val root = rootEnv.getOrElse(cancel("AGDA_NATIVE_AIR_ROOT not set; skipping the judge's Agda gate test"))
    assume(sys.env.contains("AGDA_DIR"), "AGDA_DIR not set: run inside nix develop .#backend")
    val e    = entry(root, "stdlib-nat-plus-comm")
    val ob   = new String(Files.readAllBytes(root.resolve(e.obligationPath)), StandardCharsets.UTF_8)
    val gold = new String(Files.readAllBytes(root.resolve(e.goldPath)), StandardCharsets.UTF_8)
    val dir  = Files.createTempDirectory(Paths.get("target").toAbsolutePath, "agentbench-judge-")
    val file = dir.resolve("Nat-plus-comm.agda")

    Files.write(file, gold.getBytes(StandardCharsets.UTF_8))
    val v1 = Judge.judge(e, ob, gold, file, root, safe = true, 300.seconds).unsafeRunSync()
    v1.gate shouldBe None
    v1.agdaExit shouldBe Some(0)
    v1.solved shouldBe true
    v1.restated shouldBe false

    val wrong = ob.replace("{!!}", "refl")
    Files.write(file, wrong.getBytes(StandardCharsets.UTF_8))
    val v2 = Judge.judge(e, ob, wrong, file, root, safe = true, 300.seconds).unsafeRunSync()
    v2.gate.map(_.gate) shouldBe Some("typecheck")
    v2.agdaExit.exists(_ != 0) shouldBe true
    v2.solved shouldBe false

    // A rule broken but the file green: the gate is named AND Agda's verdict is recorded.
    val edited = gold.replace("using ( _≡_ ; refl ; cong ; sym )", "using ( _≡_ ; refl ; cong ; sym ; trans )")
    Files.write(file, edited.getBytes(StandardCharsets.UTF_8))
    val v3 = Judge.judge(e, ob, edited, file, root, safe = true, 300.seconds).unsafeRunSync()
    v3.gate.map(_.gate) shouldBe Some("preservation")
    v3.agdaExit shouldBe Some(0)
    v3.solved shouldBe false
  }
}
