/**
 * AgdaExtractor.scala
 *
 * A Scala utility to extract theorem-like definitions and their proofs
 * from Agda source files. It scans a specified directory for `.agda` files,
 * parses them to identify theorems and proofs, and outputs the results
 * in JSON Lines format.
 *
 * File: agda-ai-prover/proof-parser/src/main/scala/proofparser/AgdaExtractor.scala
 *
 * Features:
 * - Recursively searches for `.agda` files in a given directory.
 * - Identifies module names, theorem definitions, and associated proofs.
 * - Handles multi-line definitions and comments.
 * - Outputs extracted data in a structured JSON Lines format.
 *
 * Usage:
 *   scala AgdaExtractor.scala <path-to-agda-lib>
 *
 * Output:
 *   The extracted theorems and proofs are saved in `output/theorems.jsonl`.
 *
 * Note:
 *   This utility requires Scala 2.13+ and the uPickle library for JSON handling.
 *
 * Copyright (c) 2025 Thmpr.
 */
package proofparser

import java.nio.file.{Files, Paths, Path}
import scala.jdk.CollectionConverters._
import scala.util.Using
import upickle.default._


object AgdaExtractor {

  // 📂 File Collection
  def getAgdaFiles(dir: Path): List[Path] = Files.walk(dir)
    .iterator()
    .asScala
    .filter(p => p.toString.endsWith(".agda"))
    .toList

  // Module Detection
  // A simple check for `module` lines.
  def extractModuleName(lines: List[String]): Option[String] =
    lines.collectFirst {
      case line if line.trim.startsWith("module ") =>
        line.trim.stripPrefix("module").trim.split("\\s+").headOption
    }.flatten

  // 📚 Theorem Extraction

  // extractTheorems
  // @param lines The lines of the Agda file.
  // @param fileName The name of the file being processed.
  // @param moduleName The name of the module being processed.
  // @return A sequence of `AgdaData` objects containing the file name,
  // module name, theorem name, type, and proof.
  //
  // @description This function extracts theorems from a list of lines.
  // It uses a mutable map to keep track of theorem names and their types.
  // It also uses a mutable list to store the results.
  // The function iterates through the lines, checking for theorem-like
  // definitions and proof-like lines.
  // When it finds a theorem definition, it stores the name and type in the map.
  // When it finds a proof-like line, it checks if the name exists in the map.
  // If it does, it creates an `AgdaData` object with the file name, module name,
  // theorem name, type, and proof, and adds it to the results list.
  // If the name does not exist in the map, it updates the map with the proof.
  // Finally, it returns the results list as a sequence of `AgdaData` objects.
  //
  // @example
  // val lines = Seq(
  //   "myTheorem : A -> B",
  //   "myTheorem = ...",
  //   "anotherTheorem : C -> D",
  //   "anotherTheorem = ..."
  // )
  // val fileName = "example.agda"
  // val moduleName = Some("MyModule")
  // val theorems = extractTheorems(lines, fileName, moduleName)
  // theorems.foreach { theorem =>
  //   println(s"File: ${theorem.file}, Module: ${theorem.module.getOrElse("N/A")}, Name: ${theorem.name}, Type: ${theorem.`type`}, Proof: ${theorem.proof}")
  // }
  //
  case class AgdaDataOld(
  file      : String,
  module    : Option[String],
  name      : String,
  agdaType  : String,
  proof     : String
)
object AgdaDataOld { implicit val rw: ReadWriter[AgdaDataOld] = macroRW }


  // @note This function is designed to handle both single-line and multi-line
  // theorem definitions.
  def extractTheorems(lines: Seq[String], fileName: String, moduleName: Option[String]): Seq[AgdaDataOld] = {
    var theoremMap = scala.collection.mutable.Map[String, (String, Option[String])]()
    var results = scala.collection.mutable.ListBuffer[AgdaDataOld]()

    lines.foreach { line =>
      val trimmed = line.trim

      if (isTheoremLike(trimmed)) {
        val parts = trimmed.split(":", 2)
        if (parts.length == 2) {
          val name = parts(0).trim
          val typ = parts(1).trim
          theoremMap.update(name, (typ, None))
        }
      } else if (isProofLike(trimmed)) {
        val parts = trimmed.split("=", 2)
        if (parts.length == 2) {
          val name = parts(0).trim
          val proof = parts(1).trim
          if (theoremMap.contains(name)) {
            val (typ, _) = theoremMap(name)
            results += AgdaDataOld(fileName, moduleName, name, typ, proof)
            theoremMap.remove(name)
          } else {
            theoremMap.update(name, ("", Some(proof)))
          }
        }
      }
    }

    // Add any leftover declarations without proofs
    theoremMap.foreach { case (name, (typ, proofOpt)) =>
      val proof = proofOpt.getOrElse("")
      results += AgdaDataOld(fileName, moduleName, name, typ, proof)
    }

    results.toSeq
  }

  // 📚 Theorem Detection
  def isTheoremLike(line: String): Boolean =
    line.trim.nonEmpty && !line.trim.startsWith("--") && line.contains(" : ")

  // ✍️ Proof Detection
  def isProofLike(line: String): Boolean =
    line.trim.nonEmpty && !line.trim.startsWith("--") && line.contains(" = ")

