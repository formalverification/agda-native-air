/** ============================================================================
 *  PremiseEval.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/PremiseEval.scala
 *  Package: proofparser
 *  Copyright: (c) 2024 Thmpr Lab, LLC.
 *
 *  Description
 *  ----------
 *  A unified micro-benchmark for premise selection with two modes:
 *  1.  Single-file mode (default): one JSONL of training rows where
 *      `premises` are the gold labels. Train/test split is hash-based.
 *  2.  Two-file mode (retrieval): <agda-data.jsonl> <goals.jsonl> —
 *      builds a TF bag-of-words index over (agdaType \n proof), retrieves
 *      nearest neighbors for each goal, unions their premises, and evaluates
 *      recall@K against the goal's imports (gold premises).
 *
 *  Key traits
 *  ----------
 *  - Deterministic: no RNG; split uses FNV-1a hash on (file,module,name)
 *  - Fast baselines: Global/PerModule frequency rankers (mode 1)
 *  - Lightweight retrieval: integer TF + dot-product (mode 2)
 *  - Metrics: macro Precision@K, Recall@K, F1@K, Coverage
 *
 *  Usage
 *  -----
 *     # Mode 1 (single-file, default)
 *     sbt "runMain proofparser.PremiseEval data/train.jsonl --k 10 --split 90"
 *
 *     # Mode 2 (two-file retrieval)
 *     sbt "runMain proofparser.PremiseEval data/agda.jsonl data/goals.jsonl --k 10"
 *
 *  Notes
 *  -----
 *  -  Case classes here mirror only the fields we need; they are intentionally
 *     decoupled from any shared model file to stay robust across refactors.
 *  -  Mode 1 split is stable across runs and machines via hash-based partitioning.
 *  -  Mode 2 uses a simple bag-of-words TF representation for speed; more advanced
 *     embeddings can be slotted in later.
 *  -  Keep the schemas stable to avoid breaking existing corpora.
 *
 *  ============================================================================
 */

package proofparser

import scala.io.Source
import scala.util.Using
import upickle.default._

object PremiseEval {
  // --------- Shared helpers ---------
  private def readJsonlVec[A: Reader](path: String): Vector[A] =
    Using.resource(Source.fromFile(path)) { src =>
      src.getLines().iterator.map(_.trim).filter(_.nonEmpty).map(s => read[A](s)).toVector
    }

  // --------- Mode 1 schema (single file) ---------
  final case class Row(
    file: String,
    module: Option[String],
    name: String,
    agdaType: String,
    proof: String,
    premises: List[String] = Nil
  )
  object Row { implicit val rw: ReadWriter[Row] = macroRW }

  // --------- Mode 2 schema (two files) ---------
  final case class AgdaData(
    file: String,
    module: Option[String],
    name: String,
    agdaType: String,
    proof: String,
    premises: List[String] = Nil
  )
  object AgdaData { implicit val rw: ReadWriter[AgdaData] = macroRW }

  final case class TrainGoal(
    module: Option[String],
    goalType: String,
    imports: List[String] = Nil
  )
  object TrainGoal { implicit val rw: ReadWriter[TrainGoal] = macroRW }

  // --------- CLI ---------
  def main(args: Array[String]): Unit = {
    if (args.isEmpty) {
      Console.err.println("Usage: PremiseEval <in.jsonl> [--k K] [--split PCT]  |  PremiseEval <agda.jsonl> <goals.jsonl> [--k K]");
      sys.exit(1)
    }

    val kArg   = args.sliding(2,1).collectFirst{case Array("--k",n)=>n.toInt}.getOrElse(10)
    val splitP = args.sliding(2,1).collectFirst{case Array("--split",p)=>p.toInt}.getOrElse(90)

    // Detect mode by arity before flags
    val dataArgs = args.takeWhile(!_.startsWith("--"))
    dataArgs.length match {
      case 1 => runSingleFile(dataArgs(0), kArg, splitP)
      case 2 => runTwoFile(dataArgs(0), dataArgs(1), kArg)
      case _ => Console.err.println("Bad arguments."); sys.exit(1)
    }
  }

  // --------- Mode 1: single-file, frequency baselines ---------
  private def runSingleFile(in: String, k: Int, pct: Int): Unit = {
    val rows = readJsonlVec[Row](in)
    if (rows.isEmpty) { println(s"No rows in $in"); return }

    val (train, test) = hashSplit(rows, pct)
    // Ensure we always have at least 1 test when dataset is non-empty.
    val (train1, test1) =
      if (rows.nonEmpty && test.isEmpty && train.nonEmpty) (train.dropRight(1), train.takeRight(1))
      else (train, test)
    println(s"train: ${train1.size}  test: ${test1.size}  (split=${pct}%)")
    if (test1.isEmpty) println("hint: try --split 50 or a larger dataset")

    val global = new GlobalFreq(train1)
    val perMod = new PerModuleFreq(train1)

    println("\n=== GlobalFreq baseline ===")
    printReport(evaluate(global, test1, k, label = s"GlobalFreq@$k"))

    println("\n=== PerModuleFreq baseline ===")
    printReport(evaluate(perMod, test1, k, label = s"PerModuleFreq@$k"))
  }

