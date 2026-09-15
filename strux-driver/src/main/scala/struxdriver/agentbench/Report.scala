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
  *  corpora, obligations, totals, perTier, perStratum, perTool, outcomes),
  *  `results.jsonl` (one eval-proof-completion.v0 row per fill_hole probe),
  *  `fixtures.jsonl` (one per obligation), and the console summary.  The
  *  config block records the protocol (every cap and client flag, the
  *  prompts' digests, the client version; Protocol.scala) and the run's own
  *  knobs; a re-judge carries the run's own config and corpora blocks
  *  forward, since it is not told them again.
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

  /** The counters for one slice of outcomes (a tier, a stratum, the run). */
  private def block(sel: Vector[Outcome]): Json = {
    val gates = sel.flatMap(_.gate.map(_.gate))
    Json.obj(
      "total"     -> sel.size.asJson,
      "solved"    -> sel.count(_.solved).asJson,
      "restated"  -> sel.count(_.restated).asJson,
      "gates"     -> Json.obj(gates.distinct.sorted.map(g => g -> gates.count(_ == g).asJson): _*),
      "anomalies" -> sel.count(_.anomaly.isDefined).asJson,
      "turns"     -> sel.map(_.turns).sum.asJson,
      "toolCalls" -> sel.map(_.toolCallsTotal).sum.asJson,
      "wallMs"    -> sel.map(_.wallMs).sum.asJson,
      "costUsd"   -> Scaffold.round3(sel.map(_.costUsd).sum).asJson
    )
  }

  /** Calls per tool over the run, most-called first. */
  private def perTool(outcomes: Vector[Outcome]): Vector[(String, Int)] = {
    val all = outcomes.flatMap(_.toolCalls)
    all.map(_._1).distinct.map(n => n -> all.filter(_._1 == n).map(_._2).sum).sortBy { case (n, k) => (-k, n) }
  }

  /** The config block of a fresh run: the protocol (Protocol.of, every knob
    * a subject sees and the judge applies) plus what only this run of it
    * chose (parallelism, the client binary, resume) and the gate names.
    */
  private def builtConfig(cfg: AgentBenchConfig, version: String, sysP: String, userT: String): Json =
    Protocol.of(cfg, version, sysP, userT).deepMerge(Json.obj(
      "parallelism" -> cfg.parallelism.asJson,
      "claudeBin"   -> cfg.claudeBin.asJson,
      "resume"      -> cfg.resume.asJson,
      "gates"       -> Vector("preservation", "escape", "holes", "typecheck", "isolation").asJson
    ))

  /** Write the three files and print the summary. */
  def write(
    cfg:            AgentBenchConfig,
    entries:        Vector[IndexEntry],
    driven:         Vector[Judged],
    corpora:        Json,
    version:        String,
    sysP:           String,
    userT:          String,
    previousConfig: Option[Json]
  ): IO[Unit] = {
    val layout   = cfg.layout
    val outcomes = driven.map(_.outcome)
    val strata   = outcomes.map(_.stratum).distinct
    val config   = previousConfig match {
      case Some(prev) if cfg.rejudge =>
        prev.deepMerge(Json.obj("safe" -> cfg.safe.asJson, "rejudgedAt" -> java.time.Instant.now().toString.asJson))
      case _ => builtConfig(cfg, version, sysP, userT)
    }
    val report = Json.obj(
      "schemaVersion" -> "agent-bench-report.v0".asJson,
      "runId"         -> cfg.runId.asJson,
      "timestamp"     -> java.time.Instant.now().toString.asJson,
      "rejudged"      -> cfg.rejudge.asJson,
      "config"        -> config,
      "corpora"       -> corpora,
      "obligations"   -> entries.size.asJson,
      "totals"        -> block(outcomes),
      "perTier"       -> Json.obj(tiers.map(t => t -> block(outcomes.filter(_.entry.difficulty.tag == t))): _*),
      "perStratum"    -> Json.obj(strata.map(s => s -> block(outcomes.filter(_.stratum == s))): _*),
      "perTool"       -> Json.obj(perTool(outcomes).map { case (n, k) => n -> k.asJson }: _*),
      "outcomes"      -> Json.arr(outcomes.map(_.toJson): _*)
    ).dropNullValues
    for {
      _ <- Scaffold.writeJsonl(layout.results, driven.flatMap(_.attempts).map(_.toJson))
      _ <- Scaffold.writeJsonl(layout.fixtures, driven.map(_.fixtureRow))
      _ <- TextIO.write(layout.report, report.spaces2)
      _ <- IO.println(summarize(cfg, outcomes))
      _ <- IO.println(s">> wrote ${layout.report}")
    } yield ()
  }

  private def summarize(cfg: AgentBenchConfig, outcomes: Vector[Outcome]): String = {
    def line(label: String, sel: Vector[Outcome]) =
      f"$label%-26s ${sel.count(_.solved)}%2d/${sel.size}%-2d solved  ${sel.count(_.restated)}%2d restated  ${sel.count(_.anomaly.isDefined)}%2d anomaly  turns=${sel.map(_.turns).sum}%4d calls=${sel.map(_.toolCallsTotal).sum}%4d cost=$$${sel.map(_.costUsd).sum}%.2f"
    val byTier    = tiers.map(t => line(t, outcomes.filter(_.entry.difficulty.tag == t)))
    val byStratum = outcomes.map(_.stratum).distinct.map(s => line(s, outcomes.filter(_.stratum == s)))
    val tools     = perTool(outcomes).map { case (n, k) => s"$n=$k" }.mkString(" ")
    s"""
       |== agent-bench (model=${cfg.model.getOrElse("?")} turns=${cfg.maxTurns} wall=${cfg.wallCapSec}s budget=${cfg.maxBudgetUsd} safe=${cfg.safe}) ==
       |${byTier.mkString("\n")}
       |${byStratum.mkString("\n")}
       |${line("total", outcomes)}
       |tools: $tools
       |""".stripMargin
  }
}
