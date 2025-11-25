/** ============================================================================
 *  SampleGen.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/util/SampleGen.scala
 *  Package: proofparser.util
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  Tiny synthetic generator for JSONL datasets compatible with the canonical
 *  AgdaData schema (proofparser.schema.AgdaData). This is useful for:
 *
 *    • smoke-testing DatasetStats, PremiseEval, and any Scala/Python loaders
 *    • end-to-end CI checks without needing real Agda extraction output
 *
 *  The generator fabricates a small, structured universe of:
 *
 *    • modules       (e.g., Algebra.Basic, Algebra.Group, ...)
 *    • theorems      (names “thm<i>_<j>”)
 *    • types         (“∀ x y z → P_i x → Q_j y → R z”)
 *    • proofs        (“λ x y z → proof_k”)
 *    • premises      (module-qualified names like “Algebra.Basic.assoc”)
 *
 *  All rows are emitted as canonical AgdaData and normalized via AgdaDataOps.
 *
 *  Usage
 *  -----
 *      sbt "runMain proofparser.util.SampleGen out.jsonl --n 16"
 *
 *  ============================================================================
 */

package proofparser.util

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Paths}

import upickle.default._

import proofparser.schema.{AgdaData, AgdaDataOps}
import proofparser.schema.Semantic

object SampleGen {

  // ---------------------------------------------------------------------------
  // Public CLI
  // ---------------------------------------------------------------------------

  def main(args: Array[String]): Unit = {
    if (args.isEmpty) {
      Console.err.println("Usage: SampleGen <out.jsonl> [--n N]")
      sys.exit(1)
    }

    val outPath = args(0)
    val n       = args.sliding(2, 1).collectFirst {
      case Array("--n", x) => x.toInt
    }.getOrElse(16)

    val rows = generate(n)
    writeJsonl(rows, outPath) match {
      case Left(err) =>
        Console.err.println(s"[SampleGen] error: $err")
        sys.exit(2)
      case Right(_) =>
        println(s"[SampleGen] wrote $n synthetic rows to $outPath")
    }
  }

  // ---------------------------------------------------------------------------
  // Pure synthetic generator (Spark-ready core)
  // ---------------------------------------------------------------------------

  /** Generate N canonical, normalized AgdaData rows. */
  def generate(n: Int): Vector[AgdaData] = {
    val modules  = Vector("Algebra.Basic", "Algebra.Group", "Logic.Core", "Data.Vec")
    val premPool = Vector("assoc", "comm", "id-left", "id-right", "distrib", "map-id", "map-comp", "zero", "succ")

    (0 until n).toVector.map { i =>
      val m  = modules(i % modules.size)
      val nm = s"thm${i % 7}_${i}"

      val k   = 1 + (i % 4)
      val off = i % premPool.size
      val ps  = premPool
        .slice(off, off + k)
        .map(p => s"$m.$p")
        .toList

      val tpe   = s"∀ x y z → P${i % 3} x → Q${i % 5} y → R z"
      val proof = s"λ x y z → proof_${i}"

      val sem = Semantic.from(
        name     = nm,
        agdaType = Some(tpe),
        module   = Some(m),
        proof    = Some(proof)
      )

      val raw = AgdaData(
        file     = s"/fake/$m.agda",
        module   = Some(m),
        name     = nm,
        agdaType = Some(tpe),
        proof    = Some(proof),
        premises = ps,
        declKind = sem.kind,
        astSize  = sem.astSize
      )

      AgdaDataOps.normalize(raw)
    }
  }

  // ---------------------------------------------------------------------------
  // IO helpers
  // ---------------------------------------------------------------------------

  private def writeJsonl(rows: Vector[AgdaData], out: String): Either[String, Unit] =
    Either.catchNonFatal {
      val path   = Paths.get(out)
      val parent = path.getParent
      if (parent != null) Files.createDirectories(parent)

      val sb = new StringBuilder
      rows.foreach { r =>
        sb.append(write(r))
        sb.append('\n')
      }
      Files.write(path, sb.result().getBytes(StandardCharsets.UTF_8))
    }.left.map(_.getMessage)
}
