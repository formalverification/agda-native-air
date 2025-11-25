/** ============================================================================
 *  DatasetStats.scala
 *  -----------------------------------------------------------------------------
 *
 *  File: src/main/scala/proofparser/util/DatasetStats.scala
 *  Package: proofparser.util
 *  Copyright: (c) 2024-2025 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  Dataset statistics tool for canonical AgdaData JSONL datasets.
 *
 *  The purpose of this tool is to give immediate insight into:
 *
 *      • dataset size
 *      • distribution of declaration kinds
 *      • lengths of types and proofs (Unicode codepoints)
 *      • module distribution
 *      • premise distribution
 *      • premises-per-row histogram
 *      • basic invariants (non-empty fields, self-premise counts)
 *
 *  This refactored version uses the **canonical schema**:
 *
 *      import proofparser.schema.Row   // type alias for AgdaData
 *
 *  It is fully functional:
 *
 *      • no mutable state
 *      • no exceptions (Except in CLI wrapper)
 *      • referentially transparent helpers
 *
 *  And fully Spark-ready:
 *
 *      All “core” computations are pure functions on `Vector[Row]`,
 *      so they can be lifted to Spark RDDs or Datasets trivially.
 *
 *  Usage
 *  -----
 *      sbt "runMain proofparser.util.DatasetStats data/train.jsonl --top 20"
 *
 *  ============================================================================ */

package proofparser.util

import scala.io.Source
import scala.util.Using

import upickle.default._
import proofparser.schema._                // brings Row = AgdaData into scope

object DatasetStats {

  // ===========================================================================
  //  Public CLI
  // ===========================================================================

  def main(args: Array[String]): Unit = {
    if (args.isEmpty) {
      Console.err.println("Usage: DatasetStats <in.jsonl> [--top K]")
      sys.exit(1)
    }

    val in   = args(0)
    val topK = args.sliding(2, 1).collectFirst {
      case Array("--top", k) => k.toInt
    }.getOrElse(20)

    val rows = readJsonlVec[Row](in)
    if (rows.isEmpty) {
      println(s"No rows found in $in")
      sys.exit(0)
    }

    val report = summarize(rows, topK)
    println(report)
  }

  // ===========================================================================
  //  Pure dataset analysis (Spark-ready)
  // ===========================================================================

  /** Produce a human-readable multi-line statistics report. */
  def summarize(rows: Vector[Row], topK: Int): String = {
    val b = new StringBuilder

    val distinctNames   = rows.iterator.map(_.name).toSet.size
    val nonEmptyTypes   = rows.count(_.agdaType.exists(_.trim.nonEmpty))
    val nonEmptyProofs  = rows.count(_.proof.exists(_.trim.nonEmpty))
    val nonEmptyPremise = rows.count(_.premises.nonEmpty)

    b.append("\n=== Dataset Summary ===\n")
    b.append(f"rows:                ${rows.size}\n")
    b.append(f"distinct names:      $distinctNames\n")
    b.append(f"non-empty type:      $nonEmptyTypes\n")
    b.append(f"non-empty proof:     $nonEmptyProofs\n")
    b.append(f"non-empty premises:  $nonEmptyPremise\n")

    // lengths
    val typeLens =
      rows.map(r => strlen(r.agdaType.getOrElse("")))
    val proofLens =
      rows.map(r => strlen(r.proof.getOrElse("")))

    b.append("\n--- Lengths (Unicode codepoints) ---\n")
    b.append(formatStats("type",  typeLens) + "\n")
    b.append(formatStats("proof", proofLens) + "\n")

    // declaration kinds
    val kindCounts =
      rows.groupBy(_.declKind.asString).view.mapValues(_.size).toVector
        .sortBy { case (_, c) => -c }

    b.append("\n--- Declaration Kinds ---\n")
    kindCounts.foreach { case (k, c) =>
      b.append(f"$k%-12s : $c%6d\n")
    }

    // Premise histogram
    val premiseCounts =
      rows.flatMap(_.premises).groupBy(identity).view.mapValues(_.size).toVector
        .sortBy { case (_, c) => -c }

    b.append(s"\n--- Premises (top-$topK) ---\n")
    premiseCounts.take(topK).zipWithIndex.foreach { case ((p, c), i) =>
      b.append(f"#${i+1}%2d  ${c}%6d  $p\n")
    }

    // Modules histogram
    val moduleCounts =
      rows.map(_.module.getOrElse("<none>"))
        .groupBy(identity).view.mapValues(_.size).toVector
        .sortBy{ case (_, c) => -c }

    b.append(s"\n--- Modules (top-$topK) ---\n")
    moduleCounts.take(topK).zipWithIndex.foreach { case ((m, c), i) =>
      b.append(f"#${i+1}%2d  ${c}%6d  $m\n")
    }

    // Premises-per-row histogram
    val premSizes =
      rows.map(_.premises.size)
    val premHist =
      premSizes.groupBy(identity).view.mapValues(_.size).toVector.sortBy(_._1)

    b.append("\n--- Premises-per-row distribution ---\n")
    premHist.foreach { case (k, n) =>
      b.append(f"k=$k%2d : $n%6d rows\n")
    }

    // Detect rows where name reappears in premises
    val selfPrem =
      rows.count(r => r.premises.contains(r.name))

    b.append(s"\nheuristic self-premises (name ∈ premises): $selfPrem\n")

    b.toString
  }

  // ===========================================================================
  //  IO helpers (purely functional)
  // ===========================================================================

  /** Read a JSONL file into a Vector[A] safely. */
  private def readJsonlVec[A: Reader](path: String): Vector[A] =
    Using.resource(Source.fromFile(path)) { src =>
      src.getLines().iterator
        .map(_.trim)
        .filter(_.nonEmpty)
        .flatMap { line =>
          // safe read: catch JSON parse errors as None
          scala.util.Try(read[A](line)).toOption
        }
        .toVector
    }

  // ===========================================================================
  //  Statistics helpers
  // ===========================================================================

  /** Codepoint-aware string length. */
  private def strlen(s: String): Int =
    s.codePointCount(0, s.length)

  /** Format 5-number summary + avg for a vector of integers. */
  private def formatStats(label: String, xs: Vector[Int]): String = {
    if (xs.isEmpty)
      return f"$label%-10s | (no data)"

    val ys = xs.sorted
    def pct(p: Double): Int = {
      val idx = ((ys.size - 1) * p).toInt
      ys(idx)
    }

    val avg = ys.sum.toDouble / ys.size
    f"$label%-10s | min=${ys.head}%d  p50=${pct(0.50)}%d  p90=${pct(0.90)}%d  p99=${pct(0.99)}%d  max=${ys.last}%d  avg=${avg}%.1f"
  }
}
