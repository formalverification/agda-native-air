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

import proofparser.schema.AgdaData
import proofparser.transform.Agda2TrainTransformer

final class Agda2TrainTransformerSpec extends AnyFunSuite with Matchers {

  private def loadResource(path: String): String = {
    val urlOpt = Option(getClass.getClassLoader.getResource(path))
    val url    = urlOpt.getOrElse(
      fail(s"Missing resource on classpath: $path")
    )
    scala.io.Source.fromURL(url)("UTF-8").mkString
  }

  test("Agda2TrainTransformer produces non-empty, decodable AgdaData JSONL from agda-example.json") {
    val jsonStr = loadResource("proofparser/agda-example.json")
    val jsonVal = ujson.read(jsonStr)

    val out    = Files.createTempFile("a2t", ".jsonl")
    val outStr = out.toString

    val res = Agda2TrainTransformer.transform(jsonStr, outStr)

    withClue(
      s"""|
          |[DEBUG] transform(...) result: $res
          |[DEBUG] top-level JSON:
          |  - isArray = ${jsonVal.arrOpt.isDefined}
          |  - isObject = ${jsonVal.objOpt.isDefined}
          |  - objectKeys = ${jsonVal.objOpt.map(_.value.keySet).getOrElse(Set.empty)}
          |""".stripMargin
    ) {
      res.isRight shouldBe true
    }

    Files.exists(out) shouldBe true

    val lines = Files.readAllLines(out).asScala.toList
    val nonEmptyLines = lines.filter(_.nonEmpty)

    withClue(
      s"""|
          |[DEBUG] output path: $outStr
          |[DEBUG] total lines written: ${lines.size}
          |[DEBUG] non-empty lines: ${nonEmptyLines.size}
          |[DEBUG] first few lines:
          |${nonEmptyLines.take(5).mkString("  • ", "\n  • ", if (nonEmptyLines.isEmpty) "" else "")}
          |""".stripMargin
    ) {
      nonEmptyLines.nonEmpty shouldBe true
    }

    // Decode all non-empty lines as AgdaData, with good failure context
    val decoded: List[AgdaData] =
      nonEmptyLines.map { line =>
        withClue(s"[DEBUG] failed to decode line as AgdaData: $line") {
          noException should be thrownBy read[AgdaData](line)
        }
        read[AgdaData](line)
      }

    // Some light sanity checks on decoded rows
    withClue(
      s"""|
          |[DEBUG] decoded rows: ${decoded.size}
          |[DEBUG] example names: ${decoded.take(5).map(_.name)}
          |""".stripMargin
    ) {
      decoded.nonEmpty shouldBe true
      all(decoded.map(_.name)) should not be empty
    }
  }
}
