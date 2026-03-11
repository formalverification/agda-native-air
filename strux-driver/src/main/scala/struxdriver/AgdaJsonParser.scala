/** ============================================================================
 *  AgdaJsonParser.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: strux-driver/src/main/scala/struxdriver/AgdaJsonParser.scala
 *  Package: struxdriver
 *
 *  Description
 *  -----------
 *  Helpers for parsing/decoding Agda/Agda2Train JSON (ujson/upickle wrappers,
 *  small adapters and field pickers).  Extracts theorem information and saves it
 *  in our JSONL format for further processing.
 *
 *  Usage
 *  -----
 *  1. import struxdriver.AgdaJsonParser // (as needed by transformers/extractors)
 *  2. scala AgdaJsonParser <input_json_file> <output_jsonl_file>
 *
 *  Examples
 *  --------
 *  Typically used internally by Agda2TrainTransformer / Agda2TrainReducer;
 *  not a CLI by itself.
 *
 *  Notes
 *  -----
 *  - Keep tolerant to schema drift (use Option/try-pick patterns).
 *  - Centralize JSON utilities here to avoid duplication between tools.
 *
 * =============================================================================
 */

package struxdriver

import java.io.{File, PrintWriter}
import scala.io.Source
import scala.util.{Try, Success, Failure}
import ujson._

object AgdaJsonParser {

  case class AgdaRecord(
    fileName: String,
    moduleName: String,
    theoremName: String,
    theoremType: String,
    proof: String
  )

  object JsonUtil {
    def optStr(v: ujson.Value, key: String): Option[String] = v match {
      case o: ujson.Obj => o.value.get(key).flatMap(_.strOpt)
      case _            => None
    }

    /** Try several common pretty fields Agda2Train/Agda-JSON use. */
    def pickPretty(v: ujson.Value): Option[String] = v.strOpt orElse {
      v match {
        case o: ujson.Obj =>
          o.value.get("pretty").flatMap(_.strOpt)
            .orElse(o.value.get("pp").flatMap(_.strOpt))
            .orElse(o.value.get("rendered").flatMap(_.strOpt))
            .orElse(o.value.get("shown").flatMap(_.strOpt))
        case _ => None
      }
    }
    /** Collect strings from an array under one of several keys. */
    def pickStringArray(v: ujson.Value, keys: String*): List[String] =
      keys.toList.flatMap { k =>
        v.obj.get(k) match {
          case Some(a: ujson.Arr) => a.value.toList.flatMap(_.strOpt)
          case _                  => Nil
        }
      }.distinct

  }

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
      val json = ujson.read(jsonString)

      // Extract the top-level name (file/module name)
      val fileModuleName = json("name").strOpt.getOrElse("")

      // Extract local scope items
      val scopeLocal = json("scope-local").arrOpt.getOrElse(Vector()).toList

      // Process each item in scope-local
      val records = scopeLocal.flatMap { item =>
        for {
          name <- item("name").strOpt
          typePretty <- item("type")("pretty").strOpt
          defPretty <- item("definition")("pretty").strOpt
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
          val recordJson = ujson.Obj(
            "fileName" -> record.fileName,
            "moduleName" -> record.moduleName,
            "theoremName" -> record.theoremName,
            "theoremType" -> record.theoremType,
            "proof" -> record.proof
          )

          writer.println(ujson.write(recordJson))
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

}
