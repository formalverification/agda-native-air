/** ============================================================================
 *  SampleGen.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/util/SampleGen.scala
 *  Package: proofparser.util
 *  Copyright: (c) 2024 Thmpr Lab, LLC.
 *
 *  Description
 *  ----------
 *  Tiny synthetic generator for a 16-row JSONL dataset compatible with
 *  DatasetStats and PremiseEval (mode 1). Useful for smoke tests.
 *
 *  Usage
 *  -----
 *      sbt "runMain proofparser.SampleGen out.jsonl --n 16"
 *
 *  ============================================================================
 */

package proofparser.util

import upickle.default._

object SampleGen {
  final case class Row(
    file: String,
    module: Option[String],
    name: String,
    agdaType: String,
    proof: String,
    premises: List[String]
  )
  implicit val rw: ReadWriter[Row] = macroRW

  def main(args: Array[String]): Unit = {
    if (args.isEmpty) { Console.err.println("Usage: SampleGen <out.jsonl> [--n N]"); sys.exit(1) }
    val out = args(0)
    val n   = args.sliding(2,1).collectFirst{case Array("--n",x)=>x.toInt}.getOrElse(16)

    val mods = Vector("Algebra.Basic","Algebra.Group","Logic.Core","Data.Vec")
    val premPool = Vector("assoc","comm","id-left","id-right","distrib","map-id","map-comp","zero","succ")

    val rows = (0 until n).map { i =>
      val m  = mods(i % mods.size)
      val nm = s"thm${i%7}_${i}"
      val k  = 1 + (i % 4)
      val ps = premPool.slice(i % premPool.size, (i % premPool.size) + k).map(p => s"$m.$p").toList
      Row(
        file     = s"/fake/$m.agda",
        module   = Some(m),
        name     = nm,
        agdaType = s"∀ x y z → P${i%3} x → Q${i%5} y → R z",
        proof    = s"λ x y z → proof_${i}",
        premises = ps
      )
    }

    val sb = new StringBuilder
    rows.foreach(r => sb.append(write(r)).append('\n'))
    java.nio.file.Files.write(java.nio.file.Paths.get(out), sb.result.getBytes(java.nio.charset.StandardCharsets.UTF_8))
    println(s"wrote $n synthetic rows to $out")
  }
}
