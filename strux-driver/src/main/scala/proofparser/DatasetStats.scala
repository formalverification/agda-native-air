// ============================================================================
// File: src/main/scala/proofparser/DatasetStats.scala
// Package: proofparser
// ----------------------------------------------------------------------------
// Overview
//   "Best-of-both-worlds" DatasetStats that combines:
//     - Streaming + resource-safe IO (no "Stream Closed"),
//     - Minimal local schema (decoupled from Model.scala),
//     - Codepoint-aware length stats (handles surrogate pairs),
//     - Distinct name counts and basic invariants,
//     - Actionable histograms (premises, modules, premises-per-row),
//     - Small, friendly CLI: DatasetStats <in.jsonl> [--top K].
//
// Why the previous version failed with "Stream Closed"
//   Returning an Iterator from a Using.resource block closes the source before
//   materialization. We now materialize to a Vector inside Using, then proceed.
//
// Usage
//   sbt "runMain proofparser.DatasetStats path/to/train.jsonl --top 20"
// ----------------------------------------------------------------------------
package proofparser

import scala.io.Source
import scala.util.Using
import upickle.default._

object DatasetStats {
  // Minimal, self-contained row schema for robustness.
  final case class Row(
    file: String,
    module: Option[String],
    name: String,
    agdaType: String,
    proof: String,
    premises: List[String] = Nil
  )
  object Row { implicit val rw: ReadWriter[Row] = macroRW }

  // --- CLI ------------------------------------------------------------------
  def main(args: Array[String]): Unit = {
    if (args.isEmpty) {
      Console.err.println("Usage: DatasetStats <in.jsonl> [--top K]"); sys.exit(1)
    }
    val in   = args(0)
    val topK = args.sliding(2,1).collectFirst{case Array("--top",k)=>k.toInt}.getOrElse(20)

    val rows: Vector[Row] = readJsonlVec[Row](in)
    if (rows.isEmpty) { println(s"No rows found in $in"); sys.exit(0) }

    println("\n=== Dataset Summary ===")
    println(s"rows:                ${rows.size}")
    println(s"distinct names:      ${rows.iterator.map(_.name).toSet.size}")
    println(s"non-empty agdaType:  ${rows.count(_.agdaType.trim.nonEmpty)}")
    println(s"non-empty proof:     ${rows.count(_.proof.trim.nonEmpty)}")
    println(s"non-empty premises:  ${rows.count(_.premises.nonEmpty)}")

    // Codepoint-aware lengths
    val tLens = rows.iterator.map(r => strlen(r.agdaType)).toVector
    val pLens = rows.iterator.map(r => strlen(r.proof)).toVector

    println("\n--- Lengths (Unicode codepoints) ---")
    println(formatStats("agdaType", tLens))
    println(formatStats("proof",    pLens))

    // Premises histogram
    val premiseCounts =
      rows.iterator.flatMap(_.premises).toVector
        .groupBy(identity).view.mapValues(_.size).toVector
        .sortBy{ case (_,c) => -c }
    println(s"\n--- Premises (top-$topK) ---")
    premiseCounts.take(topK).zipWithIndex.foreach { case ((p,c),i) =>
      println(f"#${i+1}%2d  ${c}%6d  $p")
    }

    // Modules histogram
    val moduleCounts =
      rows.iterator.map(_.module.getOrElse("<none>")).toVector
        .groupBy(identity).view.mapValues(_.size).toVector
        .sortBy{ case (_,c) => -c }
    println(s"\n--- Modules (top-$topK) ---")
    moduleCounts.take(topK).zipWithIndex.foreach { case ((m,c),i) =>
      println(f"#${i+1}%2d  ${c}%6d  $m")
    }

    // Premises-per-row histogram
    val premSizes = rows.iterator.map(_.premises.size).toVector
    val premHist  = premSizes.groupBy(identity).view.mapValues(_.size).toVector.sortBy(_._1)
    println("\n--- Premises-per-row distribution ---")
    premHist.foreach { case (k,n) => println(f"k=$k%2d : $n%6d rows") }

    // Lightweight self-premise probe (heuristic): name appears among premises
    val selfPrem = rows.count(r => r.premises.exists(_ == r.name))
    println(s"\nheuristic self-premises (name ∈ premises): $selfPrem")
  }

  // --- IO helpers -----------------------------------------------------------
  /** Read a JSONL file and materialize inside Using to avoid closed streams. */
  private def readJsonlVec[A: Reader](path: String): Vector[A] =
    Using.resource(Source.fromFile(path)) { src =>
      src.getLines().iterator
        .map(_.trim).filter(_.nonEmpty)
        .map(s => read[A](s))
        .toVector
    }

  // --- Stats helpers --------------------------------------------------------
  private def strlen(s: String): Int = s.codePointCount(0, s.length)

  private def formatStats(label: String, xs: Vector[Int]): String = {
    if (xs.isEmpty) return f"$label%-10s | (no data)"
    val ys  = xs.sorted
    def pct(p: Double): Int = ys(((ys.size - 1) * p).toInt)
    val avg = ys.sum.toDouble / ys.size
    f"$label%-10s | min=${ys.head}%d  p50=${pct(0.50)}%d  p90=${pct(0.90)}%d  p99=${pct(0.99)}%d  max=${ys.last}%d  avg=${avg}%.1f"
  }
}
