/** ============================================================================
  *  AgentBenchIntegrationSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/AgentBenchIntegrationSpec.scala
  *
  *  Purpose
  *  -------
  *  The judge against the real instruments (issue #154): the agda-mcp server
  *  with `--safe` in its flags, the gold verifier's `agda`, and the agda-strux
  *  extractor.  On stdlib-nat-plus-comm: the committed gold is solved; the
  *  obligation fails on holes; a weakened statement and an edited import line
  *  fail preservation (the first by Agda's elaborated type differing from the
  *  gold's, the second by the diff); a postulate fails escape by `SafeFlagPostulate`; a
  *  wrong proof fails typecheck; a proof by the library's own lemma is
  *  restated by its `bodyRefs`.  Needs AGDA_MCP_BIN, AGDA_JSON_BIN, and
  *  AGDA_NATIVE_AIR_ROOT inside `nix develop .#backend` (the agent-bench-it
  *  Make target sets them); without them the suite is cancelled.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import cats.effect.IO
import cats.effect.unsafe.implicits.global
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths}
import scala.concurrent.duration._
import scala.jdk.CollectionConverters._

import struxdriver.benchmark.GoldVerifier
import struxdriver.search.{McpClient, Oracle, Scaffold, ServerConfig}

final class AgentBenchIntegrationSpec extends AnyFunSuite with Matchers {

  private val rootEnv = sys.env.get("AGDA_NATIVE_AIR_ROOT").map(Paths.get(_))
  private val binEnv  = sys.env.get("AGDA_MCP_BIN").map(Paths.get(_))
  private val jsonEnv = sys.env.get("AGDA_JSON_BIN").map(Paths.get(_))

  private def entry(root: Path, id: String) =
    Files.readAllLines(root.resolve("data/benchmarks/benchmark-index.jsonl"), StandardCharsets.UTF_8).asScala
      .map(l => io.circe.parser.decode[struxdriver.benchmark.Obligation](l).toOption.get)
      .find(_.id == id).get

  test("the judge, through the server, agda, and the extractor, names every gate and the restatement") {
    val root = rootEnv.getOrElse(cancel("AGDA_NATIVE_AIR_ROOT not set; skipping the judge's live test"))
    val bin  = binEnv.getOrElse(cancel("AGDA_MCP_BIN not set; skipping the judge's live test"))
    val json = jsonEnv.getOrElse(cancel("AGDA_JSON_BIN not set; skipping the judge's live test"))
    assume(sys.env.contains("AGDA_DIR"), "AGDA_DIR not set: run inside nix develop .#backend")
    assume(Files.isRegularFile(bin) && Files.isRegularFile(json), "the server or the extractor binary is missing")

    val e    = entry(root, "stdlib-nat-plus-comm")
    val obF  = root.resolve(e.obligationPath)
    val gdF  = root.resolve(e.goldPath)
    val ob   = new String(Files.readAllBytes(obF), StandardCharsets.UTF_8)
    val gold = new String(Files.readAllBytes(root.resolve(e.goldPath)), StandardCharsets.UTF_8)
    val base = Files.createTempDirectory(Paths.get("target").toAbsolutePath, "agentbench-judge-")
    val server = ServerConfig(bin, Scaffold.defaultAgdaFlags + " --safe", 600, root, base.resolve("server-stderr.log"), None)
    val agdaDir = GoldVerifier.agdaDirOf(root)

    def judge(agda: Agda, name: String, text: String): Verdict = {
      val dir  = base.resolve(name); Files.createDirectories(dir)
      val file = dir.resolve("Nat-plus-comm.agda")
      Files.write(file, text.getBytes(StandardCharsets.UTF_8))
      Judge.judge(e, ob, text, gdF, file, agda, root, safe = true, 300.seconds).unsafeRunSync()
    }

    val verdicts = McpClient.resource(server).use { client =>
      for {
        oracle   <- Oracle.create(client)
        includes <- Extractor.includesFromRegistry(Paths.get(agdaDir).resolve("libraries"))
        agda      = new ServerAgda(oracle, Extractor(json, includes, agdaDir, 300.seconds), "it")
        // A file Agda checks but the extractor cannot read: the statement is
        // unverified, so the row must not pass as a solve.
        blind     = new Agda {
                      def check(f: Path)            = agda.check(f)
                      def rows(f: Path)             = IO.pure(Left("agda-json exit 1: forced"))
                    }
      } yield Map(
        "unreadable" -> judge(blind, "unreadable", gold),
        "gold"      -> judge(agda, "gold", gold),
        "hole"      -> judge(agda, "hole", ob),
        "weakened"  -> judge(agda, "weakened", ob.replace("+-comm : ∀ (m n : ℕ) → m + n ≡ n + m", "+-comm : ∀ (m n : ℕ) → m + n ≡ m + n").replace("{!!}", "refl")),
        "import"    -> judge(agda, "import", gold.replace("using ( _≡_ ; refl ; cong ; sym )", "using ( _≡_ ; refl ; cong ; sym ; trans )")),
        "postulate" -> judge(agda, "postulate", ob.replace("+-comm : ∀ (m n : ℕ) → m + n ≡ n + m", "postulate\n  ax : ∀ (m n : ℕ) → m + n ≡ n + m\n\n+-comm : ∀ (m n : ℕ) → m + n ≡ n + m").replace("{!!}", "ax m n")),
        "wrong"     -> judge(agda, "wrong", ob.replace("{!!}", "refl")),
        "restated"  -> judge(agda, "restated", ob.replace("{!!}", "Data.Nat.Properties.+-comm m n"))
      )
    }.unsafeRunSync()

    // The gold is extracted once per case; every extraction elaborates it
    // from source, so its printed statement is one string, in the module's
    // own names (loaded from an interface, Agda would print it qualified).
    val goldPrintings = verdicts.values.flatMap(_.statement.map(_.gold)).toSet
    goldPrintings.size shouldBe 1
    goldPrintings.head should not include "Agda.Builtin"

    val u = verdicts("unreadable")
    u.agdaExit shouldBe Some(0)                        // Agda checked it
    u.gate.map(_.gate) shouldBe Some("statement")      // and the judge still refuses to call it solved
    u.gate.exists(_.detail.startsWith("the final file type-checks but could not be extracted")) shouldBe true
    u.statement shouldBe None
    u.evidenceSource should startWith ("unavailable")

    val g = verdicts("gold")
    g.gate shouldBe None
    g.solved shouldBe true
    g.restated shouldBe false
    g.agdaExit shouldBe Some(0)
    g.checkExit shouldBe Some(0)
    g.checkCodes shouldBe Vector.empty
    g.statement.map(_.equal) shouldBe Some(true)
    g.evidenceSource shouldBe "bodyRefs"
    g.addedImports shouldBe Vector("open import Relation.Binary.PropositionalEquality.Properties")

    verdicts("hole").gate.map(_.gate) shouldBe Some("holes")
    verdicts("hole").checkCodes should contain("UnsolvedInteractionMetas")

    val w = verdicts("weakened")
    w.gate.map(_.gate) shouldBe Some("preservation")
    w.gate.exists(_.detail.startsWith("statement changed")) shouldBe true
    w.agdaExit shouldBe Some(0)                       // the weakened file type-checks; the gate is the protocol's

    val i = verdicts("import")
    i.gate.map(_.gate) shouldBe Some("preservation")
    i.gate.exists(_.detail.startsWith("import line")) shouldBe true
    i.statement.isDefined shouldBe true                // Agda agrees the statement itself is intact

    val p = verdicts("postulate")
    p.gate.map(_.gate) shouldBe Some("escape")
    p.gate.exists(_.detail.startsWith("SafeFlagPostulate")) shouldBe true

    verdicts("wrong").gate.map(_.gate) shouldBe Some("typecheck")
    verdicts("wrong").agdaExit.exists(_ != 0) shouldBe true
    verdicts("wrong").checkExit.exists(_ != 0) shouldBe true

    val r = verdicts("restated")
    r.gate shouldBe None
    r.restated shouldBe true
    r.evidence shouldBe Vector("ref Data.Nat.Properties.+-comm")
  }
}
