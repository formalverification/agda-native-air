/** ============================================================================
  *  Model.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/search/Model.scala
  *  Package: struxdriver.search
  *
  *  Purpose
  *  -------
  *  The proof-search state model for issue #113 (P0): an obligation set with
  *  CONJUNCTIVE semantics, a proof script that records only committed actions,
  *  and the cache key types the #112 post-mortem calls for.
  *
  *  Design notes (the #112 lessons, as types)
  *  -----------------------------------------
  *  - The state carries a SET of obligations and "all discharged" is defined as
  *    emptiness of the whole set.  There is no per-goal success anywhere in the
  *    model, so the disjunctive defect of the retired search.py (success as
  *    soon as ANY one subgoal closed) is unrepresentable rather than avoided.
  *  - `SolvedClaim` is the only way to say "solved", and its constructor is
  *    private: the claim exists only for a state with no obligations left AND a
  *    final batch verdict (`check_file` success, i.e. Agda exit code 0) on the
  *    committed content.  An empty obligation set alone is merely a candidate.
  *  - Probes are not moves.  `ProbeOutcome` (what fill_hole answered about a
  *    candidate; the server restores the file, so every fill_hole is a peek)
  *    and `Move` (an action committed to the working copy) are distinct types,
  *    and the script has type Vector[Move].  A ProbeOutcome becomes a Move only
  *    through `SearchState.commit`, never implicitly.
  *  - The obligation set is the oracle's, not ours: `commit` adopts the
  *    re-anchored `holes` list carried by the fill_hole response (issue #79),
  *    so client-side hole arithmetic can never drift from Agda's.
  *  - Two caches, two key types: `OracleKey` memoises oracle calls (each one an
  *    Agda subprocess — the cost centre) and `StateKey` identifies states for
  *    the P1 frontier dedup.  Distinct case classes so P1 cannot conflate them.
  *
  *  Integration
  *  -----------
  *  Consumed by Oracle.scala (probing/committing against agda-mcp) and
  *  SingleStepHarness.scala (the P0 entry point).  Pure values only; all
  *  effects live in McpClient/Oracle.
  *
  *  ============================================================================
  */
package struxdriver.search

/** One open proof obligation: a hole in the working copy, at the 1-based
  * position the oracle reports, with the goal type it printed (`"?"` when the
  * response did not carry one).
  */
final case class Obligation(line: Int, col: Int, goal: String)

/** A committed action: this candidate was spliced into the working copy at the
  * hole that sat at (line, col).  Only `SearchState.commit` creates these; the
  * proof script is a Vector[Move] and can therefore never contain a probe.
  */
final case class Move private[search] (line: Int, col: Int, candidate: String)

/** How the oracle judged a probed candidate.  Mirrors fill_hole's own status
  * vocabulary (see agda-mcp/README.md): `Ok` tolerates only the interaction
  * metas of holes still open — including new sub-holes inside the candidate —
  * so Ok means "successful refinement", never "proved".
  */
sealed trait ProbeStatus extends Product with Serializable { def wire: String }
object ProbeStatus {
  case object Ok        extends ProbeStatus { val wire = "ok" }
  case object TypeError extends ProbeStatus { val wire = "type_error" }
  case object Timeout   extends ProbeStatus { val wire = "timeout" }
  case object Crash     extends ProbeStatus { val wire = "crash" }

  def parse(s: String): ProbeStatus = s match {
    case "ok"         => Ok
    case "type_error" => TypeError
    case "timeout"    => Timeout
    case _            => Crash
  }
}

/** What probing one candidate at one obligation revealed — a peek, never a
  * move.  `holesAfter` is the oracle's re-anchored hole list describing the
  * file as this candidate would leave it (issue #79); for a non-Ok status it
  * describes the unchanged file and is not used.
  */
final case class ProbeOutcome(
  candidate:  String,
  status:     ProbeStatus,
  holesAfter: Vector[Obligation],
  message:    Option[String]
) {
  /** Would committing this candidate discharge every obligation?  (Still not a
    * verdict: `SolvedClaim` additionally demands the final batch check.)
    */
  def closesAll: Boolean = status == ProbeStatus.Ok && holesAfter.isEmpty
}

/** Cache key for ORACLE CALLS: the same (file content, hole, candidate) triple
  * always gets the same answer, and each miss costs an Agda subprocess.  Keyed
  * on a content fingerprint rather than a path so a committed edit invalidates
  * every entry for the previous content by construction.
  */
final case class OracleKey(contentFingerprint: String, line: Int, col: Int, candidate: String)

/** Cache key for ENQUEUED STATES: the P1 frontier dedup.  Deliberately a
  * different type from OracleKey — #112's lesson is that conflating the two
  * either re-runs Agda or wrongly prunes the frontier.  The content
  * fingerprint alone identifies a state (the obligations are a function of the
  * content); P1 decides whether the dedup also wants the script.
  */
final case class StateKey(contentFingerprint: String)

