/** ============================================================================
 *  PremiseEval.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: strux-driver/src/main/scala/struxdriver/util/PremiseEval.scala
 *  Package: struxdriver.util
 *
 *  Description
 *  ----------
 *  A unified micro-benchmark for premise selection with two modes:
 *
 *  1. Single-file mode (default):
 *       - Input: one JSONL of canonical `Row` (AgdaData) rows where
 *         `premises` are the gold labels.
 *       - Train/test split is deterministic hash-based on (file, module, name).
 *       - Baselines:
 *           * GlobalFreq   – global premise frequency ranker.
 *           * PerModuleFreq – per-module premise frequency, backed by GlobalFreq.
 *
 *  2. Two-file mode (retrieval):
 *       - Input: <agda-data.jsonl> <goals.jsonl>
 *         where agda-data.jsonl contains canonical `AgdaData` rows and
 *         goals.jsonl contains `TrainGoal` rows (goalType + imports).
 *       - Builds a bag-of-words TF index over (agdaType \n proof).
 *       - Retrieves nearest neighbors for each goal via dot product.
 *       - Unions their premises and evaluates recall@K against the goal's
 *         imports (gold premises).
 *
 *  Key traits
 *  ----------
 *  - Deterministic: no RNG; split uses FNV-1a hash on (file,module,name).
 *  - Fast baselines: simple frequency-based rankers in mode 1.
 *  - Lightweight retrieval in mode 2 (TF + dot product).
 *  - Metrics: macro Precision@K, Recall@K, F1@K, Coverage.
 *
 *  Schema
 *  ------
 *    - Row       = struxdriver.schema.AgdaData
 *    - TrainGoal = struxdriver.schema.TrainGoal
 *
 *  Usage
 *  -----
 *     # Mode 1 (single-file, baselines)
 *     sbt "runMain struxdriver.util.PremiseEval data/train.jsonl --k 10 --split 90"
 *
 *     # Mode 2 (two-file retrieval)
 *     sbt "runMain struxdriver.util.PremiseEval data/agda.jsonl data/goals.jsonl --k 10"
 *
 *  ============================================================================
 */

package struxdriver.util

import scala.io.Source
import scala.util.Try

import upickle.default._
import struxdriver.schema.{ AgdaData, TrainGoal}

object PremiseEval {

  // ===========================================================================
  // CLI
  // ===========================================================================

  def main(args: Array[String]): Unit = {
    if (args.isEmpty) {
      Console.err.println(
        "Usage:\n" +
          "  PremiseEval <in.jsonl> [--k K] [--split PCT]\n" +
          "  PremiseEval <agda.jsonl> <goals.jsonl> [--k K]"
      )
      sys.exit(1)
    }

    val kArg   = args.sliding(2, 1).collectFirst { case Array("--k", n)     => n.toInt }.getOrElse(10)
    val splitP = args.sliding(2, 1).collectFirst { case Array("--split", p) => p.toInt }.getOrElse(90)

    // Detect mode by number of non-flag arguments
    val dataArgs = args.takeWhile(!_.startsWith("--"))
    val result   =
      dataArgs.length match {
        case 1 => runSingleFile(dataArgs(0), kArg, splitP)
        case 2 => runTwoFile(dataArgs(0), dataArgs(1), kArg)
        case _ => Left("Bad arguments: expected 1 or 2 JSONL paths before flags.")
      }

    result match {
      case Left(err) =>
        Console.err.println(s"[PremiseEval] error: $err")
        sys.exit(2)
      case Right(_) =>
        () // all printing done inside the functions
    }
  }

  // ===========================================================================
  // IO helpers (Either-based, no unchecked exceptions)
  // ===========================================================================

  private def readJsonlVec[A: Reader](path: String): Either[String, Vector[A]] =
    Try {
      val src = Source.fromFile(path)
      try {
        src.getLines().zipWithIndex.foldLeft[Either[String, Vector[A]]](Right(Vector.empty)) {
          case (Left(err), _) => Left(err)
          case (Right(acc), (line, idx)) =>
            val trimmed = line.trim
            if (trimmed.isEmpty) Right(acc)
            else
              Try(read[A](trimmed)).toEither.left
                .map(e => s"$path:${idx + 1}: ${e.getMessage}")
                .map(v => acc :+ v)
        }
      } finally {
        src.close()
      }
    }.toEither.left.map(_.getMessage) match {
      case Left(err) => Left(err)
      case Right(result) => result
    }

