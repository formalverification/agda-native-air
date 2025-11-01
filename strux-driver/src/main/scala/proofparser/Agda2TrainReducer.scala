/**
 * Agda2TrainReducer.scala
 *
 * FILE
 *   proof-parser/src/main/scala/proofparser/Agda2TrainReducer.scala
 *
 * DESCRIPTION
 *   Reduces Agda2Train JSON dumps into compact, human-readable JSONL training rows
 *   (TrainRecord). Focuses on file/module/decl, pretty types/terms, optional ranges,
 *   and imports; leaves context empty for v1.
 *
 * USAGE
 *   sbt "project proof-parser" \
 *       "runMain proofparser.Agda2TrainReducer <in.json|jsonl> <out.jsonl>"
 *
 * EXAMPLES
 *   sbt "project proof-parser" \
 *       "runMain proofparser.Agda2TrainReducer proof-parser/src/test/resources/agda-example.json target/a2t.simple.jsonl"
 *   # Output: one JSONL line per declaration with fields: file, module, decl, goalType, solution, imports, (range?)
 *
 * NOTES
 *   - Input can be a single JSON object/array or JSONL.
 *   - v1: context (telescope) is not filled; v2 will map binders → CtxVar.
 *   - Safe against minor schema drift by probing multiple common keys.
 *
 * (c) 2025 Thmpr Lab, LLC.
 */

package proofparser

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Paths, Path}
import scala.util.control.NonFatal
import scala.jdk.CollectionConverters._
import upickle.default._
import proofparser.AgdaJsonParser._

/** Reduce Agda2Train JSON → compact, human-friendly TrainRecord JSONL.
  *
  * Input:
  *   - A single JSON document (object or array), OR
  *   - JSON Lines (one JSON per line).
  *
  * Output:
  *   - JSONL where each line is a proofparser.TrainRecord
  *
  * What we extract now (v1):
  *   - file, module (qualified), decl (qualified)
  *   - goalType (pretty), solution (pretty; multi-clause joined), imports
  *   - context = Nil (telescope integration in v2)
  *   - range if present
  *
  * CLI:
  *   sbt "project proof-parser" \
  *       "runMain proofparser.Agda2TrainReducer <in.json|jsonl> <out.jsonl>"
  */
object Agda2TrainReducer {

  // ---- tiny helpers ---------------------------------------------------------

  private def slurp(path: Path): String =
    new String(Files.readAllBytes(path), StandardCharsets.UTF_8)

  private def isLikelyJsonl(s: String): Boolean =
    s.linesIterator.take(5).exists(_.trim.startsWith("{")) &&
    s.trim.nonEmpty &&
    !s.trim.startsWith("{") && !s.trim.startsWith("[")

  private def tryArr(v: ujson.Value): List[ujson.Value] = v match {
    case ujson.Arr(values) => values.toList
    case x                 => List(x)
  }

  private def readAnyJson(path: Path): List[ujson.Value] = {
    val s = slurp(path)
    if (isLikelyJsonl(s)) {
      // s.linesIterator.filter(_.trim.nonEmpty).map(ujson.read).toList
      s.linesIterator.filter(_.trim.nonEmpty).map(line => ujson.read(line)).toList
    } else {
      tryArr(ujson.read(s))
    }
  }

  private def objOpt(v: ujson.Value, key: String): Option[ujson.Value] =
    v.obj.get(key)

  private def arrOpt(v: ujson.Value, key: String): List[ujson.Value] =
    v.obj.get(key).collect { case a: ujson.Arr => a.value.toList }.getOrElse(Nil)

  // ---- model adapters to SimpleSchema.scala ----------------------------

  private def readPos(v: ujson.Value): Option[Pos] = for {
    l <- v.obj.get("line").flatMap(_.numOpt).map(_.toInt)
    c <- v.obj.get("col").flatMap(_.numOpt).map(_.toInt)
  } yield Pos(l, c)

  private def readRange(v: ujson.Value): Option[Range] = for {
    s <- v.obj.get("start").flatMap(readPos)
    e <- v.obj.get("end").flatMap(readPos)
  } yield Range(s, e)

  // ---- reduction logic ------------------------------------------------------

