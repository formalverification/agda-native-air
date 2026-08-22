/** ============================================================================
  *  LoopIntegrationSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/search/LoopIntegrationSpec.scala
  *
  *  Purpose
  *  -------
  *  The P0 two-obligation regression extended to a FULL SEARCH against the
  *  real agda-mcp server (issue #122's live acceptance test): on the fixture
  *  whose evident move is a two-argument lemma application, the beam loop —
  *  not a hand-driven script — must find the three-commit proof, claim it
  *  only through the final batch gate, and report a genuine SolvedClaim.
  *  Every intermediate fill_hole answers "ok"; the conjunctive state and the
  *  loop's claim discipline are what keep "ok" from ever meaning "solved".
  *
  *  The candidates are injected through the Proposer seam (the fixture is
  *  builtins-only, so the fixed `using`-import space would be empty) — which
  *  also exercises the exact interface the P2 retrieval and P3 policy
  *  proposers will implement.
  *
  *  How to run
  *  ----------
  *  Gated like SingleStepIntegrationSpec: set AGDA_MCP_BIN to the server
  *  binary and run inside the backend shell; without it the suite is
  *  cancelled, not failed.  From the repo root:
  *
  *    env -u LD_LIBRARY_PATH nix develop .#backend --command bash -c \
  *      'BACKEND_USE_NIX=0 make proof-search-loop-it'
  *
  *  ============================================================================
  */
package struxdriver.search

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import cats.effect.IO
import cats.effect.unsafe.implicits.global
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths}

final class LoopIntegrationSpec extends AnyFunSuite with Matchers {

  private val binEnv = sys.env.get("AGDA_MCP_BIN").map(Paths.get(_))

  private def repoRoot: Path =
    sys.env.get("AGDA_NATIVE_AIR_ROOT").map(Paths.get(_))
      .getOrElse(Paths.get(sys.props("user.dir")).getParent) // sbt runs in strux-driver/
      .toAbsolutePath.normalize

  test("live full search: the beam loop finds the two-obligation proof and claims it through the gate") {
    val bin = binEnv.getOrElse(cancel("AGDA_MCP_BIN not set; skipping the live loop test"))
    assume(Files.isRegularFile(bin), s"AGDA_MCP_BIN does not name a file: $bin")

    val workDir = Files.createTempDirectory(
      Files.createDirectories(Paths.get(sys.props("user.dir"), "target", "proof-search-loop-it")),
      "run-")
    val fixture = workDir.resolve("TwoObligations.agda")
    val src     = scala.io.Source.fromResource("search/TwoObligations.agda")
    try Files.write(fixture, src.mkString.getBytes(StandardCharsets.UTF_8)) finally src.close()

    val cfg = ServerConfig(
      bin        = bin,
      agdaFlags  = Scaffold.defaultAgdaFlags,
      timeoutSec = 300,
      cwd        = repoRoot,
      stderrLog  = workDir.resolve("server-stderr.log")
    )

    // Injected candidates: a misfit, the lemma application, and the closer —
    // exercised at every obligation the loop selects.
    val proposer = new Proposer {
      def propose(state: SearchState, target: Obligation, goal: GoalView): IO[Vector[String]] =
        IO.pure(Vector("mkPair", "lemma {!!} {!!}", "tt"))
    }

    val scenario = McpClient.resource(cfg).use { client =>
      for {
        oracle <- Oracle.create(client)
        chk    <- oracle.checkFile(CallCtx(1, "two-obligations", "check_file", None), fixture)
        _       = chk.body.holes should have size 1
        _       = chk.body.success shouldBe false // an open hole is never green
        content <- IO.blocking(new String(Files.readAllBytes(fixture), StandardCharsets.UTF_8))
        s0      = SearchState.initial(content, chk.body.holes.map(WireHole.toObligation))
        result <- BeamLoop.run(oracle, proposer, LoopConfig.default,
                    (ph, rk) => CallCtx(1, "two-obligations", ph, rk), fixture, s0, BeamLoop.Hooks.none)
      } yield result
    }

    val result = scenario.unsafeRunSync()
    result.status shouldBe SearchStatus.Solved
    val claim = result.solved.getOrElse(fail("solved without a claim"))
    // The proof the loop found: the lemma application, then both ⊤ closers.
    claim.state.script.map(_.candidate) shouldBe Vector("lemma {!!} {!!}", "tt", "tt")
    claim.state.allDischarged shouldBe true
    claim.finalExitCode shouldBe 0
    // The search did real work: the misfit was probed and rejected along the
    // way (mkPair underapplied is a type error), and the goal was readable.
    result.stats.probes should be >= 5
    result.rootGoal.map(_.goal) shouldBe Some("Pair")
  }
}
