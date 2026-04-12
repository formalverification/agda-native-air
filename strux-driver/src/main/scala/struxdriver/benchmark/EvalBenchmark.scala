/** ============================================================================
  *  EvalBenchmark.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/benchmark/EvalBenchmark.scala
  *  Package: struxdriver.benchmark
  *
  *  Purpose
  *  -------
  *  Benchmark evaluation runner for M1-5.  Two modes:
  *
  *    1. Gold verification  (--verify-gold):
  *       Typecheck every gold-solution .agda file to confirm the benchmark
  *       hasn't rotted due to library version drift.
  *
  *    2. Agent evaluation  (--evaluate):
  *       Invoke eval_fixtures.py on the obligation files, then aggregate
  *       results by difficulty tier.
  *
  *  Both modes read the benchmark index (benchmark-index.jsonl) to discover
  *  obligations and their metadata.
  *
  *  Design
  *  ------
  *  - Pure ADTs for the domain model (sealed traits, case classes).
  *  - cats-effect IO for all effects (subprocess, file IO, clock).
  *  - circe for JSON parsing and generation.
  *  - fs2 for streaming JSONL reads (memory-bounded for large indices).
  *  - No mutable state anywhere.
  *
  *  Integration
  *  -----------
  *  Lives in the strux-driver sbt project alongside AgdaJsonlDriver.
  *  Invoked via:
  *
  *    sbt "runMain struxdriver.benchmark.EvalBenchmark --verify-gold \
  *         --index data/benchmarks/benchmark-index.jsonl"
  *
  *  Or via the top-level Makefile: `make eval-benchmark-gold`.
  *
  *  ============================================================================
  */
package struxdriver.benchmark

import cats.effect.{ExitCode, IO, IOApp}
import cats.syntax.all._
import io.circe._
import io.circe.generic.semiauto._
import io.circe.syntax._
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths}
import java.time.Instant
import scala.concurrent.duration._
import scala.jdk.CollectionConverters._


// =============================================================================
// Domain ADTs
// =============================================================================

/** Difficulty tier for a benchmark obligation. */
sealed trait Difficulty extends Product with Serializable {
  def tag: String
}
object Difficulty {
  case object Routine       extends Difficulty { val tag = "routine" }
  case object Compositional extends Difficulty { val tag = "compositional" }
  case object NonObvious    extends Difficulty { val tag = "non-obvious" }

  /** Parse a difficulty string, tolerating common aliases. */
  def parse(s: String): Either[String, Difficulty] = {
    val normalized = s.trim.toLowerCase.replace("-", "_").replace(" ", "_")
    normalized match {
      case "routine" | "tier1"                        => Right(Routine)
      case "compositional" | "tier2"                  => Right(Compositional)
      case "non_obvious" | "nonobvious" | "tier3"     => Right(NonObvious)
      case other                                      => Left(s"Unknown difficulty: $other")
    }
  }

  implicit val encoder: Encoder[Difficulty] = Encoder.encodeString.contramap(_.tag)
  implicit val decoder: Decoder[Difficulty] = Decoder.decodeString.emap(parse)
}


/** A single benchmark obligation, parsed from the JSONL index. */
final case class Obligation(
  id:              String,
  source:          String,         // "agda-stdlib" | "agda-algebras"
  module:          String,         // e.g., "Data.Nat.Properties"
  obligationPath:  Path,           // path to the {!!} file
  goldPath:        Path,           // path to the gold solution file
  goldTerm:        String,         // the proof term
  hole:            String,         // definition name with the hole
  typeSig:         String,         // pretty-printed type
  difficulty:      Difficulty,
  domain:          String,         // e.g., "arithmetic", "algebra"
  proofStrategy:   String,         // e.g., "refl", "induction"
  tags:            Vector[String]  // additional metadata tags
)

