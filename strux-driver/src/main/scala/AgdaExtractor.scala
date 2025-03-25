import java.nio.file.{Files, Paths, Path}
import java.nio.charset.StandardCharsets
import scala.jdk.CollectionConverters._
import io.circe.generic.auto._
import io.circe.syntax._
import java.io.PrintWriter

case class TheoremData(
  file: String,
  module: Option[String],
  name: String,
  body: String
)

object AgdaExtractor {

  def main(args: Array[String]): Unit = {
    val userArgs = args.dropWhile(_ == "--")
    val root = if (userArgs.nonEmpty) userArgs(0) else {
      println("Usage: AgdaExtractor <path-to-agda-lib>")
      sys.exit(1)
    }

    val agdaFiles = Files.walk(Paths.get(root))
      .iterator()
      .asScala
      .filter(p => p.toString.endsWith(".agda"))
      .toList

    val extracted = agdaFiles.flatMap(parseFile)

    val writer = new PrintWriter("output/theorems.jsonl", "UTF-8")
    extracted.foreach { entry =>
      writer.println(entry.asJson.noSpaces)
    }
    writer.close()

    println(s"✅ Extracted ${extracted.length} theorems.")
  }

  def parseFile(path: Path): List[TheoremData] = {
    val lines = Files.readAllLines(path, StandardCharsets.UTF_8).asScala.toList
    val module = lines.collectFirst {
      case line if line.trim.startsWith("module ") => line.trim.split("\\s+")(1)
    }

    val theorems = lines
      .sliding(2)
      .collect {
        case List(header, bodyLine) if header.contains(":") && bodyLine.contains("=") =>
          val name = header.takeWhile(c => c != ':' && c != ' ').trim
          val body = bodyLine.trim.dropWhile(_ != '=').drop(1).trim
          TheoremData(
            file = path.getFileName.toString,
            module = module,
            name = name,
            body = body
          )
      }
      .toList

    theorems
  }
}
