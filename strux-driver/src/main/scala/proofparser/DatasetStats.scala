package proofparser

import upickle.default._
import java.nio.file.{Files, Paths}
import java.nio.charset.StandardCharsets

object DatasetStats {
  private def readLines(path: String): Iterator[String] =
    Files.readAllLines(Paths.get(path), StandardCharsets.UTF_8).iterator().asScala

  import scala.jdk.CollectionConverters._

  final case class LenStats(n: Long, min: Int, p50: Int, p90: Int, p99: Int, max: Int)
  private def lens(xs: Vector[Int]): LenStats = {
    def pct(p: Double) = xs((p * (xs.size - 1)).toInt)
    LenStats(xs.size, xs.headOption.getOrElse(0), pct(0.50), pct(0.90), pct(0.99), xs.lastOption.getOrElse(0))
  }

  private def lengthsOf(s: String): Int = s.codePointCount(0, s.length)

  def agdaData(path: String): Unit = {
    val rows = readLines(path).filter(_.trim.nonEmpty).map(read[AgdaData]).toVector
    val byModule = rows.groupBy(_.module.getOrElse(""))
    val nameLens = rows.map(r => lengthsOf(r.name)).sorted
    val typeLens = rows.map(r => lengthsOf(r.agdaType)).sorted
    val proofLens = rows.map(r => lengthsOf(r.proof)).sorted
    val premCount = rows.map(_.premises.size).sorted

    println(s"# AgdaData: ${rows.size} rows, ${byModule.size} modules")
    println(s"  distinct names: ${rows.map(_.name).distinct.size}")
    println(s"  empty modules : ${rows.count(_.module.isEmpty)}")
    println(s"  premises stats: n=${premCount.size}, p50=${premCount(premCount.size/2)}, max=${premCount.lastOption.getOrElse(0)}")
    def showLS(tag: String, xs: Vector[Int]) =
      if (xs.nonEmpty) {
        val s = lens(xs)
        println(f"  $tag%-8s len: n=${s.n}%d min=${s.min}%d p50=${s.p50}%d p90=${s.p90}%d p99=${s.p99}%d max=${s.max}%d")
      }
    showLS("name",  nameLens)
    showLS("type",  typeLens)
    showLS("proof", proofLens)

    // quick invariant probes
    val selfPremHits = rows.count { r =>
      r.premises.exists(AgdaDataOps.isSelfPremise(r, _))
    }
    println(s"  self-premises remaining (should be 0): $selfPremHits")
  }

  def goals(path: String): Unit = {
    val rows = readLines(path).filter(_.trim.nonEmpty).map(read[TrainRecord]).toVector
    val byModule = rows.groupBy(_.module)
    println(s"# TrainRecord: ${rows.size} rows, ${byModule.size} modules")
    println(s"  distinct decls: ${rows.map(_.decl).distinct.size}")
    val goalLens = rows.map(r => r.goalType.length).sorted
    val solnLens = rows.flatMap(_.solution).map(_.length).sorted
    if (goalLens.nonEmpty) println(f"  goalType len p50=${goalLens(goalLens.size/2)} max=${goalLens.last}%d")
    if (solnLens.nonEmpty) println(f"  solution len p50=${solnLens(solnLens.size/2)} max=${solnLens.last}%d")
  }

  def main(args: Array[String]): Unit = {
    if (args.length != 2 || !(args(0) == "agda" || args(0) == "goals")) {
      Console.err.println("Usage: DatasetStats (agda|goals) <jsonl>")
      sys.exit(1)
    }
    if (args(0) == "agda") agdaData(args(1)) else goals(args(1))
  }
}
