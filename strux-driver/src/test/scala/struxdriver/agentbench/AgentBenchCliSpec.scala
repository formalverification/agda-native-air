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
    "--server-bin", "bin", "--agda-json-bin", "j", "--model", "m", "--corpus-stdlib", "s.jsonl", "--corpus-algebras", "a.jsonl")

  test("--all alone and --ids alone parse; both together, neither, and an empty --ids are refused") {
    Cli.parse(base ++ List("--all")).map(_.ids) shouldBe Right(None)
    Cli.parse(base ++ List("--ids", "a, b,")).map(_.ids) shouldBe Right(Some(Set("a", "b")))
    Cli.parse(base ++ List("--ids", "a", "--all")) shouldBe Left("pass exactly one of --ids and --all")
    Cli.parse(base) shouldBe Left("pass exactly one of --ids and --all")
    Cli.parse(base ++ List("--ids", "")) shouldBe Left("--ids names no obligation")
    Cli.parse(base ++ List("--ids", " , ")) shouldBe Left("--ids names no obligation")
  }

  test("a re-judge needs neither model nor corpora, but still the server and the extractor") {
    val rejudge = List("--rejudge", "--index", "i.jsonl", "--out-dir", "out", "--run-id", "r", "--project-root", ".", "--all")
    Cli.parse(rejudge ++ List("--server-bin", "bin", "--agda-json-bin", "j")).map(c => (c.model, c.rejudge)) shouldBe Right((None, true))
    Cli.parse(rejudge ++ List("--agda-json-bin", "j")) shouldBe Left("missing --server-bin")
    Cli.parse(rejudge ++ List("--server-bin", "bin")) shouldBe Left("missing --agda-json-bin")
  }

  test("an unknown flag and a bad on|off value are refused by name") {
    Cli.parse(base ++ List("--all", "--bogus", "1")) shouldBe Left("unrecognized argument: --bogus")
    Cli.parse(base ++ List("--all", "--safe", "maybe")) shouldBe Left("bad --safe: maybe (on|off)")
  }
}
