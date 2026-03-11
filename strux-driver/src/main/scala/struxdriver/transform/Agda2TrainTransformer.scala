/** ============================================================================
 *  Agda2TrainTransformer.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: strux-driver/src/main/scala/struxdriver/transform/Agda2TrainTransformer.scala
 *  Package: struxdriver.transform
 *
 *  Description
 *  -----------
 *  Converts Agda’s JSON reflection output into canonical AgdaData rows.
 *
 *  Responsibilities:
 *   • parse Agda JSON reflection structures (Types + Definitions)
 *   • extract module, name, type, proof body
 *   • extract premises from Agda's dependency metadata
 *   • enrich each row with semantic-light info (DeclKind + astSize)
 *   • normalize names, premises, whitespace
 *   • write out JSONL representing List[AgdaData]
 *
 *  CLI
 *  ---
 *    sbt "runMain struxdriver.transform.Agda2TrainTransformer in.json out.jsonl"
 *
 *  The transformer accepts:
 *   • a top-level JSON array of items, OR
 *   • a legacy object with "scope-local" / "scope-private" arrays.
 *
 *  Each item is expected to contain at least:
 *   • "name"        : qualified name string
 *   • "type"        : either a string or an object containing "pretty"
 *   • "definition"  : either a string or an object containing "pretty"
 *   • "premises"    : optional array of strings (new format)
 *   • "holes"       : optional legacy Agda reflection structure whose
 *                     "premises" arrays we also mine for dependencies.
 *
 *  ============================================================================
 */

package struxdriver.transform

import struxdriver.schema._
import struxdriver.schema.AgdaDataOps._
import struxdriver.util.EitherUtil

import upickle.default._
import ujson._

import java.io.PrintWriter
import java.nio.file.{Files, Paths}
import scala.io.Source

object Agda2TrainTransformer {

  /** Short alias for ujson object type. */
  private type Obj = ujson.Obj

  // ----------------------------------------
  // Helpers for safe JSON access
  // ----------------------------------------

  private def getOpt(obj: Obj, key: String): Option[ujson.Value] =
    obj.value.get(key)

  private def getString(obj: Obj, key: String): Option[String] =
    getOpt(obj, key).flatMap(_.strOpt)

  /** Get a "pretty" string:
    *  - if the value is a string, use it;
    *  - if it's an object with a "pretty" field, use that;
    *  - otherwise, fall back to `.render()`.
    */
  private def getPretty(obj: Obj, key: String): Option[String] =
    getOpt(obj, key).flatMap { v =>
      val asStr: Option[String] =
        v.strOpt

      val asPrettyField: Option[String] =
        v.objOpt
          .flatMap(_.get("pretty"))
          .flatMap(_.strOpt)

      asStr
        .orElse(asPrettyField)
        .orElse(Some(v.render()))
    }

  /** Extract a clean filename, module, and short name from Agda’s qname. */
  private def processName(qname: String): (String, Option[String], String) = {
    val parts = qname.split("\\.")
    val short = parts.lastOption.getOrElse(qname)
    val mod   = if (parts.length > 1) Some(parts.dropRight(1).mkString(".")) else None
    // We emit "<module>.agda" if we have a module; otherwise a fallback name.
    val file  = mod.map(m => s"$m.agda").getOrElse("unknown-file.agda")
    (file, mod, short)
  }

  // ----------------------------------------
  // Primary JSON → AgdaData step
  // ----------------------------------------

  /** Extract premises from both the modern "premises" field and
    * the legacy "holes" → "premises" arrays.
    */
  private def extractPremises(item: Obj): List[String] = {
    // New-style: flat array of strings under "premises"
    val direct: List[String] =
      getOpt(item, "premises")
        .flatMap(_.arrOpt)
        .map(_.flatMap(_.strOpt).toList)
        .getOrElse(Nil)

    // Legacy-style: nested "holes" array with objects that contain "premises"
    val fromHoles: List[String] =
      getOpt(item, "holes")
        .flatMap(_.arrOpt)
        .map { holesArr =>
          holesArr.toList
            .flatMap(_.objOpt.toList)
            .flatMap { hObj =>
              hObj.obj
                .get("premises")
                .toList
                .flatMap(_.arrOpt.toList.flatten)
                .flatMap(_.strOpt)
            }
        }
        .getOrElse(Nil)

    (direct ++ fromHoles).distinct
  }