  // ===========================================================================
  // Mode 1: single-file, frequency baselines
  // ===========================================================================

  private def runSingleFile(in: String, k: Int, pct: Int): Either[String, Unit] =
    for {
      rows <- readJsonlVec[AgdaData](in)
    } yield {
      if (rows.isEmpty) {
        println(s"No rows in $in")
      } else {
        val (train, test) = hashSplit(rows, pct)

        // Ensure at least one test row (if dataset non-empty)
        val (train1, test1) =
          if (rows.nonEmpty && test.isEmpty && train.nonEmpty)
            (train.dropRight(1), train.takeRight(1))
          else
            (train, test)

        println(s"train: ${train1.size}  test: ${test1.size}  (split=${pct}%)")
        if (test1.isEmpty) println("hint: try --split 50 or a larger dataset")

        val global = GlobalFreq(train1)
        val perMod = PerModuleFreq(train1)

        println("\n=== GlobalFreq baseline ===")
        printReport(evaluate(global, test1, k, label = s"GlobalFreq@$k"))

        println("\n=== PerModuleFreq baseline ===")
        printReport(evaluate(perMod, test1, k, label = s"PerModuleFreq@$k"))
      }
    }

  // deterministic hash-based split
  private def hashSplit(rows: Vector[AgdaData], pctTrain: Int): (Vector[AgdaData], Vector[AgdaData]) = {
    val (tr, te) = rows.partition { r =>
      val key = s"${r.file}|${r.module.getOrElse("")}|${r.name}"
      (stableHash(key) % 100) < pctTrain
    }
    (tr, te)
  }

  /** FNV-1a 32-bit hash, implemented functionally. */
  private def stableHash(s: String): Int = {
    val prime = 16777619
    val bytes = s.getBytes("UTF-8")
    val h     = bytes.foldLeft(0x811c9dc5) { (hash, b) =>
      (hash ^ (b & 0xff)) * prime
    }
    h & 0x7fffffff
  }

  // ===========================================================================
  // Baseline predictors (Mode 1)
  // ===========================================================================

  trait Predictor {
    def predict(row: AgdaData, k: Int): List[String]
  }

  object GlobalFreq {
    def apply(train: Seq[AgdaData]): GlobalFreq = {
      val ranking =
        train.iterator
          .flatMap(_.premises)
          .toVector
          .groupBy(identity)
          .map { case (k, v) => (k, v.size) }
          .toVector
          .sortBy { case (_, c) => -c }
          .map(_._1)
          .toVector

      new GlobalFreq(ranking)
    }
  }

  final class GlobalFreq private (ranking: Vector[String]) extends Predictor {
    def predict(row: AgdaData, k: Int): List[String] =
      ranking.take(k).toList
  }

  object PerModuleFreq {
    def apply(train: Seq[AgdaData]): PerModuleFreq = {
      val global = GlobalFreq(train)

      val byMod: Map[String, Vector[String]] = {
        val grouped = train.groupBy(_.module.getOrElse("<none>"))
        grouped.map { case (mod, rs) =>
          val ranking = rs.iterator
            .flatMap(_.premises)
            .toVector
            .groupBy(identity).view.map { case (k, v) => (k, v.size) }.toVector
            .sortBy { case (_, c) => -c }
            .map(_._1)
            .toVector
          (mod, ranking)
        }
      }

      new PerModuleFreq(global, byMod)
    }
  }

  final class PerModuleFreq private (
    global: GlobalFreq,
    byMod: Map[String, Vector[String]]
  ) extends Predictor {
    def predict(row: AgdaData, k: Int): List[String] = {
      val modKey = row.module.getOrElse("<none>")
      val base   = byMod.getOrElse(modKey, global.predict(row, Int.MaxValue).toVector)
      base.take(k).toList
    }
  }

  // ===========================================================================
  // Metrics for Mode 1
  // ===========================================================================

  final case class Report(
    label: String,
    k: Int,
    precision: Double,
    recall: Double,
    f1: Double,
    coverage: Double,
    support: Int
  )

