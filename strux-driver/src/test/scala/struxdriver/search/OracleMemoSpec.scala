/** ============================================================================
  *  OracleMemoSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/search/OracleMemoSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins #112 lesson three on the oracle side: oracle calls are memoised on
  *  (content fingerprint, hole, candidate), so probing the same candidate
  *  twice costs ONE call; a different candidate, a different hole, or edited
  *  content each cost their own; and cache hits are ledgered as cached with no
  *  server time, so the timing split never counts saved calls.
  *
  *  Uses a counting fake ToolCaller — no server, no Agda.
  *
  *  ============================================================================
  */
package struxdriver.search

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import cats.effect.{IO, Ref}
import cats.effect.unsafe.implicits.global
import io.circe.Json
import java.nio.file.Paths

final class OracleMemoSpec extends AnyFunSuite with Matchers {

  /** A ToolCaller that answers every fill_hole with a canned ok body and
    * counts how many times it was actually asked.
    */
  private def countingCaller(counter: Ref[IO, Int]): ToolCaller = new ToolCaller {
    def callTool(tool: String, args: Json): IO[Timed[ToolReply]] =
      counter.update(_ + 1).as(Timed(
        ToolReply(isError = false,
          """{"status":"ok","candidate":"tt","holes":[],"remainingHoles":0,"elapsedMs":10}"""),
        clientNanos = 2000000L))
  }

  private val file = Paths.get("/nowhere/Fixture.agda")
  private val ob   = Obligation(3, 8, "⊤")
  private val ctx  = CallCtx(pass = 1, fixtureId = "fx", phase = "fill_hole", rank = Some(0))

  test("the same (content, hole, candidate) probed twice costs one oracle call") {
    val io = for {
      calls  <- Ref.of[IO, Int](0)
      oracle <- Oracle.create(countingCaller(calls))
      a1     <- oracle.probe(ctx, file, "fp-A", ob, "tt")
      a2     <- oracle.probe(ctx, file, "fp-A", ob, "tt")
      n      <- calls.get
      ledger <- oracle.timings.get
    } yield (a1, a2, n, ledger)
    val (a1, a2, n, ledger) = io.unsafeRunSync()

    n shouldBe 1
    a1.cached shouldBe false
    a2.cached shouldBe true
    a2.body shouldBe a1.body
    // The ledger keeps the saved call visible but with no oracle time.
    val cachedRows = ledger.filter(_.cached)
    cachedRows should have size 1
    cachedRows.head.serverElapsedMs shouldBe None
    cachedRows.head.clientMs shouldBe 0.0
  }

  test("a different candidate, hole, or content each miss the memo") {
    val io = for {
      calls  <- Ref.of[IO, Int](0)
      oracle <- Oracle.create(countingCaller(calls))
      _      <- oracle.probe(ctx, file, "fp-A", ob, "tt")
      _      <- oracle.probe(ctx, file, "fp-A", ob, "refl")               // other candidate
      _      <- oracle.probe(ctx, file, "fp-A", Obligation(9, 1, "?"), "tt") // other hole
      _      <- oracle.probe(ctx, file, "fp-B", ob, "tt")                 // edited content
      n      <- calls.get
    } yield n
    io.unsafeRunSync() shouldBe 4
  }
}
