/** ============================================================================
  *  AutoClose.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/search/AutoClose.scala
  *  Package: struxdriver.search
  *
  *  Purpose
  *  -------
  *  Agda's own proof search inside the loop (issue #206): at every state the
  *  loop expands, before any other proposal, ask agda-mcp's `auto` tool
  *  (issue #205) for a term at the selected obligation, and propose that term
  *  first.  Under Agda 2.8 and the pinned 2.9 the search is Mimer, which
  *  replaced Agsy in Agda 2.7.  It needs no corpus, costs milliseconds a hole, and on
  *  the benchmark solves 17 of the 55 original rows by itself
  *  (reports/auto-floor/), so it is the cheapest closer the loop can have.
  *
  *  The two modes, behind one knob (`--auto`)
  *  -----------------------------------------
  *    closer  the search with Agda's default space: the goal's context,
  *            constructors, record projections, the definition's own where-
  *            functions, and recursive calls;
  *    hints   the same search given the retrieval proposer's accepted
  *            renderings for this goal as hint names: the top-k lemmas after
  *            both exclusion rules and lane resolution (`lemmasFor`), so a
  *            hint set can hold the restated lemma only if retrieval's own
  *            ledger let it through, and that ledger names every exclusion.
  *  `off` leaves the loop exactly as it was: no proposer is wrapped, the
  *  server is started without `--auto`, and the report gains no key.
  *
  *  What the search's term is, and is not
  *  -------------------------------------
  *  A candidate, judged by fill_hole like every other: the lane accepts a
  *  found term without the termination check, so only the batch oracle
  *  decides.  Two things set it apart from other candidates, and both are
  *  stated here:
  *    - it is proposed first, since it is the one candidate Agda itself
  *      built for this goal;
  *    - it skips the type_of peek (`unpeeked`), because Agda has just typed
  *      it at this goal, and the peek's textual match is measured to
  *      misjudge terms whose type is the goal's only up to definitional
  *      equality (`refl` at `lift ∘ lower ≡ 𝑖𝑑 (Lift b A)`, #127), which is
  *      what a search that works up to unfolding returns.  The peek only
  *      ever saves a probe; the probe still runs.  The exemption holds at
  *      the state and obligation the term was found for and nowhere else:
  *      the same text proposed at another goal is an ordinary candidate
  *      there, peeked like any other (a Copilot catch on PR #233, where an
  *      exemption that outlived its proposal let it through).
  *  A multi-token term is parenthesized, the convention every proposer
  *  follows (a hole is an argument position as often as a right-hand side);
  *  a single token is left bare so it deduplicates with the closers.
  *
  *  The ledger
  *  ----------
  *  Per fixture, for report.json: the calls, how each came out (Agda's four
  *  outcomes, plus a reply the server failed), the distinct terms found, the
  *  distinct hint sets sent, and the search's own milliseconds beside the
  *  resets'.  With the retrieval ledger beside it, a reader can check every
  *  hint set against the exclusions.
  *
  *  ============================================================================
  */
package struxdriver.search

import cats.effect.{IO, Ref}
import cats.syntax.all._
import io.circe.Json
import io.circe.syntax._

/** The knob: whether, and how, the loop asks Agda's own proof search. */
sealed trait AutoMode extends Product with Serializable { def tag: String }
object AutoMode {
  case object Off    extends AutoMode { val tag = "off" }
  case object Closer extends AutoMode { val tag = "closer" }
  case object Hints  extends AutoMode { val tag = "hints" }

  def parse(s: String): Either[String, AutoMode] = s match {
    case "off"    => Right(Off)
    case "closer" => Right(Closer)
    case "hints"  => Right(Hints)
    case other    => Left(s"bad --auto: $other (off|closer|hints)")
  }
}

