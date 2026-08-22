/** ============================================================================
  *  Scaffold.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/search/Scaffold.scala
  *  Package: struxdriver.search
  *
  *  Purpose
  *  -------
  *  The fixture-run scaffolding the P0 single-step harness and the P1 loop
  *  harness share (issue #122's "factor, do not duplicate"): benchmark-index
  *  reading, the per-fixture staging step (work copy + baseline check_file +
  *  the exactly-one-hole gate), the JSONL writer, the committed default Agda
  *  flag set, and the small numeric helpers the reports use.
  *
  *  Design notes
  *  ------------
  *  Extracted verbatim from SingleStepHarness.scala (PR #121) so behavior is
  *  identical by construction — the anomaly message of the one-hole gate
  *  included, since the P0 sweep's outputs are the comparison baseline.
  *
  *  ============================================================================
  */
package struxdriver.search

import cats.effect.IO
import cats.syntax.all._
import io.circe.Json
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, StandardCopyOption}
import scala.jdk.CollectionConverters._

import struxdriver.benchmark.{Obligation => IndexEntry}

/** One fixture staged for driving: its working copy, the content as read, and
  * the single obligation the baseline check anchored.
  */
final case class StagedFixture(workFile: Path, content: String, obligation: Obligation)

object Scaffold {

  /** The committed .mcp.json flag set — the flags every harness spawns the
    * server with unless overridden.
    */
  val defaultAgdaFlags: String =
    "-i agda-dojang/agda --library-file=agda/libraries -l agda-dojang -l standard-library"

  /** Read the benchmark index, keeping the requested ids (None = all). */
  def readIndex(index: Path, ids: Option[Set[String]]): IO[Vector[IndexEntry]] =
    IO.blocking(Files.readAllLines(index, StandardCharsets.UTF_8).asScala.toVector)
      .flatMap(_.filter(_.trim.nonEmpty).traverse(l =>
        IO.fromEither(io.circe.parser.decode[IndexEntry](l).leftMap(e =>
          new RuntimeException(s"bad index row: ${e.getMessage}")))))
      .map(all => ids.fold(all)(want => all.filter(e => want(e.id))))

  /** The eval schema's fixtureId: the fixture module stem (file name sans
    * .agda), exactly as the Python evaluator derives it.
    */
  def fixtureStem(entry: IndexEntry): String =
    entry.obligationPath.getFileName.toString.stripSuffix(".agda")

  /** Stage one fixture: create the work and log directories, copy the
    * obligation to its working file, read it, and run the baseline
    * check_file.  A fixture that does not present exactly one obligation is
    * an anomaly (Left), with P0's exact message.
    */
  def stage(
    source:  Path,
    workDir: Path,
    logsDir: Path,
    oracle:  Oracle,
    ctx:     CallCtx
  ): IO[Either[String, StagedFixture]] = {
    val workFile = workDir.resolve(source.getFileName)
    for {
      _       <- IO.blocking { Files.createDirectories(workDir); Files.createDirectories(logsDir) }
      _       <- IO.blocking(Files.copy(source, workFile, StandardCopyOption.REPLACE_EXISTING))
      content <- IO.blocking(new String(Files.readAllBytes(workFile), StandardCharsets.UTF_8))
      check   <- oracle.checkFile(ctx, workFile)
    } yield check.body.holes match {
      case Vector(h) => Right(StagedFixture(workFile, content, WireHole.toObligation(h)))
      case hs        => Left(s"expected exactly 1 hole, check_file reported ${hs.size}")
    }
  }

  def writeJsonl(path: Path, rows: Vector[Json]): IO[Unit] =
    IO.blocking {
      Files.write(path, rows.map(_.noSpaces).mkString("", "\n", "\n").getBytes(StandardCharsets.UTF_8)); ()
    }

  def round3(d: Double): BigDecimal = BigDecimal(d).setScale(3, BigDecimal.RoundingMode.HALF_UP)

  def pct(part: Double, whole: Double): BigDecimal =
    if (whole <= 0) BigDecimal(0) else BigDecimal(part / whole * 100).setScale(2, BigDecimal.RoundingMode.HALF_UP)
}
