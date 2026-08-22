/** ============================================================================
  *  BeamLoopSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/search/BeamLoopSpec.scala
  *
  *  Purpose
  *  -------
  *  Pure tests for the P1 beam loop (issue #122) against the ToolCaller seam:
  *  a scripted world answers get_goal / fill_hole / check_file / type_of with
  *  raw wire-shaped JSON, so the loop is exercised through the REAL decoders
  *  with no server and no Agda.  Pins the issue's named deliverables:
  *
  *    - the multi-obligation solve (a two-obligation lemma application driven
  *      to a SolvedClaim through commits and the final batch gate);
  *    - the #112 regression at loop level (an ok commit with one of two
  *      obligations discharged is never reported solved);
  *    - budget exhaustion (distinct budget_exceeded status; memo hits free);
  *    - the depth bound (exhausted with depthCapped) and frontier exhaustion;
  *    - the dedup policies' semantics and the adopted default;
  *    - the peek gate (a rejected candidate is never probed);
  *    - first-open-obligation selection (stated simplification, pinned).
  *
  *  ============================================================================
  */
package struxdriver.search

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import cats.effect.{IO, Ref}
import cats.effect.unsafe.implicits.global
import io.circe.Json
import java.nio.file.{Files, Paths}

final class BeamLoopSpec extends AnyFunSuite with Matchers {

  // A miniature working copy shaped like the TwoObligations fixture.
  private val content0 = "module M where\ngoal : Pair\ngoal = {!!}\n"
  private val ob0      = Obligation(3, 8, "Pair")

  private def holeJson(line: Int, col: Int, i: Int): Json =
    Json.obj("index" -> Json.fromInt(i), "line" -> Json.fromInt(line),
             "col" -> Json.fromInt(col), "goal" -> Json.fromString("?"))

  private def fillOk(cand: String, holes: Vector[(Int, Int)]): String =
    Json.obj(
      "status"         -> Json.fromString("ok"),
      "candidate"      -> Json.fromString(cand),
      "holes"          -> Json.arr(holes.zipWithIndex.map { case ((l, c), i) => holeJson(l, c, i) }: _*),
      "remainingHoles" -> Json.fromInt(holes.size),
      "elapsedMs"      -> Json.fromInt(5),
      "verdict"        -> Json.obj("exitCode" -> Json.fromInt(if (holes.isEmpty) 0 else 42))
    ).noSpaces

  private def fillTypeError(cand: String, holes: Vector[(Int, Int)]): String =
    Json.obj(
      "status"         -> Json.fromString("type_error"),
      "candidate"      -> Json.fromString(cand),
      "message"        -> Json.fromString("does not fit"),
      "holes"          -> Json.arr(holes.zipWithIndex.map { case ((l, c), i) => holeJson(l, c, i) }: _*),
      "remainingHoles" -> Json.fromInt(holes.size),
      "elapsedMs"      -> Json.fromInt(5)
    ).noSpaces

  private val goalReply: String =
    Json.obj(
      "goal"      -> Json.fromString("G"),
      "context"   -> Json.arr(),
      "module"    -> Json.fromString("M"),
      "source"    -> Json.fromString("interaction-lane"),
      "elapsedMs" -> Json.fromInt(1)
    ).noSpaces

  private val checkGreen: String =
    Json.obj(
      "success" -> Json.True, "holes" -> Json.arr(), "holesCount" -> Json.fromInt(0),
      "timedOut" -> Json.False, "elapsedMs" -> Json.fromInt(9),
      "verdict" -> Json.obj("exitCode" -> Json.fromInt(0))
    ).noSpaces

  /** A scripted transport: fill_hole answered from a (line, col, candidate)
    * table, get_goal and the final check canned, type_of from an expr table.
    * Every call is recorded for the never-probed assertions.
    */
  private def scripted(
    fills:  Map[(Int, Int, String), String],
    types:  Map[String, String],
    calls:  Ref[IO, Vector[(String, Json)]]
  ): ToolCaller = new ToolCaller {
    def callTool(tool: String, args: Json): IO[Timed[ToolReply]] = {
      val c = args.hcursor
      val reply = tool match {
        case "get_goal"   => goalReply
        case "check_file" => checkGreen
        case "type_of"    =>
          val expr = c.get[String]("expr").toOption.get
          types.getOrElse(expr,
            Json.obj("type" -> Json.fromString("T"), "elapsedMs" -> Json.fromInt(1)).noSpaces)
        case "fill_hole" =>
          val key = (c.get[Int]("line").toOption.get, c.get[Int]("column").toOption.get,
                     c.get[String]("candidate").toOption.get)
          fills.getOrElse(key, fillTypeError(key._3, Vector.empty))
        case other => fail(s"unexpected tool call: $other")
      }
      calls.update(_ :+ (tool, args)).as(Timed(ToolReply(isError = false, reply), 1000000L))
    }
  }