object Obligation {
  /** Decode from the JSONL schema. */
  implicit val decoder: Decoder[Obligation] = (c: HCursor) =>
    for {
      id         <- c.get[String]("id")
      source     <- c.get[String]("source")
      module     <- c.get[String]("module")
      obPath     <- c.get[String]("obligation").map(Paths.get(_))
      goldPath   <- c.get[String]("gold").map(Paths.get(_))
      goldTerm   <- c.get[String]("goldTerm")
      hole       <- c.get[String]("hole")
      typeSig    <- c.get[String]("type")
      difficulty <- c.get[Difficulty]("difficulty")
      domain     <- c.getOrElse[String]("domain")("")
      strategy   <- c.getOrElse[String]("proofStrategy")("")
      tags       <- c.getOrElse[Vector[String]]("tags")(Vector.empty)
    } yield Obligation(
      id, source, module, obPath, goldPath, goldTerm,
      hole, typeSig, difficulty, domain, strategy, tags
    )
}


/** Result of typechecking a single gold solution. */
final case class GoldResult(
  obligationId:  String,
  passed:        Boolean,
  elapsedMs:     Long,
  errorMsg:      Option[String] = None
)

object GoldResult {
  implicit val encoder: Encoder[GoldResult] = (r: GoldResult) => {
    val base = Json.obj(
      "id"        -> r.obligationId.asJson,
      "passed"    -> r.passed.asJson,
      "elapsedMs" -> r.elapsedMs.asJson
    )
    r.errorMsg.fold(base)(e => base.deepMerge(Json.obj("error" -> e.asJson)))
  }
}


/** Aggregated statistics for a single difficulty tier. */
final case class TierStats(
  tier:            String,
  total:           Int,
  solved:          Int,
  solveRate:       Double,
  meanIterations:  Double,
  meanElapsedMs:   Double
)

object TierStats {
  implicit val encoder: Encoder[TierStats] = deriveEncoder[TierStats]
}


/** Complete gold verification report. */
final case class GoldReport(
  schemaVersion: String,
  timestamp:     String,
  total:         Int,
  passed:        Int,
  failed:        Int,
  allPassed:     Boolean,
  results:       Vector[GoldResult]
)

object GoldReport {
  implicit val encoder: Encoder[GoldReport] = deriveEncoder[GoldReport]
}


// =============================================================================
// Configuration
// =============================================================================

sealed trait Mode
object Mode {
  case object VerifyGold extends Mode
  case object Evaluate   extends Mode
}

final case class Config(
  mode:             Mode,
  indexPath:        Path,
  outDir:           Path,
  projectRoot:      Path,
  agdaAlgebrasSrc:  Option[Path]
)


// =============================================================================
// Parsing
// =============================================================================

object IndexParser {

  /** Read a JSONL index file into a vector of obligations.
    *
    * Lines that fail to parse are logged to stderr but do not abort.
    * Returns (parsed, errors) so the caller can decide policy.
    */
  def parseIndex(path: Path): IO[(Vector[Obligation], Vector[String])] =
    IO.blocking {
      val lines = Files.readAllLines(path, StandardCharsets.UTF_8).asScala.toVector
      val (obligations, errors) =
        lines
          .filter(_.trim.nonEmpty)
          .filterNot(_.trim.startsWith("#"))
          .zipWithIndex
          .partitionMap { case (line, idx) =>
            io.circe.parser.decode[Obligation](line) match {
              case Right(ob)  => Left(ob)
              case Left(err)  => Right(s"line ${idx + 1}: ${err.getMessage}")
            }
          }
      (obligations, errors)
    }
}


// =============================================================================
// Filtering (pure)
// =============================================================================

object Filter {

  /** Partition obligations into available and skipped.
    *
    * agda-algebras obligations are skipped when agdaAlgebrasSrc is None.
    * Obligations whose files don't exist are also skipped.
    */
  def filterAvailable(
    obligations:     Vector[Obligation],
    agdaAlgebrasSrc: Option[Path],
    projectRoot:     Path
  ): (Vector[Obligation], Vector[String]) = {
    val (available, skipped) =
      obligations.partitionMap { ob =>
        val skip: Option[String] =
          if (ob.source == "agda-algebras" && agdaAlgebrasSrc.isEmpty)
            Some(ob.id)
          else if (!Files.isRegularFile(projectRoot.resolve(ob.goldPath)))
            Some(ob.id)
          else
            None
        skip.toRight(ob)
      }
    (available, skipped)
  }
}


// =============================================================================
// Gold Verification (effectful)
// =============================================================================

object GoldVerifier {

