/** ============================================================================
  *  ModelSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/search/ModelSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins the #113 P0 state model — above all the regression the tracking issue
  *  names as non-negotiable: a lemma with two obligations is NOT reported
  *  solved when only one is discharged.  Also pins the probe/move separation,
  *  the splice used by commits, the two distinct cache key types, and the
  *  outcome ranking (#112 lessons one, three, and four; lesson two lives in
  *  ActionsSpec).
  *
  *  All pure: no Agda, no server.  The same scenario runs against the real
  *  server in SingleStepIntegrationSpec.
  *
  *  ============================================================================
  */
package struxdriver.search

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

final class ModelSpec extends AnyFunSuite with Matchers {

  // A miniature working copy shaped like the TwoObligations fixture: one hole
  // whose evident move is a two-argument application.
  private val content =
    """module M where
      |goal : Pair
      |goal = {!!}
      |""".stripMargin

  private val ob0 = Obligation(3, 8, "Pair")

  private def okProbe(candidate: String, holesAfter: Vector[Obligation]): ProbeOutcome =
    ProbeOutcome(candidate, ProbeStatus.Ok, holesAfter, None)

  // --------------------------------------------------------------------------
  // The non-negotiable regression: conjunctive obligations
  // --------------------------------------------------------------------------

  test("#112 regression: two obligations, one discharged, is NOT solved") {
    val s0 = SearchState.initial(content, Vector(ob0))

    // Applying the lemma answers ok and leaves TWO obligations (as the real
    // fill_hole does: status ok, remainingHoles 2).
    val twoObs = Vector(Obligation(3, 14, "⊤"), Obligation(3, 19, "⊤"))
    val s1 = s0.commit(ob0, okProbe("lemma {!!} {!!}", twoObs)).toOption.get
    s1.obligations should have size 2
    s1.allDischarged shouldBe false

    // Discharging ONE of the two also answers ok — that is exactly the trap.
    val s2 = s1.commit(s1.obligations.head, okProbe("tt", Vector(Obligation(3, 19, "⊤")))).toOption.get
    s2.obligations should have size 1

    // The old search.py would have declared success here.  The model cannot:
    s2.allDischarged shouldBe false
    SolvedClaim.fromFinalCheck(s2, checkSuccess = true, exitCode = 0).isLeft shouldBe true
  }

  test("solved requires BOTH the empty obligation set and the batch verdict") {
    val done = SearchState(content, Vector.empty, Vector.empty)
    // Empty set alone is not enough: a failing final check refuses the claim.
    SolvedClaim.fromFinalCheck(done, checkSuccess = false, exitCode = 42).isLeft shouldBe true
    // Both together grant it.
    SolvedClaim.fromFinalCheck(done, checkSuccess = true, exitCode = 0).isRight shouldBe true
  }

  // --------------------------------------------------------------------------
  // Lesson 1: peeks are not moves
  // --------------------------------------------------------------------------

  test("probes never enter the script; commit appends exactly one move") {
    val s0 = SearchState.initial(content, Vector(ob0))
    // Probing is pure observation: ProbeOutcome values exist, the state is
    // untouched, and Vector[Move] cannot hold a ProbeOutcome by type.
    val probes = Vector(okProbe("tt", Vector.empty), okProbe("lemma {!!} {!!}", Vector(ob0)))
    probes.foreach(_ => s0.script shouldBe empty)

    val s1 = s0.commit(ob0, probes.head).toOption.get
    s1.script should have size 1
    s1.script.head.candidate shouldBe "tt"
  }

  test("commit refuses a probe that was not Ok") {
    val s0  = SearchState.initial(content, Vector(ob0))
    val bad = ProbeOutcome("nonsense", ProbeStatus.TypeError, Vector.empty, Some("A !=< B"))
    s0.commit(ob0, bad).isLeft shouldBe true
  }

  test("commit refuses a target this state does not carry") {
    val s0 = SearchState.initial(content, Vector(ob0))
    s0.commit(Obligation(99, 1, "?"), okProbe("tt", Vector.empty)).isLeft shouldBe true
  }

  // --------------------------------------------------------------------------
  // Commit adopts the oracle's re-anchored holes and splices the content
  // --------------------------------------------------------------------------

  test("commit splices the candidate over the hole token and adopts the oracle's holes") {
    val s0 = SearchState.initial(content, Vector(ob0))
    val after = Vector(Obligation(3, 14, "⊤"), Obligation(3, 19, "⊤"))
    val s1 = s0.commit(ob0, okProbe("lemma {!!} {!!}", after)).toOption.get
    s1.content should include ("goal = lemma {!!} {!!}")
    s1.obligations shouldBe after
    // The new content's sub-holes are exactly where the oracle said: the next
    // commit can address them without any client-side hole arithmetic.
    Splice.holeAt(s1.content, 3, 14, "tt").isRight shouldBe true
    Splice.holeAt(s1.content, 3, 19, "tt").isRight shouldBe true
  }

  test("splice refuses a position that does not hold a hole token") {
    Splice.holeAt(content, 3, 7, "tt").isLeft shouldBe true   // one before the hole
    Splice.holeAt(content, 2, 1, "tt").isLeft shouldBe true   // no hole on the line
    Splice.holeAt(content, 99, 1, "tt").isLeft shouldBe true  // beyond the file
  }

  // --------------------------------------------------------------------------
  // Lesson 3: two caches, two key types
  // --------------------------------------------------------------------------

  test("oracle keys and state keys are distinct types with distinct content") {
    val ok = OracleKey(Fingerprint.of(content), 3, 8, "tt")
    val sk = StateKey(Fingerprint.of(content))
    // Same fingerprint, different types: the compiler already refuses to mix
    // them; this pins that the values are not accidentally interconvertible.
    ok.contentFingerprint shouldBe sk.contentFingerprint
    (ok: Any) should not be (sk: Any)
  }

  test("a committed edit changes the state key and every oracle key") {
    val s0 = SearchState.initial(content, Vector(ob0))
    val s1 = s0.commit(ob0, okProbe("lemma {!!} {!!}", Vector(Obligation(3, 14, "⊤")))).toOption.get
    s0.key should not be s1.key
    Fingerprint.of(s0.content) should not be Fingerprint.of(s1.content)
  }

  // --------------------------------------------------------------------------
  // Lesson 4: order by remaining obligations
  // --------------------------------------------------------------------------

  test("ranking: closer < fewer subgoals < more subgoals < timeout < type_error < crash") {
    val closer  = okProbe("tt", Vector.empty)
    val one     = okProbe("sym {!!}", Vector(Obligation(1, 1, "?")))
    val two     = okProbe("lemma {!!} {!!}", Vector(Obligation(1, 1, "?"), Obligation(1, 6, "?")))
    val tmo     = ProbeOutcome("slow", ProbeStatus.Timeout, Vector.empty, None)
    val terr    = ProbeOutcome("bad", ProbeStatus.TypeError, Vector.empty, None)
    val crash   = ProbeOutcome("boom", ProbeStatus.Crash, Vector.empty, None)
    Rank.order(Vector(crash, terr, tmo, two, one, closer)) shouldBe
      Vector(closer, one, two, tmo, terr, crash)
  }
}