/** What the search did for one fixture: the honesty ledger's twin. */
final case class AutoLedger(
  calls:    Int                 = 0,
  outcomes: Map[String, Int]    = Map.empty, // found | no-solution | out-of-scope | error | failed
  terms:    Vector[String]      = Vector.empty,
  hintSets: Vector[Vector[String]] = Vector.empty,
  searchMs: Long                = 0L,
  resetMs:  Long                = 0L
) {
  /** One call's answer, folded in. */
  def record(hints: Vector[String], answer: Either[String, AutoBody]): AutoLedger = {
    val outcome = answer.fold(_ => "failed", _.outcome)
    copy(
      calls    = calls + 1,
      outcomes = outcomes.updated(outcome, outcomes.getOrElse(outcome, 0) + 1),
      terms    = (terms ++ answer.toOption.flatMap(_.found)).distinct,
      hintSets = if (hints.isEmpty) hintSets else (hintSets :+ hints).distinct,
      searchMs = searchMs + answer.toOption.flatMap(_.searchMs).getOrElse(0L),
      resetMs  = resetMs + answer.toOption.flatMap(_.resetMs).getOrElse(0L)
    )
  }

  def toJson(mode: AutoMode): Json = Json.obj(
    "mode"     -> mode.tag.asJson,
    "calls"    -> calls.asJson,
    "outcomes" -> Json.obj(outcomes.toVector.sortBy(_._1).map { case (k, v) => k -> v.asJson }: _*),
    "terms"    -> terms.asJson,
    "hintSets" -> hintSets.asJson,
    "searchMs" -> searchMs.asJson,
    "resetMs"  -> resetMs.asJson
  )
}

/** The proposer: Agda's own term first, then whatever `inner` proposes.
  * `search` is the oracle's auto call at an obligation with the given hints;
  * `hintsFor` names the hints for a goal (empty in `closer` mode).
  */
final class AutoCloseProposer private (
  inner:    Proposer,
  mode:     AutoMode,
  search:   (Obligation, Vector[String]) => IO[Either[String, AutoBody]],
  hintsFor: GoalView => IO[Vector[String]],
  found:    Ref[IO, Map[(SearchState, Obligation), String]], // the term found for each goal asked
  ledger:   Ref[IO, AutoLedger]
) extends Proposer {

  def stats: IO[AutoLedger] = ledger.get

  override def propose(state: SearchState, target: Obligation, goal: GoalView): IO[Vector[String]] =
    for {
      hints  <- if (mode == AutoMode.Hints) hintsFor(goal) else IO.pure(Vector.empty[String])
      answer <- search(target, hints)
      term    = answer.toOption.flatMap(_.found).map(AutoCloseProposer.shaped)
      _      <- term.traverse_(t => found.update(_.updated((state, target), t)))
      _      <- ledger.update(_.record(hints, answer))
      rest   <- inner.propose(state, target, goal)
    } yield (term.toVector ++ rest).distinct

  override def unpeeked(state: SearchState, target: Obligation, candidate: String): IO[Boolean] =
    found.get.flatMap { fs =>
      if (fs.get((state, target)).contains(candidate)) IO.pure(true)
      else inner.unpeeked(state, target, candidate)
    }
}

object AutoCloseProposer {

  /** The search's bound when a call names none: Agda's own, 1,000 ms of CPU
    * time (`optTimeout` in `Agda.Mimer.Options`).  The loop names none, so
    * this is every search's bound, and the server refuses a search whose
    * bound reaches its --timeout.
    */
  val defaultSearchMs: Int = 1000

  /** A term as a candidate: parenthesized when it is more than one token,
    * the convention of every proposer here, and bare otherwise so that
    * `refl` found by the search and `refl` proposed as a closer are one
    * candidate, probed once.
    */
  def shaped(term: String): String =
    if (term.exists(_.isWhitespace)) s"($term)" else term

  def create(
    inner:    Proposer,
    mode:     AutoMode,
    search:   (Obligation, Vector[String]) => IO[Either[String, AutoBody]],
    hintsFor: GoalView => IO[Vector[String]]
  ): IO[AutoCloseProposer] =
    for {
      found  <- Ref.of[IO, Map[(SearchState, Obligation), String]](Map.empty)
      ledger <- Ref.of[IO, AutoLedger](AutoLedger())
    } yield new AutoCloseProposer(inner, mode, search, hintsFor, found, ledger)
}
