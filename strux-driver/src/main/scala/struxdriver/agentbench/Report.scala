/** ============================================================================
  *  Report.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Report.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  The run's outputs (issue #154), in the loop's shape so the two
  *  instruments read side by side: `report.json` (runId, timestamp, config,
  *  corpora, pricing, obligations, totals, perTier, perStratum, perTool,
  *  perShell, perVia, outcomes),
  *  `results.jsonl` (one eval-proof-completion.v0 row per fill_hole probe),
  *  `fixtures.jsonl` (one per obligation), and the console summary.  The
  *  config block records the protocol (every cap and client flag, the
  *  prompts' digests, the client version; Protocol.scala) and the run's own
  *  knobs; a re-judge carries the run's own config and corpora blocks
  *  forward, since it is not told them again.
  *
  *  The arm's three additions (issue #162).  `perShell` is the shell side of
  *  `perTool`: the Bash calls of the run counted by what they were
  *  (`ShellAudit.classes`), which is the only way a Bash column says anything,
  *  since every shell call is one tool name.  `perVia` counts the rows by
  *  which instruments the subject used, and `perVerdictVia` by which it took
  *  its last verdict from; on the `both` arm those two are the result.  The
  *  classes are disjoint and exhaustive, so `perShell` sums to the run's Bash
  *  calls and `perVia` to its rows.
  *
  *  The original in view (issue #188).  Beside `solved` and `restated`, every
  *  slice counts `solvedOriginalInView`: its solves whose original's proof was
  *  in view before the subject's last edit (OriginalInView.scala).  A slice
  *  with no row that names an original (the stdlib strata) has nothing to
  *  count and reports `null`, never 0.
  *
  *  The priced cost (issue #237).  Beside the client's `costUsd`, every slice
  *  carries `pricedCostUsd`, the sum of its rows' priced figures (Outcomes,
  *  Pricing.scala), and `unpricedRows`, how many rows had none, so a total
  *  never silently leaves a row out: with any unpriced row it is a lower
  *  bound.  The `pricing` block names the table that priced this report
  *  (path, digest, date, and the rates of the rows used; a re-judge prices
  *  at the run's own copy unless it is given another), the run's tokens and
  *  both figures per model with the row that priced it, the models no row
  *  priced, how many rows have no figure, and the client's own price bases
  *  (`list`, `managed`, `unknown`), which say whether its `costUsd` was a
  *  list price or a guess.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.IO
import io.circe.Json
import io.circe.syntax._

import struxdriver.benchmark.{Obligation => IndexEntry}
import struxdriver.io.TextIO
import struxdriver.search.Scaffold

object Report {

  private val tiers = Vector("routine", "compositional", "non-obvious")

  /** A slice's solves with the original in view; None when no row of the
    * slice names an original, so there is nothing to count.
    */
  private def originalInView(sel: Vector[Outcome]): Option[Int] =
    if (sel.exists(_.original.isDefined)) Some(sel.count(_.solvedOriginalInView)) else None

  /** The counters for one slice of outcomes (a tier, a stratum, the run). */
  /** Has this slice no client figure: every row lacks one, or it has no rows in a run whose client gives none? */
  private def clientless(sel: Vector[Outcome], noClientFigure: Boolean): Boolean =
    if (sel.isEmpty) noClientFigure else sel.forall(_.costUsd.isEmpty)

  private def block(sel: Vector[Outcome], noClientFigure: Boolean = false): Json = {
    val gates = sel.flatMap(_.gate.map(_.gate))
    Json.obj(
      "total"                -> sel.size.asJson,
      "solved"               -> sel.count(_.solved).asJson,
      "restated"             -> sel.count(_.restated).asJson,
      "solvedOriginalInView" -> originalInView(sel).asJson,
      "gates"     -> Json.obj(gates.distinct.sorted.map(g => g -> gates.count(_ == g).asJson): _*),
      "anomalies" -> sel.count(_.anomaly.isDefined).asJson,
      "turns"     -> sel.map(_.turns).sum.asJson,
      "toolCalls" -> sel.map(_.toolCallsTotal).sum.asJson,
      "wallMs"    -> sel.map(_.wallMs).sum.asJson,
      // Null for a slice whose rows all lack a client figure (Codex rows,
      // issue #239), and for an empty slice of a run whose client gives none;
      // an empty slice of a Claude run keeps its 0, as every archived one.
      "costUsd"   -> (if (clientless(sel, noClientFigure)) Json.Null else Scaffold.round3(sel.flatMap(_.costUsd).sum).asJson),
      "pricedCostUsd" -> Pricing.round3(pricedTotal(sel).usd).asJson,
      "unpricedRows"  -> pricedTotal(sel).unpricedRows.asJson
    )
  }

  /** A slice's priced cost: the sum over its priced rows, and how many had none. */
  private def pricedTotal(sel: Vector[Outcome]): Priced.Total = Priced.total(sel.map(_.priced))

  /** The `pricing` block: the table with the rates of the rows used, then
    * per model the run's tokens, the client's figure, the priced one (null
    * for a model with no row), and the row that priced it; the models no row
    * priced, how many rows have no figure, and the price bases the client
    * reported.  These are the counts to check against a provider's usage
    * page: the report's `tokens` is the main loop's `usage` block, which can
    * miss calls.
    */
  private[agentbench] def pricing(outcomes: Vector[Outcome], prices: PriceTable, harness: String = Harness.Claude.name): Json = {
    val usages = outcomes.flatMap(_.usageByModel)
    val byModel = ModelUsage.totals(usages).map { case (m, tokens, client) =>
      val row = usages.find(_.model == m).flatMap(u => prices.rowOf(m, u.canonical))
      m -> Json.fromFields(tokens.fields ++ Vector(
        "costUsd"       -> client.map(Scaffold.round3).asJson,
        "pricedCostUsd" -> (if (tokens.isZero) Some(BigDecimal(0)) else row.map(r => prices.models(r).cost(tokens))).map(Pricing.round3).asJson,
        "pricedAs"      -> row.asJson))
    }
    val used = usages.flatMap(u => prices.rowOf(u.model, u.canonical))
    Json.obj(
      "prices"          -> prices.toJson(used),
      "byModel"         -> Json.obj(byModel: _*),
      "unpricedModels"  -> outcomes.flatMap(_.priced.models).distinct.asJson,
      "unpricedRows"    -> outcomes.count(!_.priced.isPriced).asJson,
      "clientCostBasis" -> usages.flatMap(_.costBasis).distinct.sorted.asJson,
      // What a Codex run's priced figure is and is not (issue #239), once
      // for the run rather than on every row.
      "caveats"         -> (if (harness == Harness.Codex.name) codexCaveats.asJson else Json.Null)
    ).dropNullValues
  }

  /** What every Codex run's priced figure is and is not. */
  val codexCaveats: Vector[String] = Vector(
    "Codex reports no cost: the figure is OpenAI's list price for the tokens it reported",
    "the ChatGPT backend reports cache writes as 0, so written tokens are priced as uncached input, at most 20 % under OpenAI's write price",
    "reasoning tokens are inside output, as OpenAI bills them",
    "a ChatGPT plan is billed by usage windows, not per token: the run's windows are its bill")

  /** Calls per tool over the run, most-called first. */
  private def perTool(outcomes: Vector[Outcome]): Vector[(String, Int)] = {
    val all = outcomes.flatMap(_.toolCalls)
    all.map(_._1).distinct.map(n => n -> all.filter(_._1 == n).map(_._2).sum).sortBy { case (n, k) => (-k, n) }
  }

  /** Bash calls per class over the run, in the classes' own order. */
  private def perShell(outcomes: Vector[Outcome]): Vector[(String, Int)] = {
    val all = outcomes.flatMap(_.isolation.toVector.flatMap(_.shellClasses))
    ShellAudit.classes.map(c => c -> all.filter(_._1 == c).map(_._2).sum).filter(_._2 > 0)
  }

  /** Rows per value of a `via` column, in a fixed order so two arms' reports
    * line up field for field.
    */
  private def perVia(outcomes: Vector[Outcome], of: Outcome => String): Vector[(String, Int)] =
    Vector("mcp", "shell", "both", "none").map(v => v -> outcomes.count(of(_) == v)).filter(_._2 > 0)

  /** The config block of a fresh run: the protocol (Protocol.of, every knob
    * a subject sees and the judge applies, every input by content) plus what
    * only this run of it chose (parallelism, the client binary, resume) and
    * the gate names.
    */
  private def builtConfig(cfg: AgentBenchConfig, protocol: Json): Json = {
    // The client binary of the run's harness: the protocol's, which a
    // re-judge of a Codex run with no report carries (issue #239).
    val harness = protocol.hcursor.get[String]("harness").toOption.flatMap(Harness.parse(_).toOption).getOrElse(cfg.harness)
    protocol.deepMerge(Json.obj(
      "arm"         -> cfg.arm.name.asJson,
      "parallelism" -> cfg.parallelism.asJson,
      (if (harness == Harness.Codex) "codexBin" else "claudeBin") -> (if (harness == Harness.Codex) cfg.codexBin else cfg.claudeBin).asJson,
      "resume"      -> cfg.resume.asJson,
      "gates"       -> Vector("preservation", "escape", "holes", "typecheck", "isolation").asJson
    ))
  }

  /** The config block of a re-judge: the run's own, stamped with the judge's
    * `safe` and the time.  The arm stays the run's: each subject is audited
    * under the arm its own record names, whatever `--arm` the operator
    * passed (the Makefile's default is `mcp`), so the operator's arm is
    * stamped only on an archive made before the arm existed, which records
    * none and was the `mcp` arm (issue #188 found three re-judged shell-arm
    * reports relabeled `mcp` by the earlier stamp).
    */
  def rejudgedConfig(prev: Json, cfg: AgentBenchConfig, at: String): Json = {
    val arm = prev.hcursor.get[String]("arm").toOption.getOrElse(cfg.arm.name)
    prev.deepMerge(Json.obj("arm" -> arm.asJson, "safe" -> cfg.safe.asJson, "rejudgedAt" -> at.asJson))
  }

  /** Write the three files and print the summary. */
  def write(
    cfg:            AgentBenchConfig,
    entries:        Vector[IndexEntry],
    driven:         Vector[Judged],
    corpora:        Json,
    protocol:       Json,
    previousConfig: Option[Json],
    prices:         PriceTable
  ): IO[Unit] = {
    val layout   = cfg.layout
    val outcomes = driven.map(_.outcome)
    val strata   = outcomes.map(_.stratum).distinct
    val now      = java.time.Instant.now().toString
    val config   = previousConfig match {
      case Some(prev) if cfg.rejudge => rejudgedConfig(prev, cfg, now)
      // A re-judge of a Codex run that never wrote its report: its protocol,
      // stamped as any re-judge's config is (issue #239).
      case None if cfg.rejudge && protocol.hcursor.get[String]("harness").toOption.contains(Harness.Codex.name) =>
        rejudgedConfig(builtConfig(cfg, protocol), cfg, now)
      case _                         => builtConfig(cfg, protocol)
    }
    val noClient = config.hcursor.get[String]("harness").toOption.contains(Harness.Codex.name)
    val report = Json.obj(
      "schemaVersion" -> "agent-bench-report.v0".asJson,
      "runId"         -> cfg.runId.asJson,
      "timestamp"     -> java.time.Instant.now().toString.asJson,
      "rejudged"      -> cfg.rejudge.asJson,
      "config"        -> config,
      "corpora"       -> corpora,
      "pricing"       -> pricing(outcomes, prices, config.hcursor.get[String]("harness").getOrElse(Harness.Claude.name)),
      "obligations"   -> entries.size.asJson,
      "totals"        -> block(outcomes, noClient),
      "perTier"       -> Json.obj(tiers.map(t => t -> block(outcomes.filter(_.entry.difficulty.tag == t), noClient)): _*),
      "perStratum"    -> Json.obj(strata.map(s => s -> block(outcomes.filter(_.stratum == s), noClient)): _*),
      "perTool"       -> Json.obj(perTool(outcomes).map { case (n, k) => n -> k.asJson }: _*),
      "perShell"      -> Json.obj(perShell(outcomes).map { case (n, k) => n -> k.asJson }: _*),
      "perVia"        -> Json.obj(perVia(outcomes, _.via).map { case (n, k) => n -> k.asJson }: _*),
      "perVerdictVia" -> Json.obj(perVia(outcomes, _.verdictVia).map { case (n, k) => n -> k.asJson }: _*),
      "outcomes"      -> Json.arr(outcomes.map(_.toJson): _*)
    ).dropNullValues
    for {
      _ <- Scaffold.writeJsonl(layout.results, driven.flatMap(_.attempts).map(_.toJson))
      _ <- Scaffold.writeJsonl(layout.fixtures, driven.map(_.fixtureRow))
      _ <- TextIO.write(layout.report, report.spaces2)
      _ <- IO.println(summarize(cfg, config, endpointOf(config), outcomes, prices))
      _ <- IO.println(s">> wrote ${layout.report}")
    } yield ()
  }

  /** The base URL a report's config names, when the run had one (issue #237). */
  private def endpointOf(config: Json): Option[String] =
    config.hcursor.downField("endpoint").get[String](Endpoint.baseUrlVar).toOption.filter(_ != Endpoint.absent)

  private def summarize(cfg: AgentBenchConfig, config: Json, endpoint: Option[String], outcomes: Vector[Outcome], prices: PriceTable): String = {
    val c       = config.hcursor
    val arm     = c.get[String]("arm").getOrElse(cfg.arm.name)
    // The harness, its version, and the effort, from the run's own record
    // (issue #239), so a re-judge prints them too; a Claude run prints as before.
    val harness = c.get[String]("harness").toOption.fold("")(h =>
                    s"harness=$h ${c.get[String]("harnessVersion").getOrElse("?")} effort=${c.get[String]("effort").getOrElse("?")} ")
    def cost(sel: Vector[Outcome]): String =
      if (clientless(sel, c.get[String]("harness").toOption.contains(Harness.Codex.name))) "-" else f"$$${sel.flatMap(_.costUsd).sum}%.2f"
    def line(label: String, sel: Vector[Outcome]) =
      f"$label%-26s ${sel.count(_.solved)}%2d/${sel.size}%-2d solved  ${sel.count(_.restated)}%2d restated  ${originalInView(sel).fold("-")(_.toString)}%2s original in view  ${sel.count(_.anomaly.isDefined)}%2d anomaly  turns=${sel.map(_.turns).sum}%4d calls=${sel.map(_.toolCallsTotal).sum}%4d cost=${cost(sel)} priced=$$${pricedTotal(sel).usd.toDouble}%.2f${pricedTotal(sel).unpricedRows match { case 0 => ""; case n => s" (+$n unpriced)" }}"
    val byTier    = tiers.map(t => line(t, outcomes.filter(_.entry.difficulty.tag == t)))
    val byStratum = outcomes.map(_.stratum).distinct.map(s => line(s, outcomes.filter(_.stratum == s)))
    val tools     = perTool(outcomes).map { case (n, k) => s"$n=$k" }.mkString(" ")
    val shell     = perShell(outcomes).map { case (n, k) => s"$n=$k" }.mkString(" ")
    val via       = perVia(outcomes, _.via).map { case (n, k) => s"$n=$k" }.mkString(" ")
    val verdict   = perVia(outcomes, _.verdictVia).map { case (n, k) => s"$n=$k" }.mkString(" ")
    val unpriced  = outcomes.flatMap(_.priced.models).distinct
    val bases     = outcomes.flatMap(_.usageByModel.flatMap(_.costBasis)).distinct.sorted
    s"""
       |== agent-bench (${harness}arm=$arm model=${cfg.model.getOrElse("?")}${endpoint.fold("")(u => s" endpoint=$u")} turns=${cfg.maxTurns} wall=${cfg.wallCapSec}s budget=${cfg.maxBudgetUsd} safe=${cfg.safe}) ==
       |${byTier.mkString("\n")}
       |${byStratum.mkString("\n")}
       |${line("total", outcomes)}
       |tools: $tools
       |shell: ${if (shell.isEmpty) "(none)" else shell}
       |via:   ${if (via.isEmpty) "(none)" else via}   verdict via: ${if (verdict.isEmpty) "(none)" else verdict}
       |priced at ${prices.path} (${prices.asOf})${if (unpriced.isEmpty) "" else s"; no price for ${unpriced.mkString(", ")}"}; the client's cost basis: ${if (bases.isEmpty) "(none reported)" else bases.mkString(", ")}
       |""".stripMargin
  }
}
