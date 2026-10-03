/** ============================================================================
  *  AutoCloseSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/search/AutoCloseSpec.scala
  *
  *  Purpose
  *  -------
  *  Pure tests for Agda's own proof search in the loop (issue #206), against a
  *  scripted search: the knob's spellings; the found term proposed first and
  *  shaped like every other candidate (parenthesized when more than one
  *  token, bare so a found `refl` and the closer `refl` are one candidate);
  *  hints sent in `hints` mode only, and taken from the goal's own pool; a
  *  failed reply or an empty search leaving the inner space untouched; the
  *  peek exemption for exactly the terms the search found; and the ledger.
  *
  *  ============================================================================
  */
package struxdriver.search

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import cats.effect.{IO, Ref}
import cats.effect.unsafe.implicits.global

final class AutoCloseSpec extends AnyFunSuite with Matchers {

  private val ob    = Obligation(3, 8, "G")
  private val st    = SearchState.initial("module M where\ng : G\ng = {!!}\n", Vector(ob))
  private val goal  = GoalView("G", Vector.empty, Some("M"))
  private val inner = new Proposer {
    def propose(state: SearchState, target: Obligation, goal: GoalView): IO[Vector[String]] =
      IO.pure(Vector("refl", "tt", "(lemma {!!})"))
  }

  private def found(term: String): Either[String, AutoBody] =
    Right(AutoBody(AutoBody.Found, Some(term), None, None, "", Some(2L), Some(90L), 95L))
  private val none: Either[String, AutoBody] =
    Right(AutoBody(AutoBody.NoSolution, None, Some("No solution found"), None, "", Some(1L), None, 3L))

  /** A proposer over a scripted search that records the hints it was sent. */
  private def withSearch(mode: AutoMode, answer: Either[String, AutoBody], pool: Vector[String] = Vector("h1", "h2"))
      : (AutoCloseProposer, Ref[IO, Vector[Vector[String]]]) = {
    val io = for {
      sent <- Ref.of[IO, Vector[Vector[String]]](Vector.empty)
      p    <- AutoCloseProposer.create(inner, mode,
                (_, hints) => sent.update(_ :+ hints).as(answer),
                _ => IO.pure(pool))
    } yield (p, sent)
    io.unsafeRunSync()
  }

  test("the knob: off, closer, hints, and nothing else") {
    Vector("off", "closer", "hints").map(AutoMode.parse) shouldBe
      Vector(Right(AutoMode.Off), Right(AutoMode.Closer), Right(AutoMode.Hints))
    AutoMode.parse("on").isLeft shouldBe true
  }

  test("closer: the found term comes first, parenthesized, and is exempt from the peek") {
    val (p, sent) = withSearch(AutoMode.Closer, found("m , n"))
    p.propose(st, ob, goal).unsafeRunSync() shouldBe Vector("(m , n)", "refl", "tt", "(lemma {!!})")
    sent.get.unsafeRunSync() shouldBe Vector(Vector.empty)   // the default space: no hints
    p.unpeeked("(m , n)").unsafeRunSync() shouldBe true
    p.unpeeked("(lemma {!!})").unsafeRunSync() shouldBe false
    p.unpeeked("refl").unsafeRunSync() shouldBe true          // the inner rule still holds
  }

  test("closer: a one-token term is the closer it equals, proposed once") {
    val (p, _) = withSearch(AutoMode.Closer, found("refl"))
    p.propose(st, ob, goal).unsafeRunSync() shouldBe Vector("refl", "tt", "(lemma {!!})")
  }

  test("hints: the goal's pool is sent as the hints, and the term still comes first") {
    val (p, sent) = withSearch(AutoMode.Hints, found("h1 x"))
    p.propose(st, ob, goal).unsafeRunSync().head shouldBe "(h1 x)"
    sent.get.unsafeRunSync() shouldBe Vector(Vector("h1", "h2"))
  }

  test("no solution, or a failed reply, proposes nothing of its own and leaves the space as it was") {
    val (p1, _) = withSearch(AutoMode.Closer, none)
    p1.propose(st, ob, goal).unsafeRunSync() shouldBe Vector("refl", "tt", "(lemma {!!})")
    val (p2, _) = withSearch(AutoMode.Closer, Left("lane timeout"))
    p2.propose(st, ob, goal).unsafeRunSync() shouldBe Vector("refl", "tt", "(lemma {!!})")
    p2.unpeeked("(lemma {!!})").unsafeRunSync() shouldBe false
  }

  test("the ledger: calls, outcomes, distinct terms and hint sets, and the two timings") {
    val (p, _) = withSearch(AutoMode.Hints, found("h1 x"))
    p.propose(st, ob, goal).unsafeRunSync()
    p.propose(st, ob, goal).unsafeRunSync()
    val l = p.stats.unsafeRunSync()
    (l.calls, l.outcomes, l.terms, l.hintSets, l.searchMs, l.resetMs) shouldBe
      ((2, Map("found" -> 2), Vector("h1 x"), Vector(Vector("h1", "h2")), 4L, 180L))
    val js = l.toJson(AutoMode.Hints).hcursor
    js.get[String]("mode") shouldBe Right("hints")
    js.downField("outcomes").get[Int]("found") shouldBe Right(2)
  }
}
