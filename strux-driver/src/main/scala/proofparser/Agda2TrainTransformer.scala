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
                          , module: String
                          , name: String
                          , agdaType: String
                          , premises: List[String]
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

import java.io.{File, PrintWriter}
import org.json4s._
import org.json4s.JsonDSL._
import org.json4s.native.JsonMethods._
import scala.io.Source
import scala.util.{Try, Success, Failure}
import upickle.default._

case class TheoremData(file: String, module: Option[String], name: String, body: String)
object TheoremData { implicit val rw: ReadWriter[TheoremData] = macroRW }

// Define the case class for our custom structure
case class AgdaData(
  file      : String,
  module    : String,
  name      : String,
  agdaType  : String,
  proof     : String,
  premises  : List[String]
)
object AgdaData { implicit val rw: ReadWriter[AgdaData] = macroRW }

object Agda2TrainTransformer {
  // Set up JSON parsing with the correct implicit formats
  implicit val formats: Formats = DefaultFormats

  // Helper extension method for safer extraction
  implicit class RichJValue(val jValue: JValue) extends AnyVal {
    def extractOrElse[T](default: T)(implicit formats: Formats, mf: Manifest[T]): T =
      jValue.extractOpt[T].getOrElse(default)
  }

  def writeToJsonl(records: List[AgdaData], outputPath: String): Unit = {
      // Write records to JSONL file
      val writer = new PrintWriter(new File(outputPath))
      try {
        records.foreach { record =>
          val recordJson =
            ("file" -> record.file) ~
            ("module" -> record.module) ~
            ("name" -> record.name) ~
            ("agdaType" -> record.agdaType) ~
            ("proof" -> record.proof) ~
            ("premises" -> record.premises)
          // Convert to JSON and write to file.
          // Serialize the record
          //   - could use upickle: writer.println(write(record)),
          //   - we'll use json4s:
          writer.println(compact(render(recordJson)))
          // Use compact to avoid pretty printing and ensure single line
        }
        println(s"Successfully processed ${records.size} records to $outputPath")
      } finally {
        writer.close()
      }

  }
  def processName(name: String): List[String] = {
    // Process the name to remove unwanted characters
    val names = name.split('.').toList
    val fileName = names(0)
    val defName = names.lastOption.getOrElse("")
    if (names.length > 2) {
      List(fileName, names(1), defName)
    } else {
      List(fileName, "", defName)
    }
  }

  def extractAgdaDataFromJson(inputPath: String): List[AgdaData] = {
    try {
      // Read the input file
      val jsonString = Source.fromFile(inputPath).mkString

      // Parse the JSON
      val json = parse(jsonString)

      // Extract the top-level name (file name)
      val fileName : String = (json \ "name").extractOpt[String].getOrElse("")

      // Extract local scope items
      val scopeLocal : List[JValue] = (json \ "scope-local").extract[List[JValue]]

      // Extract private scope items
      val scopePrivate : List[JValue] = (json \ "scope-private").extract[List[JValue]]

      // Process each item in scope-local

      (scopeLocal ++ scopePrivate).flatMap { item =>
        for {
          name <- (item \ "name").extractOpt[String]
          typeObj <- (item \ "type").extractOpt[JValue]
          typePretty <- (typeObj \ "pretty").extractOpt[String]
          defObj <- (item \ "definition").extractOpt[JValue]
          defPretty <- (defObj \ "pretty").extractOpt[String]
          // premisesObj <- (item \ "premises").extractOpt[List[String]]
          // Check if the item is a theorem-like definition
          // if premises.isDefined && premises.get.nonEmpty
        } yield {
          val premises = (item \ "holes").extractOpt[List[JValue]].getOrElse(List()).flatMap { hole =>
             (hole \ "premises").extractOpt[List[String]].getOrElse(List())
           }.toSet.toList // Remove duplicates

          val nameParts = processName(name)
          AgdaData(
            file = nameParts(0),
            module = nameParts(1),
            name = nameParts.lastOption.getOrElse(""),
            agdaType = typePretty,
            proof = defPretty,
            premises = premises
          )
        }
      }
     } catch {
      case e: Exception =>
        println(s"Error processing file: ${e.getMessage}")
        e.printStackTrace()
        List.empty[AgdaData]
    }
   }

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

    val records = extractAgdaDataFromJson(inputFile)
    writeToJsonl(records, outputFile)
    println(s"Extracted ${records.length} theorem/proof pairs to $outputFile")
  }

}

