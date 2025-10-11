/**
 * AgdaSimplifiedExtractor.scala
 *
 * File: proof-parser/src/main/scala/proofparser/AgdaSimplifiedExtractor.scala
 *
 * Description:
 *   Minimal end-to-end extractor using `agda --interaction-json`.
 *   Loads modules, listens for goal/pretty info, and emits simplified JSONL.
 *
 * Usage:
 *   sbt "project proof-parser" \
 *       "runMain proofparser.AgdaSimplifiedExtractor <root-dir> <out.jsonl> [--include DIR]* [--lib LIB]*"
 *
 * Examples:
 *   sbt "project proof-parser" \
 *       "runMain proofparser.AgdaSimplifiedExtractor agda/ target/simple.jsonl --include . --lib standard-library"
 *
 * Notes:
 *   - v1 focuses on “AllGoalsWarnings”/pretty output. For solved files with no holes,
 *     prefer Agda2Train-based reducers to recover RHS/clauses and ranges.
 *   - Extend with solution tracking (give/solve) and telescope extraction in v2.
 *
 * (c) 2025 Thmpr Lab, LLC.
 */

package proofparser

import java.nio.file.{Files, Path, Paths}
import scala.jdk.CollectionConverters._
import scala.util.control.NonFatal
import upickle.default._


object AgdaSimplifiedExtractor {

  private def agdaFiles(root: Path): List[Path] =
    Files.walk(root).iterator().asScala
      .filter(p => Files.isRegularFile(p) && p.getFileName.toString.endsWith(".agda"))
      .toList

  // Very simple module extraction (works for “module X where” in the first 100 lines)
  private def moduleName(p: Path): String = {
    val lines = Files.readAllLines(p).asScala.take(100).mkString("\n")
    val M = """(?m)^\s*module\s+([A-Za-z0-9\._']+)\s+where""".r
    M.findFirstMatchIn(lines).map(_.group(1)).getOrElse(p.getFileName.toString.stripSuffix(".agda"))
  }

  /** Pull out human-printed context/goals from “AllGoalsWarnings” payload.
    * NOTE: we’re deliberately “schema-lite”: we pick pretty-printed strings Agda emits.
    */
  private def extractGoalsPretty(msg: ujson.Value): List[(List[CtxVar], String)] = {
    // The structure varies a bit across Agda versions; we walk the value looking for
    // arrays of goal blocks that contain: "type" (goal type pretty) and "context" items.
    def collect(v: ujson.Value, acc: List[(List[CtxVar], String)]): List[(List[CtxVar], String)] = v match {
      case ujson.Obj(o) =>
        val fromHere =
          for {
            info <- o.get("info").toList
            if info.obj.get("kind").exists(_.str == "AllGoalsWarnings")
            body <- info.obj.get("payload").toList
            // body is often a string with pretty-printed text; if so, we can’t structurally parse.
            // Newer Agda emits structured fields inside; handle both.
          } yield {
            // Try structured
            val goals = body.obj.get("goals")
            goals match {
              case Some(arr) =>
                arr.arr.toList.flatMap { g =>
                  val gtype = g.obj.get("type").flatMap(_.strOpt).orElse(g.obj.get("type").map(_.render())).getOrElse("")
                  val ctx   = g.obj.get("context").toList.flatMap {
                    case ujson.Arr(items) =>
                      items.toList.flatMap { it =>
                        val nm = it.obj.get("name").flatMap(_.strOpt)
                        val tp = it.obj.get("type").flatMap(_.strOpt).orElse(it.obj.get("type").map(_.render()))
                        (nm, tp) match {
                          case (Some(n), Some(t)) => Some(CtxVar(n, t))
                          case _ => None
                        }
                      }
                    case _ => Nil
                  }
                  List((ctx, gtype))
                }
              case None =>
                // Fallback: try to split pretty text, crude but usable for minimal MVP.
                // We return nothing here to avoid brittle heuristics by default.
                Nil
            }
          }
        fromHere.flatten ++ o.values.toList.flatMap(collect(_, Nil))
      case ujson.Arr(xs) => xs.toList.flatMap(collect(_, Nil))
      case _ => acc
    }
    collect(msg, Nil)
  }

  /** Entry: run Agda on a single file and harvest training records. */
  def runOnFile(file: Path, include: Seq[String], libs: Seq[String]): List[TrainRecord] = {
    val bridge = new AgdaBridge()
    try {
      bridge.start()
      // bridge.send(AgdaIOTCM.load(file.toString, include, libs))
      bridge.send(AgdaIOTCM.load(file.toString, include, libs).toString)

      val mod = moduleName(file)
      var out: List[TrainRecord] = Nil

      var keepReading = true
      val startTime = System.currentTimeMillis()

      while (keepReading && System.currentTimeMillis() - startTime < 20000) {
        bridge.readLine() match {
          case None =>
            keepReading = false

          case Some(msg) =>
            // if (AgdaMsgs.isAllGoals(msg)) {
            if (AgdaMsgs.isAllGoals(msg)) {
              val pairs = extractGoalsPretty(msg)
              // We don’t know decl name reliably from this message alone; use file stem for MVP.
              val decl = file.getFileName.toString.stripSuffix(".agda")
              val recs = pairs.map { case (ctx, gty) =>
                TrainRecord(
                  file = file.getFileName.toString,
                  module = mod,
                  decl = decl,
                  context = ctx,
                  goalType = gty,
                  solution = None,
                  range = None,
                  imports = Nil
                )
              }
              out = out ++ recs
            }
        }
      }
      out
    } catch {
      case NonFatal(e) =>
        System.err.println(s"[AgdaSimplifiedExtractor] ${file}: ${e.getMessage}")
        Nil
    } finally bridge.stop()
  }

  def writeJsonl(records: List[TrainRecord], outPath: Path): Unit = {
    val parent = outPath.getParent
    if (parent != null) Files.createDirectories(parent)
    val w = Files.newBufferedWriter(outPath)
    try {
      records.foreach { r =>
        w.write(write(r))
        w.write("\n")
      }
    } finally w.close()
  }

  /** CLI:
    *   runMain proofparser.AgdaSimplifiedExtractor <agda-root> <out.jsonl> [--include path]* [--lib stdlib]*
    */
  def main(args: Array[String]): Unit = {
    if (args.length < 2) {
      Console.err.println("Usage: AgdaSimplifiedExtractor <root> <out.jsonl> [--include DIR]* [--lib LIB]*")
      sys.exit(1)
    }
    val root = Paths.get(args(0))
    val out  = Paths.get(args(1))

    // collect options
    var inc: List[String] = Nil
    var libs: List[String] = Nil
    var i = 2
    while (i < args.length) {
      args(i) match {
        case "--include" if i+1 < args.length => inc = inc :+ args(i+1); i += 2
        case "--lib"     if i+1 < args.length => libs = libs :+ args(i+1); i += 2
        case other =>
          Console.err.println(s"Unrecognized option: $other")
          i += 1
      }
    }

    val files = agdaFiles(root)
    val recs  = files.flatMap(p => runOnFile(p, inc, libs))
    writeJsonl(recs, out)
    println(s"wrote ${recs.size} examples to $out")
  }
}
