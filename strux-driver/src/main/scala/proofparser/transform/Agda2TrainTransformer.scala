/** ============================================================================
 *  Agda2TrainTransformer.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/transform/Agda2TrainTransformer.scala
 *  Package: proofparser.transform
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
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
 *  This module uses only functional style: no mutable vars, no loops,
 *  no exceptions (all errors captured in Either).
 *  ============================================================================ */

package proofparser.transform

import proofparser.schema._
import proofparser.schema.AgdaDataOps._
import proofparser.schema.{DeclKind, SemanticInfo,TheoremData}
import proofparser.util.EitherUtil

import upickle.default._
import ujson._

import java.io.PrintWriter
import java.nio.file.{ Files, Paths }

object Agda2TrainTransformer {

  /** ---------------------------
    * Helpers for safe JSON access
    * --------------------------- */
  private def getOpt(obj: Obj, key: String): Option[ujson.Value] =
    obj.value.get(key)

  private def getString(obj: Obj, key: String): Option[String] =
    getOpt(obj, key).flatMap(_.strOpt)

  private def getPretty(obj: Obj, key: String): Option[String] =
    getOpt(obj, key).map(_.render())

  /** Extract a clean filename, module, and short name from Agda’s qname. */
  private def processName(qname: String): (String, Option[String], String) = {
    val parts = qname.split("\\.")
    val short = parts.lastOption.getOrElse(qname)
    val mod   = if (parts.length > 1) Some(parts.dropRight(1).mkString(".")) else None
    val file  = mod.map(m => s"$m.agda").getOrElse("unknown-file.agda")
    (file, mod, short)
  }

  /** ----------------------------
    * Primary JSON → AgdaData step
    * ---------------------------- */
  private def parseItem(item: Obj): Option[AgdaData] = {
    val nameOpt  = getString(item, "name")
    val typeStr  = getPretty(item, "type")
    val defStr   = getPretty(item, "definition")

    val premises: List[String] =
      getOpt(item, "premises")
        .flatMap(_.arrOpt)
        .map(_.flatMap(_.strOpt).toList)
        .getOrElse(Nil)

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

  /** Parse entire JSON file into rows. */
  private def parseJson(json: ujson.Value): List[AgdaData] =
    json.arrOpt
      .map(_.toList.flatMap(_.objOpt.map(ujson.Obj(_)).flatMap(parseItem)))
      .getOrElse(Nil)

  /** Write JSONL in a referentially transparent way. */
  private def writeJsonl(rows: List[AgdaData], outPath: String): Either[String, Unit] =
    EitherUtil.catchNonFatal {
      val parent = Paths.get(outPath).toAbsolutePath.getParent
      if (parent != null) Files.createDirectories(parent)

      val pw = new PrintWriter(outPath, "UTF-8")
      try rows.foreach(r => pw.println(upickle.default.write(r)))
      finally pw.close()
    }

  /** Entry point: transform Agda reflection JSON → canonical rows. */
  def transform(inputJson: String, outputJsonl: String): Either[String, Unit] =
    for {
      json  <- EitherUtil.catchNonFatal(ujson.read(inputJson))
      rows  <- Right(parseJson(json))
      _     <- writeJsonl(rows, outputJsonl)
    } yield ()
}
