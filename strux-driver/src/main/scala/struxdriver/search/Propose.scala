/** ============================================================================
  *  Propose.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/search/Propose.scala
  *  Package: struxdriver.search
  *
  *  Purpose
  *  -------
  *  The proposal side of the P1 search loop (issue #122): the `Proposer` seam
  *  the loop expands states through — the interface the P2 retrieval and P3
  *  policy proposers will implement (#123/#124) — and its first, deliberately
  *  fixed implementation, plus the `type_of` peek matcher the #122 experiment
  *  measures.
  *
  *  The fixed action space (non-learned but real, per #122)
  *  --------------------------------------------------------
  *  For the obligation the loop selected, in proposal order:
  *    1. The P0 closers `refl` and `tt` — proposed unconditionally; on
  *       fixtures that do not import them the oracle (or the peek, when
  *       enabled) rejects them, and that cost is part of what the peek
  *       experiment measures.
  *    2. The goal context's assumptions, by name, in context order (from
  *       get_goal; the lane path carries {name, type} per entry).
  *    3. Applications of the fixture's imported lemmas: every name the
  *       fixture imports through `using` lists, applied with one fresh `{!!}`
  *       per remaining visible binder via the landed partial-application
  *       arithmetic (Actions.applicationCandidate with zero supplied
  *       arguments) — binder counts read from lane `type_of` answers through
  *       the deliberately small pi splitter (Actions.bindersOfPrinted), and
  *       the whole application parenthesized so the same candidate is the
  *       same term in argument position as on a right-hand side.
  *       Ordered cheap-before-expensive (fewer holes first, then import
  *       order), #112's lesson four applied to proposal order, which matters
  *       because the probe budget can run out mid-expansion.
  *  Duplicates keep their first (cheapest-category) occurrence, so an
  *  imported `refl` does not get probed twice.
  *
  *  The peek (issue #122's measured experiment)
  *  -------------------------------------------
  *  `Peek` turns a candidate into its `_`-meta form (holes become metas) and
  *  judges the lane's inferred type against the goal display.  Verified on
  *  the wire (captures in test/resources/search/): the lane ANSWERS
  *  under-determined metas — `sym _` infers `_y_8 ≡ _x_7`, `refl` infers
  *  `_x_9 ≡ _x_9` — and rejects bad expressions with an in-body error
  *  (NotInScope / CannotApply / UnequalTerms) in milliseconds.  A candidate
  *  is rejected when the lane rejects the expression, or when the inferred
  *  type cannot textually match the goal even with every meta read as a
  *  wildcard (same meta, same text — so `_x_9 ≡ _x_9` refuses `m + n ≡ n + m`
  *  but accepts `n ≡ n`).  Peeks inform probe SELECTION only: they never
  *  enter the script and never decide anything — only fill_hole judges — so
  *  a lane failure keeps the candidate rather than dropping it.
  *
  *  Integration
  *  -----------
  *  Consumed by BeamLoop.scala; pure except for the type_of calls made
  *  through the function the harness wires to Oracle.typeOf.
  *
  *  ============================================================================
  */
package struxdriver.search

import cats.effect.{IO, Ref}
import cats.syntax.all._
import java.util.regex.Pattern

/** What the loop shows a proposer about the obligation it selected: the goal
  * display and local context exactly as get_goal answered them, plus the
  * resolved module name for reporting.
  */
final case class GoalView(goal: String, context: Vector[CtxEntry], module: Option[String])

/** The proposer seam: candidates for ONE obligation of one state, in proposal
  * order.  P1 wires the fixed space below; P2 (#123) plugs retrieval and P3
  * (#124) a policy backend into the same signature.  Proposers only ever see
  * oracle-anchored state and only ever return candidate text — judging is the
  * oracle's alone.
  */
trait Proposer {
  def propose(state: SearchState, target: Obligation, goal: GoalView): IO[Vector[String]]
}

