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
  *  gold's, the second by the diff); a postulate fails escape by
  *  `SafeFlagPostulate`; a wrong proof fails typecheck; a proof by the
  *  library's own lemma is restated by its `bodyRefs`.  Two archived subjects
  *  judged again end to end: a stdlib row, whose `original` column is null
  *  (issue #188), and an agda-algebras row of the shell arm, whose column
  *  names the library file it read before its last edit; the first is priced
  *  at the committed price table to the client's own figure (issue #237).  And
  *  the harness end to end on another endpoint (issue #237), with a stand-in
  *  client that prints a planted credential into everything it writes: the run
  *  records the endpoint, prices the row at the run's own table, scrubs the
  *  value, and leaves it nowhere in the run directory or on the console.
  *  Needs AGDA_MCP_BIN, AGDA_JSON_BIN, and AGDA_NATIVE_AIR_ROOT inside `nix
  *  develop .#backend` (the agent-bench-it Make target sets them); without
  *  them the suite is cancelled.
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
import struxdriver.io.TextIO
import struxdriver.search.{McpClient, Oracle, Scaffold, ServerConfig}

final class AgentBenchIntegrationSpec extends AnyFunSuite with Matchers {

  /** The harness's parser under an environment the test names: none unless
    * it says, so no test reads the endpoint of the machine it runs on.
    */
  private def cliParse(args: List[String], env: Map[String, String] = Map.empty): Either[String, AgentBenchConfig] = Cli.parse(args, env)

  private val rootEnv = sys.env.get("AGDA_NATIVE_AIR_ROOT").map(Paths.get(_))
  private val binEnv  = sys.env.get("AGDA_MCP_BIN").map(Paths.get(_))
  private val jsonEnv = sys.env.get("AGDA_JSON_BIN").map(Paths.get(_))

  private def entry(root: Path, id: String) =
    Files.readAllLines(root.resolve("data/benchmarks/benchmark-index.jsonl"), StandardCharsets.UTF_8).asScala
      .map(l => io.circe.parser.decode[struxdriver.benchmark.Obligation](l).toOption.get)
      .find(_.id == id).get

  test("an anomalous subject is never published as a solve, though its file earns one") {
    val root = rootEnv.getOrElse(cancel("AGDA_NATIVE_AIR_ROOT not set; skipping the judge's live test"))
    val bin  = binEnv.getOrElse(cancel("AGDA_MCP_BIN not set; skipping the judge's live test"))
    val json = jsonEnv.getOrElse(cancel("AGDA_JSON_BIN not set; skipping the judge's live test"))
    assume(sys.env.contains("AGDA_DIR"), "AGDA_DIR not set: run inside nix develop .#backend")
    assume(Files.isRegularFile(bin) && Files.isRegularFile(json), "the server or the extractor binary is missing")
    val archived = root.resolve("reports/agent-bench/smoke-haiku-1/subjects/stdlib-nat-plus-identity-l")
    assume(Files.isDirectory(archived), "the archived smoke subject is missing")

    // One archived subject, judged twice: intact, and with its result record
    // removed, which is a process that died before saying how it ended.
    val out = Files.createTempDirectory(Paths.get("target").toAbsolutePath, "agentbench-anomaly-")
    val dst = out.resolve("it-anomaly/subjects/stdlib-nat-plus-identity-l")
    Files.createDirectories(dst.resolve("final"))
    Files.list(archived).forEach { p => if (Files.isRegularFile(p)) Files.copy(p, dst.resolve(p.getFileName)) }
    Files.list(archived.resolve("final")).forEach { p => Files.copy(p, dst.resolve("final").resolve(p.getFileName)) }

    val cfg = cliParse(List("--rejudge", "--index", root.resolve("data/benchmarks/benchmark-index.jsonl").toString,
      "--all", "--out-dir", out.toString, "--run-id", "it-anomaly", "--project-root", root.toString,
      "--server-bin", bin.toString, "--agda-json-bin", json.toString)).getOrElse(fail("cli"))
    val e       = entry(root, "stdlib-nat-plus-identity-l")
    val server  = ServerConfig(bin, Scaffold.defaultAgdaFlags + " --safe", 600, root, out.resolve("server-stderr.log"), None)
    val agdaDir = GoldVerifier.agdaDirOf(root)

    def judgeArchive(): Outcome = McpClient.resource(server).use { client =>
      for {
        oracle   <- Oracle.create(client)
        includes <- Extractor.includesFromRegistry(Paths.get(agdaDir).resolve("libraries"))
        prices   <- Pricing.load(root.resolve(Cli.defaultPrices))
        judged   <- Outcomes.judgeOne(cfg, e, new ServerAgda(oracle, Extractor(json, includes, agdaDir, 300.seconds), e.id), includes, prices)
      } yield judged.outcome
    }.unsafeRunSync()

    val intact = judgeArchive()
    intact.anomaly shouldBe None
    intact.gate    shouldBe None
    intact.solved  shouldBe true
    intact.terminal shouldBe "completed"
    // A stdlib row names no original: the column is null, not false.
    intact.original shouldBe None
    intact.toJson.hcursor.downField("original").focus shouldBe Some(io.circe.Json.Null)
    // Priced at the committed table, the row costs what the client said (#237).
    intact.priced.unpriced shouldBe None
    (intact.priced.usd.map(_.toDouble).getOrElse(-1.0) - intact.costUsd.getOrElse(-2.0)).abs should be < 1e-9

    val transcript = dst.resolve("transcript.jsonl")
    val kept = new String(Files.readAllBytes(transcript), StandardCharsets.UTF_8)
      .linesIterator.filterNot(_.contains("\"type\":\"result\"")).mkString("\n") + "\n"
    Files.write(transcript, kept.getBytes(StandardCharsets.UTF_8))

    val crashed = judgeArchive()
    crashed.terminal shouldBe "crash"
    crashed.anomaly.exists(_.startsWith("no result record")) shouldBe true
    crashed.gate     shouldBe None            // the file itself still passes every gate
    crashed.solved   shouldBe false           // and is still not published as a solve
    crashed.restated shouldBe false
    crashed.priced.usd shouldBe None          // what it spent was never reported, so it is unpriced, not free
    crashed.priced.unpriced.exists(_.startsWith("no result record")) shouldBe true
  }

  test("an archived agda-algebras solve of the shell arm carries the original it read, and its verdict is unchanged") {
    val root = rootEnv.getOrElse(cancel("AGDA_NATIVE_AIR_ROOT not set; skipping the judge's live test"))
    val bin  = binEnv.getOrElse(cancel("AGDA_MCP_BIN not set; skipping the judge's live test"))
    val json = jsonEnv.getOrElse(cancel("AGDA_JSON_BIN not set; skipping the judge's live test"))
    assume(sys.env.contains("AGDA_DIR"), "AGDA_DIR not set: run inside nix develop .#backend")
    assume(Files.isRegularFile(bin) && Files.isRegularFile(json), "the server or the extractor binary is missing")
    val id       = "algebras-homs-mon-to-hom"
    val archived = root.resolve(s"reports/agent-bench/arm162-shell-1/subjects/$id")
    assume(Files.isDirectory(archived), "the archived shell subject is missing")
    val record = TextIO.readJson(archived.resolve("subject.json")).unsafeRunSync().flatMap(SubjectRecord.fromJson)
    assume(record.exists(_.roots.readRoots.exists(Files.isDirectory(_))), "the subject's read roots are not on this machine")

    // A copy of the archived subject, re-judged as `make agent-bench-rejudge` would.
    val out = Files.createTempDirectory(Paths.get("target").toAbsolutePath, "agentbench-original-")
    val dst = out.resolve(s"it-original/subjects/$id")
    Files.createDirectories(dst.resolve("final"))
    Files.list(archived).forEach { p => if (Files.isRegularFile(p)) Files.copy(p, dst.resolve(p.getFileName)) }
    Files.list(archived.resolve("final")).forEach { p => Files.copy(p, dst.resolve("final").resolve(p.getFileName)) }
    val cfg = cliParse(List("--rejudge", "--index", root.resolve("data/benchmarks/benchmark-index.jsonl").toString,
      "--all", "--out-dir", out.toString, "--run-id", "it-original", "--project-root", root.toString,
      "--server-bin", bin.toString, "--agda-json-bin", json.toString)).getOrElse(fail("cli"))
    val e       = entry(root, id)
    val server  = ServerConfig(bin, Scaffold.defaultAgdaFlags + " --safe", 600, root, out.resolve("server-stderr.log"), None)
    val agdaDir = GoldVerifier.agdaDirOf(root)
    val o = McpClient.resource(server).use { client =>
      for {
        oracle   <- Oracle.create(client)
        includes <- Extractor.includesFromRegistry(Paths.get(agdaDir).resolve("libraries"))
        prices   <- Pricing.load(root.resolve(Cli.defaultPrices))
        judged   <- Outcomes.judgeOne(cfg, e, new ServerAgda(oracle, Extractor(json, includes, agdaDir, 300.seconds), e.id), includes, prices)
      } yield judged.outcome
    }.unsafeRunSync()

    o.anomaly  shouldBe None
    o.solved   shouldBe true                     // as archived: the column moves no verdict
    o.restated shouldBe false
    val r = o.original.getOrElse(fail("a row with a restates: tag has an original block"))
    r.inView shouldBe Some(true)
    r.how.isDefined shouldBe true
    r.at.exists(i => i >= 0 && i < o.toolCallsTotal) shouldBe true
    r.file.exists(_.endsWith("/src/Setoid/Homomorphisms/Basic.lagda.md")) shouldBe true
    r.file.exists(f => record.get.roots.readRoots.exists(root => Paths.get(f).startsWith(root))) shouldBe true
    o.solvedOriginalInView shouldBe true
    o.toJson.hcursor.downField("original").downField("inView").as[Boolean] shouldBe Right(true)
  }

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

  test("a run on another endpoint records it, prices at its own table, and leaves a credential the subject printed nowhere (#237)") {
    val root = rootEnv.getOrElse(cancel("AGDA_NATIVE_AIR_ROOT not set; skipping the judge's live test"))
    val bin  = binEnv.getOrElse(cancel("AGDA_MCP_BIN not set; skipping the judge's live test"))
    val json = jsonEnv.getOrElse(cancel("AGDA_JSON_BIN not set; skipping the judge's live test"))
    assume(sys.env.contains("AGDA_DIR"), "AGDA_DIR not set: run inside nix develop .#backend")
    assume(Files.isRegularFile(bin) && Files.isRegularFile(json), "the server or the extractor binary is missing")
    // A value no real credential has, standing for one, and a stand-in client
    // that prints it into its stream, its result, its stderr, and the file.
    val planted = "sk-test-not-a-credential-237-e2e"
    val out     = Files.createTempDirectory(Paths.get("target").toAbsolutePath, "agentbench-endpoint-")
    // The shell arm starts no server with a corpus, so stand-ins do: the run
    // only digests them.
    val corpora = Vector("stdlib.jsonl", "algebras.jsonl").map(n => Files.write(out.resolve(n), Array.emptyByteArray))
    val client  = out.resolve("stand-in-claude")
    val usage   = """"usage":{"input_tokens":10,"output_tokens":1000,"cache_read_input_tokens":100000,"cache_creation_input_tokens":5000}"""
    val mu      = """"modelUsage":{"kimi-k3":{"inputTokens":10,"outputTokens":1000,"cacheReadInputTokens":100000,"cacheCreationInputTokens":5000,"costUSD":0.12505,"canonicalModel":"kimi-k3","provider":"firstParty","costBasis":"unknown"}}"""
    Files.write(client, Vector(
      "#!/usr/bin/env bash",
      """if [ "$1" = "--version" ]; then echo "0.0.0 (a stand-in client)"; exit 0; fi""",
      """tok="$ANTHROPIC_AUTH_TOKEN"; url="$ANTHROPIC_BASE_URL"""",
      """printf '%s\n' '{"type":"system","subtype":"init","tools":["Bash","Edit","Read"],"mcp_servers":[],"model":"kimi-k3","permissionMode":"acceptEdits"}'""",
      """printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"printenv ANTHROPIC_AUTH_TOKEN"}}]}}'""",
      """printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"%s"}]}}\n' "$tok"""",
      """printf '{"type":"assistant","message":{"content":[{"type":"text","text":"served by %s with %s"}]}}\n' "$url" "$tok"""",
      """for f in *.agda; do printf -- '-- %s\n' "$tok" >> "$f"; done""",
      """printf 'stderr: %s\n' "$tok" >&2""",
      s"""printf '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"duration_ms":10,"total_cost_usd":0.12505,$usage,$mu,"result":"done: %s"}\\n' "$$tok""""
    ).mkString("\n").getBytes(StandardCharsets.UTF_8))
    client.toFile.setExecutable(true)
    // Prices that differ from the client's own figure (USD 0.12505 above), so
    // the two columns cannot be mistaken for each other.
    val prices = out.resolve("prices-standin.json")
    Files.write(prices, """{"schemaVersion":"agent-bench-prices.v0","asOf":"2026-10-13","models":{"kimi-k3":{"input":0.6,"cacheWrite":0.6,"cacheRead":0.15,"output":2.5}}}"""
      .getBytes(StandardCharsets.UTF_8))
    // The subjects' environment, named in full: no variable of the machine's
    // own reaches the record or the scrub.
    val env = Map("PATH" -> sys.env.getOrElse("PATH", "/usr/bin:/bin"), "HOME" -> sys.env.getOrElse("HOME", "/tmp"),
      "ANTHROPIC_BASE_URL" -> "https://api.moonshot.ai/anthropic", "ANTHROPIC_AUTH_TOKEN" -> planted)
    val args = List("--index", root.resolve("data/benchmarks/benchmark-index.jsonl").toString, "--ids", "stdlib-nat-plus-identity-l",
      "--out-dir", out.toString, "--run-id", "it-endpoint", "--arm", "shell", "--project-root", root.toString,
      "--server-bin", bin.toString, "--agda-json-bin", json.toString, "--model", "kimi-k3", "--max-turns", "5", "--wall-cap", "120",
      "--claude-bin", client.toString, "--prices", prices.toString,
      "--corpus-stdlib", corpora(0).toString, "--corpus-algebras", corpora(1).toString)

    // The console, captured for the run, is searched too.
    val console = new java.io.ByteArrayOutputStream()
    val stdout  = System.out
    val exit    = try { System.setOut(new java.io.PrintStream(console, true, "UTF-8")); AgentBench.runWith(args, env).unsafeRunSync() }
                  finally System.setOut(stdout)
    val runRoot = out.resolve("it-endpoint")
    val subj    = runRoot.resolve("subjects/stdlib-nat-plus-identity-l")
    def text(p: Path) = new String(Files.readAllBytes(p), StandardCharsets.UTF_8)

    // Nothing the run kept, and nothing it printed, holds the value.
    val kept = Files.walk(runRoot).iterator.asScala.toVector.filter(f => Files.isRegularFile(f) && !f.startsWith(runRoot.resolve("work")))
    kept.map(f => runRoot.relativize(f).toString) should contain allOf ("protocol.json", "prices.json", "report.json",
      "subjects/stdlib-nat-plus-identity-l/transcript.jsonl", "subjects/stdlib-nat-plus-identity-l/stderr.log")
    kept.foreach(f => withClue(runRoot.relativize(f).toString)(new String(Files.readAllBytes(f), StandardCharsets.ISO_8859_1) should not include (planted)))
    console.toString("UTF-8") should not include (planted)
    // The run's own search of its directory found nothing either (an
    // anomaly of the row's verdict would fail the run for another reason).
    console.toString("UTF-8") should not include ("!! credential")
    Files.exists(runRoot.resolve("credential-leaks.json")) shouldBe false
    withClue(console.toString("UTF-8"))(exit shouldBe cats.effect.ExitCode.Success)

    // The subject saw the endpoint the protocol records, and printed it.
    val protocol = TextIO.readJson(runRoot.resolve("protocol.json")).unsafeRunSync().get
    protocol.hcursor.downField("endpoint").get[String]("ANTHROPIC_BASE_URL").toOption shouldBe Some("https://api.moonshot.ai/anthropic")
    protocol.hcursor.downField("endpoint").get[String]("ANTHROPIC_AUTH_TOKEN").toOption shouldBe Some("set")
    text(subj.resolve("transcript.jsonl")) should include ("served by https://api.moonshot.ai/anthropic with <redacted:ANTHROPIC_AUTH_TOKEN>")
    val finalFile = Files.list(subj.resolve("final")).iterator.asScala.find(_.toString.endsWith(".agda")).getOrElse(fail("no final file"))
    text(finalFile) should include ("-- <redacted:ANTHROPIC_AUTH_TOKEN>")
    val run = TextIO.readJson(subj.resolve("run.json")).unsafeRunSync().flatMap(SubjectRun.fromJson).get
    run.redacted shouldBe Vector("ANTHROPIC_AUTH_TOKEN")
    run.startedAt.isDefined shouldBe true

    // The table is the run's own, byte for byte, named by the protocol; the
    // row is priced at it, beside the client's guess, and the report says so.
    Files.readAllBytes(runRoot.resolve("prices.json")) shouldBe Files.readAllBytes(prices)
    protocol.hcursor.downField("inputs").downField("prices").get[String]("sha256").toOption shouldBe
      Some(Pricing.load(prices).unsafeRunSync().sha256)
    // 10*0.6 + 5000*0.6 + 100000*0.15 + 1000*2.5, per million tokens,
    // beside the client's 0.12505.
    val outcome = TextIO.readJson(subj.resolve("outcome.json")).unsafeRunSync().get
    outcome.hcursor.get[BigDecimal]("pricedCostUsd").toOption shouldBe Some(BigDecimal("0.020506"))
    outcome.hcursor.get[Double]("costUsd").toOption shouldBe Some(0.12505)
    outcome.hcursor.get[Vector[String]]("credentialsRedacted").toOption shouldBe Some(Vector("ANTHROPIC_AUTH_TOKEN"))
    val report = TextIO.readJson(runRoot.resolve("report.json")).unsafeRunSync().get
    report.hcursor.downField("totals").get[BigDecimal]("pricedCostUsd").toOption shouldBe Some(BigDecimal("0.021"))
    report.hcursor.downField("totals").get[BigDecimal]("costUsd").toOption shouldBe Some(BigDecimal("0.125"))
    report.hcursor.downField("totals").get[Int]("unpricedRows").toOption shouldBe Some(0)
    report.hcursor.downField("pricing").downField("prices").downField("rows").downField("kimi-k3").get[BigDecimal]("output").toOption shouldBe
      Some(BigDecimal("2.5"))
    report.hcursor.downField("pricing").get[Vector[String]]("clientCostBasis").toOption shouldBe Some(Vector("unknown"))
    report.hcursor.downField("pricing").downField("prices").get[String]("sha256").toOption shouldBe
      protocol.hcursor.downField("inputs").downField("prices").get[String]("sha256").toOption
  }

  test("a Codex run end to end with a stand-in codex: the protocol, the derived transcript, the price, and the login nowhere (#239)") {
    val root = rootEnv.getOrElse(cancel("AGDA_NATIVE_AIR_ROOT not set; skipping the judge's live test"))
    val bin  = binEnv.getOrElse(cancel("AGDA_MCP_BIN not set; skipping the judge's live test"))
    val json = jsonEnv.getOrElse(cancel("AGDA_JSON_BIN not set; skipping the judge's live test"))
    assume(sys.env.contains("AGDA_DIR"), "AGDA_DIR not set: run inside nix develop .#backend")
    assume(Files.isRegularFile(bin) && Files.isRegularFile(json), "the server or the extractor binary is missing")
    assume(Files.isExecutable(Paths.get("/usr/bin/python3")), "the stand-in codex is a python3 script")
    val out  = Files.createTempDirectory(Paths.get("target").toAbsolutePath, "agentbench-codex-")
    // A login that is no real one, standing for the operator's: its token,
    // and an identity in its ID token's claims.
    val token   = "tok-planted-not-a-credential-239-e2e"
    val email   = "nobody-239@example.org"
    val claims  = java.util.Base64.getUrlEncoder.withoutPadding.encodeToString(
      s"""{"email":"$email","https://api.openai.com/auth":{"chatgpt_user_id":"user-planted-0123456789"}}""".getBytes(StandardCharsets.UTF_8))
    val home    = Files.createDirectories(out.resolve("home/.codex"))
    Files.write(home.resolve("auth.json"), s"""{"tokens":{"access_token":"$token","id_token":"h.$claims.s","account_id":"acct-planted-0123456789"}}""".getBytes(StandardCharsets.UTF_8))
    val e       = entry(root, "stdlib-nat-plus-identity-l")
    val gold    = new String(Files.readAllBytes(root.resolve(e.goldPath)), StandardCharsets.UTF_8)
    val agda    = Subject.agdaToolsRequired.map(_.stripPrefix(Arm.agdaPrefix))
    // The stand-in writes what Codex 0.162.1 writes: the --json stream, a
    // rollout under its CODEX_HOME (whose session record names the account),
    // and a request trace; its read answer and its stderr print the token,
    // and it leaves the gold in the work file with the token in a comment.
    val codex = out.resolve("codex")
    Files.write(codex, s"""#!/usr/bin/env python3
import json, os, pathlib, sys, tomllib
if sys.argv[1:] == ["--version"]:
    print("codex-cli 0.162.1"); sys.exit(0)
home  = pathlib.Path(os.environ["CODEX_HOME"])
cfg   = tomllib.loads((home / "config.toml").read_text())
auth  = json.loads((home / "auth.json").read_text())
tok   = auth["tokens"]["access_token"]
f     = sorted(pathlib.Path.cwd().glob("*.agda"))[0]
f.write_text(${io.circe.Json.fromString(gold).noSpaces} + "\\n-- " + tok + "\\n")
T = "T-it-239"
def rec(t, p): return json.dumps({"type": t, "payload": p})
def item(i): return rec("event_msg", {"type": "item_completed", "item": i})
def usage(n, inp, cached): return rec("token_usage_record", {"response_id": "r%d" % n, "usage": {"input_tokens": inp, "cached_input_tokens": cached, "cache_write_input_tokens": 0, "output_tokens": 50, "reasoning_output_tokens": 5}})
lines = [
  rec("session_meta", {"id": T, "cli_version": "0.162.1", "cwd": str(f.parent), "creator_account_id": auth["tokens"]["account_id"], "git": {"branch": "x"}, "base_instructions": {"text": "BASE"}}),
  rec("turn_context", {"model": cfg["model"], "effort": cfg["model_reasoning_effort"], "approval_policy": "never"}),
  item({"type": "AgentMessage", "id": "m1", "content": [{"type": "Text", "text": "reading"}]}),
  rec("response_item", {"type": "function_call", "call_id": "c1", "namespace": "mcp__files", "name": "read"}),
  item({"type": "McpToolCall", "id": "c1", "server": "files", "tool": "read", "arguments": {"file_path": str(f)}, "status": "completed", "result": {"content": [{"type": "text", "text": "1\\tthe token " + tok}]}}),
  usage(1, 10000, 0),
  rec("response_item", {"type": "custom_tool_call", "call_id": "cell1", "name": "exec", "input": "apply_patch"}),
  usage(2, 11000, 9000),
  item({"type": "FileChange", "id": "fc", "status": "completed", "stdout": "Success.", "changes": {str(f): {"type": "update", "unified_diff": "@@ -1 +1 @@\\n-x\\n+y\\n", "move_path": None}}}),
  rec("response_item", {"type": "custom_tool_call_output", "call_id": "cell1"}),
  rec("response_item", {"type": "function_call", "call_id": "c3", "namespace": "mcp__agda", "name": "check_file"}),
  usage(3, 12000, 10000),
  item({"type": "McpToolCall", "id": "c3", "server": "agda", "tool": "check_file", "arguments": {"filePath": str(f)}, "status": "completed", "result": {"content": [{"type": "text", "text": "{\\"success\\":true}"}]}}),
  item({"type": "AgentMessage", "id": "m2", "content": [{"type": "Text", "text": "check_file reports success"}]}),
  usage(4, 12500, 12000),
  rec("event_msg", {"type": "token_count", "rate_limits": {"primary": {"used_percent": 5.0, "resets_at": 1791936924}, "secondary": {"used_percent": 1.0}, "credits": {"has_credits": False, "unlimited": False}}}),
  rec("event_msg", {"type": "task_complete", "last_agent_message": "check_file reports success", "duration_ms": 1000}),
]
day = home / "sessions" / "2026" / "10" / "13"; day.mkdir(parents=True)
(day / ("rollout-2026-10-13T00-00-00-%s.jsonl" % T)).write_text("\\n".join(lines) + "\\n")
tool = lambda n, ps: {"type": "function", "name": n, "parameters": {"properties": {p: {} for p in ps}}}
request = {"model": cfg["model"], "reasoning": {"effort": cfg["model_reasoning_effort"]}, "input": [
  {"type": "additional_tools", "tools": [
    {"type": "namespace", "name": "functions", "tools": [{"type": "custom", "name": "exec", "description": "declare const tools: { apply_patch(input: string): Promise<unknown>; };"}, tool("wait", ["cell_id"]), tool("request_user_input_async", ["message"])]},
    {"type": "namespace", "name": "mcp__agda", "tools": [tool(n, ["filePath"]) for n in ${io.circe.Json.fromValues(agda.map(io.circe.Json.fromString)).noSpaces}]},
    {"type": "namespace", "name": "mcp__files", "tools": [tool("read", ["file_path", "offset", "limit"])]}]},
  {"type": "message", "role": "developer", "content": [{"type": "input_text", "text": "BASE"}]},
  {"type": "message", "role": "developer", "content": [{"type": "input_text", "text": cfg["developer_instructions"]}]},
  {"type": "message", "role": "user", "content": [{"type": "input_text", "text": sys.argv[-1]}]}]}
bundle = pathlib.Path(os.environ["CODEX_ROLLOUT_TRACE_ROOT"]) / "trace-1"; (bundle / "payloads").mkdir(parents=True)
(bundle / "payloads" / "1.json").write_text(json.dumps(request))
(bundle / "trace.jsonl").write_text(json.dumps({"payload": {"type": "inference_started", "request_payload": {"path": "payloads/1.json"}}}) + "\\n")
for e in [{"type": "thread.started", "thread_id": T}, {"type": "turn.started"},
          {"type": "item.completed", "item": {"id": "item_0", "type": "mcp_tool_call"}},
          {"type": "item.completed", "item": {"id": "item_1", "type": "file_change"}},
          {"type": "item.completed", "item": {"id": "item_2", "type": "mcp_tool_call"}},
          {"type": "turn.completed", "usage": {}}]:
    print(json.dumps(e))
print("stderr " + tok, file=sys.stderr)
""".getBytes(StandardCharsets.UTF_8))
    codex.toFile.setExecutable(true)
    val env = Map("PATH" -> sys.env.getOrElse("PATH", "/usr/bin:/bin"), "HOME" -> out.resolve("home").toString)
    val args = List("--index", root.resolve("data/benchmarks/benchmark-index.jsonl").toString, "--ids", e.id,
      "--out-dir", out.toString, "--run-id", "it-codex", "--project-root", root.toString,
      "--server-bin", bin.toString, "--agda-json-bin", json.toString, "--model", "gpt-6.1-sol", "--wall-cap", "120",
      "--harness", "codex", "--codex-bin", codex.toString,
      "--corpus-stdlib", root.resolve("data/corpora/agda-stdlib/v0/corpus.jsonl").toString,
      "--corpus-algebras", root.resolve("data/corpora/agda-algebras/v0.1/corpus.jsonl").toString)
    val console = new java.io.ByteArrayOutputStream()
    val stdout  = System.out
    val exit    = try { System.setOut(new java.io.PrintStream(console, true, "UTF-8")); AgentBench.runWith(args, env).unsafeRunSync() }
                  finally System.setOut(stdout)
    val shown   = console.toString("UTF-8")
    val runRoot = out.resolve("it-codex")
    val subj    = runRoot.resolve(s"subjects/${e.id}")
    def read(p: Path) = new String(Files.readAllBytes(p), StandardCharsets.UTF_8)

    withClue(shown)(exit shouldBe cats.effect.ExitCode.Success)
    // No value of the login anywhere the run kept or printed, and no CODEX_HOME left.
    val kept = Files.walk(runRoot).iterator.asScala.toVector.filter(f => Files.isRegularFile(f) && !f.startsWith(runRoot.resolve("work")))
    kept.map(f => runRoot.relativize(f).toString) should contain allOf ("protocol.json", "codex-models.json", "prompts/codex-config.toml",
      s"subjects/${e.id}/codex-rollout.jsonl", s"subjects/${e.id}/codex-events.jsonl", s"subjects/${e.id}/codex-surface.json",
      s"subjects/${e.id}/transcript.jsonl", s"subjects/${e.id}/codex-config.toml", s"subjects/${e.id}/mcp.json")
    Vector(token, email, "acct-planted-0123456789", "user-planted-0123456789").foreach { v =>
      kept.foreach(f => withClue(s"${runRoot.relativize(f)}")(new String(Files.readAllBytes(f), StandardCharsets.ISO_8859_1) should not include (v)))
      shown should not include (v)
    }
    Files.exists(runRoot.resolve("credential-leaks.json")) shouldBe false
    Files.exists(out.resolve(".codex-homes/it-codex").resolve(e.id)) shouldBe false
    read(subj.resolve("codex-rollout.jsonl")) should not include ("creator_account_id")
    TextIO.readJson(subj.resolve("run.json")).unsafeRunSync().flatMap(SubjectRun.fromJson).map(_.redacted).getOrElse(Vector.empty) should
      contain ("CODEX_LOGIN_ACCESS_TOKEN")

    // The protocol is the Codex run's; the subject's record names the harness.
    val protocol = TextIO.readJson(runRoot.resolve("protocol.json")).unsafeRunSync().get.hcursor
    protocol.get[String]("harness").toOption shouldBe Some("codex")
    protocol.get[String]("harnessVersion").toOption shouldBe Some("codex-cli 0.162.1")
    protocol.get[String]("effort").toOption shouldBe Some("low")
    protocol.downField("endpoint").get[String]("authMode").toOption shouldBe Some("chatgpt")
    protocol.downField("inputs").downField("codexCatalog").get[String]("sha256").toOption.isDefined shouldBe true
    TextIO.readJson(subj.resolve("subject.json")).unsafeRunSync().flatMap(SubjectRecord.fromJson).map(_.harness) shouldBe Some(Harness.Codex)

    // The derived transcript reads as an mcp-arm subject; the row is solved,
    // priced at OpenAI's table, and has no client figure.
    val outcome = TextIO.readJson(subj.resolve("outcome.json")).unsafeRunSync().get.hcursor
    withClue(read(subj.resolve("outcome.json")))(outcome.get[Boolean]("solved").toOption shouldBe Some(true))
    outcome.get[Option[String]]("anomaly").toOption.flatten shouldBe None
    outcome.downField("toolCalls").get[Int]("Read").toOption shouldBe Some(1)
    outcome.downField("toolCalls").get[Int]("Edit").toOption shouldBe Some(1)
    outcome.downField("toolCalls").get[Int]("mcp__agda__check_file").toOption shouldBe Some(1)
    outcome.get[Int]("turns").toOption shouldBe Some(4)
    outcome.downField("costUsd").focus shouldBe Some(io.circe.Json.Null)
    // (10000 + 2000 + 2000 + 500) x 2 + (9000 + 10000 + 12000) x 0.1 + 200 x 10 = 34,100, per million
    outcome.get[BigDecimal]("pricedCostUsd").toOption shouldBe Some(BigDecimal("0.0341"))
    val report = TextIO.readJson(runRoot.resolve("report.json")).unsafeRunSync().get.hcursor
    report.downField("totals").downField("costUsd").focus shouldBe Some(io.circe.Json.Null)
    report.downField("config").get[String]("codexBin").toOption shouldBe Some(codex.toString)
    report.downField("pricing").get[Vector[String]]("caveats").toOption shouldBe Some(Report.codexCaveats)
  }
}

