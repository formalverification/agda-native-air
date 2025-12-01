/** ============================================================================
 *  AgdaSimplifiedExtractor.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/extract/AgdaSimplifiedExtractor.scala
 *  Package: proofparser.extract
 *
 *  Purpose
 *  -------
 *  A small, robust, CLI-friendly program that:
 *
 *    1. Launches `agda --interaction-json` (via AgdaBridge)
 *    2. Sends a "load" command (IOTCM / Cmd_load) for one or more `.agda` files
 *    3. Listens for JSON messages and harvests "AllGoalsWarnings" to produce
 *       *goal examples* as canonical `AgdaData` JSONL rows.
 *
 *  Each row is a canonical schema element:
 *
 *    AgdaData(
 *      file      : String                // file name
 *      module    : Option[String]        // module name, if found
 *      name      : String                // synthetic goal name (e.g. "MyModule.goal_0")
 *      agdaType  : Option[String]        // goal type
 *      proof     : Option[String]        // None (there is no proof yet)
 *      premises  : List[String]          // Nil (no deps yet)
 *      declKind  : DeclKind              // inferred via Semantic.from
 *      astSize   : Int                   // cheap size from type text
 *    )
 *
 *  Context in Project
 *  ------------------
 *  - Lives in the `proofparser.extract` package, alongside:
 *      * AgdaBridge.scala        : process I/O for Agda
 *      * AgdaExtractor.scala     : regex-only, no Agda process
 *      * Agda2TrainTransformer   : JSON → training rows
 *  - Emits canonical `AgdaData` so that downstream tools (stats, filters,
 *    ML pipelines) can treat goal examples just like any other dataset.
 *
 *  Design Goals
 *  ------------
 *  - Observability: optional verbose logging (`--verbose`) shows send/recv lines.
 *  - Robustness   : tolerate non-JSON lines, timeouts, and IO failures via `Either`.
 *  - Modularity   : all Agda protocol details isolated here.
 *  - Purity       : core logic is referentially transparent; side effects explicit.
 *
 *  JSON Protocol Notes (Agda --interaction-json)
 *  ---------------------------------------------
 *  - We look for messages satisfying:
 *
 *        AgdaMsgs.isAllGoals(js) == true
 *
 *    which typically means:
 *
 *      { "kind": "DisplayInfo",
 *        "payload": {
 *          "info": {
 *            "kind": "AllGoalsWarnings",
 *            "payload": { "goals": [ ... ] }
 *          }
 *        }
 *      }
 *
 *  Usage
 *  -----
 *      runMain proofparser.extract.AgdaSimplifiedExtractor <agda-file-or-dir> <out.jsonl>
 *         [--include DIR]* [--lib LIB]* [--library-file FILE]
 *         [--mode NonInteractive|Direct] [--empty-is-null]
 *         [--verbose] [--timeout-ms N]
 *
 *  Example
 *  -------
 *  From inside the `agda-ai-prver/proof-parser` directory, enter the following command:
 *
 *      sbt "runMain proofparser.extract.AgdaSimplifiedExtractor \
 *        ../agda-jang/agda output/goals.jsonl \
 *        --include ../agda-jang/agda --lib standard-library \
 *        --library-file ../agda-jang/agda/libraries \
 *        --dump-raw-goals output/raw-goals --verbose"
 *
 *  ============================================================================
 */

package proofparser.extract

import java.io.PrintWriter
import java.nio.file.{Files, Path, Paths}
import java.time.Instant

import scala.jdk.CollectionConverters._
import scala.util.Try

import upickle.default._

import proofparser.schema.{AgdaData, AgdaDataOps, SemanticInfo, DeclKind}
import proofparser.schema.Semantic

/* -----------------------------
 * Lightweight logger
 * -----------------------------
 * No external deps; stderr so logs don’t mix with JSONL on stdout.
 */
private final case class Logger(verbose: Boolean) {
  def info(msg: => String): Unit  = if (verbose) Console.err.println(s"[info] $msg")
  def send(msg: => String): Unit  = if (verbose) Console.err.println(s"[send] $msg")
  def recv(msg: => String): Unit  = if (verbose) Console.err.println(s"[recv] $msg")
  def warn(msg: => String): Unit  = Console.err.println(s"[warn] $msg")
  def err (msg: => String): Unit  = Console.err.println(s"[error] $msg")
}

