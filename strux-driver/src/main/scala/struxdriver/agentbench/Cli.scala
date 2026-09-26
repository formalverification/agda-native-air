/** ============================================================================
  *  Cli.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Cli.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  The agent bench's configuration and its argument parser (issue #154):
  *  the caps, the paths, the model, the corpora, the arm (issue #162: which
  *  instrument the subjects get), the tools the server exposes (issue #191:
  *  `--expose`, a subset of the server's surface), and the two modes that need less
  *  (`--rejudge`) or skip archived work (`--resume`).  Parsing is strict
  *  in the LoopHarness style: unknown flags are refused by name, exactly one
  *  of `--ids` and `--all` is required, and an `--ids` that names nothing is
  *  refused at once rather than an hour into a sweep.  Pinned by
  *  AgentBenchCliSpec.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import java.nio.file.{Path, Paths}

import struxdriver.search.Scaffold

final case class AgentBenchConfig(
  index:           Path,
  ids:             Option[Set[String]],
  arm:             Arm,
  expose:          Option[Vector[String]],
  outDir:          Path,
  runId:           String,
  projectRoot:     Path,
  serverBin:       Option[Path],
  serverTimeout:   Int,
  agdaFlags:       String,
  model:           Option[String],
  maxTurns:        Int,
  wallCapSec:      Int,
  maxBudgetUsd:    BigDecimal,
  parallelism:     Int,
  safe:            Boolean,
  persistSessions: Boolean,
  claudeBin:       String,
  corpusStdlib:    Option[Path],
  corpusAlgebras:  Option[Path],
  agdaJsonBin:     Option[Path],
  rejudge:         Boolean,
  resume:          Boolean
) {
  def layout: RunLayout = RunLayout(outDir.resolve(runId))

  /** The flags every Agda of the protocol runs with: the subjects' servers,
    * the harness's own server that stages the work copies and answers the
    * judge, and the verifier's `agda` (Judge.typecheck adds the same flag
    * itself).  `--safe` joins them whenever the judge is safe, so the
    * `check_file` verdict a subject sees is the judge's.
    */
  def serverAgdaFlags: String = if (safe) agdaFlags + " --safe" else agdaFlags
}

object Cli {

  val usage: String =
    """usage: runMain struxdriver.agentbench.AgentBench
      |    --index PATH              benchmark-index.jsonl (relative: from --project-root, as every input path)
      |    (--ids id1,id2 | --all)   exactly one
      |    --out-dir PATH            run roots land here
      |    --run-id STR              the run directory name (a new protocol is a new run id)
      |    [--arm shell|mcp|both]    which instrument the subjects get (default mcp: the archived protocol)
      |    [--expose t1,t2,...]      the agda tools the subjects' servers present (default: all); an arm with the server only
      |    --project-root PATH       repo root: the server's cwd; index paths resolve here
      |    --server-bin PATH         the agda-mcp binary (the subjects' servers, and the harness's own that stages and judges)
      |    --agda-json-bin PATH      the agda-strux extractor, for the judge's body references
      |    --model STR               the subject model, e.g. claude-sonnet-5
      |    --corpus-stdlib PATH      the agda-stdlib corpus, served to agda-stdlib rows
      |    --corpus-algebras PATH    the agda-algebras corpus, served to agda-algebras rows
      |    [--max-turns N]           per-subject turn cap (default 30)
      |    [--wall-cap N]            per-subject wall cap, seconds (default 900)
      |    [--max-budget-usd D]      per-subject cost cap (default 3.00)
      |    [--parallelism N]         subjects at once (default 1; wall clocks are indicative only above 1)
      |    [--safe on|off]           the subjects' servers and the judge run with --safe (default on: every committed gold passes under it)
      |    [--persist-sessions on|off]  let the client write its session to disk (default off)
      |    [--claude-bin PATH]       the claude CLI (default: claude on PATH)
      |    [--agda-flags STR]        default: the committed .mcp.json flag set
      |    [--server-timeout N]      per-Agda-call bound, seconds (default 600)
      |    [--rejudge]               re-judge an existing run root from subjects/ with its own prompts; no model call (the server and the extractor are still needed)
      |    [--resume on|off]         keep the archived, non-anomalous subjects of this run id and run only the rest (default off); refused when the run id's recorded protocol differs
      |""".stripMargin

  private val known = Set("index", "ids", "out-dir", "run-id", "project-root", "server-bin", "model", "corpus-stdlib",
    "corpus-algebras", "max-turns", "wall-cap", "max-budget-usd", "parallelism", "safe", "persist-sessions",
    "claude-bin", "agda-flags", "server-timeout", "resume", "agda-json-bin", "arm", "expose")

