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
  *  a mis-selection fails at parse time rather than an hour into a sweep.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

final class AgentBenchCliSpec extends AnyFunSuite with Matchers {

  private val base = List("--index", "i.jsonl", "--out-dir", "out", "--run-id", "r", "--project-root", ".",
    "--server-bin", "bin", "--model", "m", "--corpus-stdlib", "s.jsonl", "--corpus-algebras", "a.jsonl")

  test("--all alone and --ids alone parse; both together, neither, and an empty --ids are refused") {
    AgentBench.parseArgs(base ++ List("--all")).map(_.ids) shouldBe Right(None)
    AgentBench.parseArgs(base ++ List("--ids", "a, b,")).map(_.ids) shouldBe Right(Some(Set("a", "b")))
    AgentBench.parseArgs(base ++ List("--ids", "a", "--all")) shouldBe Left("pass exactly one of --ids and --all")
    AgentBench.parseArgs(base) shouldBe Left("pass exactly one of --ids and --all")
    AgentBench.parseArgs(base ++ List("--ids", "")) shouldBe Left("--ids names no obligation")
    AgentBench.parseArgs(base ++ List("--ids", " , ")) shouldBe Left("--ids names no obligation")
  }

  test("an unknown flag and a bad on|off value are refused by name") {
    AgentBench.parseArgs(base ++ List("--all", "--bogus", "1")) shouldBe Left("unrecognized argument: --bogus")
    AgentBench.parseArgs(base ++ List("--all", "--safe", "maybe")) shouldBe Left("bad --safe: maybe (on|off)")
  }
}