  // --------- Mode 2: two-file retrieval (TF dot-product) ---------
  private def runTwoFile(agdaJsonl: String, goalsJsonl: String, k: Int): Unit = {
    val decls = readJsonlVec[AgdaData](agdaJsonl).map { r =>
      val tfv = tf(tokens(r.agdaType + "\n" + r.proof))
      (r, tfv)
    }
    val goals = readJsonlVec[TrainGoal](goalsJsonl).map { g =>
      val tfv = tf(tokens(g.goalType))
      (g, tfv)
    }

    val support = goals.count{ case (g, _) => g.imports.nonEmpty }
    var hits = 0

    goals.foreach { case (qg, qtf) =>
      val topPremises = decls.iterator
        .map { case (d, dtf) => (dot(qtf, dtf), d) }
        .filter(_._1 > 0).toVector
        .sortBy(-_._1)
        .take(8)                 // union premises from top-8 neighbors
        .flatMap(_._2.premises)
        .distinct
        .take(k)
      val gold = qg.imports.toSet
      if (gold.nonEmpty && topPremises.exists(gold)) hits += 1
    }

    val recallAtK = if (support == 0) 0.0 else hits.toDouble / support.toDouble
    println(f"retrieval recall@$k on goals-with-gold: $recallAtK%.3f  (hits=$hits/$support)")
  }

  // --------- Split/hash ---------
  private def hashSplit(rows: Vector[Row], pctTrain: Int): (Vector[Row], Vector[Row]) = {
    val (tr, te) = rows.partition { r =>
      val key = s"${r.file}|${r.module.getOrElse("")}|${r.name}"
      (stableHash(key) % 100) < pctTrain
    }
    (tr, te)
  }

  private def stableHash(s: String): Int = {
    val prime = 16777619
    var hash  = 0x811c9dc5
    val bs    = s.getBytes("UTF-8")
    var i = 0
    while (i < bs.length) { hash ^= (bs(i) & 0xff); hash *= prime; i += 1 }
    (hash & 0x7fffffff)
  }

  // --------- Baselines (mode 1) ---------
  trait Predictor { def predict(row: Row, k: Int): List[String] }

  final class GlobalFreq(train: Seq[Row]) extends Predictor {
    private val ranking: Vector[String] =
      train.iterator.flatMap(_.premises).toVector
        .groupBy(identity).view.mapValues(_.size).toVector
        .sortBy{ case (_,c) => -c }
        .map(_._1).toVector
    def predict(row: Row, k: Int): List[String] = ranking.take(k).toList
  }

  final class PerModuleFreq(train: Seq[Row]) extends Predictor {
    private val global = new GlobalFreq(train)
    private val byMod: Map[String, Vector[String]] = {
      val grouped = train.groupBy(_.module.getOrElse("<none>"))
      grouped.view.mapValues { rs =>
        rs.iterator.flatMap(_.premises).toVector
          .groupBy(identity).view.mapValues(_.size).toVector
          .sortBy{ case (_,c) => -c }.map(_._1).toVector
      }.toMap
    }
    def predict(row: Row, k: Int): List[String] =
      byMod.getOrElse(row.module.getOrElse("<none>"), global.predict(row, Int.MaxValue).toVector).take(k).toList
  }

  // --------- Metrics (mode 1) ---------
  final case class Report(label: String, k: Int, precision: Double, recall: Double, f1: Double, coverage: Double, support: Int)

  private def evaluate(model: Predictor, test: Seq[Row], k: Int, label: String): Report = {
    var precSum = 0.0
    var recSum  = 0.0
    var covered = 0
    var support = 0

    test.foreach { r =>
      val gold = r.premises.toSet
      if (gold.nonEmpty) {
        support += 1
        val pred = model.predict(r, k).toSet
        val tp   = (gold intersect pred).size.toDouble
        val p    = if (pred.nonEmpty) tp / pred.size else 0.0
        val rcl  = tp / gold.size
        precSum += p
        recSum  += rcl
        if (tp > 0) covered += 1
      }
    }

    val precision = if (support > 0) precSum / support else 0.0
    val recall    = if (support > 0) recSum  / support else 0.0
    val f1        = if (precision + recall > 0) 2 * precision * recall / (precision + recall) else 0.0
    val coverageP = if (support > 0) covered.toDouble / support.toDouble else 0.0
    Report(label, k, precision, recall, f1, coverageP, support)
  }

  private def tokens(s: String): Array[String] =
    s.toLowerCase.replaceAll("[^\\p{L}0-9]+", " ").trim.split("\\s+").filter(_.nonEmpty)
  private def tf(toks: Array[String]): Map[String, Int] = toks.groupBy(identity).view.mapValues(_.length).toMap
  private def dot(a: Map[String, Int], b: Map[String, Int]): Int =
    if (a.size < b.size) a.iterator.map{ case (k,v) => v * b.getOrElse(k,0) }.sum
    else                 b.iterator.map{ case (k,v) => v * a.getOrElse(k,0) }.sum

  private implicit class ExistsAny[A](as: Iterable[A]) {
    def exists(set: Set[A]): Boolean = as.exists(set.contains)
  }

  private def printReport(r: Report): Unit = {
    println(f"label=${r.label}  k=${r.k}%d  support=${r.support}%d")
    println(f"precision@k=${r.precision}%.4f  recall@k=${r.recall}%.4f  f1=${r.f1}%.4f  coverage=${r.coverage}%.4f")
  }
}
