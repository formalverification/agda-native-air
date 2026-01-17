/** ============================================================================
  *  AgdaJsonlDriver.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: proof-parser/src/main/scala/proofparser/extract/AgdaJsonlDriver.scala
  *  Package: proofparser.extract
  *
  *  Purpose
  *  -------
  *  The "real-run" driver that scales:
  *
  *    modules list  -->  per-module agda-json invocation  -->  per-module JSONL
  *                      + validation + logs + manifest
  *
  *  Key constraint / philosophy
  *  ---------------------------
  *  We do NOT re-implement Agda parsing in Scala. We delegate parsing/typechecking
  *  to the Haskell backend `agda-json` (which runs Agda-as-a-library), and use
  *  Scala + Spark for orchestration, resumability, and large-scale downstream ETL.
  *
  *  Practical reality about Spark
  *  -----------------------------
  *  Running external processes is inherently effectful, and Spark executors are
  *  distributed JVMs. We encapsulate effects in IO and evaluate them at the Spark
  *  boundary (inside mapPartitions). This keeps the majority of the code pure/total,
  *  and makes side-effects explicit and isolated.
  *
  *  Filters
  *  -------
  *  IMPORTANT: We only run TOP-LEVEL modules (no nested submodules).
  *  That is: keep module names with NO '.' characters.
  *
  *  Outputs
  *  -------
  *    <outDir>/jsonl/<Module>.jsonl
  *    <outDir>/logs/<Module>.log
  *    <outDir>/run-manifest.json
  *
  *  ============================================================================
  */

package proofparser.extract

import cats.effect.{ExitCode, IO, IOApp}
import cats.effect.implicits._
import cats.effect.unsafe.implicits.global
import cats.syntax.all._

import fs2.Stream

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths}
import java.time.Instant

import org.apache.spark.sql.{Dataset, Encoder, Encoders, SparkSession}

import scala.collection.JavaConverters._
import scala.collection.mutable

import upickle.default._

object AgdaJsonlDriver extends IOApp {

  // ---------------------------------------------------------------------------
  // Manifest model (uPickle)
  // ---------------------------------------------------------------------------

  final case class ModuleRun(
    module: String,
    inputFile: String,
    outputFile: String,
    logFile: String,
    skipped: Boolean,
    ok: Boolean,
    exitCode: Option[Int],
    seconds: Double,
    rows: Long,
    validateOk: Boolean,
    validateErrors: Vector[String]
  )

  private object Log {
    private val fmt = java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
    private def ts: String =
      java.time.ZonedDateTime.now().format(fmt)

    def info(s: String): IO[Unit] =
      IO.println(s"${ts} - $s")
  }

  object ModuleRun {
    // Custom writer to avoid uPickle Option encoding ([] / [n]).
    // Policy: omit "exitCode" when None; write a number when Some(n).
    implicit val rw: ReadWriter[ModuleRun] =
      upickle.default.readwriter[ujson.Value].bimap[ModuleRun](
        r => {
          val fields = mutable.LinkedHashMap.empty[String, ujson.Value]
          fields += "module"         -> ujson.Str(r.module)
          fields += "inputFile"      -> ujson.Str(r.inputFile)
          fields += "outputFile"     -> ujson.Str(r.outputFile)
          fields += "logFile"        -> ujson.Str(r.logFile)
          fields += "skipped"        -> ujson.Bool(r.skipped)
          fields += "ok"             -> ujson.Bool(r.ok)
          r.exitCode.foreach(ec => fields += "exitCode" -> ujson.Num(ec))
          fields += "seconds"        -> ujson.Num(r.seconds)
          fields += "rows"           -> ujson.Num(r.rows.toDouble)
          fields += "validateOk"     -> ujson.Bool(r.validateOk)
          fields += "validateErrors" -> ujson.Arr(r.validateErrors.map(ujson.Str(_)))
          ujson.Obj.from(fields)
        },
        json => {
          val o = json.obj
          def str(k: String): String = o(k).str
          def bool(k: String): Boolean = o(k).bool
          def numDouble(k: String): Double = o(k).num
          def numLong(k: String): Long = o(k).num.toLong
          def optInt(k: String): Option[Int] = o.get(k).map(_.num.toInt)
          def vecStr(k: String): Vector[String] =
            o.get(k).map(_.arr.toVector.map(_.str)).getOrElse(Vector.empty)

          ModuleRun(
            module         = str("module"),
            inputFile      = str("inputFile"),
            outputFile     = str("outputFile"),
            logFile        = str("logFile"),
            skipped        = bool("skipped"),
            ok             = bool("ok"),
            exitCode       = optInt("exitCode"),
            seconds        = numDouble("seconds"),
            rows           = numLong("rows"),
            validateOk     = bool("validateOk"),
            validateErrors = vecStr("validateErrors")
          )
        }
      )
  }

