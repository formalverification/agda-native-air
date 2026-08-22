/** ============================================================================
  *  SingleStepIntegrationSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/search/SingleStepIntegrationSpec.scala
  *
  *  Purpose
  *  -------
  *  The #112 regression scenario END TO END against the real agda-mcp server:
  *  on a fixture whose evident move is a two-argument lemma application, every
  *  intermediate fill_hole answers "ok" — and the state must still refuse to
  *  be solved until BOTH obligations are discharged and the final batch check
  *  passes.  This is the live twin of ModelSpec's pure regression test.
  *
  *  How to run
  *  ----------
  *  Requires the real server binary and the pinned toolchain, so it is gated
  *  like AgdaJsonlBackendSmokeSpec: set AGDA_MCP_BIN to the binary (e.g.
  *  `cd agda-mcp && cabal list-bin exe:agda-mcp`) and run inside the backend
  *  shell; without it the suite is cancelled, not failed.  From the repo root:
  *
  *    env -u LD_LIBRARY_PATH nix develop .#backend --command bash -c \
  *      'AGDA_MCP_BIN=$(cd agda-mcp && cabal list-bin exe:agda-mcp) \
  *       make proof-search-it'
  *
  *  The working copy lives under strux-driver/target/ (gitignored); the server
  *  is spawned with the repo root as cwd and the committed .mcp.json flag set,
  *  exactly as the harness spawns it.
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

final class SingleStepIntegrationSpec extends AnyFunSuite with Matchers {

  private val binEnv = sys.env.get("AGDA_MCP_BIN").map(Paths.get(_))

  private def repoRoot: Path =
    sys.env.get("AGDA_NATIVE_AIR_ROOT").map(Paths.get(_))
      .getOrElse(Paths.get(sys.props("user.dir")).getParent) // sbt runs in strux-driver/
      .toAbsolutePath.normalize

  private val agdaFlags =
    "-i agda-dojang/agda --library-file=agda/libraries -l agda-dojang -l standard-library"

  test("live #112 regression: ok probes, conjunctive state, solved only after the final verdict") {
    val bin = binEnv.getOrElse(cancel("AGDA_MCP_BIN not set; skipping the live regression test"))
    assume(Files.isRegularFile(bin), s"AGDA_MCP_BIN does not name a file: $bin")

    val workDir = Files.createTempDirectory(
      Files.createDirectories(Paths.get(sys.props("user.dir"), "target", "proof-search-it")),
      "run-")
    val fixture = workDir.resolve("TwoObligations.agda")
    val src     = scala.io.Source.fromResource("search/TwoObligations.agda")
    try Files.write(fixture, src.mkString.getBytes(StandardCharsets.UTF_8)) finally src.close()

    val cfg = ServerConfig(
      bin        = bin,
      agdaFlags  = agdaFlags,
      timeoutSec = 300,
      cwd        = repoRoot,
      stderrLog  = workDir.resolve("server-stderr.log")
    )

    val scenario = McpClient.resource(cfg).use { client =>
      for {
        oracle <- Oracle.create(client)
        ctx     = (phase: String) => CallCtx(1, "two-obligations", phase, None)

        // Baseline: one obligation.
        chk0   <- oracle.checkFile(ctx("check_file"), fixture)
        _       = chk0.body.holes should have size 1
        _       = chk0.body.success shouldBe false // an open hole is never green
        content <- IO.blocking(new String(Files.readAllBytes(fixture), StandardCharsets.UTF_8))
        ob0     = WireHole.toObligation(chk0.body.holes.head)
        s0      = SearchState.initial(content, Vector(ob0))

        // Move 1: the lemma application. The oracle answers OK and re-anchors
        // TWO obligations — ok is refinement, not proof.
        fp0    <- IO.pure(Fingerprint.of(s0.content))
        p1     <- oracle.probe(ctx("fill_hole"), fixture, fp0, ob0, "lemma {!!} {!!}")
        _       = p1.body.status shouldBe ProbeStatus.Ok
        _       = p1.body.holesAfter should have size 2
        s1     <- IO.fromEither(s0.commit(ob0, p1.body).left.map(new RuntimeException(_)))
        _      <- IO.blocking(Files.write(fixture, s1.content.getBytes(StandardCharsets.UTF_8)))
        _       = s1.allDischarged shouldBe false

        // Move 2: discharge ONE of the two. Still ok, still not solved — the
        // exact defect #112 recorded, refused by the model against the live
        // oracle.
        p2     <- oracle.probe(ctx("fill_hole"), fixture, Fingerprint.of(s1.content), s1.obligations.head, "tt")
        _       = p2.body.status shouldBe ProbeStatus.Ok
        s2     <- IO.fromEither(s1.commit(s1.obligations.head, p2.body).left.map(new RuntimeException(_)))
        _      <- IO.blocking(Files.write(fixture, s2.content.getBytes(StandardCharsets.UTF_8)))
        _       = s2.obligations should have size 1
        _       = s2.allDischarged shouldBe false
        _       = SolvedClaim.fromFinalCheck(s2, checkSuccess = true, exitCode = 0).isLeft shouldBe true

        // Move 3: discharge the second. NOW the set is empty — and the claim
        // still waits for the batch verdict.
        p3     <- oracle.probe(ctx("fill_hole"), fixture, Fingerprint.of(s2.content), s2.obligations.head, "tt")
        _       = p3.body.status shouldBe ProbeStatus.Ok
        s3     <- IO.fromEither(s2.commit(s2.obligations.head, p3.body).left.map(new RuntimeException(_)))
        _      <- IO.blocking(Files.write(fixture, s3.content.getBytes(StandardCharsets.UTF_8)))
        _       = s3.allDischarged shouldBe true

        fin    <- oracle.checkFile(ctx("final_check"), fixture)
        claim   = SolvedClaim.fromFinalCheck(s3, fin.body.success, fin.body.exitCode.getOrElse(-1))
      } yield (chk0, p1, p2, p3, fin, claim)
    }

    val (_, p1, p2, p3, fin, claim) = scenario.unsafeRunSync()

    // Every intermediate answer was "ok" — the trap the state model defuses.
    Vector(p1, p2, p3).map(_.body.status).distinct shouldBe Vector(ProbeStatus.Ok)
    fin.body.success shouldBe true
    claim.isRight shouldBe true
  }
}