  /** Typecheck a single gold solution file with Agda.
    *
    * This is the IO boundary: it spawns a subprocess and measures wall-clock time.
    */
  def verifyOne(ob: Obligation, projectRoot: Path): IO[GoldResult] = {
    val goldAbs = projectRoot.resolve(ob.goldPath)
    val agdaDir =
      sys.env.getOrElse("AGDA_DIR",
        projectRoot.resolve("agda-dojang/agda").toString)

    val librariesFile = Paths.get(agdaDir).resolve("libraries").toString

    if (!Files.isRegularFile(goldAbs)) {
      IO.pure(GoldResult(
        obligationId = ob.id,
        passed       = false,
        elapsedMs    = 0L,
        errorMsg     = Some(s"Gold file missing: $goldAbs")
      ))
    } else {
      val cmd = Vector(
        "agda",
        "--no-default-libraries",
        "--library-file", librariesFile,
        goldAbs.toString
      )

      for {
        t0     <- IO.monotonic
        result <- IO.blocking {
                    val pb = new ProcessBuilder(cmd.asJava)
                    pb.environment().put("AGDA_DIR", agdaDir)
                    pb.redirectErrorStream(true)
                    val proc = pb.start()
                    val output = new String(
                      proc.getInputStream.readAllBytes(),
                      StandardCharsets.UTF_8
                    )
                    val exited = proc.waitFor()
                    (exited, output)
                  }.timeout(120.seconds)
                   .handleError(e => (-1, s"Exception: ${e.getMessage}"))
        t1     <- IO.monotonic
        elapsedMs = (t1 - t0).toMillis
        (exitCode, output) = result
      } yield {
        if (exitCode == 0)
          GoldResult(ob.id, passed = true, elapsedMs)
        else
          GoldResult(ob.id, passed = false, elapsedMs,
            Some(output.take(500)))
      }
    }
  }

  /** Typecheck all gold solutions sequentially.
    *
    * Sequential to avoid saturating the Agda process (which can be heavy).
    */
  def verifyAll(
    obligations: Vector[Obligation],
    projectRoot: Path
  ): IO[Vector[GoldResult]] =
    obligations.traverse(ob =>
      verifyOne(ob, projectRoot).flatTap { r =>
        val icon = if (r.passed) "✅" else "❌"
        val suffix = r.errorMsg.fold("")(e => s"  ($e)")
        IO.println(s"  $icon ${r.obligationId} [${r.elapsedMs}ms]$suffix")
      }
    )
}


// =============================================================================
// Report Generation (pure)
// =============================================================================

object Report {

  def buildGoldReport(results: Vector[GoldResult]): GoldReport = {
    val passed = results.count(_.passed)
    val failed = results.size - passed
    GoldReport(
      schemaVersion = "benchmark-gold-report.v0",
      timestamp     = Instant.now().toString,
      total         = results.size,
      passed        = passed,
      failed        = failed,
      allPassed     = failed == 0,
      results       = results
    )
  }

  def writeReport(report: GoldReport, outDir: Path): IO[Path] = {
    val json = report.asJson.spaces2
    val outPath = outDir.resolve("gold-verification.json")
    IO.blocking {
      Files.createDirectories(outDir)
      Files.write(outPath, json.getBytes(StandardCharsets.UTF_8))
      outPath
    }
  }
}


// =============================================================================
// CLI Parsing
// =============================================================================

object CliParser {

  private val usage: String =
    """Usage:
      |  runMain struxdriver.benchmark.EvalBenchmark --verify-gold \
      |    --index data/benchmarks/benchmark-index.jsonl \
      |    [--out-dir data/benchmarks/reports] \
      |    [--project-root .]
      |
      |Modes:
      |  --verify-gold    Typecheck all gold solutions (regression guard)
      |  --evaluate       Run propose→check evaluator on obligations
      |""".stripMargin

