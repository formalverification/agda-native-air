/** ============================================================================
  *  Actions.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/search/Actions.scala
  *  Package: struxdriver.search
  *
  *  Purpose
  *  -------
  *  Candidate construction for issue #113 (P0 and P1): the partial-application
  *  arithmetic inherited from the retired search.py (`drop_first_k_visible`),
  *  the application-candidate constructor built on it, the fixed stub action
  *  space the single-step harness probes with, and — for the P1 loop (issue
  *  #122) — the deliberately small pi-type splitter that reads a binder
  *  telescope off a lane-printed type.
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

  /** The deliberately small top-level pi-type splitter of issue #122: read a
    * binder telescope off a printed type as the interaction lane renders it
    * (type_of, Normalised — captures in test/resources/search/).  The type is
    * split on arrows at bracket depth 0 (counting (), {}, ⦃⦄); every segment
    * before the last is a domain.  A domain consisting only of binder groups
    * — optionally ∀-prefixed — contributes one binder per bound name, with
    * the group's own visibility; any other domain is a single visible one
    * (an unnamed function-type domain like `x ≡ y` or `(A → B)`).  This is a
    * PROPOSAL device, not an authority: the oracle polices what it gets
    * wrong — an overcount is judged CannotApply/type_error by fill_hole, an
    * undercount leaves a partial application the goal must then accept.
    */
  def bindersOfPrinted(printed: String): Vector[Binder] = {
    val segs = splitTopLevel(printed.replaceAll("\\s+", " ").trim)
    if (segs.size <= 1) Vector.empty
    else segs.init.flatMap(domainBinders)
  }

  /** Split a normalized type on depth-0 `→`. */
  private def splitTopLevel(s: String): Vector[String] = {
    val out   = Vector.newBuilder[String]
    val cur   = new StringBuilder
    var depth = 0
    s.foreach {
      case c @ ('(' | '{' | '⦃') => depth += 1; cur += c
      case c @ (')' | '}' | '⦄') => depth -= 1; cur += c
      case '→' if depth == 0     => out += cur.result().trim; cur.clear()
      case c                     => cur += c
    }
    out += cur.result().trim
    out.result()
  }

  /** One depth-0 group of a domain segment, or a bare token run between groups. */
  private sealed trait Piece
  private final case class Group(open: Char, content: String) extends Piece
  private final case class Bare(text: String)                 extends Piece

  private def pieces(seg: String): Vector[Piece] = {
    val out   = Vector.newBuilder[Piece]
    val cur   = new StringBuilder
    var depth = 0
    var open  = ' '
    def flushBare(): Unit = { val t = cur.result().trim; if (t.nonEmpty) out += Bare(t); cur.clear() }
    seg.foreach {
      case c @ ('(' | '{' | '⦃') =>
        if (depth == 0) { flushBare(); open = c } else cur += c
        depth += 1
      case c @ (')' | '}' | '⦄') =>
        depth -= 1
        if (depth == 0) { out += Group(open, cur.result()); cur.clear() } else cur += c
      case c => cur += c
    }
    flushBare()
    out.result()
  }

  private def domainBinders(seg: String): Vector[Binder] = {
    val ps = pieces(seg)
    val rest = ps match {
      case Bare("∀") +: tail => tail
      case other             => other
    }
    val groups     = rest.collect { case g: Group => g }
    val onlyGroups = rest.nonEmpty && rest.forall(_.isInstanceOf[Group])
    val parensBind = groups.forall(g => g.open != '(' || g.content.contains(':'))
    if (onlyGroups && parensBind)
      groups.flatMap { g =>
        val vis = g.open match {
          case '(' => Visible
          case '{' => Hidden
          case _   => Instance
        }
        g.content.indexOf(':') match {
          case -1 => Vector(Binder(vis, g.content.trim))
          case i  => g.content.take(i).trim.split("\\s+").toVector.filter(_.nonEmpty)
                       .map(_ => Binder(vis, g.content.drop(i + 1).trim))
        }
      }
    else Vector(Binder(Visible, seg))
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