/** The search state: the working copy's content, the obligations still open in
  * it (ALL of which must be discharged — conjunctive), and the proof script of
  * committed actions only.
  */
final case class SearchState(
  content:     String,
  obligations: Vector[Obligation],
  script:      Vector[Move]
) {
  /** Every obligation discharged?  This is emptiness of the whole set — the
    * conjunctive gate — and it makes the state a CANDIDATE solution only.
    */
  def allDischarged: Boolean = obligations.isEmpty

  def key: StateKey = StateKey(Fingerprint.of(content))

  /** Commit a probed candidate at one of THIS state's obligations: splice it
    * into the content and adopt the oracle's re-anchored hole list as the new
    * obligation set.  The only constructor of Move.  Refuses a probe that was
    * not Ok, a target this state does not carry, or content whose hole token
    * is not where the target says (drift between state and disk).
    */
  def commit(target: Obligation, probe: ProbeOutcome): Either[String, SearchState] =
    if (probe.status != ProbeStatus.Ok)
      Left(s"refusing to commit a ${probe.status.wire} probe: ${probe.candidate}")
    else if (!obligations.contains(target))
      Left(s"target obligation at (${target.line},${target.col}) is not open in this state")
    else
      Splice.holeAt(content, target.line, target.col, probe.candidate).map { spliced =>
        SearchState(
          content     = spliced,
          obligations = probe.holesAfter,
          script      = script :+ Move(target.line, target.col, probe.candidate)
        )
      }
}

object SearchState {
  /** The initial state for a working copy: content as read, obligations as the
    * oracle's check_file reported them, empty script.
    */
  def initial(content: String, obligations: Vector[Obligation]): SearchState =
    SearchState(content, obligations, Vector.empty)
}

/** The one way to claim a proof is done.  Constructible only from a state with
  * no obligations left AND a final batch check_file whose `success` was true —
  * the exit-code-derived verdict (agda-mcp README, issues #72/#69), mirroring
  * eval_fixtures.py's `_final_strict_check`.  A lemma with two obligations and
  * one discharged cannot reach this type; that is the #112 regression, pinned
  * in ModelSpec.
  */
final case class SolvedClaim private (state: SearchState, finalExitCode: Int)

object SolvedClaim {
  def fromFinalCheck(state: SearchState, checkSuccess: Boolean, exitCode: Int): Either[String, SolvedClaim] =
    if (!state.allDischarged)
      Left(s"${state.obligations.size} obligation(s) remain: not solved")
    else if (!checkSuccess)
      Left(s"final batch check failed (exit $exitCode): not solved")
    else
      Right(SolvedClaim(state, exitCode))
}

/** Rank probe outcomes, lowest first — #112's "order by remaining obligations"
  * carried onto the new substrate: closers before refinements, refinements
  * with fewer remaining obligations before those with more, judged failures
  * after every success, timeouts (never judged) before type errors, crashes
  * last.  The candidate string is the final tie-break so ranking is total and
  * deterministic.
  */
object Rank {
  def of(o: ProbeOutcome): (Int, Int, String) = {
    val cls = o.status match {
      case ProbeStatus.Ok if o.holesAfter.isEmpty => 0
      case ProbeStatus.Ok                         => 1
      case ProbeStatus.Timeout                    => 2
      case ProbeStatus.TypeError                  => 3
      case ProbeStatus.Crash                      => 4
    }
    (cls, o.holesAfter.size, o.candidate)
  }

  def order(outcomes: Vector[ProbeOutcome]): Vector[ProbeOutcome] =
    outcomes.sortBy(of)
}

/** SHA-1 content fingerprints for the cache keys. */
object Fingerprint {
  def of(content: String): String = {
    val md = java.security.MessageDigest.getInstance("SHA-1")
    md.digest(content.getBytes(java.nio.charset.StandardCharsets.UTF_8))
      .map(b => f"$b%02x").mkString
  }
}

/** Client-side splicing for COMMITS.  Probes never need this (fill_hole edits
  * and restores server-side); a commit rewrites the working copy, and P0's
  * action space only ever fills `{!!}` holes, so the splice demands exactly
  * that token at the target position and refuses anything else rather than
  * guess at spans.
  */
object Splice {
  private val HoleToken = "{!!}"

  def holeAt(content: String, line: Int, col: Int, candidate: String): Either[String, String] = {
    // Split keeping line structure intact; -1 keeps trailing empty lines.
    val lines = content.split("\n", -1).toVector
    if (line < 1 || line > lines.size)
      Left(s"splice: line $line out of range (file has ${lines.size} lines)")
    else {
      val l = lines(line - 1)
      if (col < 1 || col - 1 + HoleToken.length > l.length || !l.startsWith(HoleToken, col - 1))
        Left(s"splice: no $HoleToken at line $line, column $col")
      else {
        val patched = l.substring(0, col - 1) + candidate + l.substring(col - 1 + HoleToken.length)
        Right(lines.updated(line - 1, patched).mkString("\n"))
      }
    }
  }
}
