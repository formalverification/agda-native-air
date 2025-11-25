/** ============================================================================
 *  AgdaSimplifiedExtractor.scala
 *  --------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/AgdaSimplifiedExtractor.scala
 *  Package: proofparser
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
 *
 *  Purpose
 *  -------
 *  A small, robust, CLI-friendly program that:
 *
 *  1.  Launches `agda --interaction-json` (via AgdaBridge)
 *  2.  Sends a "load" command (IOTCM / Cmd_load) for one or more `.agda` files
 *  3.  Listens for JSON messages and harvests "AllGoalsWarnings" to produce
 *      training examples (goal type + local context) as JSONL rows.
 *
 *  Context in Project
 *  ------------------
 *  -  Lives in the `proofparser` package alongside:
 *     * AgdaBridge.scala        : process I/O (line-in/line-out) for Agda
 *     * AgdaJsonParser.scala    : (not required here) shared parsing helpers
 *     * Agda2TrainTransformer   : transforms other JSON into training rows
 *     * Model.scala / SimpleSchema.scala : data models + schema helpers
 *  -  The extractor emits `TrainRecord` rows---a compact, line-oriented format
 *     that downstream ETL/training code can consume directly (e.g., Spark or
 *     Python trainers). This keeps the end-to-end ML pipeline observable and
 *     diffable in git.
 *
 *  Design Goals
 *  ------------
 *  -  **Observability**: optional verbose logging (`--verbose`) prints what we
 *     send and what we receive (JSON vs non-JSON), so debugging is fast.
 *  -  **Robustness**: tolerate non-JSON lines (e.g., "JSON> ...") without
 *     crashing; use timeouts to avoid indefinite hangs; on the happy path,
 *     we do not throw stuff---we return `Either[String, A]` instead.
 *  -  **Protocol agility**: small CLI toggles (`--mode`, `--empty-is-null`)
 *     let us probe protocol shape differences across Agda builds (2.6–2.8+)
 *     without rewriting code. If local Agda expects slightly different IOTCM
 *     payloads, we can tweak the builder in one place.
 *  -  **Modularity**: each step is a small helper---easy to test in isolation.
 *  -  **No hidden global state**: all state lives in local vals; side effects
 *     (I/O) are explicit.
 *
 *  JSON Protocol Notes (Agda --interaction-json)
 *  -----------------------
 *  -  Many Agda builds accept a load of the form:
 *
 *        { "command":"IOTCM"
 *        , "payload":[ "", [], "NonInteractive"
 *          , { "command":"Cmd_load"
 *            , "file":".../Foo.agda"
 *            , "args":["-i","/path/include","-l","standard-library"] } ] }
 *
 *     Some builds are picky about the **first payload cell** (empty string vs
 *     null) and/or **mode** ("NonInteractive" vs "Direct"). We expose both via
 *     flags so we can try variants without editing code.
 *
 *  -  Library resolution:
 *
 *     *  `--library-file PATH` must be passed to the **Agda process**, not
 *        inside `Cmd_load`. We therefore attach it when starting the bridge.
 *        (This matches Agda’s CLI contract.)
 *
 *  Usage
 *  -----
 *      runMain proofparser.AgdaSimplifiedExtractor <agda-file-or-dir> <out.jsonl>
 *         [--include DIR]* [--lib LIB]* [--library-file FILE]
 *         [--mode NonInteractive|Direct] [--empty-is-null]
 *         [--verbose] [--timeout-ms N]
 *
 *  Examples (from proof-parser/)
 *  --------
 *      sbt "runMain proofparser.AgdaSimplifiedExtractor \
 *           ../agda-jang/agda/ApplyDemo.agda \
 *           ../proof-parser/output/goals.jsonl \
 *           --include ../agda-jang/agda \
 *           --lib standard-library \
 *           --library-file ../agda-jang/agda/libraries \
 *           --verbose"
 *
 *      # Protocol probes whether current Agda version rejects the default:
 *      sbt "runMain proofparser.AgdaSimplifiedExtractor ... --mode Direct --verbose"
 *      sbt "runMain proofparser.AgdaSimplifiedExtractor ... --empty-is-null --verbose"
 *      sbt "runMain proofparser.AgdaSimplifiedExtractor ... --mode Direct --empty-is-null --verbose"
 *
 *  Error Handling Philosophy
 *  -------------------------
 *  -  Prefer `Either[String, A]` over throwing. The main aggregates errors and
 *     prints actionable messages.
 *  -  Only the CLI `main` uses `sys.exit(code)` after printing a single line.
 *
 *  Testing Tips
 *  ------------
 *  -  Unit test the pure helpers (`moduleName`, `iotcmLoad`, `extractGoalsPretty`)
 *     with canned inputs.
 *  -  Use `--verbose` and small timeouts in integration tests to keep runs fast.
 *
 *  Extension Points
 *  ----------------
 *  -  Want decl-specific records? Thread the declaration name into records
 *     when Agda exposes it in messages (or parse from pretty text heuristically).
 *  -  Need more message kinds (e.g., solved metas)? Add recognizers to AgdaMsgs.
 *
 * ==========================================================================
 */

