/** ============================================================================
  *  PricingSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/PricingSpec.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  Pins the priced cost (issue #237) to the archive, so a typo in the price
  *  table cannot pass.  The committed default table prices the archived Opus
  *  5 arms' report tokens at the client's own totals, USD 7.066 and 7.713;
  *  and every archived subject whose client priced it at its list prices,
  *  priced from its own transcript's `modelUsage`, costs what the client
  *  said, to a billionth of a dollar.  That second test grows with the
  *  archive: a run archived on an Anthropic model the table prices wrongly,
  *  or not at all, fails it until the row is right (a subject the flat table
  *  cannot price exactly, which carries a caveat, is left out of it).  No
  *  archived run pins the claude-opus-5-5 row yet; the first archived Opus
  *  5.5 arm will.  Beside them: why rows are priced from `modelUsage` rather
  *  than the `usage` block, the table's strict reading, the lookup, an
  *  unpriced row's reason, and a slice's lower bound.
  *
  *  The archive is read from the repository root, the parent of the
  *  directory sbt runs the suite in, as OriginalInViewSpec reads it.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.unsafe.implicits.global
import io.circe.Json
import io.circe.syntax._
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths}
import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import scala.jdk.CollectionConverters._

import struxdriver.benchmark.{Difficulty, Obligation => IndexEntry}
import struxdriver.io.TextIO

final class PricingSpec extends AnyFunSuite with Matchers {

  private val root    = Paths.get("..").toAbsolutePath.normalize
  private val archive = root.resolve("reports/agent-bench")
  private lazy val table = Pricing.load(root.resolve(Cli.defaultPrices)).unsafeRunSync()

  private def json(p: Path): Json = TextIO.readJson(p).unsafeRunSync().getOrElse(fail(s"no JSON at $p"))
  private def outcomes(report: Json): Vector[Json] = report.hcursor.downField("outcomes").as[Vector[Json]].getOrElse(fail("no outcomes"))
  private def costOf(o: Json): Double = o.hcursor.get[Double]("costUsd").getOrElse(fail("no costUsd"))

  /** A report's `tokens`, every row priced under the run's own model, as the
    * kickoff's jq one-liner prices them.
    */
  private def pricedFromTokens(report: Json): BigDecimal = {
    val model = report.hcursor.downField("config").get[String]("model").getOrElse(fail("no model"))
    val price = table.priceOf(model).getOrElse(fail(s"no row for $model"))
    outcomes(report).map(o => price.cost(Tokens.fromJson(o.hcursor.downField("tokens").focus.getOrElse(Json.obj())))).sum
  }

  /** A subject's result record and init record, read through the parser the
    * judge uses; only those two records are handed to it, which is all the
    * pricing reads, so the archive's 112 MB of tool traffic is not parsed.
    */
  private def resultOf(transcript: Path): Transcript =
    Transcript.parse(Files.readAllLines(transcript, StandardCharsets.UTF_8).asScala
      .filter(l => l.contains("\"type\":\"result\"") || l.contains("\"subtype\":\"init\"")).mkString("\n"))

  private def runs: Vector[Path] =
    Files.list(archive).iterator.asScala.toVector.filter(d => Files.isRegularFile(d.resolve("report.json"))).sortBy(_.toString)

  test("the default table prices the archived Opus 5 arms' tokens at the client's own totals: USD 7.066 and 7.713") {
    Vector("suite219-opus5-mcp-1" -> "7.066", "hard219-opus5-mcp-1" -> "7.713").foreach { case (run, usd) =>
      val report = json(archive.resolve(s"$run/report.json"))
      val priced = pricedFromTokens(report)
      withClue(run) {
        Pricing.round3(priced) shouldBe BigDecimal(usd)
        report.hcursor.downField("totals").get[BigDecimal]("costUsd").toOption shouldBe Some(BigDecimal(usd))
        (priced.toDouble - outcomes(report).map(costOf).sum).abs should be < 1e-9
      }
    }
  }

  test("every archived subject the client priced at its list prices, priced from its own modelUsage, costs what the client said") {
    val checked = runs.flatMap { run =>
      outcomes(json(run.resolve("report.json"))).flatMap { o =>
        val id = o.hcursor.get[String]("benchmarkId").getOrElse("?")
        o.hcursor.get[String]("transcriptPath").toOption.map(run.resolve).filter(Files.isRegularFile(_)).flatMap { tp =>
          val t      = resultOf(tp)
          val usages = t.result.map(_.modelUsage).getOrElse(Vector.empty)
          val exact  = t.result.exists(r => Pricing.caveats(r.usage).isEmpty)
          if (usages.isEmpty || !exact || !usages.forall(_.costBasis.contains("list"))) None
          else {
            val priced = table.price(usages)
            withClue(s"${run.getFileName}/$id: ") {
              priced.unpriced shouldBe None
              (priced.usd.getOrElse(fail("unpriced")).toDouble - costOf(o)).abs should be < 1e-9
            }
            Some(usages.map(_.model))
          }
        }
      }
    }
    // 1,263 subjects in 57 runs on 2026-10-13; the archive only grows.
    checked.size should be >= 1263
    checked.flatten.distinct.toSet should contain allOf ("claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5-20251001")
  }

  test("the usage block alone misses what the client spent beside the subject's model, which is why rows are priced from modelUsage") {
    // Client 2.1.261 made one Haiku call per session beside Sonnet 5's; the
    // `usage` block (the report's `tokens`) never counted it.
    val run    = archive.resolve("arm162-shell-1")
    val report = json(run.resolve("report.json"))
    val client = outcomes(report).map(costOf).sum
    val fromModelUsage = outcomes(report).flatMap { o =>
      val t = resultOf(run.resolve(o.hcursor.get[String]("transcriptPath").getOrElse(fail("no transcript"))))
      table.price(t.result.map(_.modelUsage).getOrElse(Vector.empty)).usd
    }.sum
    Pricing.round3(pricedFromTokens(report)) shouldBe BigDecimal("2.816")
    Pricing.round3(fromModelUsage) shouldBe BigDecimal("2.879")
    (fromModelUsage.toDouble - client).abs should be < 1e-9
  }

  private val goodRow = Json.obj("input" -> 3.asJson, "cacheWrite" -> 3.asJson, "cacheRead" -> 0.3.asJson, "output" -> 15.asJson)
  private def tableJson(rows: (String, Json)*): Json = Json.obj(
    "schemaVersion" -> Pricing.schemaVersion.asJson, "asOf" -> "2026-10-13".asJson, "models" -> Json.obj(rows: _*))
  private def parsed(j: Json): Either[String, PriceTable] = Pricing.parse(j, Paths.get("t.json"), "00")

  test("a table is refused by name: a missing, unknown, or negative price, no date, no row, the wrong schema") {
    parsed(tableJson("kimi-k3" -> goodRow)).map(_.priceOf("kimi-k3")) shouldBe
      Right(Some(ModelPrice(BigDecimal(3), BigDecimal(3), BigDecimal("0.3"), BigDecimal(15))))
    parsed(tableJson("m" -> goodRow.mapObject(_.remove("cacheRead")))) shouldBe Left("m: missing cacheRead")
    parsed(tableJson("m" -> goodRow.mapObject(_.add("cacheWrite5m", 1.asJson)))).left.map(_.startsWith("m: unknown field(s) cacheWrite5m ")) shouldBe
      Left(true)
    parsed(tableJson("m" -> goodRow.mapObject(_.add("output", (-1).asJson)))) shouldBe Left("m: output is not a number no smaller than 0")
    parsed(tableJson("m" -> goodRow.mapObject(_.add("input", "3".asJson)))) shouldBe Left("m: input is not a number no smaller than 0")
    parsed(tableJson()) shouldBe Left("models names no model")
    parsed(tableJson("m" -> goodRow).mapObject(_.remove("asOf"))) shouldBe Left("missing asOf (the date the prices were taken)")
    parsed(tableJson("m" -> goodRow).mapObject(_.add("schemaVersion", "v9".asJson))) shouldBe Left(s"schemaVersion v9 is not ${Pricing.schemaVersion}")
    parsed(tableJson("m" -> goodRow).mapObject(_.add("modles", Json.obj()))) shouldBe Left("unknown field(s) modles")
    // The committed table is read like any other, and dated.
    table.asOf shouldBe "2026-10-13"
    table.sha256.length shouldBe 64
  }

  private val spent = Tokens(input = 10, output = 1000, cacheRead = 100000, cacheCreation = 5000)

  test("a model is priced by its id, then by the id the client priced it by; a model that spent tokens with no row leaves the row unpriced") {
    val haiku = ModelUsage("claude-haiku-4-5-20251001", spent, 0.0, Some("claude-haiku-4-5"), Some("firstParty"), Some("list"))
    // 10*1 + 5000*2 + 100000*0.1 + 1000*5, per million tokens
    table.price(Vector(haiku)) shouldBe Priced(Some(BigDecimal("0.02501")), None, Vector.empty, Map("claude-haiku-4-5-20251001" -> "claude-haiku-4-5"))
    val k3 = ModelUsage("kimi-k3", spent, 0.0, None, Some("firstParty"), Some("unknown"))
    val both = table.price(Vector(haiku, k3))
    both.usd shouldBe None
    both.unpriced shouldBe Some("no price for kimi-k3 in the table")
    both.models shouldBe Vector("kimi-k3")
    table.price(Vector(haiku, k3.copy(tokens = Tokens.zero))).usd shouldBe Some(BigDecimal("0.02501"))  // nothing spent, nothing to price
    table.price(Vector.empty).usd shouldBe Some(BigDecimal(0))
    // Before any subject runs, a --model id is looked up as given, then
    // without a snapshot date.
    table.priceOfModelId("claude-haiku-4-5-20251001") shouldBe table.priceOf("claude-haiku-4-5")
    table.priceOfModelId("claude-opus-5-5").isDefined shouldBe true
    table.priceOfModelId("kimi-k3") shouldBe None
  }

  test("a row is priced from its result record's modelUsage, and left unpriced, with the reason, without a result record or without modelUsage") {
    val withUsage = Transcript.parse("""{"type":"result","subtype":"success","total_cost_usd":0.2,"usage":{},""" +
      """"modelUsage":{"claude-opus-5":{"inputTokens":10,"outputTokens":1000,"cacheReadInputTokens":100000,"cacheCreationInputTokens":5000,"costUSD":0.2}}}""").result
    Pricing.ofResult(withUsage, table).usd shouldBe Some(BigDecimal("0.12505"))
    val noUsage = Pricing.ofResult(Transcript.parse("""{"type":"result","subtype":"success","total_cost_usd":0.1,"usage":{"input_tokens":10}}""").result, table)
    noUsage.usd shouldBe None
    noUsage.unpriced shouldBe Some("the client reported no modelUsage")              // never the usage block, never 0
    val killed = Pricing.ofResult(None, table)
    killed.usd shouldBe None
    killed.unpriced.exists(_.startsWith("no result record")) shouldBe true
  }

  test("the usage block is never priced, and what the flat table cannot price exactly is a caveat") {
    val result = """{"type":"result","subtype":"success","is_error":false,"num_turns":3,"total_cost_usd":0.1,""" +
      """"usage":{"input_tokens":10,"output_tokens":1000,"cache_read_input_tokens":100000,"cache_creation_input_tokens":5000,""" +
      """"cache_creation":{"ephemeral_1h_input_tokens":4000,"ephemeral_5m_input_tokens":1000},"inference_geo":"us","speed":"fast",""" +
      """"server_tool_use":{"web_search_requests":2}}}"""
    val r = Transcript.parse(result).result.getOrElse(fail("no result"))
    r.modelUsage shouldBe Vector.empty
    r.usageTokens shouldBe spent
    Pricing.caveats(r.usage) shouldBe Vector(
      "1000 five-minute cache-write tokens, priced at the one-hour rate",
      "inference_geo us, which the client prices at 1.1 times the rate",
      "2 web searches, not priced",
      "fast mode, priced at the standard rate")
    Pricing.caveats(Json.obj("inference_geo" -> "not_available".asJson)) shouldBe Vector.empty
  }

  private val entry = IndexEntry("x-id", "agda-stdlib", "M", Paths.get("data/x/X.agda"), Paths.get("data/g/X.agda"),
    "refl", "x", "T", Difficulty.Routine, "d", "s", Vector.empty)

  test("an unpriced row carries a null priced cost and names its model, and the report's pricing block names it too") {
    // The client's figures differ from the priced ones, so a swapped column shows.
    val k3   = ModelUsage("kimi-k3", spent, 0.27, None, Some("firstParty"), Some("unknown"))
    val opus = ModelUsage("claude-opus-5", spent, 0.2, Some("claude-opus-5"), Some("firstParty"), Some("list"))
    val row      = Outcome.anomaly(entry, "x", 0L, Priced.nothing).copy(anomaly = None, costUsd = 0.2)
    val unpriced = row.copy(usageByModel = Vector(k3), priced = table.price(Vector(k3)))
    val priced   = row.copy(usageByModel = Vector(opus), priced = table.price(Vector(opus)))
    unpriced.toJson.hcursor.downField("pricedCostUsd").focus shouldBe Some(Json.Null)
    unpriced.toJson.hcursor.get[String]("unpriced").toOption shouldBe Some("no price for kimi-k3 in the table")
    unpriced.toJson.hcursor.get[Vector[String]]("unpricedModels").toOption shouldBe Some(Vector("kimi-k3"))
    unpriced.toJson.hcursor.downField("usageByModel").downField("kimi-k3").get[String]("costBasis").toOption shouldBe Some("unknown")
    unpriced.toJson.hcursor.downField("usageByModel").downField("kimi-k3").downField("pricedAs").focus shouldBe Some(Json.Null)
    priced.toJson.hcursor.get[BigDecimal]("pricedCostUsd").toOption shouldBe Some(BigDecimal("0.12505"))
    priced.toJson.hcursor.get[Double]("costUsd").toOption shouldBe Some(0.2)
    priced.toJson.hcursor.downField("usageByModel").downField("claude-opus-5").get[String]("pricedAs").toOption shouldBe Some("claude-opus-5")
    priced.toJson.hcursor.downField("unpriced").focus shouldBe None
    priced.toJson.hcursor.downField("unpricedModels").focus shouldBe None
    // A slice sums the rows it can price and counts the rest: a lower
    // bound, which says so.
    Priced.total(Vector(priced.priced, unpriced.priced)) shouldBe Priced.Total(BigDecimal("0.12505"), 1)
    Priced.total(Vector(priced.priced, priced.priced)) shouldBe Priced.Total(BigDecimal("0.25010"), 0)
    val block = Report.pricing(Vector(priced, unpriced), table)
    block.hcursor.get[Vector[String]]("unpricedModels").toOption shouldBe Some(Vector("kimi-k3"))
    block.hcursor.get[Int]("unpricedRows").toOption shouldBe Some(1)
    block.hcursor.get[Vector[String]]("clientCostBasis").toOption shouldBe Some(Vector("list", "unknown"))
    block.hcursor.downField("byModel").downField("kimi-k3").downField("pricedCostUsd").focus shouldBe Some(Json.Null)
    block.hcursor.downField("byModel").downField("claude-opus-5").get[BigDecimal]("pricedCostUsd").toOption shouldBe Some(BigDecimal("0.125"))
    block.hcursor.downField("byModel").downField("claude-opus-5").get[BigDecimal]("costUsd").toOption shouldBe Some(BigDecimal("0.2"))
    // The rates of every row the report used travel with it, so its figures
    // can be recomputed from it alone.
    block.hcursor.downField("prices").downField("rows").focus.flatMap(_.asObject).map(_.keys.toVector) shouldBe Some(Vector("claude-opus-5"))
    block.hcursor.downField("prices").downField("rows").downField("claude-opus-5").get[BigDecimal]("cacheWrite").toOption shouldBe Some(BigDecimal(10))
    block.hcursor.downField("byModel").downField("claude-opus-5").get[String]("pricedAs").toOption shouldBe Some("claude-opus-5")
    block.hcursor.downField("prices").get[String]("asOf").toOption shouldBe Some("2026-10-13")
    // A row whose subject never spawned spent nothing; one the harness could
    // not read is unpriced, with the reason.
    Outcome.anomaly(entry, "x", 0L, Priced.nothing).toJson.hcursor.get[BigDecimal]("pricedCostUsd").toOption shouldBe Some(BigDecimal(0))
    val unread = Outcome.anomaly(entry, "x", 0L, Priced.unread("no archived subject")).toJson
    unread.hcursor.downField("pricedCostUsd").focus shouldBe Some(Json.Null)
    unread.hcursor.get[String]("unpriced").toOption shouldBe Some("no archived subject")
  }

  private val pricesArgs = List("--index", "i.jsonl", "--out-dir", "/out", "--run-id", "r", "--project-root", "/repo", "--all",
    "--server-bin", "b", "--agda-json-bin", "j", "--corpus-stdlib", "s", "--corpus-algebras", "a")

  test("the table a run prices at: --prices, else a re-judge's or a resume's own copy, else the committed table") {
    def cfg(extra: String*) = Cli.parse(pricesArgs ++ extra, Map.empty).getOrElse(fail("parse"))
    AgentBench.pricesPath(cfg("--model", "m"), runHasTable = true).toString shouldBe "/repo/data/benchmarks/prices-anthropic.json"
    AgentBench.pricesPath(cfg("--model", "m", "--prices", "p.json"), runHasTable = true).toString shouldBe "/repo/p.json"
    AgentBench.pricesPath(cfg("--rejudge"), runHasTable = true).toString shouldBe "/out/r/prices.json"
    AgentBench.pricesPath(cfg("--rejudge"), runHasTable = false).toString shouldBe "/repo/data/benchmarks/prices-anthropic.json"   // a run before #237
    AgentBench.pricesPath(cfg("--rejudge", "--prices", "fixed.json"), runHasTable = true).toString shouldBe "/repo/fixed.json"
    // A resume prices at its own copy too, so a row added to the committed
    // table never stops a run in flight.
    AgentBench.pricesPath(cfg("--model", "m", "--resume", "on"), runHasTable = true).toString shouldBe "/out/r/prices.json"
    AgentBench.pricesPath(cfg("--model", "m", "--resume", "on"), runHasTable = false).toString shouldBe "/repo/data/benchmarks/prices-anthropic.json"
  }

  test("a model with no row refuses a fresh run on another endpoint, warns on Anthropic's, and never stops a re-judge") {
    val moon = Map("ANTHROPIC_BASE_URL" -> "https://api.moonshot.ai/anthropic", "ANTHROPIC_AUTH_TOKEN" -> "sk-test-not-a-credential-237")
    def cfg(env: Map[String, String], extra: String*) = Cli.parse(pricesArgs ++ extra, env).getOrElse(fail("parse"))
    AgentBench.modelPriced(cfg(Map.empty, "--model", "claude-opus-5"), table) shouldBe Right(None)
    AgentBench.modelPriced(cfg(Map.empty, "--model", "claude-haiku-4-5-20251001"), table) shouldBe Right(None)   // the snapshot's row
    AgentBench.modelPriced(cfg(Map.empty, "--model", "claude-next"), table).map(_.exists(_.startsWith("--model claude-next has no row"))) shouldBe Right(true)
    AgentBench.modelPriced(cfg(moon, "--model", "kimi-k3", "--prices", "p.json"), table).left.map(_.startsWith("--model kimi-k3 has no row")) shouldBe Left(true)
    AgentBench.modelPriced(cfg(moon, "--rejudge"), table) shouldBe Right(None)
  }
}