  /** Parse a single item into AgdaData, if possible. */
  private def parseItem(item: Obj): Option[AgdaData] = {
    val nameOpt  = getString(item, "name")
    val typeStr  = getPretty(item, "type")
    val defStr   = getPretty(item, "definition")
    val premises = extractPremises(item)

    (nameOpt, typeStr, defStr) match {
      case (Some(qname), Some(tp), Some(df)) =>
        val (file, module, shortName) = processName(qname)

        val sem = Semantic.from(
          name     = shortName,
          agdaType = Some(tp),
          module   = module,
          proof    = Some(df)
        )

        val raw = AgdaData(
          file     = file,
          module   = module,
          name     = shortName,
          agdaType = Some(tp),
          proof    = Some(df),
          premises = premises,
          declKind = sem.kind,
          astSize  = sem.astSize
        )

        Some(AgdaDataOps.normalize(raw))

      case _ =>
        None
    }
  }

  /** Parse entire JSON into rows.
    *
    * Supports:
    *   1. Top-level JSON array:
    *        [ { "name": ..., "type": ..., ... }, ... ]
    *
    *   2. Legacy object with "scope-local" / "scope-private":
    *        {
    *          "scope-local":   [ { item }, ... ],
    *          "scope-private": [ { item }, ... ]
    *        }
    */
  private def parseJson(json: ujson.Value): List[AgdaData] = {
    // Case 1: top-level array of items
    val fromArray: Option[List[AgdaData]] =
      json.arrOpt.map { arr =>
        arr.toList.flatMap(_.objOpt.map(ujson.Obj(_)).flatMap(parseItem))
      }

    fromArray.getOrElse {
      // Case 2: legacy "scope-local" / "scope-private" object
      json.objOpt
        .map { underlying =>
          val root   = ujson.Obj(underlying)
          val locals = getOpt(root, "scope-local").flatMap(_.arrOpt).map(_.toList).getOrElse(Nil)
          val privs  = getOpt(root, "scope-private").flatMap(_.arrOpt).map(_.toList).getOrElse(Nil)
          val all    = locals ++ privs

          all.flatMap(_.objOpt.map(ujson.Obj(_)).flatMap(parseItem))
        }
        .getOrElse(Nil)
    }
  }

  /** Write JSONL in a referentially transparent way. */
  private def writeJsonl(rows: List[AgdaData], outPath: String): Either[String, Unit] =
    EitherUtil.catchNonFatal {
      val parent = Paths.get(outPath).toAbsolutePath.getParent
      if (parent != null) Files.createDirectories(parent)

      val pw = new PrintWriter(outPath, "UTF-8")
      try rows.foreach(r => pw.println(upickle.default.write(r)))
      finally pw.close()
    }

  /** Core API: transform Agda reflection JSON file → canonical JSONL rows. */
  def transform(inputJsonPath: String, outputJsonlPath: String): Either[String, Unit] =
    for {
      text <- EitherUtil.catchNonFatal {
        val src = Source.fromFile(inputJsonPath, "UTF-8")
        try src.mkString
        finally src.close()
      }
      json  <- EitherUtil.catchNonFatal(ujson.read(text))
      rows   = parseJson(json)
      _     <- writeJsonl(rows, outputJsonlPath)
    } yield ()

  // ----------------------------------------
  // CLI entry point for sbt runMain
  // ----------------------------------------

  def main(args: Array[String]): Unit = {
    if (args.length != 2) {
      System.err.println(
        s"Usage: struxdriver.transform.Agda2TrainTransformer <input.json> <output.jsonl> (got ${args.length} args)"
      )
      sys.exit(1)
    }

    val in  = args(0)
    val out = args(1)

    transform(in, out) match {
      case Left(err) =>
        System.err.println(s"[Agda2TrainTransformer] ERROR: $err")
        sys.exit(1)

      case Right(_) =>
        // For CI / smoke tests it’s helpful to log something.
        println(s"[Agda2TrainTransformer] Wrote canonical rows to: $out")
    }
  }
}