package proofparser

import java.nio.file.{Files, Path, Paths}
import java.time.{Duration, Instant}
import scala.jdk.CollectionConverters._
import scala.util.Try
import upickle.default._


/* -----------------------------
 * Lightweight logger
 * -----------------------------
 * No external deps; stderr so logs don’t mix with JSONL on stdout.
 */
private final case class Logger(verbose: Boolean) {
  def info(msg: => String): Unit  = if (verbose) Console.err.println(s"[info] $msg")
  def send(js:  => String): Unit  = if (verbose) Console.err.println(s"[send] $js")
  def recv(line: => String): Unit = if (verbose) Console.err.println(s"[recv] $line")
  def warn(msg: => String): Unit  = Console.err.println(s"[warn] $msg")
  def err (msg: => String): Unit  = Console.err.println(s"[error] $msg")
}


/* -----------------------------
 * Data model (rows we emit)
 * -----------------------------
 * Keep this tiny and stable; downstream code depends on it.
 */
// final case class CtxVar(name: String, tpe: String)
// object CtxVar { implicit val rw: ReadWriter[CtxVar] = macroRW }

// final case class TrainRecord(
//   file:     String,               // e.g., "ApplyDemo.agda"
//   module:   String,               // best-effort module name (or file base)
//   decl:     String,               // top-level declaration (best-effort for now)
//   context:  List[CtxVar],         // telescope: x : A, ...
//   goalType: String,               // pretty goal type
//   solution: Option[String],       // unused in this extractor (future: solved terms)
//   range:    Option[String],       // unused (future: source spans)
//   imports:  List[String]          // unused (future: visible imports)
// )
// object TrainRecord { implicit val rw: ReadWriter[TrainRecord] = macroRW }


/* -----------------------------
 * CLI configuration
 * -----------------------------
 */
private final case class Config(
  root:         Path,
  out:          Path,
  includes:     List[String],
  libs:         List[String],
  libraryFile:  Option[String],
  mode:         String,        // "NonInteractive" or "Direct"
  emptyIsNull:  Boolean,       // true => first payload cell is null; false => ""
  verbose:      Boolean,
  timeoutMs:    Long
)


object AgdaSimplifiedExtractor {

  /* ===========================
   * Filesystem helpers
   * ===========================
   */

  /** A path is an Agda file if it’s a regular file that ends with ".agda". */
  private def isAgda(p: Path): Boolean =
    Files.isRegularFile(p) && p.getFileName.toString.endsWith(".agda")

  /** Collect all .agda files under a directory, or the file itself if root is a file. */
  private def agdaFiles(root: Path): List[Path] =
    if (Files.isDirectory(root))
      Files.walk(root).iterator().asScala.filter(isAgda).toList
    else if (Files.isRegularFile(root) && isAgda(root)) List(root)
    else Nil

  /** Best-effort module name: try "module X where" in the file; fallback to file base. */
  private def moduleName(p: Path): String = {
    val fname = p.getFileName.toString.stripSuffix(".agda")
    Try {
      val lines = Files.readAllLines(p).asScala.take(100).mkString("\n")
      val rx = "(?m)^\\s*module\\s+([A-Za-z0-9_'.]+)\\s+where\\b".r
      rx.findFirstMatchIn(lines).map(_.group(1)).getOrElse(fname)
    }.getOrElse(fname)
  }

  /** Write JSONL atomically-enough for our purpose (single writer). */
  private def writeJsonl(records: List[TrainRecord], out: Path, log: Logger): Either[String, Unit] =
    Try {
      val parent = Option(out.getParent).getOrElse(out.toAbsolutePath.getParent)
      if (parent != null) Files.createDirectories(parent)
      val w  = java.nio.file.Files.newBufferedWriter(out)
      val pw = new java.io.PrintWriter(w)
      try { records.foreach(r => pw.println(write(r))); pw.flush() }
      finally pw.close()
      log.info(s"wrote ${records.length} examples to $out")
    }.toEither.left.map(_.getMessage)


