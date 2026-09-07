/** ============================================================================
  *  RetrievalIntegrationSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/search/RetrievalIntegrationSpec.scala
  *
  *  Purpose
  *  -------
  *  The P2 (#123) live transport test: start the REAL agda-mcp with
  *  `--corpus` pointing at the committed mini-corpus (nine real rows from
  *  the agda-stdlib extraction, test/resources/search/corpus-mini.jsonl) and
  *  drive the three search tools through the landed client — the whole
  *  chain the retrieval proposer rides: ServerConfig's corpus flag, the
  *  tool registration, Oracle's ledgered retrieval calls, and the strict
  *  SearchHit / DependenciesBody decoders against the live serializer.
  *
  *  How to run
  *  ----------
  *  Gated like the other live specs: AGDA_MCP_BIN names the server binary;
  *  without it the suite cancels.  From the repo root:
  *
  *    env -u LD_LIBRARY_PATH nix develop .#backend --command bash -c \
  *      'BACKEND_USE_NIX=0 make proof-search-retrieval-it'
  *
  *  ============================================================================
  */
package struxdriver.search

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import cats.effect.unsafe.implicits.global
import java.nio.file.{Files, Path, Paths}

final class RetrievalIntegrationSpec extends AnyFunSuite with Matchers {

  private val binEnv = sys.env.get("AGDA_MCP_BIN").map(Paths.get(_))

  private def repoRoot: Path =
    sys.env.get("AGDA_NATIVE_AIR_ROOT").map(Paths.get(_))
      .getOrElse(Paths.get(sys.props("user.dir")).getParent) // sbt runs in strux-driver/
      .toAbsolutePath.normalize

  test("live corpus tools: --corpus registers them and the decoders hold against the real serializer") {
    val bin = binEnv.getOrElse(cancel("AGDA_MCP_BIN not set; skipping the live retrieval test"))
    assume(Files.isRegularFile(bin), s"AGDA_MCP_BIN does not name a file: $bin")

    val workDir = Files.createTempDirectory(
      Files.createDirectories(Paths.get(sys.props("user.dir"), "target", "proof-search-retrieval-it")),
      "run-")
    val corpus = Paths.get(getClass.getClassLoader.getResource("search/corpus-mini.jsonl").toURI)

    val cfg = ServerConfig(
      bin        = bin,
      agdaFlags  = Scaffold.defaultAgdaFlags,
      timeoutSec = 300,
      cwd        = repoRoot,
      stderrLog  = workDir.resolve("server-stderr.log"),
      corpus     = Some(corpus)
    )

    val scenario = McpClient.resource(cfg).use { client =>
      for {
        oracle <- Oracle.create(client)
        ctx     = CallCtx(1, "retrieval-it", "retrieval", None)
        byName <- oracle.searchByName(ctx, "Data.Nat.Properties.+-", 10)
        byType <- oracle.searchByType(ctx, "Commutative", 10)
        deps   <- oracle.dependenciesOf(ctx, "Data.Nat.Properties.+-comm")
        rows   <- oracle.timings.get
      } yield (byName, byType, deps, rows)
    }

    val (byName, byType, deps, rows) = scenario.unsafeRunSync()

    byName.map(_.bareName) should contain allOf ("+-comm", "+-identityʳ", "+-suc")
    byName.foreach(_.module shouldBe "Data.Nat.Properties")

    // The alias-form statement class retrieval exists to reach: stated via
    // Algebra.Definitions, fully qualified, exactly as the scorer expects.
    byType.map(_.bareName) should contain allOf ("+-comm", "*-comm")
    byType.foreach(h => h.tpe should include ("Algebra.Definitions.Commutative"))

    deps should not be empty // expand=true resolves neighbor rows

    // Every call above landed in the ledger under the retrieval phase.
    rows.count(_.phase == "retrieval") shouldBe 3
    rows.foreach(_.cached shouldBe false)
  }
}
