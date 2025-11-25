/** =============================================================================
 *  Agda2TrainTransformer.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/transform/Agda2TrainTransformer.scala
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
 *  Package: proofparser.transform
 *
 *  Purpose
 *  -------
 *    Transform an Agda2train-style JSON dump (our simplified Agda AST
 *    snapshot) into the project’s canonical AgdaData/TrainRecord rows for
 *    downstream training or inspection.  The canonical, line-oriented training
 *    format used across the agda-ai-prover project is one JSON object per line
 *    with fields; specifically,
 *
 *      { file, module?, name, agdaType, proof, premises[] }
 *
 *    This is the data contract that downstream ETL and training code expect.
 *
 *  Context in Project
 *  ------------------
 *    - Upstream:
 *        * `AgdaExtractorMain` (Scala) or other tools produce a single JSON
 *          dump per Agda module (e.g., `agda-example.json`).
 *    - This transformer:
 *        * consumes that JSON (or a JSON Lines file of many such JSON blobs),
 *        * extracts definitions that look like theorems/lemmas/defs,
 *        * normalizes names and premises,
 *        * writes a single JSONL file of `AgdaData` rows.
 *    - Downstream:
 *        * Spark ETL (`PreprocessAgda`) or Python loaders produce features
 *          and feed trainers.
 *
 *  Design Goals
 *  ------------
 *    - **Consistency**: use the same JSON stack (`ujson`/`upickle`) as the
 *      bridge/extractor tools to keep the project uniform.
 *    - **Purity** at the edges: most helpers are total/pure functions; I/O is
 *      localized to two small functions (read whole file, write JSONL).
 *    - **Robust premise filtering**: drop “self-premises” even when spelled
 *      differently (angle suffixes like `<40>`, hidden-module `._.`, or stray
 *      `.agda.` segments).
 *    - **Friendly errors**: if the input is malformed, fail with context.
 *
 *  Input Shape (what we read)
 *  --------------------------
 *    A single JSON object (or JSONL of such objects) with keys like:
 *
 *      {
 *        "name": "agda-example",
 *        "scope-local":   [ <items> ],
 *        "scope-private": [ <items> ]
 *      }
 *
 *    where each item often has:
 *      - "name": "agda-example.properties.+-suc<40>"
 *      - "type": { "pretty": "..." }
 *      - "definition": { "pretty": "..." }
 *      - "holes": [ { "premises": ["agda-example._+_<8>", ...] }, ... ]
 *
 *  Output Shape (what we write)
 *  ----------------------------
 *    One JSON object per line conforming to `AgdaData` from `Model.scala`:
 *      {
 *        "file": "agda-example",
 *        "module": "properties",   // optional
 *        "name": "+-suc<40>",
 *        "agdaType": "…",
 *        "proof": "…",
 *        "premises": [ "qual.id", ... ]
 *      }
 *
 *  CLI
 *  ---
 *    sbt "project proof-parser" \
 *        "runMain proofparser.Agda2TrainTransformer <in.json|jsonl> <out.jsonl>"
 *
 *  Examples
 *  --------
 *    sbt "project proof-parser" \
 *        "runMain proofparser.Agda2TrainTransformer proof-parser/src/test/resources/agda-example.json target/a2t.jsonl"
 *
 *  Testing Tips
 *  ------------
 *    - Unit-test the pure helpers (`parseOne`, `normalizePremise`, `isSelfPremise`)
 *      with small JSON snippets.
 *    - Run on `src/test/resources/agda-example.json` and inspect the JSONL.
 *
 *  Notes
 *  -----
 *   - Ensure only the canonical AgdaData from Model.scala is used (remove duplicate type defs).
 *   - Prefer pretty-printed terms/types from the dump; normalize module/file names.
 *   - Complements Agda2TrainReducer: this file may expose richer fields or a different mapping.
 *
 *  =============================================================================
 */
package proofparser.transform

import java.io.{File, PrintWriter}
import java.nio.file.{Files, Paths}
import scala.io.Source
import scala.util.{Try, Success, Failure}
import upickle.default._
import ujson._

case class TheoremData(file: String, module: Option[String], name: String, body: String)
object TheoremData { implicit val rw: ReadWriter[TheoremData] = macroRW }

// Canonical training record (defined in Model.scala). We import and write it out.
//   case class AgdaData(file: String, module: Option[String], name: String,
//                       agdaType: String, proof: String, premises: List[String])
import proofparser.schema.AgdaData

object Agda2TrainTransformerAlt {

