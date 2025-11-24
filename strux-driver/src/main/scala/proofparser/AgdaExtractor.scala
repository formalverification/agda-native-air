/** ============================================================================
 *  AgdaExtractor.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/AgdaExtractor.scala
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
 *  Package: proofparser
 *
 *  Description
 *  -----------
 *  Lightweight, regex-based extractor for Agda files (no Agda process).
 *  Useful as a fast baseline on solved files: infers module/name/type/body
 *  heuristically and outputs the results in JSON Lines format.
 *
 *  Features
 *  --------
 *  - Recursively searches for `.agda` files in a given directory.
 *  - Identifies module names, theorem definitions, and associated proofs.
 *  - Handles multi-line definitions and comments.
 *  - Outputs extracted data in a structured JSON Lines format.
 *
 *  Usage
 *  -----
 *    import proofparser.AgdaExtractor
 *    val rows: List[AgdaData] = AgdaExtractor.extract(Paths.get("path/to/file.agda"))
 *
 *  Examples
 *  --------
 *    // See AgdaExtractorMain for CLI usage that writes JSONL.
 *
 *  Notes
 *  -----
 *    - Heuristic by design; use Agda2Train-based tools for authoritative data.
 *    - Good for smoke tests and CI when Agda is unavailable.
 *    - This utility requires Scala 2.13+ and the uPickle library for JSON handling.
 *
 *  ============================================================================
 */

package proofparser

import java.nio.file.{Files, Paths, Path}
import scala.jdk.CollectionConverters._
import scala.util.Using
import scala.util.matching.Regex
import upickle.default._

object AgdaExtractor {

  // 📂 File Collection and Discovery ----------
  def getAgdaFiles(dir: Path): List[Path] =
    Files.walk(dir).iterator.asScala.filter(_.toString.endsWith(".agda")).toList

  // ------------------------------------------------------------
  // Module/header parsing
  // ------------------------------------------------------------

  // Module Detection
  // A simple check for `module` lines.
  /** Extract `module Foo.Bar where` → Some("Foo.Bar"), else None. */
  def extractModuleName(lines: List[String]): Option[String] = {
    val ModuleDecl: Regex = """^\s*module\s+([A-Za-z_][A-Za-z0-9_\.]*)\s+where\s*$""".r
    lines.collectFirst {
      case ModuleDecl(name) => name
    }
  }

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

  // ------------------------------------------------------------
  // “Theorem-like” declarations
  // ------------------------------------------------------------

  // A (very) small token list we do NOT consider “theorem-like”.
  // (We want lemma/theorem-style bindings:  `name : Type`)
  private val ForbiddenFirstToken: Set[String] = Set(
    "postulate", "open", "import", "module",
    "data", "record", "mutual", "where",
    "infix", "infixl", "infixr", "syntax", "pragma", "private"
  )

  // Greedy but useful: a name, a colon, then the rest is the type string.
  private val Decl: Regex = """^\s*([^\s:]+)\s*:\s*(.+)$""".r

  // Quick comment/whitespace recognizers
  private def isLineComment(s: String): Boolean = s.trim.startsWith("--")
  private def isBlockCommentStart(s: String): Boolean = s.trim.startsWith("{-")
  private def isEmpty(s: String): Boolean = s.trim.isEmpty

  // 📚 Theorem Detection
  /** Returns true iff the line looks like an Agda theorem/lemma type declaration. */
  def isTheoremLike(line: String): Boolean = {
    if (isEmpty(line) || isLineComment(line) || isBlockCommentStart(line)) return false
    line match {
      case Decl(name, _) =>
        val firstTok = line.trim.takeWhile(!_.isWhitespace)
        // Filter out known non-theorem forms:
        !ForbiddenFirstToken.contains(firstTok)
      case _ => false
    }
  }

  // ✍️ Proof Detection
  def isProofLike(line: String): Boolean =
    line.trim.nonEmpty && !line.trim.startsWith("--") && line.contains(" = ")

  // 📚 Theorem Collection
  // ------------------------------------------------------------
  // Collect (name, type) pairs from a text buffer
  // ------------------------------------------------------------

  /** Collect simple `(name, type)` pairs from lines containing `name : Type`.
    * We ignore comments, noise, and orphan proofs (lines with `=` but no `:`).
    * This is intentionally conservative: just the declarations.
    */
  def collectTheorems(lines: List[String]): List[(String, String)] = {
    lines.iterator
      .filterNot(s => isEmpty(s) || isLineComment(s) || isBlockCommentStart(s))
      .flatMap {
        case Decl(name, tpe) if isTheoremLike(name + " : " + tpe) =>
          Some(name -> tpe.trim)
        case _ =>
          None
      }
      .toList
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
