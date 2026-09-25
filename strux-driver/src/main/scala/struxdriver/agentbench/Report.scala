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
  *  corpora, obligations, totals, perTier, perStratum, perTool, perShell,
  *  perVia, outcomes),
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
  private def block(sel: Vector[Outcome]): Json = {
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
      "costUsd"   -> Scaffold.round3(sel.map(_.costUsd).sum).asJson
    )
  }

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
  private def builtConfig(cfg: AgentBenchConfig, protocol: Json): Json =
    protocol.deepMerge(Json.obj(
      "arm"         -> cfg.arm.name.asJson,
      "parallelism" -> cfg.parallelism.asJson,
      "claudeBin"   -> cfg.claudeBin.asJson,
      "resume"      -> cfg.resume.asJson,
      "gates"       -> Vector("preservation", "escape", "holes", "typecheck", "isolation").asJson
    ))

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
    previousConfig: Option[Json]
  ): IO[Unit] = {
    val layout   = cfg.layout
    val outcomes = driven.map(_.outcome)
    val strata   = outcomes.map(_.stratum).distinct
    val config   = previousConfig match {
      case Some(prev) if cfg.rejudge => rejudgedConfig(prev, cfg, java.time.Instant.now().toString)
      case _                         => builtConfig(cfg, protocol)
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
      "perShell"      -> Json.obj(perShell(outcomes).map { case (n, k) => n -> k.asJson }: _*),
      "perVia"        -> Json.obj(perVia(outcomes, _.via).map { case (n, k) => n -> k.asJson }: _*),
      "perVerdictVia" -> Json.obj(perVia(outcomes, _.verdictVia).map { case (n, k) => n -> k.asJson }: _*),
      "outcomes"      -> Json.arr(outcomes.map(_.toJson): _*)
    ).dropNullValues
    for {
      _ <- Scaffold.writeJsonl(layout.results, driven.flatMap(_.attempts).map(_.toJson))
      _ <- Scaffold.writeJsonl(layout.fixtures, driven.map(_.fixtureRow))
      _ <- TextIO.write(layout.report, report.spaces2)
      _ <- IO.println(summarize(cfg, config.hcursor.get[String]("arm").getOrElse(cfg.arm.name), outcomes))
      _ <- IO.println(s">> wrote ${layout.report}")
    } yield ()
  }

  private def summarize(cfg: AgentBenchConfig, arm: String, outcomes: Vector[Outcome]): String = {
    def line(label: String, sel: Vector[Outcome]) =
      f"$label%-26s ${sel.count(_.solved)}%2d/${sel.size}%-2d solved  ${sel.count(_.restated)}%2d restated  ${originalInView(sel).fold("-")(_.toString)}%2s original in view  ${sel.count(_.anomaly.isDefined)}%2d anomaly  turns=${sel.map(_.turns).sum}%4d calls=${sel.map(_.toolCallsTotal).sum}%4d cost=$$${sel.map(_.costUsd).sum}%.2f"
    val byTier    = tiers.map(t => line(t, outcomes.filter(_.entry.difficulty.tag == t)))
    val byStratum = outcomes.map(_.stratum).distinct.map(s => line(s, outcomes.filter(_.stratum == s)))
    val tools     = perTool(outcomes).map { case (n, k) => s"$n=$k" }.mkString(" ")
    val shell     = perShell(outcomes).map { case (n, k) => s"$n=$k" }.mkString(" ")
    val via       = perVia(outcomes, _.via).map { case (n, k) => s"$n=$k" }.mkString(" ")
    val verdict   = perVia(outcomes, _.verdictVia).map { case (n, k) => s"$n=$k" }.mkString(" ")
    s"""
       |== agent-bench (arm=$arm model=${cfg.model.getOrElse("?")} turns=${cfg.maxTurns} wall=${cfg.wallCapSec}s budget=${cfg.maxBudgetUsd} safe=${cfg.safe}) ==
       |${byTier.mkString("\n")}
       |${byStratum.mkString("\n")}
       |${line("total", outcomes)}
       |tools: $tools
       |shell: ${if (shell.isEmpty) "(none)" else shell}
       |via:   ${if (via.isEmpty) "(none)" else via}   verdict via: ${if (verdict.isEmpty) "(none)" else verdict}
       |""".stripMargin
  }
}