  // ------------------------------------------------------------
  // Small JSON helpers (ujson is dynamically typed)
  // ------------------------------------------------------------
  private type JObject = upickle.core.LinkedHashMap[String, ujson.Value]
  private type JArray  = scala.collection.mutable.ArrayBuffer[ujson.Value]

  private def asObj(v: ujson.Value): Option[JObject] = v match {
    case ujson.Obj(o) => Some(o)
    case _            => None
  }
  private def asArr(v: ujson.Value): Option[JArray] = v match {
    case ujson.Arr(a) => Some(a)
    case _            => None
  }

  private def field(o: JObject, k: String): Option[ujson.Value] = o.get(k)
  private def str(o: JObject, k: String): Option[String]        = field(o, k).flatMap(_.strOpt)

  /** Find `obj[key].pretty` as a String, if present. */
  private def getPretty(o: JObject, key: String): Option[String] =
    field(o, key).flatMap(asObj).flatMap(_.get("pretty")).flatMap(_.strOpt)

  // ------------------------------------------------------------
  // Name normalization & self-premise filtering
  // ------------------------------------------------------------

  /** Strip a trailing `<number>` suffix, e.g., "+-suc<40>" -> "+-suc". */
  private def stripAngle(s: String): String =
    s.replaceAll("<\\d+>$", "")

  /** Remove a single `.agda` extension from the middle or end of a path fragment. */
  private def stripAgdaDot(path: String): String =
    path.replace(".agda.", ".").stripSuffix(".agda")

  /** Collapse hidden-module separator `._.` into `.`. */
  private def collapseHidden(path: String): String =
    path.replace("._.", ".")

  /** Normalize a fully-qualified premise id for robust equality checks. */
  private def normalizePremise(p: String): String = {
    val noAngle  = stripAngle(p)
    val noHidden = collapseHidden(noAngle)
    stripAgdaDot(noHidden)
  }

  /** Base file name without .agda, e.g., "agda-example.agda" -> "agda-example". */
  private def baseFile(f: String): String =
    if (f.endsWith(".agda")) f.stripSuffix(".agda") else f

  /** Produce possible qualified ids for this record, normalized. */
  private def idVariants(rec: AgdaData): List[String] = {
    val b  = baseFile(rec.file)
    val nm = stripAngle(rec.name)
    val vNoMod   = s"$b.$nm"
    val vWithMod = rec.module.filter(_.nonEmpty).map(m => s"$b.$m.$nm").getOrElse(vNoMod)
    val vWithExt = s"$b.agda.$nm"
    val vWithExtMod = rec.module.filter(_.nonEmpty).map(m => s"$b.agda.$m.$nm")
    List(vWithMod, vNoMod, vWithExt) ++ vWithExtMod
  }.map(normalizePremise)

  /** True if a premise points back to the record itself (under any spelling). */
  private def isSelfPremise(rec: AgdaData, premise: String): Boolean = {
    val pN = normalizePremise(premise)
    idVariants(rec).exists(_ == pN)
  }

  // ------------------------------------------------------------
  // Parsing one “agda2train” JSON object into AgdaData rows
  // ------------------------------------------------------------

  private def processName(qualified: String): (String, Option[String], String) = {
    // Split on dots. Examples:
    //   "agda-example.properties.+-suc<40>"  -> file="agda-example", module="properties", name="+-suc<40>"
    //   "agda-example._+_<8>"                -> file="agda-example", module=None, name="_+_<8>"
    val parts = qualified.split('.').toList
    val file             = parts.headOption.getOrElse("")
    val moduleAndName    = parts.drop(1)
    val (moduleOpt,name) = moduleAndName match {
      case Nil         => (None, "")
      case only :: Nil => (None, only)
      case many        => (Some(many.init.mkString(".")), many.last)
    }
    (file, moduleOpt.filter(_.nonEmpty), name)
  }