  final case class RunManifest(
    startedAt: String,
    finishedAt: String,
    projectRoot: String,
    agdaDir: String,
    srcDir: String,
    modulesFile: String,
    outDir: String,
    agdaJsonBin: String,
    parallelism: Int,
    resume: Boolean,
    runner: String,
    sparkMaster: String,
    failOnError: Boolean
  ) extends Serializable

  object RunManifest { implicit val rw: ReadWriter[RunManifest] = macroRW }

  // ---------------------------------------------------------------------------
  // Config
  // ---------------------------------------------------------------------------

  sealed trait Runner { def asString: String }
  object Runner {
    case object Spark extends Runner { val asString = "spark" }
    case object Local extends Runner { val asString = "local" }
    case object Spark2 extends Runner { val asString = "spark2" }

    def parse(s: String): Option[Runner] =
      s.trim.toLowerCase match {
        case "spark" => Some(Spark)
        case "local" => Some(Local)
        case "spark2" => Some(Spark2)
        case _       => None
      }
  }

  final case class Config(
    projectRoot: Path,
    agdaDir: Path,
    srcDir: Path,
    modulesFile: Path,
    outDir: Path,
    agdaJsonBin: Path,
    parallelism: Int,
    resume: Boolean,
    runner: Runner,
    sparkMaster: String,
    failOnError : Boolean = true,
    jsonlFormat: String = "full"
  )

  final case class ConfigData(
    projectRoot: String,
    agdaDir: String,
    srcDir: String,
    modulesFile: String,
    outDir: String,
    agdaJsonBin: String,
    parallelism: Int,
    resume: Boolean,
    sparkMaster: String,
    failOnError : Boolean,
    jsonlFormat: String
  ) extends Serializable

  private def toData(c: Config): ConfigData =
    ConfigData(
      c.projectRoot.toString,
      c.agdaDir.toString,
      c.srcDir.toString,
      c.modulesFile.toString,
      c.outDir.toString,
      c.agdaJsonBin.toString,
      c.parallelism,
      c.resume,
      c.sparkMaster,
      c.failOnError,
      c.jsonlFormat
    )

  private def fromData(d: ConfigData): Config =
    Config(
      Paths.get(d.projectRoot),
      Paths.get(d.agdaDir),
      Paths.get(d.srcDir),
      Paths.get(d.modulesFile),
      Paths.get(d.outDir),
      Paths.get(d.agdaJsonBin),
      d.parallelism,
      d.resume,
      runner = Runner.Spark, // only used inside Spark executors; not read there
      sparkMaster = d.sparkMaster,
      failOnError = d.failOnError,
      jsonlFormat = d.jsonlFormat
    )

  private val usage: String =
    """Usage:
      |  runMain proofparser.extract.AgdaJsonlDriver \
      |    --project-root <repo-root> \
      |    --agda-dir     <repo-root>/agda-jang/agda \
      |    --src-dir      <path-to-library-src> \
      |    --modules-file <everything-modules.txt> \
      |    --out-dir      <out-dir> \
      |    --agda-json    <path-to-agda-json-exe> \
      |    [--parallelism N] [--no-resume]
      |    [--runner spark|local|spark2]
      |    [--spark-master local[*]]
      |    [--fail-on-error true|false]
      |    [--format full|human] [--human]
      |
      |""".stripMargin

