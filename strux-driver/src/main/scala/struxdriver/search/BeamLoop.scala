/** ============================================================================
  *  BeamLoop.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/search/BeamLoop.scala
  *  Package: struxdriver.search
  *
  *  Purpose
  *  -------
  *  The P1 search loop of issue #113 (sub-issue #122): level-synchronous beam
  *  search over the P0 `SearchState` model, expanding through the `Proposer`
  *  seam and judging every candidate with the agda-mcp oracle.  P0 landed the
  *  state model and the single step; this file is the loop, its budgets, and
  *  its termination statuses — proposals stay deliberately fixed (P2/#123
  *  brings retrieval, P3/#124 a policy).
  *
  *  The loop, per level
  *  -------------------
  *  Each frontier state is expanded at its FIRST open obligation — a fixed
  *  selection policy, stated and tested as a deliberate simplification:
  *  selection order affects which proofs are found under budget, never
  *  soundness, because the obligation set is conjunctive and every commit
  *  re-anchors from the oracle's own hole list.  Expansion writes the state's
  *  content to the working file, reads the goal (get_goal), asks the proposer
  *  for candidates, optionally peeks each (type_of; see Propose.scala), and
  *  probes the survivors (fill_hole).  Ok probes commit to child states;
  *  children are deduped against every state ever enqueued (the policy is a
  *  tunable — see `DedupPolicy`), ranked by the landed `Rank` on their
  *  creating probe, and the best `beamWidth` become the next level.  A probe
  *  that closes every obligation is claimed immediately through
  *  `SolvedClaim`'s final batch gate — search work after a proof would be
  *  spent budget for nothing.
  *
  *  Termination, per fixture (distinct reported statuses)
  *  -----------------------------------------------------
  *    solved          — the final strict check passed (SolvedClaim granted);
  *    exhausted       — the frontier emptied, or the depth bound cut a live
  *                      frontier (stats.depthCapped says which);
  *    budget_exceeded — the probe budget ran out with work remaining.
  *
  *  The budget counts fill_hole probes that MISS the OracleKey memo — the
  *  ~2.6 s batch coin the P0 measurement on #113 identified as effectively
  *  the entire cost.  Memo hits are free (no Agda runs).  The per-fixture
  *  baseline check_file, the final strict checks (bounded by closing probes,
  *  themselves budgeted), and the millisecond interaction-lane knowledge
  *  calls (get_goal, type_of, peeks; bounded by beamWidth x maxDepth
  *  expansions) are reported in the ledger but not gated: gating the
  *  verification call would forfeit an already-found proof over accounting.
  *
  *  Anomalies
  *  ---------
  *  A commit the state refuses (client/disk drift) and a closing probe whose
  *  final batch check disagrees (fill_hole ok with no holes left is the same
  *  judgement check_file makes, so disagreement is infrastructure drift, not
  *  a search outcome) raise out of the loop; the harness records them per
  *  fixture and turns the run red without aborting the sweep, P0's
  *  anomaly-red-exit discipline unchanged.
  *
  *  Integration
  *  -----------
  *  Pure control flow over Oracle.scala (effects) and Propose.scala
  *  (candidates); driven per fixture by LoopHarness.scala; exercised against
  *  a fake ToolCaller in BeamLoopSpec and against the live server in
  *  LoopIntegrationSpec.
  *
  *  ============================================================================
  */
package struxdriver.search

import cats.effect.IO
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path}

/** The frontier dedup policy — the #122 decision taken by measurement.
  * `ScriptInclusive` keys on the landed `StateKey` (content fingerprint plus
  * committed script): conservative, never wrongly prunes two live states.
  * `ContentOnly` keys on the fingerprint alone: two histories reaching one
  * content share every future (the same obligations, the same probes — and
  * the same memo entries), so keeping both spends knowledge calls and beam
  * slots on a proven duplicate.  The adopted default is pinned in
  * BeamLoopSpec beside the measurement that chose it.
  */
sealed trait DedupPolicy extends Product with Serializable {
  def tag: String
  def keyOf(s: SearchState): String
}
object DedupPolicy {
  case object ScriptInclusive extends DedupPolicy {
    val tag = "script"
    def keyOf(s: SearchState): String = {
      val k = s.key
      k.contentFingerprint + "|" +
        k.script.map(m => s"${m.line}:${m.col}:${m.candidate}").mkString(" ")
    }
  }
  case object ContentOnly extends DedupPolicy {
    val tag = "content"
    def keyOf(s: SearchState): String = s.key.contentFingerprint
  }

  def parse(s: String): Either[String, DedupPolicy] = s match {
    case "script"  => Right(ScriptInclusive)
    case "content" => Right(ContentOnly)
    case other     => Left(s"unknown dedup policy: $other (script|content)")
  }
}

/** The loop's tunables, with the #122 stated defaults. */
final case class LoopConfig(
  beamWidth:   Int,
  maxDepth:    Int,
  probeBudget: Int,
  dedup:       DedupPolicy,
  peek:        Boolean
)
object LoopConfig {
  val default: LoopConfig =
    LoopConfig(beamWidth = 4, maxDepth = 6, probeBudget = 60,
               dedup = DedupPolicy.ScriptInclusive, peek = false)
}