  // 📚 Theorem Collection
  def collectTheorems(lines: List[String]): List[(String, String)] = {
    val buffer = scala.collection.mutable.ListBuffer.empty[(String, String)]
    val current = scala.collection.mutable.ListBuffer.empty[String]
    var name = ""
    val cleanedLines = removeComments(lines)

    cleanedLines.foreach { line =>
      if (isTheoremLike(line)) {
        if (current.nonEmpty) {
          buffer += ((name, current.mkString(" ")))
          current.clear()
        }
        val split = line.split("\\s+").toList
        name = split.headOption.getOrElse("")
        current += line
      } else if (current.nonEmpty) current += line
    }

    if (current.nonEmpty) buffer += ((name, current.mkString(" ")))

    buffer.toList
  }


  // Comment Removal
  def removeComments(lines: List[String]): List[String] = {
    val blockStart = "{-"
    val blockEnd   = "-}"

    val buffer = scala.collection.mutable.ListBuffer[String]()
    var inBlock = false

    for (line <- lines) {
      val trimmed = line.trim
      if (!inBlock && trimmed.contains(blockStart)) {
        inBlock = true
      }
      if (!inBlock && !trimmed.startsWith("--")) {
        buffer += line
      }
      if (inBlock && trimmed.contains(blockEnd)) {
        inBlock = false
      }
    }
    buffer.toList
  }


  // ✂️ Block-Based Parsing:  a state machine-style parser that tracks
  //    whether we are:
  //    - Outside a block (`state = None`)
  //    - Inside a block (`state = Some((name, lines))`)
  //
  //    A "block" is a contiguous set of lines that:
  //    - Starts with a name and `:` or `=`
  //    - Is indented consistently (or ends with an empty line / unindented line)
  //
  // 🔍 Utility Functions
  // Detect block starters like: `myFunc : Nat -> Nat` or `myProof = ...`
  def isBlockStart(line: String): Boolean =
    line.matches("""^\s*\S+\s*[:=].*""")

  def getBlockName(line: String): String =
    line.trim.takeWhile(c => !c.isWhitespace && c != ':' && c != '=')

  def isIndented(line: String): Boolean =
    line.startsWith(" ") || line.startsWith("\t")


  // 🧱 Block Parser
  def extractBlocks(lines: List[String]): List[(String, List[String])] = {
    @annotation.tailrec
    def loop( remaining: List[String]
            , current: Option[(String, List[String])]
            , acc: List[(String, List[String])]): List[(String, List[String])] =
      remaining match {
        case Nil => current.map(acc :+ _).getOrElse(acc)
        case line :: rest =>
          if (isBlockStart(line)) {
            current match {
              case Some(block) =>
                // Close the previous block and start new one
                loop(rest, Some((getBlockName(line), List(line))), acc :+ block)
              case None =>
                loop(rest, Some((getBlockName(line), List(line))), acc)
              }
        } else if (isIndented(line) || line.trim.isEmpty) {
          // Continue the current block
          current match {
            case Some((name, body)) => loop(rest, Some((name, body :+ line)), acc)
            case None => loop(rest, None, acc)
          }
        } else {
          // New top-level declaration or unrelated line
          current match {
            case Some(block) => loop(rest, None, acc :+ block)
            case None => loop(rest, None, acc)
          }
        }
      }
    loop(lines, None, Nil)
  }



  // 📂 File Processing
  def parseFile(path: java.nio.file.Path): List[TheoremData] = {
    val lines = Files.readAllLines(path).toArray(new Array[String](0)).toList
    val module = extractModuleName(lines)
    collectTheorems(lines).map {
      case (name, body) => TheoremData(path.getFileName.toString, module, name, body)
    }
  }

  def parseAgdaFile(path: java.nio.file.Path): Seq[AgdaDataOld] = {
    val lines = Files.readAllLines(path).toArray(new Array[String](0)).toList
    val module = extractModuleName(lines)
    extractTheorems(lines, path.getFileName.toString, module)
  }

  // 📤 JSON Output
  def writeAsJsonl[T: upickle.default.Writer](entries: Seq[T], out: Path): Unit = {
    Using(Files.newBufferedWriter(out)) { writer =>
      entries.foreach { thm =>
        writer.write(upickle.default.write(thm))
        writer.newLine()
      }
    }.get
  }

  // using `ujson` for simplicity
  def writeAsJsonlAlt(entries: List[(String, String, String, String)], out: Path): Unit = {
    val writer = Files.newBufferedWriter(out)
    try {
      entries.foreach { case (file, module, name, body) =>
        val json = ujson.Obj(
          "file"   -> file,
          "module" -> module,
          "name"   -> name,
          "body"   -> body.trim
        )
        writer.write(json.render() + "\n")
      }
    } finally writer.close()
  }


  // 🧩 Putting It All Together
  def oldMain(args: Array[String]): Unit = {

    val userArgs = args.dropWhile(_ == "--")
    val root = if (userArgs.nonEmpty) userArgs(0) else {
      println("Usage: AgdaExtractor <path-to-agda-lib>")
      sys.exit(1)
    }
    //val extracted = getAgdaFiles(Paths.get(root)).flatMap(parseFile)
    val extracted = getAgdaFiles(Paths.get(root)).flatMap(parseAgdaFile)
    writeAsJsonl(extracted, Paths.get("output/theorems.jsonl"))

  }
}
