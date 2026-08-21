/** ============================================================================
  *  WireSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/search/WireSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins the Wire.scala decoders against responses captured VERBATIM from the
  *  live agda-mcp server (test/resources/search/wire-*.json; the capture
  *  procedure is the driving-agda-mcp skill's pipeline).  If the server's
  *  response shape drifts, this is where the search finds out — not mid-sweep.
  *
  *  ============================================================================
  */
package struxdriver.search

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import scala.io.Source

final class WireSpec extends AnyFunSuite with Matchers {

  private def resource(name: String): String = {
    val src = Source.fromResource(s"search/$name")
    try src.mkString.trim finally src.close()
  }

  private def replyOf(name: String, id: Long): ToolReply =
    Wire.envelope(resource(name), id) match {
      case Wire.Envelope.Reply(r) => r
      case other                  => fail(s"$name did not unwrap to a reply: $other")
    }

  test("check_file: open hole makes the batch verdict red, and the hole list is the obligation set") {
    val body = replyOf("wire-check-file-open-hole.json", 2).decodeAs[CheckFileBody].toOption.get
    body.success shouldBe false          // an open hole is not green — the verdict discipline
    body.holesCount shouldBe 1
    body.holes.map(WireHole.toObligation) shouldBe Vector(Obligation(26, 8, "?"))
    body.timedOut shouldBe false
    body.elapsedMs.isDefined shouldBe true
  }

  test("get_goal: goal type, resolved module, and which lane answered") {
    val body = replyOf("wire-get-goal.json", 3).decodeAs[GetGoalBody].toOption.get
    body.goal shouldBe "Pair"
    body.module shouldBe Some("TwoObligations")
    body.source shouldBe Some("interaction-lane")
  }

  test("fill_hole ok with sub-holes: status ok, remainingHoles 2 — ok is refinement, not proof") {
    val body = replyOf("wire-fill-hole-ok-two-subholes.json", 4).decodeAs[FillHoleBody].toOption.get
    body.status shouldBe "ok"
    body.remainingHoles shouldBe 2
    body.holes.map(WireHole.toObligation) shouldBe
      Vector(Obligation(26, 14, "?"), Obligation(26, 19, "?"))
    body.toOutcome.closesAll shouldBe false // the trap, pinned on the real wire shape
  }

  test("fill_hole type_error: an underapplied lemma is judged, not tolerated") {
    val body = replyOf("wire-fill-hole-type-error.json", 5).decodeAs[FillHoleBody].toOption.get
    body.status shouldBe "type_error"
    body.message.isDefined shouldBe true
    body.toOutcome.status shouldBe ProbeStatus.TypeError
  }

  test("fill_hole ok closing: no holes left, and the verdict exit code is 0") {
    val body = replyOf("wire-fill-hole-ok-closing.json", 6).decodeAs[FillHoleBody].toOption.get
    body.status shouldBe "ok"
    body.remainingHoles shouldBe 0
    body.exitCode shouldBe Some(0)
    body.toOutcome.closesAll shouldBe true
  }

  test("a failing call arrives as isError with prose content, not a protocol error") {
    val reply = replyOf("wire-fill-hole-no-hole-error.json", 7)
    reply.isError shouldBe true
    reply.text should include ("No hole at line 99")
    // Its content is prose: the second-level parse fails, which the client
    // must treat as an answer about the call, not a transport failure.
    reply.bodyJson.isLeft shouldBe true
  }

  test("envelope: lines for other ids and non-JSON noise are NotOurs, never fatal") {
    Wire.envelope(resource("wire-init.json"), 99) shouldBe Wire.Envelope.NotOurs
    Wire.envelope("not json at all", 1) shouldBe Wire.Envelope.NotOurs
    Wire.envelope("""{"error":{"code":-32700,"message":"Parse error"},"id":null,"jsonrpc":"2.0"}""", 1) shouldBe Wire.Envelope.NotOurs
  }
}