/** How one fixture's search ended — each a distinct reported status. */
sealed trait SearchStatus extends Product with Serializable { def tag: String }
object SearchStatus {
  case object Solved         extends SearchStatus { val tag = "solved" }
  case object Exhausted      extends SearchStatus { val tag = "exhausted" }
  case object BudgetExceeded extends SearchStatus { val tag = "budget_exceeded" }
}

/** The loop's own counters, for the report and the experiments.  `probes`
  * counts memo MISSES (the budgeted coin); `memoHits` the free replays;
  * `peeks`/`peekRejects` the experiment's numerator and its savings;
  * `dedupSkips` children refused by the dedup policy; `depthReached` the
  * deepest level expanded; `depthCapped` whether exhaustion was the depth
  * bound cutting a live frontier.
  */
final case class LoopStats(
  expansions:   Int     = 0,
  probes:       Int     = 0,
  memoHits:     Int     = 0,
  peeks:        Int     = 0,
  peekRejects:  Int     = 0,
  dedupSkips:   Int     = 0,
  finalChecks:  Int     = 0,
  depthReached: Int     = 0,
  depthCapped:  Boolean = false
)

/** One probe as the harness sees it (for results.jsonl rows and logs):
  * `depth` is the expanded state's script length — the eval schema's
  * `holeIndex`, the position in the solving sequence — and `rank` the 1-based
  * position in this expansion's proposal list.
  */
final case class ProbeEvent(
  depth:     Int,
  target:    Obligation,
  rank:      Int,
  candidate: String,
  answer:    OracleAnswer[ProbeOutcome],
  goal:      GoalView
)

/** What one fixture's search concluded.  `solved` carries the unforgeable
  * claim (state and final exit code inside); `rootGoal` the root expansion's
  * goal view for reporting.
  */
final case class FixtureSearchResult(
  status:   SearchStatus,
  solved:   Option[SolvedClaim],
  rootGoal: Option[GoalView],
  stats:    LoopStats
)

object BeamLoop {

  /** Harness callbacks: one per probe (row writing, raw-reply logging). */
  final case class Hooks(onProbe: ProbeEvent => IO[Unit])
  object Hooks { val none: Hooks = Hooks(_ => IO.unit) }

  private final case class St(
    visited:  Set[String],
    stats:    LoopStats,
    rootGoal: Option[GoalView]
  )

  private sealed trait CandsOutcome
  private final case class SolvedNow(claim: SolvedClaim)                        extends CandsOutcome
  private case object BudgetHit                                                 extends CandsOutcome
  private final case class Done(children: Vector[(SearchState, ProbeOutcome)])  extends CandsOutcome

