package proofparser

/* 🎯 GOALS:
  + Parse `.agda` files in a given directory recursively.
  + Extract named definitions: functions, theorems, records, data types, etc.
  + Support multi-line definitions.
  + Capture their file of origin, module, name, and body.
  + Output in a line-delimited JSON format (e.g., `theorems.jsonl`).
*/

/* Logic for Pairing Theorem Statements and Proofs

1.  Data Representation
    +  Replace the current `TheoremData` with a more comprehensive case 
       class called `AgdaData`:
       ```scala
       case class AgdaData( file: String
                          , module: Option[String]
                          , name: String
                          , `type`: String
                          , proof: String )
       ```
   
2.  Extraction Logic
    +  Use a `Map[String, (String, Option[String])]` to temporarily store 
       the name, type, and proof as they are collected.
    +  First, collect the theorem/type declarations as we did before.
    +  When encountering a proof (i.e., `name = ...`), pair it with the 
       already collected type from the map.
    +  If no matching type is found, store the proof separately for later 
       reconciliation.

3.  Merging Rules
    +  If the map already has a type but no proof for a given name, 
       update the entry with the proof.
    +  If both the type and proof are available, create an `AgdaData` 
       instance and store it in the result list.
    +  Handle edge cases where a proof is encountered without a 
       preceding type or vice versa.
*/

import java.nio.file.{Files, Paths, Path}
import java.nio.charset.StandardCharsets
import java.io.{File, PrintWriter}
import scala.io.Source
import scala.util.{Try,Using}
import upickle.default._

case class TheoremData(file: String, module: Option[String], name: String, body: String)
object TheoremData { implicit val rw: ReadWriter[TheoremData] = macroRW }

// Define the case class for our custom structure
case class AgdaData(file: String, module: Option[String], name: String, typ: String, proof: String)
object AgdaData { implicit val rw: ReadWriter[AgdaData] = macroRW }

object Agda2TrainTransformer {

  /**
    * Main entry point for the Agda2TrainExtractor application.
    *
    * @param args Command-line arguments: input JSON file and output JSONL file.
    */
  def main(args: Array[String]): Unit = {
    if (args.length != 2) {
      println("Usage: Agda2TrainExtractor <input-json-file> <output-jsonl-file>")
      sys.exit(1)
    }

    val inputFile = args(0)
    val outputFile = args(1)

    val agdaData = extractAgdaDataFromJson(inputFile)

    saveToJsonl(agdaData, outputFile)
    println(s"Extracted ${agdaData.length} theorem/proof pairs to $outputFile")
  }

  /**
    * Extract Agda data from a JSON file.
    * 1. Filename Extraction
    *    - Attempts to read the file path from the JSON metadata section.
    *    - Defaults to `"Unknown"` if not found.
    * 2. Module Extraction
    *    - Attempts to read the module name from the `"topLevelModule"` section.
    *    - Uses `Option[String]` to account for the possibility of it being absent.
    * 3. Building `AgdaData`
    *    - Uses the extracted file and module names along with the theorem name, type, and proof.
    *    - Ensures that both the name and proof are non-empty before including the data.
    *
    * @param jsonPath The path to the JSON file.
    * @return A sequence of AgdaData objects containing the extracted data.
    */
  def extractAgdaDataFromJson(jsonPath: String): Seq[AgdaData] = {
    // Read the JSON content from file
    val data1 = ujson.read(Source.fromFile(jsonPath).getLines().mkString)
    val data2 = ujson.read(Files.readString(Paths.get(jsonPath), StandardCharsets.UTF_8))

    // Attempt to extract the module name and file name
    val moduleName = Try(data2("topLevelModule")("name").str).toOption
    val fileName = Try(data2("metadata")("filePath").str).getOrElse("Unknown")

    // The following are two alternative means of extracting data.
    // Option 1. Extract global scope
    val globalScope = data1("scopes")(0)("globalScope").arr
    val answer1 = globalScope.flatMap { entry =>
      val name = entry("name").strOpt
      val tp = entry("type").strOpt
      val defn = entry("definition").strOpt
      // Filter out entries without necessary fields:
      (name, tp, defn) match {
        case (Some(n), Some(t), Some(d)) if n.nonEmpty && t.nonEmpty && d.nonEmpty =>
          Some(AgdaData(fileName, moduleName, n, t, d))
        case _ => None
      }
    }.toSeq

    // Option 2. Extract definitions
    val definitions = data2("definitions").arr.toSeq
    val answer2 = definitions.flatMap { definition =>
      val name = Try(definition("name").str).getOrElse("Unnamed")
      val typ = Try(definition("type").str).getOrElse("NoType")
      val bodyArray = Try(definition("clauses").arr).getOrElse(ujson.Arr())
      val proof = bodyArray.asInstanceOf[ujson.Arr].value.map(clause => clause("body").str).mkString("\n")
      // Only keep the entry if both name and proof are non-empty
      if (name.nonEmpty && proof.nonEmpty) {
        Some(AgdaData(fileName, moduleName, name, typ, proof))
      } else {
        None
      }
    }
    // answer1  // return result of Option 1
    answer2  // return result of Option 2
  }


  def saveToJsonl(data: Seq[AgdaData], outputPath: String): Unit = {
    val writer = new PrintWriter(new File(outputPath))

    try {
      data.foreach { agdaData =>
        val json = ujson.Obj(
          "file" -> agdaData.file,
          "module" -> agdaData.module,
          "name" -> agdaData.name,
          "type" -> agdaData.typ,
          "proof" -> agdaData.proof
        )
        writer.println(json.render())
      }
    } finally {
      writer.close()
    }
  }
}