  /** Extract premises from `holes[*].premises[]`, deduped.
  private def collectPremises(item: Obj): List[String] = {
    objOpt(Value(item), "holes")
      .toList // None or Some(obj) -> List(obj) for easy flatMap
      .flatMap(_.value.values) // holes array (if present)
      .flatMap(_.arrOpt.map(_.value).getOrElse(Nil)) // safe array unwrap
      .flatMap(_.objOpt.toList) // each hole as Obj
      .flatMap { h =>
        arrOpt(Value(h), "premises").toList.flatMap(_.value).flatMap(_.strOpt)
      }
      .distinct
  }
  */
  /** Parse a single item object into AgdaData (if minimally well-formed). */
  private def parseItem(item: JObject): Option[AgdaData] = {
    val nameOpt = str(item, "name")
    val typeStr = getPretty(item, "type")
    val defStr  = getPretty(item, "definition")

    // Collect premises from holes[*].premises[]
    val premises: List[String] =
      field(item, "holes").toList
        .flatMap(asArr)               // holes array
        .flatMap(_.toList)            // values inside
        .flatMap {
          case ujson.Obj(h) =>
            h.get("premises").toList
              .flatMap(asArr)
              .flatMap(_.toList)
              .flatMap(_.strOpt)
          case _ => Nil
        }
        .distinct

    (nameOpt, typeStr, defStr) match {
      case (Some(qname), Some(tp), Some(df)) =>
        val (file, module, shortName) = processName(qname)
        Some(AgdaData(
          file     = file,
          module   = module,
          name     = shortName,
          agdaType = tp,
          proof    = df,
          premises = premises
        ))
      case _ => None
    }
  }

  /** Parse one agda2train JSON object into multiple AgdaData rows. */
  private def parseOne(json: ujson.Value): List[AgdaData] = {
    val locals = json.obj.get("scope-local").toList
      .flatMap(asArr).flatMap(_.toList)

    val privs  = json.obj.get("scope-private").toList
      .flatMap(asArr).flatMap(_.toList)

    val all = locals ++ privs

    all.flatMap {
      case ujson.Obj(o) => parseItem(o).toList
      case _            => Nil
    }
  }

  // ------------------------------------------------------------
  // I/O helpers
  // ------------------------------------------------------------

  private def readWhole(path: String): Either[String, String] =
    Try(Source.fromFile(path, "UTF-8").mkString).toEither.left.map(_.getMessage)

  private def writeJsonl(records: List[AgdaData], outputPath: String): Either[String, Unit] =
    Try {
      val parent = Paths.get(outputPath).toAbsolutePath.getParent
      if (parent != null) Files.createDirectories(parent)
      val pw = new PrintWriter(new File(outputPath), "UTF-8")
      try {
        records.foreach { r =>
          // filter self-premises on the way out
          val cleaned = r.copy(premises = r.premises.filterNot(p => isSelfPremise(r, p)))
          pw.println(upickle.default.write(cleaned))
        }
        pw.flush()
      } finally pw.close()
    }.toEither.left.map(_.getMessage)

  // ------------------------------------------------------------
  // Top-level: support both a single JSON file or a JSONL of many JSON blobs
  // ------------------------------------------------------------

  private def parseInput(text: String): Either[String, List[AgdaData]] = {
    // Heuristic: if the file contains multiple top-level JSON objects split by newlines,
    // treat it as JSONL; otherwise parse as one JSON object.
    val trimmed = text.dropWhile(_.isWhitespace)
    if (trimmed.isEmpty) Right(Nil)
    else if (trimmed.head == '{' || trimmed.head == '[') {
      // Single JSON value (object expected)
      Try(ujson.read(text)).toEither.left.map(_.getMessage).map(parseOne)
    } else {
      // JSONL: each line should be one JSON object
      val rows = text.linesIterator.toList.filter(_.trim.nonEmpty)
      val parsed = rows.map { line =>
        Try(ujson.read(line)).toEither.left.map(_.getMessage).map(parseOne)
      }
      val (errs, oks) = parsed.partitionMap(identity)
      if (errs.nonEmpty) Left("Failed to parse some JSONL lines: " + errs.mkString("; "))
      else Right(oks.flatten)
    }
  }

  // ------------------------------------------------------------
  // CLI
  // ------------------------------------------------------------

  private def usage: String =
    "Usage: Agda2TrainTransformer <input-json-or-jsonl> <output-jsonl>"

  def main(args: Array[String]): Unit = {
    if (args.length != 2) {
      Console.err.println(usage)
      sys.exit(1)
    }

    val in  = args(0)
    val out = args(1)

    val result =
      for {
        text    <- readWhole(in)
        records <- parseInput(text)
        _        = println(s"Successfully processed ${records.size} records to $out")
        _       <- writeJsonl(records, out)
      } yield {
        println(s"Extracted ${records.length} theorem/proof pairs to $out")
      }

    result match {
      case Left(err) =>
        Console.err.println(s"[Agda2TrainTransformer] ERROR: $err")
        sys.exit(2)
      case Right(_)  => () // success
    }
  }
}
