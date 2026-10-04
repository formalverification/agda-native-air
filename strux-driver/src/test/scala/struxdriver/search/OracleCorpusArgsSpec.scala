/** ============================================================================
  *  OracleCorpusArgsSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/search/OracleCorpusArgsSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins what the oracle sends the server's corpus search: since agda-mcp
  *  issue #202, search_by_type matches the type as a statement writes it by
  *  default, and the loop's retrieval proposer keeps the substring match its
  *  published runs measured by asking for it, `qualified: true`.  The recall
  *  instrument's in-memory corpus mirrors that match, so a call without the
  *  flag would let the live loop and the instrument drift apart silently.
  *
  *  Uses a recording fake ToolCaller: no server, no Agda.
  *
  *  ============================================================================
  */
package struxdriver.search

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import cats.effect.{IO, Ref}
import cats.effect.unsafe.implicits.global
import io.circe.Json

final class OracleCorpusArgsSpec extends AnyFunSuite with Matchers {

  /** A ToolCaller that answers every call with an empty hit list and keeps
    * each call's tool name and arguments.
    */
  private def recordingCaller(seen: Ref[IO, Vector[(String, Json)]]): ToolCaller = new ToolCaller {
    def callTool(tool: String, args: Json): IO[Timed[ToolReply]] =
      seen.update(_ :+ (tool -> args)).as(Timed(ToolReply(isError = false, "[]"), clientNanos = 1000000L))
  }

  private val ctx = CallCtx(pass = 1, fixtureId = "fx", phase = "retrieval", rank = None)

  test("search_by_type asks for the qualified match the loop was measured with (#202)") {
    val io = for {
      seen   <- Ref.of[IO, Vector[(String, Json)]](Vector.empty)
      oracle <- Oracle.create(recordingCaller(seen))
      _      <- oracle.searchByType(ctx, "Commutative", 7)
      calls  <- seen.get
    } yield calls
    val calls = io.unsafeRunSync()

    calls.map(_._1) shouldBe Vector("search_by_type")
    val args = calls.head._2.hcursor
    args.get[String]("pattern").toOption shouldBe Some("Commutative")
    args.get[Int]("limit").toOption shouldBe Some(7)
    args.get[Boolean]("qualified").toOption shouldBe Some(true)
  }

  test("search_by_name is unchanged: no qualified flag") {
    val io = for {
      seen   <- Ref.of[IO, Vector[(String, Json)]](Vector.empty)
      oracle <- Oracle.create(recordingCaller(seen))
      _      <- oracle.searchByName(ctx, "comm", 5)
      calls  <- seen.get
    } yield calls
    val calls = io.unsafeRunSync()

    calls.map(_._1) shouldBe Vector("search_by_name")
    calls.head._2.hcursor.downField("qualified").focus shouldBe None
  }
}
