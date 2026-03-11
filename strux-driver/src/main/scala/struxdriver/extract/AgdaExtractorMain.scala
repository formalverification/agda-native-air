/** ============================================================================
 *  AgdaExtractorMain.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: strux-driver/src/main/scala/struxdriver/extract/AgdaExtractorMain.scala
 *  Package: struxdriver.extract
 *
 *  Description
 *  -----------
 *  CLI entrypoint for the regex-based extractor; writes JSONL of canonical
 *  `AgdaData` rows.
 *
 *  The input can be a single `.agda` file or a directory containing multiple
 *  `.agda` files.  The output will be a JSONL file where each line is a JSON
 *  object representing one extracted declaration.
 *
 *  Schema
 *  ------
 *    - AgdaData (from struxdriver.schema):
 *        file      : String
 *        module    : Option[String]
 *        name      : String
 *        agdaType  : Option[String]
 *        proof     : Option[String]
 *        premises  : List[String]
 *        declKind  : DeclKind
 *        astSize   : Int
 *
 *  Usage
 *  -----
 *      sbt "project strux-driver" \
 *          "runMain struxdriver.extract.AgdaExtractorMain <in.agda|dir> <out.jsonl>"
 *
 *  Examples
 *  --------
 *      sbt "project strux-driver" \
 *          "runMain struxdriver.extract.AgdaExtractorMain \
 *           src/test/resources/agda-example.agda \
 *           target/example.jsonl"
 *
 *  Notes
 *  -----
 *   - Uses `AgdaExtractor` (heuristic, regex-based). Prefer Agda2Train-based
 *     tools for correctness on complex code.
 *   - Accepts a single file or a directory; filters `*.agda` files.
 *   - Premises are left empty (Nil) by this extractor. Other tools (e.g.,
 *     semantic filters or dependency analyzers) can populate them later.
 *
 *  ============================================================================
 */

package struxdriver.extract

import java.nio.file.{Files, Paths, Path}

import upickle.default._
import struxdriver.schema.AgdaData

object AgdaExtractorMain {

  // Reuse our existing AgdaExtractor helpers.
  import AgdaExtractor._

  def main(args: Array[String]): Unit = {
    if (args.length != 2) {
      Console.err.println("Usage: AgdaExtractorMain <in:.agda or dir> <out.jsonl>")
      sys.exit(1)
    }

    val in  = Paths.get(args(0))
    val out = Paths.get(args(1))

    val paths: List[Path] =
      if (Files.isDirectory(in)) getAgdaFiles(in)
      else if (args(0).endsWith(".agda")) List(in)
      else {
        Console.err.println(s"ERROR: input must be a .agda file or directory: $in")
        sys.exit(2); Nil
      }

    val rows: Vector[AgdaData] =
      paths.toVector.flatMap(parseAgdaFile)

    // Write JSONL
    val writer = Files.newBufferedWriter(out)
    try {
      rows.foreach { r =>
        writer.write(write(r))
        writer.newLine()
      }
    } finally {
      writer.close()
    }
    println(s"Extracted ${rows.size} rows to ${out.toAbsolutePath}")
  }
}
