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

import org.apache.spark.sql.{Dataset, Encoder, Encoders, SparkSession}

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths}
import java.time.Instant
import scala.collection.JavaConverters._

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
  object ModuleRun { implicit val rw: ReadWriter[ModuleRun] = macroRW }

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
    results: Vector[ModuleRun]
  )
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
    sparkMaster: String
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
    sparkMaster: String
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
      c.sparkMaster
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
      sparkMaster = d.sparkMaster
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
      |
      |Notes:
      |  - Only TOP-LEVEL modules are run (no dots in name).
      |""".stripMargin

  private def parseArgs(args: List[String]): Either[String, Config] = {
    // simple, boring parser (no cats)
    def next(i: Int): Either[String, String] =
      args.lift(i + 1).toRight(s"Missing value after ${args(i)}\n\n$usage")

    var i = 0
    var m = Map.empty[String, String]
    while (i < args.length) {
      args(i) match {
        case "--no-resume" =>
          m = m.updated("resume", "false")
          i += 1

        case "--project-root" | "--agda-dir" | "--src-dir" | "--modules-file" | "--out-dir" | "--agda-json"
            | "--parallelism" | "--runner" | "--spark-master" =>
          val k = args(i).drop(2)
          next(i) match {
            case Left(e)  => return Left(e)
            case Right(v) => m = m.updated(k, v); i += 2
          }

        case bad =>
          return Left(s"Unrecognized arg: $bad\n\n$usage")
      }
    }

    def req(k: String): Either[String, String] =
      m.get(k).toRight(s"Missing --$k\n\n$usage")

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
        sparkMaster = sparkMaster
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
        IO.blocking(Files.exists(out) && Files.size(out) > 0L).attempt.flatMap {
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
      val cmd = Seq(
        cfg.agdaJsonBin.toString,
        "--input", input.toString,
        "--output", out.toString,
        "--include", cfg.srcDir.toString
      )

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

  private def runLocally(cfg: Config, modules: Vector[String]): IO[Vector[ModuleRun]] =
    modules.parTraverseN(cfg.parallelism)(m => runOne(cfg, m))

  // ---------------------------------------------------------------------------
  // Spark runner (simple SparkSession config)
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

        val out: Array[ModuleRun] =
          ds.map { mod =>
              val localCfg = fromData(bc.value)
              // Spark boundary escape hatch
              runOne(localCfg, mod).unsafeRunSync()
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
      results     = results
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

        t0 <- start

        results <-
          cfg.runner match {
            case Runner.Local =>
              runLocally(cfg, mods)

            case Runner.Spark =>
              runWithSpark(cfg, mods).handleErrorWith { e =>
                // automatic fallback
                IO.println(s"[AgdaJsonlDriver] Spark failed (${e.getClass.getSimpleName}): ${e.getMessage}") *>
                IO.println(s"[AgdaJsonlDriver] Falling back to local runner...") *>
                runLocally(cfg.copy(runner = Runner.Local), mods)
              }

            case Runner.Spark2 =>
              runWithSpark(cfg, mods).handleErrorWith { e =>
                IO.println(s"[AgdaJsonlDriver] Spark failed (${e.getClass.getName}): ${e.getMessage}") *>
                IO.blocking(e.printStackTrace()) *>
                IO.println("[AgdaJsonlDriver] Falling back to local runner...") *>
                runLocally(cfg.copy(runner = Runner.Local), mods)
              }
          }

        t1 <- IO.delay(Instant.now().toString)
        mf <- writeManifest(cfg, t0, t1, results)

        okN  = results.count(_.ok)
        badN = results.size - okN

        _ <- IO.println(s"[AgdaJsonlDriver] manifest: $mf")
        _ <- IO.println(s"[AgdaJsonlDriver] summary: ok=$okN failed=$badN total=${results.size}")

      } yield if (badN == 0) ExitCode.Success else ExitCode.Error

    prog.handleErrorWith { e =>
      IO.println(s"[AgdaJsonlDriver] ERROR: ${e.getMessage}").as(ExitCode.Error)
    }
  }
}
