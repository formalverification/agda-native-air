/**
 * AgdaExtractorMain.scala
 *
 * File: agda-ai-prover/proof-parser/src/main/scala/AgdaExtractorMain.scala
 *
 * Decription:
 *   Main program to extract proofs from Agda files and output them in JSONL format.
 *   The input can be a single .agda file or a directory containing multiple .agda files.
 *   The output will be a JSONL file where each line is a JSON object representing an extracted proof.
 *
 * Why:
 *   This lets the root `make extract` produce `train.jsonl` directly from `.agda`
 *   sources (no agda2train JSON required). (We keep `Agda2TrainTransformer.scala`
 *   around for future compatibility with agda2train.)
 *
 * Usage:
 *   sbt "runMain proofparser.AgdaExtractorMain <input.agda or dir> <output.jsonl>"
 *
 * Notes:
 *   Each JSON object has the following fields:
 *   - file: The name of the Agda file.
 *   - module: The module name (if any).
 *   - name: The name of the proof.
 *   - agdaType: The type of the proof in Agda syntax.
 *   - proof: The proof term in Agda syntax.
 *   - premises: A list of premises (currently empty, can be populated as needed).
 *
 * Example output line:
 *   {"file":"Example.agda","module":"ExampleModule","name":"myProof","agdaType":"A -> B","proof":"myProofTerm","premises":[]}
 *
 * Copyright (c) 2025 Thmpr.
 */

package proofparser

import java.nio.file.{Files, Paths, Path}
import scala.util.Using
import upickle.default._
import proofparser.AgdaData

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
        Console.err.println(s"ERROR: input must be a .agda file or directory: ${in}")
        sys.exit(2); Nil
      }

    val rows: Seq[AgdaData] =
      paths.flatMap { p =>
        val olds = parseAgdaFile(p) // returns Seq[AgdaDataOld]
        olds.map(o => AgdaData(o.file, o.module, o.name, o.agdaType, o.proof))
      }

    // Write JSONL
    Using(Files.newBufferedWriter(out)) { w =>
      rows.foreach { r => w.write(write(r)); w.newLine() }
    }.get

    println(s"Extracted ${rows.size} rows to ${out.toAbsolutePath}")
  }
}
