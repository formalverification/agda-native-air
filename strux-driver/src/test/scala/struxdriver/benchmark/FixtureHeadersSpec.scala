// strux-driver/src/test/scala/struxdriver/benchmark/FixtureHeadersSpec.scala
//
// A guard on the benchmark fixtures' header comments (issue #219).
//
// A subject of the agent bench works on a byte-for-byte copy of its
// obligation (Scaffold.stage), header comments included, and the suite's
// original fixture template put hints in that header: a `Source:` line naming
// the module and sometimes the lemma to use, a `Strategy:` line sketching the
// proof, and on the haystack tier `Haystack:`, `Needle:`, and `Note:` lines
// naming the very lemma the tier asks a searcher to find.  Neither the judge
// nor the loop reads comments (the judge strips them before it compares; the
// loop parses only `open import` lines), so nothing else would notice such a
// line coming back.  This spec does.
//
// It covers the tiers whose headers are clean so far: the hard tiers
// (`stratum:novel`) and the composition tier (`stratum:composition`).  Issue
// #219 strips the other tiers; when it lands, the filter below goes and the
// guard covers every row.

package struxdriver.benchmark

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Paths}

import scala.jdk.CollectionConverters._

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

final class FixtureHeadersSpec extends AnyFunSuite with Matchers {

  /** The header keys that hand a subject a hint. */
  private val Hint = """^--\s*(Source|Strategy|Haystack|Needle|Note)\s*:""".r

  /** The strata whose headers issue #219 has cleaned so far. */
  private val Clean = Set("stratum:novel", "stratum:composition")

  test("no clean tier's obligation header names a source, a strategy, a needle, or a haystack (issue #219)") {
    val root  = Paths.get("..").toAbsolutePath.normalize
    val index = root.resolve("data/benchmarks/benchmark-index.jsonl")
    assume(Files.isRegularFile(index), s"benchmark index not found at $index")
    val rows = Files.readAllLines(index, StandardCharsets.UTF_8).asScala.toVector.filter(_.trim.nonEmpty)
      .map(l => io.circe.parser.decode[Obligation](l).fold(e => fail(s"bad index row: ${e.getMessage}"), identity))
      .filter(e => Clean.exists(e.tags.contains))
    // The fourteen hard-tier rows at least; the composition tier adds twelve.
    rows.size should be >= 14
    rows.foreach { e =>
      val header = Files.readAllLines(root.resolve(e.obligationPath), StandardCharsets.UTF_8).asScala
        .takeWhile(l => !l.startsWith("module "))
      withClue(s"${e.id}: ") {
        header.filter(l => Hint.findFirstIn(l).isDefined) shouldBe empty
      }
    }
  }
}
