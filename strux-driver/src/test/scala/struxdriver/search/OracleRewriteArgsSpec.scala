/** ============================================================================
  *  OracleRewriteArgsSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/search/OracleRewriteArgsSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins the display mode the oracle asks get_goal and type_of for: since
  *  agda-mcp issue #248 both answer in Agda's Simplified mode by default, and
  *  the loop keeps the Normalised mode its published runs measured by asking
  *  for it, `rewrite: "Normalised"`.  The binder counts read a lemma's
  *  expanded pi type, the peek compares two printings as text, and the
  *  idf-unfold scorer states rows in the vocabulary of a normalized goal, so
  *  a call without the argument would change the loop's numbers silently.
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
import java.nio.file.Paths

final class OracleRewriteArgsSpec extends AnyFunSuite with Matchers {

  /** A ToolCaller that keeps each call's tool name and arguments and answers
    * with the smallest body each decoder accepts.
    */
  private def recordingCaller(seen: Ref[IO, Vector[(String, Json)]]): ToolCaller = new ToolCaller {
    def callTool(tool: String, args: Json): IO[Timed[ToolReply]] = {
      val body = tool match {
        case "get_goal" => """{"goal":"Nat","context":[],"elapsedMs":1}"""
        case _          => """{"expr":"p","scope":"toplevel","type":"Nat","elapsedMs":1}"""
      }
      seen.update(_ :+ (tool -> args)).as(Timed(ToolReply(isError = false, body), clientNanos = 1000000L))
    }
  }

  private val ctx  = CallCtx(pass = 1, fixtureId = "fx", phase = "type_of", rank = None)
  private val file = Paths.get("/work/Fx.agda")

  test("get_goal and type_of ask for the Normalised display the loop was measured with (#248)") {
    val io = for {
      seen   <- Ref.of[IO, Vector[(String, Json)]](Vector.empty)
      oracle <- Oracle.create(recordingCaller(seen))
      _      <- oracle.getGoal(ctx, file, Obligation(line = 3, col = 7, goal = "?"))
      _      <- oracle.typeOf(ctx, file, "p", Some((3, 7)))
      _      <- oracle.typeOf(ctx, file, "p", None)
      calls  <- seen.get
    } yield calls
    val calls = io.unsafeRunSync()

    calls.map(_._1) shouldBe Vector("get_goal", "type_of", "type_of")
    calls.map(_._2.hcursor.get[String]("rewrite").toOption) shouldBe Vector.fill(3)(Some("Normalised"))
  }
}
