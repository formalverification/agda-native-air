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
  *  Your style constraints
  *  ----------------------
  *  - FP-first: explicit effects in IO; no uncontrolled exceptions.
  *  - Category-theory-friendly: EitherT/Resource/traverse for structured control flow.
  *  - Spark-ready: SparkSession + Dataset to keep scaling path open.
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

import cats.data.EitherT
import cats.effect.{ExitCode, IO, IOApp, Resource}
import cats.effect.unsafe.implicits.global
import cats.effect.implicits._
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
    results: Vector[ModuleRun]
  )
  object RunManifest { implicit val rw: ReadWriter[RunManifest] = macroRW }

  // ---------------------------------------------------------------------------
  // Config + FP arg parsing
  // ---------------------------------------------------------------------------

  final case class Config(
    projectRoot: Path,
    agdaDir: Path,
    srcDir: Path,
    modulesFile: Path,
    outDir: Path,
    agdaJsonBin: Path,
    parallelism: Int,
    resume: Boolean,
    sparkMaster: Option[String]
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
    sparkMaster: Option[String]
  ) extends Serializable

  private def toData(cfg: Config): ConfigData =
    ConfigData(
      cfg.projectRoot.toString,
      cfg.agdaDir.toString,
      cfg.srcDir.toString,
      cfg.modulesFile.toString,
      cfg.outDir.toString,
      cfg.agdaJsonBin.toString,
      cfg.parallelism,
      cfg.resume,
      cfg.sparkMaster
    )

  private def fromData(d: ConfigData): Config =
    Config(
      projectRoot = Paths.get(d.projectRoot),
      agdaDir     = Paths.get(d.agdaDir),
      srcDir      = Paths.get(d.srcDir),
      modulesFile = Paths.get(d.modulesFile),
      outDir      = Paths.get(d.outDir),
      agdaJsonBin = Paths.get(d.agdaJsonBin),
      parallelism = d.parallelism,
      resume      = d.resume,
      sparkMaster = d.sparkMaster
    )

  private val usage: String =
    """Usage:
      |  runMain proofparser.extract.AgdaJsonlDriver \
      |    --project-root <repo-root> \
      |    --agda-dir     <repo-root>/agda-jang/agda \
      |    --src-dir      <path-to-agda-algebras-src> \
      |    --modules-file <everything-modules.txt> \
      |    --out-dir      <out-dir> \
      |    --agda-json    <path-to-agda-json-exe> \
      |    [--parallelism N] [--no-resume]
      |
      |Notes:
      |  - Only TOP-LEVEL modules are run (no dots in name).
      |  - Spark local or cluster mode: you must ensure agda-json, AGDA_DIR, and sources
      |    exist on executors (containerization recommended for clusters).
      |""".stripMargin

  private def parseArgs(args: List[String]): Either[String, Config] = {
    // Pure recursive parser into a Map, then validated construction.
    def go(rem: List[String], acc: Map[String, String]): Either[String, Map[String, String]] =
      rem match {
        case Nil => Right(acc)

        case "--no-resume" :: tail =>
          go(tail, acc.updated("resume", "false"))

        case "--project-root" :: v :: tail =>
          go(tail, acc.updated("projectRoot", v))

        case "--agda-dir" :: v :: tail =>
          go(tail, acc.updated("agdaDir", v))

        case "--src-dir" :: v :: tail =>
          go(tail, acc.updated("srcDir", v))

        case "--modules-file" :: v :: tail =>
          go(tail, acc.updated("modulesFile", v))

        case "--out-dir" :: v :: tail =>
          go(tail, acc.updated("outDir", v))

        case "--agda-json" :: v :: tail =>
          go(tail, acc.updated("agdaJsonBin", v))

        case "--parallelism" :: v :: tail =>
          go(tail, acc.updated("parallelism", v))

        case "--spark-master" :: v :: tail =>
          go(tail, acc.updated("sparkMaster", v))

        case bad =>
          Left(s"Unrecognized or incomplete args near: ${bad.take(2).mkString(" ")}\n\n$usage")
      }

    go(args, Map.empty).flatMap { m =>
      def req(k: String): Either[String, String] =
        m.get(k).toRight(s"Missing --$k\n\n$usage")

      for {
        pr  <- req("projectRoot")
        ad  <- req("agdaDir")
        sd  <- req("srcDir")
        mf  <- req("modulesFile")
        od  <- req("outDir")
        bin <- req("agdaJsonBin")
      } yield {
        val par = m.get("parallelism").flatMap(s => scala.util.Try(s.toInt).toOption)
          .getOrElse(Runtime.getRuntime.availableProcessors())
        val res = m.get("resume").forall(_ != "false")

        Config(
          projectRoot = Paths.get(pr).toAbsolutePath.normalize(),
          agdaDir     = Paths.get(ad).toAbsolutePath.normalize(),
          srcDir      = Paths.get(sd).toAbsolutePath.normalize(),
          modulesFile = Paths.get(mf).toAbsolutePath.normalize(),
          outDir      = Paths.get(od).toAbsolutePath.normalize(),
          agdaJsonBin = Paths.get(bin).toAbsolutePath.normalize(),
          parallelism = par,
          resume      = res,
          sparkMaster = m.get("sparkMaster")
        )
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Spark session as Resource (explicit lifecycle)
  // ---------------------------------------------------------------------------

  private def sparkResource(appName: String, master: String): Resource[IO, SparkSession] =
    Resource.make {
      IO.blocking {
        SparkSession.builder()
          .appName(appName)
          .master(master)
          .config("spark.ui.enabled", "false")
          .getOrCreate()
      }
    } { spark =>
      IO.blocking(spark.stop()).handleError(_ => ())
    }

  // ---------------------------------------------------------------------------
  // Module discovery (top-level only)
  // ---------------------------------------------------------------------------

  private def readTopLevelModules(modulesFile: Path): IO[Vector[String]] =
    IO.blocking {
      Files.readAllLines(modulesFile, StandardCharsets.UTF_8).asScala.toVector
        .map(_.trim)
        .filter(s => s.nonEmpty && !s.startsWith("#"))
        .filterNot(_.contains(".")) // <-- your constraint: no nested submodules
        .distinct
        .sorted
    }

  private def moduleToInput(srcDir: Path, mod: String): Path =
    srcDir.resolve(s"$mod.agda")

  private def moduleToOutJsonl(outDir: Path, mod: String): Path =
    outDir.resolve("jsonl").resolve(s"$mod.jsonl")

  private def moduleToLog(outDir: Path, mod: String): Path =
    outDir.resolve("logs").resolve(s"$mod.log")

  // ---------------------------------------------------------------------------
  // One-module run in IO (effects explicit)
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
        (IO.blocking(Files.exists(out) && Files.size(out) > 0L) >>= { existsNonEmpty =>
          if (!existsNonEmpty) IO.pure(None)
          else
            JsonlValidate.validateFile(out).map { v =>
              // If valid, we treat it as skipped+ok; otherwise, force rerun.
              if (v.ok)
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
              else None
            }
        }).handleError(_ => None)

    val runFresh: IO[ModuleRun] = {
      val missingInput: IO[ModuleRun] =
        IO.pure(
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
          v    <- if (exec.exitCode == 0) JsonlValidate.validateFile(out) else IO.pure(JsonlValidate.Result(false, 0L, Vector(s"exit_code=${exec.exitCode}")))
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

      IO.blocking(Files.exists(input)).flatMap {
        case false => missingInput
        case true  => runBackend
      }
    }

    for {
      _    <- ensureDirs
      skip <- resumeCheck
      res  <- skip.fold(runFresh)(IO.pure)
    } yield res
  }

  // ---------------------------------------------------------------------------
  // Manifest write (IO)
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
  // Spark boundary: Dataset orchestration
  // ---------------------------------------------------------------------------

  // Spark encoders
  implicit val encRun: Encoder[ModuleRun]  = Encoders.product[ModuleRun]

  private def runWithSpark(cfg: Config, modules: Vector[String]): IO[Vector[ModuleRun]] = {
    val master =
      cfg.sparkMaster
        .orElse(sys.env.get("SPARK_MASTER"))
        .orElse(Option(System.getProperty("spark.master")))
        .getOrElse("local[*]")

    sparkResource("AgdaJsonlDriver", master).use { spark =>
      import spark.implicits._

      IO.blocking {
        // Broadcast config to executors (pure data).
        val bc = spark.sparkContext.broadcast(toData(cfg))

        // Dataset so we can evolve into DataFrame-based monitoring later.
        val ds: Dataset[String] =
          spark.createDataset(modules).repartition(cfg.parallelism)

        // mapPartitions: amortize overhead; traverse in functional style.
        // NOTE: we evaluate IO at the Spark boundary; side effects are explicit
        // in runOne, but Spark requires a concrete value in executor code.
        val out: Array[ModuleRun] =
          ds.mapPartitions { it =>
              val localCfg = fromData(bc.value)
              it.toList.iterator.map { mod =>
                // Spark boundary "escape hatch":
                // - runOne is IO[ModuleRun]
                // - Spark requires ModuleRun
                runOne(localCfg, mod).unsafeRunSync()
              }
            }
            .collect()

        out.toVector
      }
    }
  }

  private def runLocally(cfg: Config, modules: Vector[String]): IO[Vector[ModuleRun]] =
    modules.parTraverseN(cfg.parallelism)(mod => runOne(cfg, mod))


  // ---------------------------------------------------------------------------
  // IOApp entrypoint
  // ---------------------------------------------------------------------------

  override def run(args: List[String]): IO[ExitCode] = {

    val program: EitherT[IO, String, Unit] =
      for {
        cfg <- EitherT.fromEither[IO](parseArgs(args))
        _   <- EitherT.right(IO.blocking {
                 Files.createDirectories(cfg.outDir.resolve("jsonl"))
                 Files.createDirectories(cfg.outDir.resolve("logs"))
               })
        mods <- EitherT.right(readTopLevelModules(cfg.modulesFile))
        _    <- EitherT.cond[IO](mods.nonEmpty, (), s"No top-level modules found in: ${cfg.modulesFile}")
        t0   <- EitherT.right(IO.delay(Instant.now().toString))
        res  <- EitherT.right(runLocally(cfg, mods))
        t1   <- EitherT.right(IO.delay(Instant.now().toString))
        mf   <- EitherT.right(writeManifest(cfg, t0, t1, res))
        okN   = res.count(_.ok)
        badN  = res.size - okN
        _    <- EitherT.right(IO.println(s"[AgdaJsonlDriver] manifest: $mf"))
        _    <- EitherT.right(IO.println(s"[AgdaJsonlDriver] summary: ok=$okN failed=$badN total=${res.size}"))
        _    <- EitherT.cond[IO](badN == 0, (), s"$badN module(s) failed; see manifest/logs.")
      } yield ()

    program.value.flatMap {
      case Left(err) => IO.println(s"[AgdaJsonlDriver] ERROR: $err").as(ExitCode.Error)
      case Right(_)  => IO.pure(ExitCode.Success)
    }
  }
}