  def parse(args: List[String]): Either[String, Config] = {
    @annotation.tailrec
    def loop(
      rest:  List[String],
      acc:   Map[String, String],
      flags: Set[String]
    ): Either[String, (Map[String, String], Set[String])] =
      rest match {
        case Nil =>
          Right((acc, flags))
        case "--verify-gold" :: xs =>
          loop(xs, acc, flags + "verify-gold")
        case "--evaluate" :: xs =>
          loop(xs, acc, flags + "evaluate")
        case "--index" :: v :: xs =>
          loop(xs, acc.updated("index", v), flags)
        case "--out-dir" :: v :: xs =>
          loop(xs, acc.updated("out-dir", v), flags)
        case "--project-root" :: v :: xs =>
          loop(xs, acc.updated("project-root", v), flags)
        case bad :: _ =>
          Left(s"Unknown argument: $bad\n\n$usage")
      }

    loop(args, Map.empty, Set.empty).flatMap { case (m, flags) =>
      val mode: Either[String, Mode] =
        (flags.contains("verify-gold"), flags.contains("evaluate")) match {
          case (true, false)  => Right(Mode.VerifyGold)
          case (false, true)  => Right(Mode.Evaluate)
          case (true, true)   => Left("Cannot specify both --verify-gold and --evaluate")
          case (false, false) => Left(s"Must specify --verify-gold or --evaluate\n\n$usage")
        }

      val projectRoot =
        Paths.get(m.getOrElse("project-root", ".")).toAbsolutePath.normalize()

      val agdaAlgebrasSrc =
        sys.env.get("AGDA_ALGEBRAS_SRC").map(s => Paths.get(s).toAbsolutePath.normalize())

      for {
        md <- mode
        ix <- m.get("index").toRight(s"Missing --index\n\n$usage")
      } yield Config(
        mode            = md,
        indexPath        = Paths.get(ix).toAbsolutePath.normalize(),
        outDir           = Paths.get(m.getOrElse("out-dir", "data/benchmarks/reports"))
                            .toAbsolutePath.normalize(),
        projectRoot      = projectRoot,
        agdaAlgebrasSrc  = agdaAlgebrasSrc
      )
    }
  }
}


// =============================================================================
// Main
// =============================================================================

object EvalBenchmark extends IOApp {

  override def run(args: List[String]): IO[ExitCode] = {
    val program: IO[ExitCode] =
      for {
        config <- IO.fromEither(
                    CliParser.parse(args)
                      .leftMap(new RuntimeException(_))
                  )

        // Parse the benchmark index.
        indexResult <- IndexParser.parseIndex(config.indexPath)
        (allObligations, parseErrors) = indexResult
        _ <- parseErrors.traverse_(e => IO.println(s"  WARN: $e"))
        _ <- IO.raiseWhen(allObligations.isEmpty)(
               new RuntimeException("No obligations parsed from index")
             )

        // Filter for available obligations.
        (available, skipped) = Filter.filterAvailable(
          allObligations, config.agdaAlgebrasSrc, config.projectRoot
        )
        _ <- IO.println(
               s"Benchmark index: ${allObligations.size} obligations " +
               s"(${available.size} available, ${skipped.size} skipped)"
             )
        _ <- IO.whenA(skipped.nonEmpty)(
               IO.println(s"  Skipped: ${skipped.take(5).mkString(", ")}" +
                          (if (skipped.size > 5) "..." else ""))
             )

        // Dispatch.
        exitCode <- config.mode match {
          case Mode.VerifyGold =>
            for {
              _       <- IO.println("\n--- Gold verification ---")
              results <- GoldVerifier.verifyAll(available, config.projectRoot)
              report   = Report.buildGoldReport(results)
              path    <- Report.writeReport(report, config.outDir)
              _       <- IO.println(
                           s"\nGold verification: ${report.passed}/${report.total} passed"
                         )
              _       <- IO.println(s"Report: $path")
            } yield if (report.allPassed) ExitCode.Success else ExitCode.Error

          case Mode.Evaluate =>
            // TODO: Invoke eval_fixtures.py as subprocess, parse its JSONL output,
            //       join with benchmark metadata, compute per-tier TierStats,
            //       write BenchmarkReport.
            IO.println("\n--- Agent evaluation ---") *>
            IO.println("  (not yet implemented — awaiting eval_fixtures.py integration)") *>
            IO.pure(ExitCode(2))
        }
      } yield exitCode

    program.handleErrorWith { e =>
      IO.println(s"ERROR: ${e.getMessage}").as(ExitCode.Error)
    }
  }
}