  /** Run the beam search for one fixture.  `mkCtx` stamps the ledger rows
    * (fixture id and phase); `workFile` is the fixture's one working copy,
    * rewritten to each expanded state's content so oracle and state can
    * never drift apart.
    */
  def run(
    oracle:   Oracle,
    proposer: Proposer,
    cfg:      LoopConfig,
    mkCtx:    (String, Option[Int]) => CallCtx,
    workFile: Path,
    s0:       SearchState,
    hooks:    Hooks
  ): IO[FixtureSearchResult] = {

    def write(content: String): IO[Unit] =
      IO.blocking { Files.write(workFile, content.getBytes(StandardCharsets.UTF_8)); () }

    /** Try to claim a child that discharged everything: write, final check,
      * gate through SolvedClaim.  Disagreement between the closing probe and
      * the batch verdict is drift, raised as an anomaly.
      */
    def claim(child: SearchState): IO[SolvedClaim] =
      for {
        _   <- write(child.content)
        fin <- oracle.checkFile(mkCtx("final_check", None), workFile)
        c   <- IO.fromEither(
                 SolvedClaim.fromFinalCheck(child, fin.body.success, fin.body.exitCode.getOrElse(-1))
                   .left.map(reason => new RuntimeException(
                     s"closing probe and final check disagree (timedOut=${fin.body.timedOut}): $reason")))
      } yield c

    def probeCands(
      state:  SearchState,
      target: Obligation,
      view:   GoalView,
      fp:     String,
      cands:  Vector[(String, Int)],
      st:     St,
      acc:    Vector[(SearchState, ProbeOutcome)]
    ): IO[(St, CandsOutcome)] =
      cands match {
        case (cand, rank) +: rest =>
          val peeked: IO[(St, Peek.Verdict)] =
            if (!cfg.peek) IO.pure((st, Peek.Verdict.Keep))
            else
              oracle.typeOf(mkCtx("peek", Some(rank)), workFile, Peek.metaForm(cand),
                            Some((target.line, target.col)))
                .map(ans => Peek.judge(view.goal, ans.body))
                .map {
                  case Peek.Verdict.Keep      =>
                    (st.copy(stats = st.stats.copy(peeks = st.stats.peeks + 1)), Peek.Verdict.Keep: Peek.Verdict)
                  case r: Peek.Verdict.Reject =>
                    (st.copy(stats = st.stats.copy(
                      peeks = st.stats.peeks + 1, peekRejects = st.stats.peekRejects + 1)), r: Peek.Verdict)
                }
          peeked.flatMap {
            case (st1, Peek.Verdict.Reject(_)) =>
              probeCands(state, target, view, fp, rest, st1, acc)
            case (st1, _) =>
              if (st1.stats.probes >= cfg.probeBudget) IO.pure((st1, BudgetHit: CandsOutcome))
              else
                for {
                  ans <- oracle.probe(mkCtx("fill_hole", Some(rank)), workFile, fp, target, cand)
                  st2  = if (ans.cached) st1.copy(stats = st1.stats.copy(memoHits = st1.stats.memoHits + 1))
                         else st1.copy(stats = st1.stats.copy(probes = st1.stats.probes + 1))
                  _   <- hooks.onProbe(ProbeEvent(state.script.size, target, rank, cand, ans, view))
                  out <- if (ans.body.status != ProbeStatus.Ok)
                           probeCands(state, target, view, fp, rest, st2, acc)
                         else
                           IO.fromEither(state.commit(target, ans.body)
                               .left.map(e => new RuntimeException(s"commit refused mid-search: $e")))
                             .flatMap { child =>
                               if (child.allDischarged)
                                 claim(child).map(c => (st2.copy(stats =
                                   st2.stats.copy(finalChecks = st2.stats.finalChecks + 1)),
                                   SolvedNow(c): CandsOutcome))
                               else
                                 probeCands(state, target, view, fp, rest, st2, acc :+ (child -> ans.body))
                             }
                } yield out
          }
        case _ => IO.pure((st, Done(acc)))
      }

    def expand(state: SearchState, st: St): IO[(St, CandsOutcome)] =
      for {
        _     <- write(state.content)
        target = state.obligations.head // never empty: discharged states are claimed, not enqueued
        gAns  <- oracle.getGoal(mkCtx("get_goal", None), workFile, target)
        view   = GoalView(gAns.body.goal, gAns.body.context, gAns.body.module)
        t0    <- IO.monotonic
        cands <- proposer.propose(state, target, view)
        t1    <- IO.monotonic
        _     <- oracle.recordProposal(mkCtx("proposal", None), (t1 - t0).toNanos)
        st1    = st.copy(
                   stats    = st.stats.copy(expansions = st.stats.expansions + 1),
                   rootGoal = st.rootGoal.orElse(Some(view)))
        out   <- probeCands(state, target, view, Fingerprint.of(state.content),
                            cands.zipWithIndex.map { case (c, i) => (c, i + 1) }, st1, Vector.empty)
      } yield out

    def expandLevel(
      frontier: Vector[SearchState],
      st:       St,
      acc:      Vector[(SearchState, ProbeOutcome)]
    ): IO[(St, CandsOutcome)] =
      frontier match {
        case state +: rest =>
          expand(state, st).flatMap {
            case (st1, Done(children)) => expandLevel(rest, st1, acc ++ children)
            case (st1, other)          => IO.pure((st1, other)) // solved or budget: stop the level
          }
        case _ => IO.pure((st, Done(acc)))
      }

    def level(frontier: Vector[SearchState], depth: Int, st: St): IO[FixtureSearchResult] =
      if (frontier.isEmpty)
        IO.pure(FixtureSearchResult(SearchStatus.Exhausted, None, st.rootGoal, st.stats))
      else if (depth >= cfg.maxDepth)
        IO.pure(FixtureSearchResult(SearchStatus.Exhausted, None, st.rootGoal,
          st.stats.copy(depthCapped = true)))
      else {
        val st1 = st.copy(stats = st.stats.copy(depthReached = depth))
        expandLevel(frontier, st1, Vector.empty).flatMap {
          case (st2, SolvedNow(c)) =>
            IO.pure(FixtureSearchResult(SearchStatus.Solved, Some(c), st2.rootGoal, st2.stats))
          case (st2, BudgetHit) =>
            IO.pure(FixtureSearchResult(SearchStatus.BudgetExceeded, None, st2.rootGoal, st2.stats))
          case (st2, Done(children)) =>
            // Dedup against everything ever enqueued, then rank and cut to the beam.
            val (st3, kept) = children.foldLeft((st2, Vector.empty[(SearchState, ProbeOutcome)])) {
              case ((s, keep), (child, probe)) =>
                val key = cfg.dedup.keyOf(child)
                if (s.visited(key))
                  (s.copy(stats = s.stats.copy(dedupSkips = s.stats.dedupSkips + 1)), keep)
                else (s.copy(visited = s.visited + key), keep :+ (child -> probe))
            }
            val next = kept.sortBy { case (_, probe) => Rank.of(probe) }
                           .take(cfg.beamWidth).map(_._1)
            level(next, depth + 1, st3)
        }
      }

    level(Vector(s0), 0, St(Set(cfg.dedup.keyOf(s0)), LoopStats(), None))
  }
}