/** Parse the lemma pool off a fixture's source: every name imported through a
  * `using ( … )` list, in file order.  Deliberately line-scoped and small —
  * the M1-5 fixtures import exactly this way (one `open import M using (…)`
  * per line) — and the oracle polices anything a fancier import form would
  * need; a fixture importing without `using` contributes no lemma names.
  */
object Imports {
  private val UsingLine =
    """^\s*open\s+import\s+\S+\s+using\s*\(\s*(.*?)\s*\)\s*$""".r

  def usingNames(source: String): Vector[String] =
    source.linesIterator.collect { case UsingLine(names) =>
      names.split(";").toVector.map(_.trim).filter(_.nonEmpty)
    }.toVector.flatten.distinct
}

/** The fixed action space.  `lemmaType` is the lane `type_of` lookup the
  * harness wires to Oracle.typeOf (phase "type_of"): Right(Some(printed)) is
  * an inferred type, Right(None) a lane rejection of the name (it stays out
  * of the space — a name the lane cannot type cannot be applied honestly),
  * and Left a lane failure (same consequence, but logged by the caller).
  * Types are cached per fixture: an imported lemma's type never changes
  * across the states of one search.
  */
final class FixedProposer private (
  lemmaPool: Vector[String],
  lemmaType: String => IO[Either[String, Option[String]]],
  cache:     Ref[IO, Map[String, Option[Vector[Binder]]]]
) extends Proposer {

  private val closers = Vector("refl", "tt")

  private def bindersOf(name: String): IO[Option[Vector[Binder]]] =
    cache.get.flatMap(_.get(name) match {
      case Some(hit) => IO.pure(hit)
      case None =>
        lemmaType(name)
          .map(_.toOption.flatten.map(Actions.bindersOfPrinted))
          .flatTap(b => cache.update(_ + (name -> b)))
    })

  override def propose(state: SearchState, target: Obligation, goal: GoalView): IO[Vector[String]] =
    lemmaPool.traverse(n => bindersOf(n).map(_.map(n -> _))).map { typed =>
      val assumptions = goal.context.map(_.name)
      val apps = typed.zipWithIndex
        .collect { case (Some((name, binders)), i) => (name, binders, i) }
        .map { case (name, binders, i) =>
          val cand    = Actions.applicationCandidate(name, binders, Vector.empty)
          val visible = binders.count(_.visibility == Visibility.Visible)
          // Parenthesize multi-token candidates: a hole is an ARGUMENT
          // position as often as a right-hand side, and a verbatim splice of
          // `sym {!!}` into `s≤s {!!}`'s sub-hole reads as `s≤s sym {!!}` —
          // a different term.  Measured on the first #122 sweep: every
          // depth-1 lemma application died exactly this way.  Parens are
          // inert on a right-hand side, so every application is shaped
          // position-independently.
          (if (visible > 0) s"($cand)" else cand, visible, i)
        }
        .sortBy { case (_, visible, i) => (visible, i) }
        .map(_._1)
      (closers ++ assumptions ++ apps).distinct
    }
}

object FixedProposer {
  def create(fixtureSource: String, lemmaType: String => IO[Either[String, Option[String]]]): IO[FixedProposer] =
    Ref.of[IO, Map[String, Option[Vector[Binder]]]](Map.empty)
      .map(new FixedProposer(Imports.usingNames(fixtureSource), lemmaType, _))
}

/** The type_of peek: candidate → `_`-meta form, and the conservative
  * compatibility judgement between the lane's inferred type and the goal
  * display.  Both strings come from the same lane load and the same
  * Normalised printer, which is what makes textual comparison meaningful;
  * where rendering still diverges the worst case is a skipped probe, and the
  * sweep measures exactly that.
  */
object Peek {

  /** The `_`-meta form of a candidate: each fresh hole becomes a meta Agda
    * must solve, so the lane can type the term without any hole machinery.
    */
  def metaForm(candidate: String): String = candidate.replace("{!!}", "_")