  /* ===========================
   * Agda JSON protocol builders
   * ===========================
   */

  /**
   * Build the IOTCM / Cmd_load command.
   *
   * Protocol slots:
   *   payload[0] : editor id (often "" or null; toggle via `emptyIsNull`)
   *   payload[1] : ignored / capabilities (often [])
   *   payload[2] : mode string ("NonInteractive" or "Direct")
   *   payload[3] : object with "command":"Cmd_load", "file":..., "args":[...]
   *
   * Only `-i` and `-l` belong in Cmd_load args. `--library-file` MUST be passed
   * to the Agda process at startup (handled by AgdaBridge construction).
   */
  private def iotcmLoad(
    file: String,
    include: Seq[String],
    libs: Seq[String],
    mode: String,          // "NonInteractive" | "Direct"
    emptyIsNull: Boolean   // true => send null at payload[0]; else ""
  ): ujson.Value = {
    val incArgs = include.flatMap(i => Seq("-i", i))
    val libArgs = libs.flatMap(l => Seq("-l", l))
    val args    = incArgs ++ libArgs
    val headCell: ujson.Value = if (emptyIsNull) ujson.Null else ujson.Str("")
    ujson.Obj(
      "command" -> "IOTCM",
      "payload" -> ujson.Arr(
        headCell, ujson.Arr(), mode,
        ujson.Obj(
          "command" -> "Cmd_load",
          "file"    -> file,
          "args"    -> ujson.Arr(args.map(ujson.Str): _*)
        )
      )
    )
  }


  /* ===========================
   * Input loop & parsing helpers
   * ===========================
   */

  /** True if a line looks like JSON (starts with '{' or '['). */
  private def isJsonLine(s: String): Boolean =
    s.nonEmpty && (s.charAt(0) == '{' || s.charAt(0) == '[')

  /**
   * Read lines until the predicate holds (or timeout/EOF). Non-JSON lines are
   * logged (so we see prompts like "JSON> ...") and skipped.
   *
   * @return Right(Some(json)) when a matching message is seen;
   *         Right(None) on timeout/EOF; Left(error) on I/O failure.
   */
  private def readUntil(
    bridge: AgdaBridge,
    log: Logger,
    timeoutMs: Long
  )(pred: ujson.Value => Boolean): Either[String, Option[ujson.Value]] = {
    val deadline = Instant.now().plusMillis(timeoutMs)
    while (Instant.now().isBefore(deadline)) {
      bridge.readLine() match {
        case Left(e)       => return Left(e)
        case Right(None)   => return Right(None) // EOF
        case Right(Some(l)) =>
          if (isJsonLine(l)) {
            log.recv(l)
            val js = ujson.read(l)
            if (pred(js)) return Right(Some(js))
          } else {
            log.recv(l) // non-JSON (prompt/diagnostic) — keep waiting
          }
      }
    }
    Right(None) // timeout
  }

  /**
   * Convert an AllGoalsWarnings message into TrainRecord rows.
   * If the build does not provide structured "goals", we return an empty list.
   */
  private def extractGoalsPretty(
    msg: ujson.Value,
    file: Path,
    module: String,
    log: Logger
  ): List[TrainRecord] = {
    val payloadOpt =
      for {
        info <- msg("payload").obj.get("info")
        if info("kind").strOpt.contains("AllGoalsWarnings")
        body <- info.obj.get("payload")
      } yield body

    payloadOpt.toList.flatMap { body =>
      body.obj.get("goals") match {
        case Some(ujson.Arr(items)) =>
          items.toList.flatMap { g =>
            val gtype = g.obj.get("type").flatMap(_.strOpt).getOrElse("")
            val ctx   = g.obj.get("context").toList.flatMap {
              case ujson.Arr(ctxItems) =>
                ctxItems.toList.flatMap { it =>
                  val nm = it.obj.get("name").flatMap(_.strOpt)
                  val tp = it.obj.get("type").flatMap(_.strOpt).orElse(it.obj.get("type").map(_.render()))
                  (nm, tp) match {
                    case (Some(n), Some(t)) => Some(CtxVar(n, t))
                    case _                  => None
                  }
                }
              case _ => Nil
            }
            if (gtype.nonEmpty)
              List(TrainRecord(
                file     = file.getFileName.toString,
                module   = module,
                decl     = module,           // future: pick the exact enclosing decl name
                context  = ctx,
                goalType = gtype,
                solution = None,
                range    = None,
                imports  = Nil
              ))
            else Nil
          }

        case _ =>
          log.info("AllGoalsWarnings without structured 'goals' array; skipping.")
          Nil
      }
    }
  }