  private def parseArgs(args: List[String]): Either[String, Config] = {
    // simple, boring parser (no cats)
    def next(i: Int): Either[String, String] =
      args.lift(i + 1).toRight(s"Missing value after ${args(i)}\n\n${usage}")

    def normBool(s: String): Option[String] =
      s.toLowerCase match {
        case "true" | "1" | "yes" | "y"  => Some("true")
        case "false" | "0" | "no" | "n"  => Some("false")
        case _                           => None
      }

    var i = 0
    var m = Map.empty[String, String]
    while (i < args.length) {
      args(i) match {
        case "--human" =>
          m = m.updated("format", "human")
          i += 1
        case "--format" =>
          next(i) match {
            case Left(e) => return Left(e)
            case Right(v) =>
              val vv = v.trim.toLowerCase
              vv match {
                case "full" | "human" =>
                  m = m.updated("format", vv)
                  i += 2
                case _ =>
                  return Left(s"[AgdaJsonlDriver]  ❌ Bad value for --format: $v (use full|human)\n\n${usage}")
              }
          }
        case "--no-resume" =>
          m = m.updated("resume", "false")
          i += 1

        case "--fail-on-error" =>
          next(i) match {
            case Left(e) => return Left(e)
            case Right(v) =>
              normBool(v) match {
                case Some(b) =>
                  m = m.updated("fail-on-error", b)
                  i += 2
                case None =>
                  return Left(s"[AgdaJsonlDriver] ❌ Bad value for --fail-on-error: $v (use true/false)\n\n${usage}")
              }
          }

        case "--project-root" | "--agda-dir" | "--src-dir" | "--modules-file" | "--out-dir" | "--agda-json"
            | "--parallelism" | "--runner" | "--spark-master" =>
          val k = args(i).drop(2)
          next(i) match {
            case Left(e)  => return Left(e)
            case Right(v) => m = m.updated(k, v); i += 2
          }

        case bad =>
          return Left(s"[AgdaJsonlDriver] ❌ Unrecognized arg: $bad\n\n${usage}")
      }
    }

    def req(k: String): Either[String, String] =
      m.get(k).toRight(s"Missing --$k\n\n${usage}")

    val failOnError: Boolean =
      m.get("fail-on-error").forall(_ == "true") // default true; we normalize values above

    for {
      pr  <- req("project-root")
      ad  <- req("agda-dir")
      sd  <- req("src-dir")
      mf  <- req("modules-file")
      od  <- req("out-dir")
      bin <- req("agda-json")
    } yield {
      val par =
        m.get("parallelism").flatMap(s => scala.util.Try(s.toInt).toOption)
          .getOrElse(Runtime.getRuntime.availableProcessors())

      val resume = m.get("resume").forall(_ != "false")

      val runner =
        m.get("runner").flatMap(Runner.parse).getOrElse(Runner.Spark)

      val sparkMaster =
        m.get("spark-master")
          .orElse(sys.env.get("SPARK_MASTER"))
          .getOrElse("local[*]")

      Config(
        projectRoot = Paths.get(pr).toAbsolutePath.normalize(),
        agdaDir     = Paths.get(ad).toAbsolutePath.normalize(),
        srcDir      = Paths.get(sd).toAbsolutePath.normalize(),
        modulesFile = Paths.get(mf).toAbsolutePath.normalize(),
        outDir      = Paths.get(od).toAbsolutePath.normalize(),
        agdaJsonBin = Paths.get(bin).toAbsolutePath.normalize(),
        parallelism = par,
        resume      = resume,
        runner      = runner,
        sparkMaster = sparkMaster,
        failOnError = failOnError,
        jsonlFormat = m.get("format").getOrElse("full")
      )
    }
  }

  // ---------------------------------------------------------------------------
  // Module discovery
  // ---------------------------------------------------------------------------

  private def readModules(modulesFile: Path): IO[Vector[String]] =
    IO.blocking {
      Files.readAllLines(modulesFile, StandardCharsets.UTF_8).asScala.toVector
        .map(_.trim)
        .filter(s => s.nonEmpty && !s.startsWith("#"))
        // .filterNot(_.contains(".")) // TOP-LEVEL only
        .distinct
        .sorted
    }

  private def modPath(mod: String): String =
    mod.replace('.', java.io.File.separatorChar)