/* -----------------------------
 * CLI configuration
 * -----------------------------
 */
private final case class Config(
  root:        Path,
  out:         Path,
  includes:    List[String],
  libs:        List[String],
  libraryFile: Option[String],
  mode:        String,     // "NonInteractive" | "Direct"
  emptyIsNull: Boolean,    // true => first payload cell is null; false => ""
  verbose:     Boolean,
  timeoutMs:   Long,
  dumpRawDir:  Option[Path]   // NEW: where to write raw AllGoalsWarnings
)

object AgdaSimplifiedExtractor {

  // ===========================================================================
  // Filesystem helpers
  // ===========================================================================

  /** A path is an Agda file if it’s a regular file that ends with ".agda". */
  private def isAgda(p: Path): Boolean =
    Files.isRegularFile(p) && p.getFileName.toString.endsWith(".agda")

  /** Collect all .agda files under a directory, or the file itself if root is a file. */
  private def agdaFiles(root: Path): List[Path] =
    if (Files.isDirectory(root))
      Files.walk(root).iterator().asScala.filter(isAgda).toList
    else if (isAgda(root)) List(root)
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

  // ===========================================================================
  // Agda JSON protocol builders (IOTCM / Cmd_load)
  // ===========================================================================

  /**
   * Build the IOTCM / Cmd_load command.
   *
   * payload[0] : editor id (often "" or null; toggled via `emptyIsNull`)
   * payload[1] : capabilities (often [])
   * payload[2] : mode string ("NonInteractive" or "Direct")
   * payload[3] : Cmd_load object
   *
   * NOTE:
   *   - Only `-i` and `-l` belong in Cmd_load args.
   *   - `--library-file` MUST be passed to the Agda process itself
   *     (handled by AgdaBridge construction).
   */
  private def iotcmLoad(
    file: String,
    include: Seq[String],
    libs: Seq[String],
    mode: String,
    emptyIsNull: Boolean
  ): ujson.Value = {
    val incArgs  = include.flatMap(i => Seq("-i", i))
    val libArgs  = libs.flatMap(l => Seq("-l", l))
    val args     = incArgs ++ libArgs
    val headCell = if (emptyIsNull) ujson.Null else ujson.Str("")
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

  // ===========================================================================
  // Input loop & parsing helpers
  // ===========================================================================

  /** True if a line looks like JSON (starts with '{' or '['). */
  private def isJsonLine(s: String): Boolean =
    s.nonEmpty && (s.charAt(0) == '{' || s.charAt(0) == '[')

  /**
   * Read lines until the predicate holds (or timeout/EOF).
   * Non-JSON lines are logged (prompts, diagnostics) and skipped.
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
    var done     = false
    var result   = Option.empty[ujson.Value]

    while (!done && Instant.now().isBefore(deadline)) {
      bridge.readLine() match {
        case Left(e) =>
          return Left(e)
        case Right(None) =>
          // EOF
          done = true
        case Right(Some(line)) =>
          if (isJsonLine(line)) {
            log.recv(line)
            val js = ujson.read(line)
            if (pred(js)) {
              result = Some(js)
              done   = true
            }
          } else {
            // Non-JSON prompt/diagnostic; keep looping.
            log.recv(line)
          }
      }
    }

    Right(result)
  }

  /**
   * Convert an AllGoalsWarnings message into canonical AgdaData rows.
   *
   * Each goal becomes:
   *
   *   AgdaData(
   *     file      = <file name>,
   *     module    = Some(moduleName),
   *     name      = s"$moduleName.goal_<idx>",
   *     agdaType  = Some(goalType),
   *     proof     = None,
   *     premises  = Nil,
   *     declKind  = Semantic.from(...).kind,
   *     astSize   = Semantic.from(...).astSize
   *   )
   */
  private def extractGoalsAsAgdaData(
    msg: ujson.Value,
    file: Path,
    module: String,
    log: Logger
  ): List[AgdaData] = {
    // Match shape:
    //   payload.info.kind == "AllGoalsWarnings"
    //   payload.info.payload.goals :: Arr
    val payloadOpt =
      for {
        payload <- msg.obj.get("payload")
        info    <- payload.obj.get("info")
        if info("kind").strOpt.contains("AllGoalsWarnings")
        body    <- info.obj.get("payload")
      } yield body

    payloadOpt.toList.flatMap { body =>
      body.obj.get("goals") match {
        case Some(ujson.Arr(items)) =>
          items.toList.zipWithIndex.flatMap { case (g, idx) =>
            val gtype = g.obj.get("type").flatMap(_.strOpt).getOrElse("").trim
            if (gtype.nonEmpty) {
              val name = s"$module.goal_$idx"
              val agdaTypeOpt = Some(gtype)
              val proofOpt: Option[String] = None

              val sem: SemanticInfo =
                Semantic.from(
                  name     = name,
                  agdaType = agdaTypeOpt,
                  module   = Some(module),
                  proof    = proofOpt
                )

              val raw = AgdaData(
                file     = file.getFileName.toString,
                module   = Some(module),
                name     = name,
                agdaType = agdaTypeOpt,
                proof    = proofOpt,
                premises = Nil,
                declKind = sem.kind,
                astSize  = sem.astSize
              )

              List(AgdaDataOps.normalize(raw))
            } else {
              Nil
            }
          }

        case _ =>
          log.info("AllGoalsWarnings without structured 'goals' array; skipping.")
          Nil
      }
    }
  }

  // ===========================================================================
  // One-file orchestration
  // ===========================================================================

  /**
   * Run Agda on a single file: start bridge, send load, wait for AllGoalsWarnings, stop;
   * Updated: so that when we *do* get an `AllGoalsWarnings` message, we also
   *   + call `dumpRawGoals` (if configured),
   *   + log a summary in verbose mode.
   */
  private def runOnFile(
    file: Path,
    cfg:  Config,
    log:  Logger
  ): Either[String, List[AgdaData]] = {
    val bridge =
      cfg.libraryFile match {
        case Some(path) =>
          new AgdaBridge(Seq("agda", "--interaction-json", "--library-file", path))
        case None =>
          new AgdaBridge()
      }

    for {
      _      <- bridge.start()
      _      <- {
        val js   = iotcmLoad(file.toString, cfg.includes, cfg.libs, cfg.mode, cfg.emptyIsNull)
        val line = ujson.write(js)
        log.send(line)
        bridge.send(line)
      }
      msgOpt <- readUntil(bridge, log, cfg.timeoutMs)(AgdaMsgs.isAllGoals)
    } yield {
      bridge.stop()

      val modName = moduleName(file)

      // NEW: dump raw JSON if requested
      msgOpt.foreach(js => dumpRawGoals(cfg, file, js, log))

      val rows = msgOpt.toList.flatMap(js => extractGoalsAsAgdaData(js, file, modName, log))

      // NEW: richer verbose output
      if (cfg.verbose) {
        logGoalSummary(file, rows, log)
      }

      rows
    }
  }

  // ===========================================================================
  // CLI parsing & main
  // ===========================================================================

  private def parseArgs(args: Array[String]): Either[String, Config] = {
    if (args.length < 2) {
      Left(
        "Usage: AgdaSimplifiedExtractor <agda-file-or-dir> <out.jsonl> " +
          "[--include DIR]* [--lib LIB]* [--library-file FILE] " +
          "[--mode NonInteractive|Direct] [--empty-is-null] [--verbose] " +
          "[--timeout-ms N] [--dump-raw-goals DIR]"
      )
    } else {
      val root = Paths.get(args(0)).toAbsolutePath.normalize()
      val out  = Paths.get(args(1)).toAbsolutePath.normalize()

      var includes    = List.empty[String]
      var libs        = List.empty[String]
      var libraryFile = Option.empty[String]
      var mode        = "NonInteractive"
      var emptyIsNull = false
      var verbose     = false
      var timeoutMs   = 10000L
      var dumpRawDir  = Option.empty[Path]     // NEW

      var i = 2
      while (i < args.length) {
        args(i) match {
          case "--include" if i + 1 < args.length =>
            includes :+= Paths.get(args(i + 1)).toAbsolutePath.normalize().toString
            i += 2

          case "--lib" if i + 1 < args.length =>
            libs :+= args(i + 1)
            i += 2

          case "--library-file" if i + 1 < args.length =>
            libraryFile = Some(Paths.get(args(i + 1)).toAbsolutePath.normalize().toString)
            i += 2

          case "--mode" if i + 1 < args.length =>
            mode = args(i + 1)
            i += 2

          case "--empty-is-null" =>
            emptyIsNull = true
            i += 1

          case "--verbose" =>
            verbose = true
            i += 1

          case "--timeout-ms" if i + 1 < args.length =>
            Try(args(i + 1).toLong).toOption.foreach(v => timeoutMs = v)
            i += 2

          // NEW: directory to dump raw AllGoalsWarnings JSON for each file
          case "--dump-raw-goals" if i + 1 < args.length =>
            dumpRawDir = Some(Paths.get(args(i + 1)).toAbsolutePath.normalize())
            i += 2

          case other =>
            Console.err.println(s"[warn] Unrecognized option: $other")
            i += 1
       }
      }

      Right(
        Config(
          root        = root,
          out         = out,
          includes    = includes,
          libs        = libs,
          libraryFile = libraryFile,
          mode        = mode,
          emptyIsNull = emptyIsNull,
          verbose     = verbose,
          timeoutMs   = timeoutMs,
          dumpRawDir  = dumpRawDir
        )
      )
    }
  }


  // ==========================================================
  // Helpers: dumping & logging
  // ==========================================================

  /** Helper: dump raw `AllGoalsWarnings` per file
   * Write the raw AllGoalsWarnings JSON for a file, if requested. */
  private def dumpRawGoals(
    cfg:   Config,
    file:  Path,
    js:    ujson.Value,
    log:   Logger
  ): Unit = {
    cfg.dumpRawDir.foreach { dir =>
      try {
        Files.createDirectories(dir)
        val stem   = file.getFileName.toString.stripSuffix(".agda")
        val out    = dir.resolve(s"$stem.all-goals.json")
        val writer = new PrintWriter(out.toFile, "UTF-8")
        try {
          writer.println(ujson.write(js, indent = 2))
        } finally writer.close()
        log.info(s"Wrote raw AllGoalsWarnings for $stem to $out")
      } catch {
        case e: Throwable =>
          log.warn(s"Failed to write raw goals JSON for $file: ${e.getMessage}")
      }
    }
  }

  /** Helper: richer verbose goal summary
   * In verbose mode, print a summary of goals for a file. */
  private def logGoalSummary(
    file: Path,
    rows: List[AgdaData],
    log:  Logger
  ): Unit = {
    if (rows.nonEmpty) {
      log.info(s"${file.getFileName.toString}: ${rows.size} goal(s)")
      rows.foreach { r =>
        val tpe       = r.agdaType.getOrElse("<no type>")
        val maxWidth  = 120
        val shortType =
          if (tpe.length <= maxWidth) tpe
          else tpe.take(maxWidth - 3) + "..."
        log.info(s"  ${r.name} : $shortType")
      }
    } else {
      log.info(s"${file.getFileName.toString}: no goals")
    }
  }



  // ===========================================================================
  // Main entrypoint
  // ==========================================================================

  /** Entrypoint: parse args, discover files, talk to Agda, and write AgdaData JSONL. */
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

        val all: List[AgdaData] =
          inputs.flatMap { p =>
            runOnFile(p, cfg, log) match {
              case Left(e) =>
                log.err(s"${p.toString}: $e")
                Nil
              case Right(rows) =>
                if (rows.nonEmpty) log.info(s"${p.getFileName}: extracted ${rows.size} goal(s).")
                else log.warn(s"${p.getFileName}: no structured goals found.")
                rows
            }
          }

        // Write JSONL
        val parent = Option(cfg.out.getParent).getOrElse(cfg.out.toAbsolutePath.getParent)
        if (parent != null) Files.createDirectories(parent)

        val w  = Files.newBufferedWriter(cfg.out)
        val pw = new java.io.PrintWriter(w)
        try {
          all.foreach { r => pw.println(write(r)) }
          pw.flush()
        } finally {
          pw.close()
        }

        println(s"wrote ${all.size} examples to ${cfg.out.toAbsolutePath}")
    }
  }
}
