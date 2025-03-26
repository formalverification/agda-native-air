package proofparser

/*
  🎯 GOALS:
+ Parse `.agda` files in a given directory recursively.
+ Extract **named** definitions: functions, theorems, records, data types, etc.
+ Support **multi-line** definitions.
+ Capture their file of origin, module, name, and body.
+ Output in a line-delimited JSON format (e.g., `theorems.jsonl`).
*/

import java.nio.file.{Files, Paths, Path}
import java.nio.charset.StandardCharsets
import scala.jdk.CollectionConverters._
import scala.jdk.StreamConverters._
import io.circe.generic.auto._
import io.circe.syntax._
import java.io.PrintWriter
import scala.util.Using
// import upickle.default.{ReadWriter, macroRW}
import upickle.default._

case class TheoremData(file: String, module: Option[String], name: String, body: String)

object TheoremData { implicit val rw: ReadWriter[TheoremData] = macroRW }


object AgdaExtractor {

// 🧠 Core Design: Step-by-Step Parsing Logic

  // 1. File Collection
  def getAgdaFiles(dir: Path): List[Path] = Files.walk(dir)
    .iterator()
    .asScala
    .filter(p => p.toString.endsWith(".agda"))
    .toList

  // 2. Module Detection:
  // A simple check for `module` lines.
  def extractModuleName(lines: List[String]): Option[String] =
    lines.collectFirst {
      case line if line.trim.startsWith("module ") =>
        line.trim.stripPrefix("module").trim.split("\\s+").headOption
    }.flatten

  // Alternative check for `module` lines.
/*   def extractModuleNameAlt(lines: List[String]): String =
    lines.collectFirst {
      case line if line.trim.startsWith("module ") =>
        line.trim.split("\\s+").lift(1).getOrElse("UnknownModule")
    }.getOrElse("UnknownModule")
 */
  def extractModuleNameAlt(lines: List[String]): String =
    lines.collectFirst {
      case line if line.trim.startsWith("module ") =>
        line.trim.split("\\s+").lift(1).getOrElse("UnknownModule")
    }.getOrElse("UnknownModule")

  // 3. ✂️ Block-Based Parsing:  a state machine-style parser that tracks
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


  // 4. 🧱 Block Parser
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


  // 5. 📚 Theorem Parser
  def isTheoremLike(line: String): Boolean =
    line.trim.nonEmpty &&
    !line.trim.startsWith("--") &&
    (line.contains(" : ") || line.contains(" = "))

  def collectTheorems(lines: List[String]): List[(String, String)] = {
    val buffer = scala.collection.mutable.ListBuffer.empty[(String, String)]
    val current = scala.collection.mutable.ListBuffer.empty[String]
    var name = ""

    lines.foreach { line =>
      if (isTheoremLike(line)) {
        if (current.nonEmpty) {
          buffer += ((name, current.mkString(" ")))
          current.clear()
        }
        val split = line.split("\\s+").toList
        name = split.headOption.getOrElse("")
        current += line
      } else if (current.nonEmpty) {
        current += line
      }
    }

    if (current.nonEmpty) {
      buffer += ((name, current.mkString(" ")))
    }

    buffer.toList
  }

  // 6. 📂 File Processing
  def parseFile(path: java.nio.file.Path): List[TheoremData] = {
    val lines = Files.readAllLines(path).toArray(new Array[String](0)).toList
    val module = extractModuleName(lines)
    collectTheorems(lines).map {
      case (name, body) => TheoremData(path.getFileName.toString, module, name, body)
    }
  }

  def processFileAlt(path: Path): List[(String, String, String, String)] = {
    val lines = Files.readAllLines(path).asScala.toList
    val module = extractModuleNameAlt(lines)
    extractBlocks(lines).map {
      case (name, body) => (path.getFileName.toString, module, name, body.mkString("\n"))
    }
  }


  // 7. 📤 JSON Output
  def writeAsJsonl(entries: List[TheoremData], out: Path): Unit = {
    Using(Files.newBufferedWriter(out)) { writer =>
      entries.foreach { thm =>
        writer.write(write(thm))
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


  // 8. 🧩 Putting It All Together
  def main(args: Array[String]): Unit = {
    val userArgs = args.dropWhile(_ == "--")
    val root = if (userArgs.nonEmpty) userArgs(0) else {
      println("Usage: AgdaExtractor <path-to-agda-lib>")
      sys.exit(1)
    }

    val extracted = getAgdaFiles(Paths.get(root)).flatMap(parseFile)

    writeAsJsonl(extracted, Paths.get("output/theorems.jsonl"))
  }
}