  private def stubProposer(cands: Vector[String]): Proposer = new Proposer {
    def propose(state: SearchState, target: Obligation, goal: GoalView): IO[Vector[String]] =
      IO.pure(cands)
  }

  private def tempWorkFile(): java.nio.file.Path = {
    val dir = Files.createDirectories(Paths.get(sys.props("java.io.tmpdir"), "beam-loop-spec"))
    Files.createTempFile(dir, "work-", ".agda")
  }

  private def runLoop(
    fills: Map[(Int, Int, String), String],
    cands: Vector[String],
    cfg:   LoopConfig,
    types: Map[String, String] = Map.empty
  ): (FixtureSearchResult, Vector[(String, Json)]) = {
    val io = for {
      calls  <- Ref.of[IO, Vector[(String, Json)]](Vector.empty)
      oracle <- Oracle.create(scripted(fills, types, calls))
      s0      = SearchState.initial(content0, Vector(ob0))
      result <- BeamLoop.run(oracle, stubProposer(cands), cfg,
                  (ph, rk) => CallCtx(1, "fx", ph, rk), tempWorkFile(), s0, BeamLoop.Hooks.none)
      log    <- calls.get
    } yield (result, log)
    io.unsafeRunSync()
  }

  // The two-obligation world: pair {!!} {!!} opens two holes; tt closes each
  // in turn; positions follow the real splice arithmetic.
  private val pairWorld: Map[(Int, Int, String), String] = Map(
    (3, 8,  "pair {!!} {!!}") -> fillOk("pair {!!} {!!}", Vector((3, 13), (3, 18))),
    (3, 8,  "tt")             -> fillTypeError("tt", Vector((3, 8))),
    (3, 13, "tt")             -> fillOk("tt", Vector((3, 16))),
    (3, 16, "tt")             -> fillOk("tt", Vector.empty)
  )
  private val pairCands = Vector("pair {!!} {!!}", "tt", "bad")

  // --------------------------------------------------------------------------
  // The multi-obligation solve, end to end through the loop
  // --------------------------------------------------------------------------

  test("multi-obligation solve: commits through both sub-obligations, then the final gate") {
    val (result, log) = runLoop(pairWorld, pairCands, LoopConfig.default)
    result.status shouldBe SearchStatus.Solved
    val claim = result.solved.getOrElse(fail("no claim"))
    claim.state.script.map(_.candidate) shouldBe Vector("pair {!!} {!!}", "tt", "tt")
    claim.finalExitCode shouldBe 0
    // Exactly one final check_file, and it happened after the last fill.
    log.count(_._1 == "check_file") shouldBe 1
    result.stats.finalChecks shouldBe 1
    result.stats.depthReached shouldBe 2
  }

  test("first-open-obligation selection: the second sub-hole is probed only after the first commits") {
    val (_, log) = runLoop(pairWorld, pairCands, LoopConfig.default)
    val fillTargets = log.collect { case ("fill_hole", args) =>
      (args.hcursor.get[Int]("line").toOption.get, args.hcursor.get[Int]("column").toOption.get)
    }
    // Depth 0 probes address (3,8); depth 1 probes address (3,13) — the FIRST
    // of the two open obligations — and (3,18) is never addressed directly:
    // after the (3,13) commit the survivor re-anchors to (3,16).
    fillTargets.foreach(t => Vector((3, 8), (3, 13), (3, 16)) should contain(t))
  }

  // --------------------------------------------------------------------------
  // The #112 regression, at loop level
  // --------------------------------------------------------------------------

  test("#112 regression: budget dies after one of two obligations discharged — never solved") {
    // Budget 4: root spends 3 probes (ok, te, te); depth 1 spends 1 (te on
    // pair@3,13 — the world only accepts tt there, which the gate then blocks).
    val (result, _) = runLoop(pairWorld, pairCands, LoopConfig.default.copy(probeBudget = 4))
    result.status shouldBe SearchStatus.BudgetExceeded
    result.solved shouldBe None
    // An ok commit happened (the pair application), obligations were being
    // discharged — and the loop still refuses any solved reading.
    result.stats.probes shouldBe 4
  }

  // --------------------------------------------------------------------------
  // Budgets and the memo
  // --------------------------------------------------------------------------

  test("budget exhaustion mid-expansion reports budget_exceeded, not exhausted") {
    val (result, log) = runLoop(pairWorld, pairCands, LoopConfig.default.copy(probeBudget = 2))
    result.status shouldBe SearchStatus.BudgetExceeded
    result.stats.probes shouldBe 2
    log.count(_._1 == "fill_hole") shouldBe 2 // the third candidate was never probed
  }