  def parse(args: List[String]): Either[String, AgentBenchConfig] = {
    @annotation.tailrec
    def go(rest: List[String], m: Map[String, String]): Either[String, Map[String, String]] =
      rest match {
        case Nil                                                            => Right(m)
        case "--all" :: xs                                                  => go(xs, m + ("all" -> "true"))
        case "--rejudge" :: xs                                              => go(xs, m + ("rejudge" -> "true"))
        case flag :: v :: xs if flag.startsWith("--") && known(flag.drop(2)) => go(xs, m + (flag.drop(2) -> v))
        case other :: _                                                     => Left(s"unrecognized argument: $other")
      }
    def intOf(m: Map[String, String], key: String, dflt: Int, min: Int): Either[String, Int] =
      m.get(key).fold[Either[String, Int]](Right(dflt))(s => s.toIntOption.filter(_ >= min).toRight(s"bad --$key: $s"))
    def onOff(m: Map[String, String], key: String, dflt: Boolean): Either[String, Boolean] =
      m.get(key).fold[Either[String, Boolean]](Right(dflt)) {
        case "on"  => Right(true)
        case "off" => Right(false)
        case other => Left(s"bad --$key: $other (on|off)")
      }
    for {
      m       <- go(args, Map.empty)
      rejudge  = m.contains("rejudge")
      ix      <- m.get("index").toRight("missing --index")
      out     <- m.get("out-dir").toRight("missing --out-dir")
      runId   <- m.get("run-id").toRight("missing --run-id")
      root    <- m.get("project-root").toRight("missing --project-root")
      ids      = m.get("ids").map(_.split(",").map(_.trim).filter(_.nonEmpty).toSet)
      // Exactly one selection, and a non-empty one: `--ids` beside `--all`
      // would silently run the subset, and `--ids ""` would fail an hour
      // later as "no obligations matched" (Copilot on PR #158).
      _       <- (ids, m.contains("all")) match {
                   case (Some(s), false) if s.nonEmpty => Right(())
                   case (Some(_), false)               => Left("--ids names no obligation")
                   case (None, true)                   => Right(())
                   case _                              => Left("pass exactly one of --ids and --all")
                 }
      rootAbs  = Paths.get(root).toAbsolutePath.normalize
      abs      = (p: String) => { val q = Paths.get(p); if (q.isAbsolute) q else rootAbs.resolve(q).normalize }
      // A re-judge reads the archive and calls no model, so it needs neither
      // the model nor the corpora; the server and the extractor answer the
      // judge in both modes.
      required = (key: String) => if (rejudge) Right(m.get(key)) else m.get(key).map(Option(_)).toRight(s"missing --$key")
      bin     <- m.get("server-bin").map(abs).map(Option(_)).toRight("missing --server-bin")
      json    <- m.get("agda-json-bin").map(abs).map(Option(_)).toRight("missing --agda-json-bin")
      model   <- required("model")
      cs      <- required("corpus-stdlib").map(_.map(abs))
      ca      <- required("corpus-algebras").map(_.map(abs))
      turns   <- intOf(m, "max-turns", 30, 1)
      wall    <- intOf(m, "wall-cap", 900, 1)
      par     <- intOf(m, "parallelism", 1, 1)
      tmo     <- intOf(m, "server-timeout", 600, 1)
      budget  <- m.get("max-budget-usd").fold[Either[String, BigDecimal]](Right(BigDecimal("3.00")))(s =>
                   scala.util.Try(BigDecimal(s)).toOption.filter(_ > 0).toRight(s"bad --max-budget-usd: $s"))
      safe    <- onOff(m, "safe", true)
      persist <- onOff(m, "persist-sessions", false)
      resume  <- onOff(m, "resume", false)
      arm     <- m.get("arm").fold[Either[String, Arm]](Right(Arm.default))(Arm.parse)
      expose  <- m.get("expose").fold[Either[String, Option[Vector[String]]]](Right(None))(s => exposeOf(s, arm).map(Some(_)))
    } yield AgentBenchConfig(
      index           = abs(ix),
      ids             = ids,
      arm             = arm,
      expose          = expose,
      outDir          = Paths.get(out).toAbsolutePath.normalize,
      runId           = runId,
      projectRoot     = rootAbs,
      serverBin       = bin,
      serverTimeout   = tmo,
      agdaFlags       = m.getOrElse("agda-flags", Scaffold.defaultAgdaFlags),
      model           = model,
      maxTurns        = turns,
      wallCapSec      = wall,
      maxBudgetUsd    = budget,
      parallelism     = par,
      safe            = safe,
      persistSessions = persist,
      claudeBin       = m.getOrElse("claude-bin", "claude"),
      corpusStdlib    = cs,
      corpusAlgebras  = ca,
      agdaJsonBin     = json,
      rejudge         = rejudge,
      resume          = resume
    )
  }

  /** The `--expose` list (issue #191): bare tool names, each one the server
    * registers with a corpus, on an arm that has the server.  Refused by name
    * otherwise, since a typo would run an arm on a surface nobody asked for
    * (the server refuses it too, but only once a subject has spawned).
    */
  private def exposeOf(s: String, arm: Arm): Either[String, Vector[String]] = {
    val names   = s.split(",").map(_.trim).filter(_.nonEmpty).toVector.distinct
    val unknown = names.filterNot(Subject.serverTools.contains)
    if (!arm.hasServer) Left(s"--expose needs an arm with the server, not ${arm.name}")
    else if (names.isEmpty) Left("--expose names no tool")
    else if (unknown.nonEmpty) Left(s"--expose names tools the server does not have: ${unknown.mkString(", ")}")
    else Right(names)
  }
}