  /** A tolerant walker that tries to recognize “declaration-like” objects:
    * something with a name + type + body/clauses and (ideally) module, file, range.
    *
    * Since Agda2Train schemas vary slightly across versions, we probe multiple keys.
    */
  private def reduceOneDoc(root: ujson.Value): List[TrainRecord] = {
    val buf = scala.collection.mutable.ListBuffer.empty[TrainRecord]

    def scan(v: ujson.Value, parentModule: Option[String], parentFile: Option[String]): Unit = v match {
      case o: ujson.Obj =>
        val module =
          optStr(o, "module")
            .orElse(optStr(o, "moduleName"))
            .orElse(optStr(o, "modName"))
            .orElse(parentModule)

        val file =
          optStr(o, "file")
            .orElse(optStr(o, "path"))
            .orElse(parentFile)

        // Potential names for the declared identifier
        val name =
          optStr(o, "decl")
            .orElse(optStr(o, "declName"))
            .orElse(optStr(o, "declaredName"))
            .orElse(optStr(o, "name"))

        // Type pretty (or fallback)
        val typePretty =
          objOpt(o, "type").flatMap(pickPretty)
            .orElse(optStr(o, "typePretty"))
            .orElse(optStr(o, "declaredType"))
            .orElse(optStr(o, "signature"))
            .orElse(optStr(o, "sig"))
            .orElse(pickPretty(o.obj.getOrElse("ty", ujson.Null)))

        // Definition pretty / clauses pretty
        val rhsPretty =
          objOpt(o, "rhs").flatMap(pickPretty)
            .orElse(objOpt(o, "def").flatMap(pickPretty))
            .orElse(objOpt(o, "definition").flatMap(pickPretty))

        // Some dumps put clauses as an array; join their pretty strings
        val clauseStrings: List[String] =
          arrOpt(o, "clauses").flatMap(pickPretty)

        // imports / opens lists often live near module root
        val imports: List[String] =
          pickStringArray(o, "imports", "opens", "openImports")

        val range: Option[Range] =
          objOpt(o, "range").flatMap(readRange)

        // Is this object good enough to be a declaration?
        val isDecl = name.isDefined && (typePretty.isDefined || rhsPretty.isDefined || clauseStrings.nonEmpty)

        if (isDecl) {
          val modName = module.getOrElse("")
          val localDecl = name.get  // keep local; module carries the qualifier

          val solutionPretty = (rhsPretty.toList ++ (if (clauseStrings.nonEmpty) List(clauseStrings.mkString("\n")) else Nil)) match {
            case Nil    => None
            case single => Some(single.mkString("\n"))
          }

          val rec0 = TrainRecord(
            file     = file.getOrElse(""),
            module   = modName,
            decl     = localDecl,
            context  = Nil, // v1: leave empty; v2 will map telescope binders here
            goalType = typePretty.getOrElse(""),
            solution = solutionPretty,
            range    = range,
            imports  = imports
          )
          buf += TrainRecordOps.normalize(rec0)
        }

        // Continue scanning children: be generous and scan all values
        o.value.values.foreach(scan(_, module.orElse(parentModule), file.orElse(parentFile)))

      case ujson.Arr(values) =>
        values.foreach(scan(_, parentModule, parentFile))

      case _ => ()
    }

    scan(root, None, None)
    buf.toList
  }

  // ---- I/O ------------------------------------------------------------------

  private def writeJsonl(recs: List[TrainRecord], out: Path): Unit = {
    val parent = out.getParent
    if (parent != null) Files.createDirectories(parent)
    val w = Files.newBufferedWriter(out, StandardCharsets.UTF_8)
    try recs.foreach { r => w.write(write(r)); w.write("\n") }
    finally w.close()
  }

  // ---- main -----------------------------------------------------------------

  def main(args: Array[String]): Unit = {
    if (args.length < 2) {
      Console.err.println("Usage: Agda2TrainReducer <in.json|jsonl> <out.jsonl>")
      sys.exit(1)
    }
    val in  = Paths.get(args(0))
    val out = Paths.get(args(1))

    try {
      val docs = readAnyJson(in)
      val recs = docs.flatMap(reduceOneDoc)
      writeJsonl(recs, out)
      println(s"wrote ${recs.size} examples to $out")
    } catch {
      case NonFatal(e) =>
        Console.err.println(s"[Agda2TrainReducer] error: ${e.getMessage}")
        sys.exit(2)
    }
  }
}