  private final case class Acc(
    precSum: Double,
    recSum: Double,
    covered: Int,
    support: Int
  )

  private def evaluate(model: Predictor, test: Seq[AgdaData], k: Int, label: String): Report = {
    val acc = test.foldLeft(Acc(0.0, 0.0, covered = 0, support = 0)) {
      case (acc0, r) =>
        val gold = r.premises.toSet
        if (gold.isEmpty) acc0
        else {
          val pred = model.predict(r, k).toSet
          val tp   = (gold intersect pred).size.toDouble
          val p    = if (pred.nonEmpty) tp / pred.size else 0.0
          val rcl  = tp / gold.size
          val cov  = if (tp > 0.0) 1 else 0

          Acc(
            precSum = acc0.precSum + p,
            recSum  = acc0.recSum + rcl,
            covered = acc0.covered + cov,
            support = acc0.support + 1
          )
        }
    }

    val precision = if (acc.support > 0) acc.precSum / acc.support else 0.0
    val recall    = if (acc.support > 0) acc.recSum  / acc.support else 0.0
    val f1        = if (precision + recall > 0.0) 2 * precision * recall / (precision + recall) else 0.0
    val coverageP = if (acc.support > 0) acc.covered.toDouble / acc.support.toDouble else 0.0

    Report(label, k, precision, recall, f1, coverageP, acc.support)
  }

  private def printReport(r: Report): Unit = {
    println(f"label=${r.label}  k=${r.k}%d  support=${r.support}%d")
    println(f"precision@k=${r.precision}%.4f  recall@k=${r.recall}%.4f  f1=${r.f1}%.4f  coverage=${r.coverage}%.4f")
  }

  // ===========================================================================
  // Mode 2: two-file retrieval (bag-of-words TF dot-product)
  // ===========================================================================

  private def runTwoFile(agdaJsonl: String, goalsJsonl: String, k: Int): Either[String, Unit] =
    for {
      decls <- readJsonlVec[AgdaData](agdaJsonl)
      goals <- readJsonlVec[TrainGoal](goalsJsonl)
    } yield {
      val declTfs: Vector[(AgdaData, Map[String, Int])] =
        decls.map { r =>
          val txt  = r.agdaType.getOrElse("") + "\n" + r.proof.getOrElse("")
          val tfv  = tf(tokens(txt))
          (r, tfv)
        }

      val goalTfs: Vector[(TrainGoal, Map[String, Int])] =
        goals.map { g =>
          val tfv = tf(tokens(g.goalType))
          (g, tfv)
        }

      val support = goalTfs.count { case (g, _) => g.premises.nonEmpty }

      val hits = goalTfs.foldLeft(0) {
        case (accHits, (qg, qtf)) =>
          val topPremises =
            declTfs.iterator
              .map { case (d, dtf) => (dot(qtf, dtf), d) }
              .filter(_._1 > 0)
              .toVector
              .sortBy { case (score, _) => -score }
              .take(8) // union premises from top-8 neighbors
              .flatMap(_._2.premises)
              .distinct
              .take(k)

          val gold = qg.premises.toSet
          if (gold.nonEmpty && topPremises.exists(gold.contains)) accHits + 1
          else accHits
      }

      val recallAtK =
        if (support == 0) 0.0
        else hits.toDouble / support.toDouble

      println(f"retrieval recall@$k on goals-with-gold: $recallAtK%.3f  (hits=$hits/$support)")
    }

  // ===========================================================================
  // Bag-of-words helpers
  // ===========================================================================

  private def tokens(s: String): Array[String] =
    s.toLowerCase
      .replaceAll("[^\\p{L}0-9]+", " ")
      .trim
      .split("\\s+")
      .filter(_.nonEmpty)

  private def tf(toks: Array[String]): Map[String, Int] =
    toks.groupBy(identity).view.map { case (k, v) => (k, v.length) }.toMap

  private def dot(a: Map[String, Int], b: Map[String, Int]): Int =
    if (a.size <= b.size)
      a.iterator.map { case (k, v) => v * b.getOrElse(k, 0) }.sum
    else
      b.iterator.map { case (k, v) => v * a.getOrElse(k, 0) }.sum
}