  /** A meta token as the lane prints one — `_6`, `_x_9`, `_A_10`, `_n_6` —
    * verified on the wire (issue #122 probes).
    */
  private val Meta = Pattern.compile("""_[^\s(){}⦃⦄]*_[0-9]+|_[0-9]+""")

  /** Can the inferred type describe the goal?  Every meta is a wildcard, the
    * SAME meta is the SAME wildcard (a backreference — `_x_9 ≡ _x_9` cannot
    * match `m + n ≡ n + m`), literals must match exactly, whitespace
    * normalized on both sides.  Metas are wildcarded on the inferred side
    * only; the goal display is taken literally.
    */
  def compatible(goalDisplayed: String, inferred: String): Boolean = {
    val goal = normalize(goalDisplayed)
    val inf  = normalize(inferred)
    val sb   = new StringBuilder("^")
    val seen = scala.collection.mutable.Map.empty[String, String]
    val m    = Meta.matcher(inf)
    var last = 0
    while (m.find()) {
      sb.append(Pattern.quote(expandNumerals(inf.substring(last, m.start()))))
      val meta = m.group()
      seen.get(meta) match {
        case Some(g) => sb.append("\\k<").append(g).append(">")
        case None =>
          val g = s"m${seen.size}"
          seen(meta) = g
          sb.append("(?<").append(g).append(">.*)")
      }
      last = m.end()
    }
    sb.append(Pattern.quote(expandNumerals(inf.substring(last)))).append("$")
    Pattern.compile(sb.toString, Pattern.DOTALL).matcher(expandNumerals(goal)).matches()
  }

  private def normalize(s: String): String = s.replaceAll("\\s+", " ").trim

  /** Agda folds closed ℕ terms to numerals in displays (`suc 0` prints as
    * `1`) but a meta blocks the folding (`suc _m_5` prints as written) —
    * measured on the wire: the 0<1+n goal displays `1 ≤ suc n` while `s≤s _`
    * infers `suc _m_5 ≤ suc _n_6`.  Matching text across that divergence
    * needs one canonical form, so both sides expand numeral TOKENS to suc
    * towers (`1` → `suc 0`, `2` → `suc (suc 0)`) before comparison.  Metas
    * are already wildcards by the time literals are expanded, so their
    * trailing digits are untouched.
    */
  private def expandNumerals(s: String): String = {
    val num = Pattern.compile("""\b([0-9]+)\b""").matcher(s)
    val out = new StringBuilder
    var last = 0
    while (num.find()) {
      out.append(s.substring(last, num.start()))
      out.append(sucTower(num.group(1).toLong))
      last = num.end()
    }
    out.append(s.substring(last))
    out.result()
  }

  private def sucTower(n: Long): String =
    if (n <= 0) "0"
    else if (n == 1) "suc 0"
    else s"suc (${sucTower(n - 1)})"

  /** The peek verdict for one candidate, from the lane's answer.  `Keep`
    * means "probe it"; a peek can only ever skip a probe, never fabricate a
    * result, and any failure to peek keeps the candidate.
    */
  sealed trait Verdict extends Product with Serializable
  object Verdict {
    case object Keep                          extends Verdict
    final case class Reject(reason: String)   extends Verdict
  }

  def judge(goalDisplayed: String, answer: Either[String, TypeOfBody]): Verdict =
    answer match {
      case Left(_)                                => Verdict.Keep // lane failure: no information, no veto
      case Right(TypeOfBody(Some(t), None, _))    =>
        if (compatible(goalDisplayed, t)) Verdict.Keep
        else Verdict.Reject(s"inferred type does not match goal: $t")
      case Right(TypeOfBody(None, Some(err), _))  => Verdict.Reject(err.code)
      case Right(_)                               => Verdict.Keep // unreachable by decoder contract
    }
}
