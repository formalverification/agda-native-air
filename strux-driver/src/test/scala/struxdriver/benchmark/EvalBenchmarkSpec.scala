// strux-driver/src/test/scala/struxdriver/benchmark/EvalBenchmarkSpec.scala
//
// Unit tests for the gold-verification pipeline of EvalBenchmark.
//
// The one invariant pinned here is the whole-index guarantee from the #132
// review: a benchmark row whose gold file is missing must surface as a FAILED
// GoldResult, never be dropped from the run.  verifyOne's missing-file branch
// is pure (no Agda subprocess is spawned), so this test runs without any
// toolchain present.

package struxdriver.benchmark

import java.nio.file.Paths

import cats.effect.unsafe.implicits.global
import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

final class EvalBenchmarkSpec extends AnyFunSuite with Matchers {

  private def obligation(id: String, goldPath: String): Obligation =
    Obligation(
      id             = id,
      source         = "agda-algebras",
      module         = "Overture.Basic",
      obligationPath = Paths.get("data/benchmarks/none/obligations/X.agda"),
      goldPath       = Paths.get(goldPath),
      goldTerm       = "refl",
      hole           = "x",
      typeSig        = "x ≡ x",
      difficulty     = Difficulty.Routine,
      domain         = "universe",
      proofStrategy  = "refl",
      tags           = Vector("stratum:using")
    )

  test("verifyOne fails (never skips) a row whose gold file is missing (#132 review)") {
    val ob     = obligation("ghost-row", "data/benchmarks/none/gold/DoesNotExist.agda")
    val result = GoldVerifier.verifyOne(ob, Paths.get(".").toAbsolutePath).unsafeRunSync()

    result.passed shouldBe false
    result.obligationId shouldBe "ghost-row"
    result.errorMsg.getOrElse("") should include ("Gold file missing")
  }
}
