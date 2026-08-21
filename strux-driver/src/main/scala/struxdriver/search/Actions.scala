/** ============================================================================
  *  Actions.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/search/Actions.scala
  *  Package: struxdriver.search
  *
  *  Purpose
  *  -------
  *  Candidate construction for issue #113 (P0): the partial-application
  *  arithmetic inherited from the retired search.py (`drop_first_k_visible`),
  *  the application-candidate constructor built on it, and the fixed stub
  *  action space the single-step harness probes with.
  *
  *  Design notes
  *  ------------
  *  - The arithmetic is #112's second lesson, kept as pure functions: applying
  *    a lemma while supplying k arguments consumes the first k VISIBLE binders;
  *    hidden and instance binders are neither consumed by those arguments nor
  *    granted holes (Agda infers them or rejects the candidate — and agda-mcp
  *    reports a candidate that leaves a hidden meta unsolved as a type_error,
  *    issue #69, so the oracle polices what the constructor cannot).
  *  - The stub action space is DELIBERATELY fixed and small (P0 measures the
  *    oracle-vs-proposal split, not the solve rate; P2 replaces this space with
  *    retrieval).  It is chosen to exercise every fill_hole status and the
  *    multi-obligation path on the M1-5 suite: closers (`refl`, `tt`),
  *    application candidates from a small binder table (`sym {!!}`,
  *    `cong suc {!!}` — the latter supplies one visible argument, exercising
  *    the drop), and deliberate misfits.
  *
  *  Integration
  *  -----------
  *  Pure; used by SingleStepHarness.scala.  Binder tables here describe
  *  agda-stdlib signatures textually for candidate construction only — nothing
  *  downstream trusts them, since every candidate is judged by the oracle.
  *
  *  ============================================================================
  */
package struxdriver.search

/** Binder visibility, as in Agda: visible `(x : A)`, hidden `{x : A}`,
  * instance `⦃ x : A ⦄`.
  */
sealed trait Visibility extends Product with Serializable
object Visibility {
  case object Visible  extends Visibility
  case object Hidden   extends Visibility
  case object Instance extends Visibility
}

/** One binder of a lemma's telescope, in source order. */
final case class Binder(visibility: Visibility, domType: String)

object Actions {
  import Visibility._

  /** search.py's `drop_first_k_visible`: the binders left after supplying k
    * visible arguments — the first k visible ones are consumed, hidden and
    * instance binders pass through untouched, in order.
    */
  def remainingAfterApply(binders: Vector[Binder], k: Int): Vector[Binder] = {
    // Fold left, spending the budget only on visible binders.
    val (_, kept) = binders.foldLeft((k, Vector.empty[Binder])) {
      case ((budget, acc), b) =>
        if (b.visibility == Visible && budget > 0) (budget - 1, acc)
        else (budget, acc :+ b)
    }
    kept
  }

  /** Build the candidate term `lemma arg₁ … argₖ {!!} … {!!}`: the supplied
    * arguments consume visible binders, and each REMAINING visible binder gets
    * one fresh hole — the sub-obligations the oracle will re-anchor and count.
    */
  def applicationCandidate(lemma: String, binders: Vector[Binder], args: Vector[String]): String = {
    val remainingVisible = remainingAfterApply(binders, args.size).count(_.visibility == Visible)
    (lemma +: (args ++ Vector.fill(remainingVisible)("{!!}"))).mkString(" ")
  }

  /** Binder tables for the stub space.  Textual stand-ins for the stdlib
    * signatures; only their shape (visibility sequence) matters here.
    */
  val symBinders: Vector[Binder] = Vector(
    Binder(Hidden, "A : Set"), Binder(Hidden, "x : A"), Binder(Hidden, "y : A"),
    Binder(Visible, "x ≡ y")
  )

  val congBinders: Vector[Binder] = Vector(
    Binder(Hidden, "A : Set"), Binder(Hidden, "B : Set"),
    Binder(Visible, "A → B"),
    Binder(Hidden, "x : A"), Binder(Hidden, "y : A"),
    Binder(Visible, "x ≡ y")
  )

  val sucBinders: Vector[Binder] = Vector(Binder(Visible, "ℕ"))

  /** The fixed stub action space (k = 6).  Order is proposal order; the
    * harness ranks by outcome afterwards (Rank.order), so nothing here needs
    * to be clever — only varied.
    */
  def stubActionSpace: Vector[String] = Vector(
    "refl",                                                // closer on ≡-by-computation goals
    "tt",                                                  // closer on ⊤ goals
    applicationCandidate("sym",  symBinders,  Vector.empty),      // sym {!!}
    applicationCandidate("cong", congBinders, Vector("suc")),     // cong suc {!!}
    applicationCandidate("suc",  sucBinders,  Vector.empty),      // suc {!!} — misfit on proof goals
    "zero"                                                 // misfit / out of scope on most
  )
}