  /* ===========================
   * One-file orchestration
   * ===========================
   */

  /**
   * Run Agda on a single file: start bridge, send load, wait for goals, stop.
   */
  private def runOnFile(
    file: Path,
    cfg: Config,
    log: Logger
  ): Either[String, List[TrainRecord]] = {
    // Build process command (attach --library-file at process level if provided).
    val bridge =
      cfg.libraryFile match {
        case Some(path) => new AgdaBridge(Seq("agda", "--interaction-json", "--library-file", path))
        case None       => new AgdaBridge()
      }

    for {
      _ <- bridge.start()
      _ <- {
        val js   = iotcmLoad(file.toString, cfg.includes, cfg.libs, cfg.mode, cfg.emptyIsNull)
        val line = ujson.write(js)
        log.send(line)
        bridge.send(line)
      }
      got <- readUntil(bridge, log, cfg.timeoutMs)(AgdaMsgs.isAllGoals)
      _ = bridge.stop()
    } yield got.toList.flatMap(js => extractGoalsPretty(js, file, moduleName(file), log))
  }


  /* ===========================
   * CLI parsing & main
   * ===========================
   */

  private def parseArgs(args: Array[String]): Either[String, Config] = {
    if (args.length < 2)
      Left(
        "Usage: AgdaSimplifiedExtractor <agda-file-or-dir> <out.jsonl> " +
        "[--include DIR]* [--lib LIB]* [--library-file FILE] " +
        "[--mode NonInteractive|Direct] [--empty-is-null] [--verbose] [--timeout-ms N]"
      )
    else {
      val root = Paths.get(args(0)).toAbsolutePath.normalize()
      val out  = Paths.get(args(1)).toAbsolutePath.normalize()

      var includes    = List.empty[String]
      var libs        = List.empty[String]
      var libraryFile = Option.empty[String]
      var mode        = "NonInteractive"
      var emptyIsNull = false
      var verbose     = false
      var timeoutMs   = 10000L

      var i = 2
      while (i < args.length) {
        args(i) match {
          case "--include" if i+1 < args.length =>
            includes :+= Paths.get(args(i+1)).toAbsolutePath.normalize().toString; i += 2
          case "--lib" if i+1 < args.length =>
            libs :+= args(i+1); i += 2
          case "--library-file" if i+1 < args.length =>
            libraryFile = Some(Paths.get(args(i+1)).toAbsolutePath.normalize().toString); i += 2
          case "--mode" if i+1 < args.length =>
            mode = args(i+1); i += 2
          case "--empty-is-null" =>
            emptyIsNull = true; i += 1
          case "--verbose" =>
            verbose = true; i += 1
          case "--timeout-ms" if i+1 < args.length =>
            Try(args(i+1).toLong).toOption.foreach(v => timeoutMs = v); i += 2
          case other =>
            Console.err.println(s"[warn] Unrecognized option: $other"); i += 1
        }
      }

      Right(Config(root, out, includes, libs, libraryFile, mode, emptyIsNull, verbose, timeoutMs))
    }
  }

  /** Entrypoint: parse args, find files, run Agda, and write JSONL. */
  def main(args: Array[String]): Unit = {
    parseArgs(args) match {
      case Left(msg) =>
        Console.err.println(msg)
        sys.exit(1)

      case Right(cfg) =>
        val log = Logger(cfg.verbose)

        val inputs = agdaFiles(cfg.root)
        if (inputs.isEmpty) {
          Console.err.println(s"[error] No .agda files under: ${cfg.root}")
          sys.exit(2)
        }
        log.info(s"Discovered ${inputs.size} file(s).")

        val all: List[TrainRecord] =
          inputs.flatMap { p =>
            runOnFile(p, cfg, log) match {
              case Left(e) =>
                log.err(s"${p.toString}: $e"); Nil
              case Right(rs) =>
                if (rs.nonEmpty) log.info(s"${p.getFileName}: extracted ${rs.size} goal(s).")
                else log.warn(s"${p.getFileName}: no structured goals found.")
                rs
            }
          }

        writeJsonl(all, cfg.out, log) match {
          case Left(e) =>
            Console.err.println(s"[error] Failed to write JSONL: $e"); sys.exit(3)
          case Right(_) =>
            // concise success on stdout; verbose already logged above
            println(s"wrote ${all.size} examples to ${cfg.out}")
        }
    }
  }
}
