/**
 * AgdaJsonParser.scala
 *
 * File: proof-parser/src/main/scala/proofparser/AgdaJsonParser.scala
 *
 * Description:
 *   Helpers for parsing/decoding Agda/Agda2Train JSON (ujson/upickle wrappers,
 *   small adapters and field pickers).  Extracts theorem information and saves it
 *   in our JSONL format for further processing.
 *
 * Usages:
 *   1. import proofparser.AgdaJsonParser // (as needed by transformers/extractors)
 *   2. scala AgdaJsonParser <input_json_file> <output_jsonl_file>
 *
 * Examples:
 *   // Typically used internally by Agda2TrainTransformer / Agda2TrainReducer;
 *   // not a CLI by itself.
 *
 * Notes:
 *   - Keep tolerant to schema drift (use Option/try-pick patterns).
 *   - Centralize JSON utilities here to avoid duplication between tools.
 *
 * (c) 2025 Thmpr Lab, LLC.
 */

package proofparser

import java.io.{File, PrintWriter}
import org.json4s._
import org.json4s.JsonDSL._
import org.json4s.native.JsonMethods._
import scala.io.Source
import scala.util.{Try, Success, Failure}

object AgdaJsonParser {
  // Set up JSON parsing with the correct implicit formats
  implicit val formats: Formats = DefaultFormats

  case class AgdaRecord(
    fileName: String,
    moduleName: String,
    theoremName: String,
    theoremType: String,
    proof: String
  )

  def optStr(v: ujson.Value, key: String): Option[String] =
    v.obj.get(key).flatMap(_.strOpt)

  /** Try several common pretty fields Agda2Train/Agda-JSON use. */
  def pickPretty(v: ujson.Value): Option[String] =
    v.strOpt
      .orElse(optStr(v, "pretty"))
      .orElse(optStr(v, "pp"))
      .orElse(optStr(v, "rendered"))
      .orElse(optStr(v, "shown"))

  /** Collect strings from an array under one of several keys. */
  def pickStringArray(v: ujson.Value, keys: String*): List[String] =
    keys.toList.flatMap { k =>
      v.obj.get(k) match {
        case Some(a: ujson.Arr) => a.value.toList.flatMap(_.strOpt)
        case _                  => Nil
      }
    }.distinct

  def main(args: Array[String]): Unit = {
    if (args.length != 2) {
      println("Usage: scala AgdaJsonParser <input_json_file> <output_jsonl_file>")
      System.exit(1)
    }

    val inputFile = args(0)
    val outputFile = args(1)

    processJsonFile(inputFile, outputFile)
  }

  def processJsonFile(inputPath: String, outputPath: String): Unit = {
    try {
      // Read the input file
      val jsonString = Source.fromFile(inputPath).mkString

      // Parse the JSON
      val json = parse(jsonString)

      // Extract the top-level name (file/module name)
      val fileModuleName = AgdaJsonParser.RichJValue(json \ "name").extractOrElse[String]("")

      // Extract local scope items
      val scopeLocal = (json \ "scope-local").extract[List[JValue]]

      // Process each item in scope-local
      val records = scopeLocal.flatMap { item =>
        for {
          name <- (item \ "name").extractOpt[String]
          typeObj <- (item \ "type").extractOpt[JValue]
          typePretty <- (typeObj \ "pretty").extractOpt[String]
          defObj <- (item \ "definition").extractOpt[JValue]
          defPretty <- (defObj \ "pretty").extractOpt[String]
        } yield {
          AgdaRecord(
            fileName = fileModuleName,
            moduleName = fileModuleName,
            theoremName = name,
            theoremType = typePretty,
            proof = defPretty
          )
        }
      }

      // Write records to JSONL file
      val writer = new PrintWriter(new File(outputPath))
      try {
        records.foreach { record =>
          val recordJson =
            ("fileName" -> record.fileName) ~
            ("moduleName" -> record.moduleName) ~
            ("theoremName" -> record.theoremName) ~
            ("theoremType" -> record.theoremType) ~
            ("proof" -> record.proof)

          writer.println(compact(render(recordJson)))
        }
        println(s"Successfully processed ${records.size} records to $outputPath")
      } finally {
        writer.close()
      }

    } catch {
      case e: Exception =>
        println(s"Error processing file: ${e.getMessage}")
        e.printStackTrace()
    }
  }

  // Helper extension method for safer extraction
  implicit class RichJValue(val jv: JValue) extends AnyVal {
    def extractOrElse[T](default: T)(implicit formats: Formats, mf: Manifest[T]): T =
      jv.extractOpt[T].getOrElse(default)
  }
}