  private def moduleToInput(srcDir: Path, mod: String): Path =
    srcDir.resolve(modPath(mod) + ".agda")

  private def moduleToOutJsonl(outDir: Path, mod: String): Path =
    outDir.resolve("jsonl").resolve(modPath(mod) + ".jsonl")

  private def moduleToLog(outDir: Path, mod: String): Path =
    outDir.resolve("logs").resolve(modPath(mod) + ".log")

  // ---------------------------------------------------------------------------
  // One-module run
  // ---------------------------------------------------------------------------

  private def runOne(cfg: Config, mod: String): IO[ModuleRun] = {
    val input = moduleToInput(cfg.srcDir, mod)
    val out   = moduleToOutJsonl(cfg.outDir, mod)
    val log   = moduleToLog(cfg.outDir, mod)

    val ensureDirs: IO[Unit] =
      IO.blocking {
        Files.createDirectories(out.getParent)
        Files.createDirectories(log.getParent)
      }

    val resumeCheck: IO[Option[ModuleRun]] =
      if (!cfg.resume) IO.pure(None)
      else
        IO.blocking(Files.exists(out)).attempt.flatMap {
          case Right(true) =>
            JsonlValidate.validateFile(out).attempt.map {
              case Right(v) if v.ok =>
                Some(
                  ModuleRun(
                    module = mod,
                    inputFile = input.toString,
                    outputFile = out.toString,
                    logFile = log.toString,
                    skipped = true,
                    ok = true,
                    exitCode = None,
                    seconds = 0.0,
                    rows = v.rows,
                    validateOk = v.ok,
                    validateErrors = v.errors
                  )
                )
              case _ => None
            }
          case _ => IO.pure(None)
        }

    def missingInput: ModuleRun =
      ModuleRun(
        module = mod,
        inputFile = input.toString,
        outputFile = out.toString,
        logFile = log.toString,
        skipped = false,
        ok = false,
        exitCode = None,
        seconds = 0.0,
        rows = 0L,
        validateOk = false,
        validateErrors = Vector(s"missing input file: $input")
      )

    val runBackend: IO[ModuleRun] = {
      val cmd = {
        val base = Seq(
          cfg.agdaJsonBin.toString,
          "--input", input.toString,
          "--output", out.toString,
          "--include", cfg.srcDir.toString
        )
        if (cfg.jsonlFormat == "human") base :+ "--human" else base
      }

      val env = Map("AGDA_DIR" -> cfg.agdaDir.toString)

      for {
        exec <- Proc.runLogged(cmd, cwd = cfg.projectRoot, env = env, logFile = log)
        v    <- if (exec.exitCode == 0) JsonlValidate.validateFile(out)
                else IO.pure(JsonlValidate.Result(false, 0L, Vector(s"exit_code=${exec.exitCode}")))
        ok    = exec.exitCode == 0 && v.ok
      } yield
        ModuleRun(
          module = mod,
          inputFile = input.toString,
          outputFile = out.toString,
          logFile = log.toString,
          skipped = false,
          ok = ok,
          exitCode = Some(exec.exitCode),
          seconds = exec.seconds,
          rows = v.rows,
          validateOk = v.ok,
          validateErrors = v.errors
        )
    }

    for {
      _    <- ensureDirs
      skip <- resumeCheck
      res  <- skip match {
                case Some(r) => IO.pure(r)
                case None =>
                  IO.blocking(Files.exists(input)).flatMap {
                    case false => IO.pure(missingInput)
                    case true  => runBackend
                  }
              }
    } yield res
  }

  // ---------------------------------------------------------------------------
  // Local bounded-parallel runner (non-Spark)
  // ---------------------------------------------------------------------------

  // private def runLocally(cfg: Config, modules: Vector[String]): IO[Vector[ModuleRun]] =
  //   modules.parTraverseN(cfg.parallelism)(m => runOne(cfg, m))
  private def runLocally(cfg: Config, modules: Vector[String]): IO[Vector[ModuleRun]] =
    Stream
      .emits(modules)
      .covary[IO]
      .parEvalMapUnordered(cfg.parallelism) { m =>
        val input = moduleToInput(cfg.srcDir, m)
        Log.info(s"> Checking $m ($input).") *>
          runOne(cfg, m).flatTap { r =>
            val status =
              if (r.ok) s"[AgdaJsonlDriver] ✅ [success] wrote ${r.rows} JSON records to ${r.outputFile}"
              else      s"[AgdaJsonlDriver] ❌ [failure] exit=${r.exitCode.getOrElse(-1)} log=${r.logFile}"
            Log.info(status)
          }
      }
      .compile
      .toVector

