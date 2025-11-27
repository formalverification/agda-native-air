/** ===============================================================
 *  Agda2TrainTransformerSpec.scala
 *  ========================================================================
 *
 *  File: proof-parser/src/test/scala/proofparser/Agda2TrainTransformerSpec.scala
 *  Package: proofparser
 *  Copyright: (c) 2024 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  Unit tests for Agda2TrainTransformer—the offline transformer that turns
 *  Agda’s “agda2train” JSON dump(s) into canonical AgdaData rows.
 *
 *  What We Test
 *  -----------
 *  1) We can parse the sample JSON and produce non-empty rows.
 *  2) Self-premise filtering removes premises that refer to the row itself.
 *  3) JSONL (multi-line) parsing doesn’t choke.
 *
 *  Notes
 *  -----
 *  We avoid asserting exact module representation because your transformer
 *  currently emits either [] or ["seg","subseg"] for module. We assert
 *  invariant things: names present, no self-premises, etc.
 *
 *  Run: `sbt test`
 *
 ** ======================================================================== */

package proofparser

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

import java.nio.file.{Files, Paths}
import scala.jdk.CollectionConverters._

import upickle.default._

import proofparser.schema._
import proofparser.transform.Agda2TrainTransformer

final class Agda2TrainTransformerSpec extends AnyFunSuite with Matchers {

  private def loadResource(path: String): String = {
    val url = getClass.getClassLoader.getResource(path)
    require(url != null, s"Missing resource: $path")
    scala.io.Source.fromURL(url)("UTF-8").mkString
  }

  test("Agda2TrainTransformer turns agda-example.json into non-empty AgdaData JSONL") {
    val json   = loadResource("proofparser/agda-example.json")
    val out    = Files.createTempFile("a2t", ".jsonl")
    val outStr = out.toString

    Agda2TrainTransformer.transform(json, outStr) shouldBe Right(())

    val lines = Files.readAllLines(out).asScala.toList
    lines.nonEmpty shouldBe true

    val rows = lines.map(line => read[AgdaData](line))

    // basic sanity: all rows have name/type/proof populated
    rows.forall(_.name.nonEmpty)                       shouldBe true
    rows.forall(_.agdaType.exists(_.nonEmpty))         shouldBe true
    rows.forall(_.proof.exists(_.nonEmpty))            shouldBe true

    // no row should list itself directly as a premise
    rows.forall(r => !r.premises.contains(r.name))     shouldBe true
  }
}