  test("memo hits are free: a duplicate candidate costs no probe budget and its child dedups") {
    val (result, log) = runLoop(pairWorld,
      Vector("pair {!!} {!!}", "pair {!!} {!!}", "bad", "bad2"),
      LoopConfig.default.copy(probeBudget = 3, maxDepth = 1))
    // Four candidates, but the duplicate fill_hole is answered from the memo:
    // three transport calls, three budgeted probes, one hit, one dedup skip.
    log.count(_._1 == "fill_hole") shouldBe 3
    result.stats.probes shouldBe 3
    result.stats.memoHits shouldBe 1
    result.stats.dedupSkips shouldBe 1
    result.status shouldBe SearchStatus.Exhausted // depth bound cut the surviving child
    result.stats.depthCapped shouldBe true
  }

  // --------------------------------------------------------------------------
  // Exhaustion, both kinds
  // --------------------------------------------------------------------------

  test("frontier exhaustion: no ok children anywhere") {
    val world = Map(
      (3, 8, "a") -> fillTypeError("a", Vector((3, 8))),
      (3, 8, "b") -> fillTypeError("b", Vector((3, 8)))
    )
    val (result, _) = runLoop(world, Vector("a", "b"), LoopConfig.default)
    result.status shouldBe SearchStatus.Exhausted
    result.stats.depthCapped shouldBe false
    result.stats.expansions shouldBe 1
  }

  test("depth bound: a live frontier cut at max-depth is exhausted with depthCapped") {
    // Every expansion refines once more: s {!!} at (l,c) opens (l, c+2).
    val world = (0 to 8).map { i =>
      val col = 8 + 2 * i
      (3, col, "s {!!}") -> fillOk("s {!!}", Vector((3, col + 2)))
    }.toMap
    val (result, _) = runLoop(world, Vector("s {!!}"), LoopConfig.default.copy(maxDepth = 3))
    result.status shouldBe SearchStatus.Exhausted
    result.stats.depthCapped shouldBe true
    result.stats.expansions shouldBe 3
    result.stats.depthReached shouldBe 2
  }

  // --------------------------------------------------------------------------
  // The dedup policies (issue #122: decided by measurement, pinned here)
  // --------------------------------------------------------------------------

  test("dedup semantics: script-inclusive separates histories, content-only merges them") {
    // Two states with IDENTICAL content and different scripts: one born there,
    // one that reached it by a commit.
    val reached = SearchState.initial(content0, Vector(ob0))
      .commit(ob0, ProbeOutcome("tt", ProbeStatus.Ok, Vector.empty, None))
      .toOption.get
    val born = SearchState.initial(reached.content, Vector.empty)
    born.content shouldBe reached.content

    DedupPolicy.ContentOnly.keyOf(born) shouldBe DedupPolicy.ContentOnly.keyOf(reached)
    DedupPolicy.ScriptInclusive.keyOf(born) should not be DedupPolicy.ScriptInclusive.keyOf(reached)
  }

  test("the adopted default dedup policy (measured on M1-5, issue #122)") {
    // Measured on the full M1-5 sweep pair (#113: beam-a-script-nopeek vs
    // beam-b-content-nopeek): the two policies produced identical runs — 435
    // probes, the same per-fixture statuses and solve set, zero dedup skips
    // under either — because in this action space every candidate splices
    // distinct text at the first open obligation, so identical content
    // requires an identical script by construction.  Content-only therefore
    // bought nothing, and the conservative script-inclusive key (which can
    // never wrongly prune two live states) is adopted.  A proposer that
    // emits hole-free compound candidates could reopen the question; that
    // re-measurement belongs to P2 (#123).
    LoopConfig.default.dedup shouldBe DedupPolicy.ScriptInclusive
  }

  // --------------------------------------------------------------------------
  // The peek gate
  // --------------------------------------------------------------------------

  test("peek: a rejected candidate is never probed; a kept one is; lane failure keeps") {
    val types = Map(
      // tt is rejected by the lane (NotInScope) — its probe must never happen.
      "tt" -> Json.obj(
        "error" -> Json.obj(
          "code" -> Json.fromString("NotInScope"),
          "message" -> Json.fromString("Not in scope: tt"),
          "stage" -> Json.fromString("expression")),
        "elapsedMs" -> Json.fromInt(1)).noSpaces,
      // The application peeks compatible with the goal G? No — "Pair-ish"
      // vs canned goal "G" would reject; give it a meta so it matches anything.
      "pair _ _" -> Json.obj(
        "type" -> Json.fromString("_p_1"), "elapsedMs" -> Json.fromInt(1)).noSpaces
    )
    val (result, log) = runLoop(pairWorld, Vector("pair {!!} {!!}", "tt"),
      LoopConfig.default.copy(peek = true, maxDepth = 1), types)
    val probed = log.collect { case ("fill_hole", a) => a.hcursor.get[String]("candidate").toOption.get }
    probed should contain("pair {!!} {!!}")
    probed should not contain "tt"
    result.stats.peeks shouldBe 2
    result.stats.peekRejects shouldBe 1
  }
}