  // ---------------------------------------------------------------------------
  // Spark runner
  // ---------------------------------------------------------------------------
  // Chunk size for processing modules within Spark partitions.
  // Balances memory usage (smaller chunks) vs. resource management overhead
  // (larger chunks allow better batching of IO operations).
  // This is a reasonable default; if needed, it could be made configurable
  // via the Config object for runtime tuning based on deployment requirements.
  private val SparkPartitionChunkSize = 10

  // NOTE: This implementation uses Spark for distributed execution across
  // partitions. Within each partition, modules are processed in chunks using
  // parTraverse which provides proper resource management and error handling via
  // cats-effect IO. The unsafeRunSync() call is made once per chunk (not per
  // module), which balances memory usage with resource management. This provides
  // better resource management than calling unsafeRunSync() individually for each
  // module while avoiding loading entire partitions into memory.
  // ---------------------------------------------------------------------------

  implicit val encRun: Encoder[ModuleRun] = Encoders.product[ModuleRun]

  private def mkSpark(appName: String, master: String, addOpens: Option[String]): SparkSession = {
    val b =
      SparkSession.builder()
        .appName(appName)
        .config("spark.master", master)
        .config("spark.ui.enabled", "false")

    // These are *often* what fixes JDK17 module-access issues in Spark/Netty
    // even when JAVA_TOOL_OPTIONS doesn't propagate.
    val b2 = addOpens match {
      case Some(opts) =>
        b
          .config("spark.driver.extraJavaOptions", opts)
          .config("spark.executor.extraJavaOptions", opts)
      case None =>
        b
    }

    b2.getOrCreate()
  }

  private def runWithSpark(cfg: Config, modules: Vector[String]): IO[Vector[ModuleRun]] =
    IO.blocking {
      val addOpens =
        sys.env.get("JAVA_TOOL_OPTIONS")
          .filter(_.contains("--add-opens=java.base/sun.nio.ch=ALL-UNNAMED"))
          .orElse(Some("--add-opens=java.base/sun.nio.ch=ALL-UNNAMED"))

      val spark = mkSpark("AgdaJsonlDriver", cfg.sparkMaster, addOpens)
      try {
        spark.sparkContext.setLogLevel("WARN")
        import spark.implicits._

        val bc = spark.sparkContext.broadcast(toData(cfg))

        val ds: Dataset[String] =
          spark.createDataset(modules).repartition(cfg.parallelism)

        // Use mapPartitions to process modules in batches per partition.
        // This improves resource management by grouping IOs and executing them
        // together with parTraverse, rather than individually with map.
        // We process in chunks to balance memory usage with resource management.
        // We still need unsafeRunSync at the Spark boundary, but this approach
        // allows for better error handling and cleanup within each chunk.
        val out: Array[ModuleRun] =
          ds.mapPartitions { partition =>
              val localCfg = fromData(bc.value)
              // Process partition in chunks to balance memory vs resource management
              partition
                .grouped(SparkPartitionChunkSize)
                .flatMap { chunk =>
                  // Execute IOs for this chunk with proper resource management
                  chunk.toVector
                    .parTraverse(m => runOne(localCfg, m))
                    .unsafeRunSync()
                }
            }
            .collect()

        out.toVector
      } finally {
        spark.stop()
      }
    }

  // ---------------------------------------------------------------------------
  // Manifest write
  // ---------------------------------------------------------------------------

  private def writeManifest(cfg: Config, startedAt: String, finishedAt: String, results: Vector[ModuleRun]): IO[Path] = {
    val manifest = RunManifest(
      startedAt   = startedAt,
      finishedAt  = finishedAt,
      projectRoot = cfg.projectRoot.toString,
      agdaDir     = cfg.agdaDir.toString,
      srcDir      = cfg.srcDir.toString,
      modulesFile = cfg.modulesFile.toString,
      outDir      = cfg.outDir.toString,
      agdaJsonBin = cfg.agdaJsonBin.toString,
      parallelism = cfg.parallelism,
      resume      = cfg.resume,
      runner      = cfg.runner.asString,
      sparkMaster = cfg.sparkMaster,
      failOnError = cfg.failOnError
    )

    val out = cfg.outDir.resolve("run-manifest.json")
    IO.blocking {
      Files.createDirectories(cfg.outDir)
      Files.write(out, write(manifest, indent = 2).getBytes(StandardCharsets.UTF_8))
      out
    }
  }

  // ---------------------------------------------------------------------------
  // Entry
  // ---------------------------------------------------------------------------

  override def run(args: List[String]): IO[ExitCode] = {
    val start = IO.delay(Instant.now().toString)

    val prog: IO[ExitCode] =
      for {
        cfg <- IO.fromEither(parseArgs(args).leftMap(new RuntimeException(_)))
        _   <- IO.blocking {
                 Files.createDirectories(cfg.outDir.resolve("jsonl"))
                 Files.createDirectories(cfg.outDir.resolve("logs"))
               }
        mods <- readModules(cfg.modulesFile)
        _    <- IO.raiseWhen(mods.isEmpty)(new RuntimeException(s"No top-level modules found in: ${cfg.modulesFile}"))

        _ <- Log.info("[AgdaJsonlDriver]  ✅ Logging configuration complete")
        _ <- Log.info(s"[AgdaJsonlDriver]  🔁 Running extractor")
        _ <- Log.info(s"[AgdaJsonlDriver]       outDir: ${cfg.outDir}")
        _ <- Log.info(s"[AgdaJsonlDriver]       srcDir: ${cfg.srcDir}")
        _ <- Log.info(s"[AgdaJsonlDriver]       modulesFile: ${cfg.modulesFile}")
        _ <- Log.info(s"[AgdaJsonlDriver]       parallelism: ${cfg.parallelism}")
        _ <- Log.info(s"[AgdaJsonlDriver]       runner: ${cfg.runner.asString}")

        t0 <- start

        results <-
          cfg.runner match {
            case Runner.Local =>
              runLocally(cfg, mods)

            case Runner.Spark =>
              runWithSpark(cfg, mods).handleErrorWith { e =>
                // automatic fallback
                IO.println(s"[AgdaJsonlDriver]  ❌ Spark failed (${e.getClass.getSimpleName}): ${e.getMessage}") *>
                IO.println(s"[AgdaJsonlDriver]       Falling back to local runner...") *>
                runLocally(cfg.copy(runner = Runner.Local), mods)
              }

            case Runner.Spark2 =>
              runWithSpark(cfg, mods).handleErrorWith { e =>
                IO.println(s"[AgdaJsonlDriver]  ❌ Spark failed (${e.getClass.getName}): ${e.getMessage}") *>
                IO.blocking(e.printStackTrace()) *>
                IO.println("[AgdaJsonlDriver]       Falling back to local runner...") *>
                runLocally(cfg.copy(runner = Runner.Local), mods)
              }
          }

        t1 <- IO.delay(Instant.now().toString)
        mf <- writeManifest(cfg, t0, t1, results)

        okN  = results.count(_.ok)
        badN = results.size - okN

        // _ <- IO.println(s"[AgdaJsonlDriver] manifest: $mf")
        // _ <- IO.println(s"[AgdaJsonlDriver] summary: ok=$okN failed=$badN total=${results.size}")
        _ <- Log.info(s"[AgdaJsonlDriver] 🏁 Extraction complete. ")
        _ <- Log.info(s"[AgdaJsonlDriver]      summary: ok=$okN failed=$badN total=${results.size}")
        _ <- Log.info(s"[AgdaJsonlDriver]      manifest: $mf")

      } yield {
        if (badN > 0 && cfg.failOnError) ExitCode.Error
        else ExitCode.Success
      }

    prog.handleErrorWith { e =>
      IO.println(s"[AgdaJsonlDriver]  ❌ ERROR: ${e.getMessage}").as(ExitCode.Error)
    }
  }
}
