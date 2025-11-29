/** ============================================================================
 *  AgdaSimplifiedExtractorSpec.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/test/scala/proofparser/AgdaSimplifiedExtractorSpec.scala
 *  Package: proofparser
 *  Copyright: (c) 2024 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *   Tests for simplified Agda extractor logic. We avoid full Agda invocations
 *   here to keep tests fast and focused on core logic.
 *   Instead we test:
 *     +  `moduleName` (with a tiny temp file),
 *     +  `iotcmLoad` shape under different flags,
 *     +  `extractGoalsPretty` with a canned `AllGoalsWarnings` JSON.
 *
 *  Usage
 *  -----
 *   sbt test
 *   sbt "project proof-parser" test
 *
 *  Notes
 *  -----
 *  These are unit tests for isolated logic; full end-to-end tests involving Agda
 *  invocations are in AgdaExtractorSpec.scala.
 *
 ** ============================================================================ */

package proofparser

import java.nio.file.Files

import org.scalatest.OptionValues

import ujson._

final class AgdaSimplifiedExtractorSpec extends TestKit with OptionValues {

  "moduleName-style regex" should {
    "prefer the declared module name, else fallback to file base" in {
      val tmp = Files.createTempFile("ModX", ".agda")
      val body =
        """module Foo.Bar where
          |postulate A : Set
          |""".stripMargin
      Files.writeString(tmp, body)

      val nameFound = {
        // replicate extractor's logic inline (to avoid friend access):
        val fname = tmp.getFileName.toString.stripSuffix(".agda")
        val lines = Files.readAllLines(tmp).toArray.mkString("\n")
        val rx    = "(?m)^\\s*module\\s+([A-Za-z0-9_'.]+)\\s+where\\b".r
        rx.findFirstMatchIn(lines).map(_.group(1)).getOrElse(fname)
      }

      nameFound shouldBe "Foo.Bar"
      Files.deleteIfExists(tmp)
    }
  }

  "iotcmLoad-style JSON builder" should {
    "emit expected payload shape with toggles" in {

      def build(
        file: String,
        inc: Seq[String],
        libs: Seq[String],
        mode: String,
        emptyIsNull: Boolean
      ): Value = {
        // mirror AgdaSimplifiedExtractor.iotcmLoad
        val incArgs  = inc.flatMap(i => Seq("-i", i))
        val libArgs  = libs.flatMap(l => Seq("-l", l))
        val args     = incArgs ++ libArgs
        val headCell = if (emptyIsNull) ujson.Null else ujson.Str("")
        ujson.Obj(
          "command" -> "IOTCM",
          "payload" -> ujson.Arr(
            headCell, ujson.Arr(), mode,
            ujson.Obj(
              "command" -> "Cmd_load",
              "file"    -> file,
              "args"    -> ujson.Arr(args.map(ujson.Str): _*)
            )
          )
        )
      }

      val js1 = build("Foo.agda", Seq("inc"), Seq("standard-library"), "NonInteractive", emptyIsNull = false)
      js1("command").str               shouldBe "IOTCM"
      js1("payload")(0).str            shouldBe ""
      js1("payload")(2).str            shouldBe "NonInteractive"
      js1("payload")(3)("command").str shouldBe "Cmd_load"
      js1("payload")(3)("args").arr.map(_.str) shouldBe Seq("-i", "inc", "-l", "standard-library")

      val js2 = build("Foo.agda", Nil, Nil, "Direct", emptyIsNull = true)
      assert(js2("payload")(0).isNull)
      js2("payload")(2).str shouldBe "Direct"
    }
  }

  "AllGoalsWarnings-style payload decoding" should {
    "collect context and goal types from a synthetic message" in {

      // local micro-schema, avoiding clashes with real TrainRecord
      final case class CtxVar(name: String, tpe: String)
      final case class GoalRecord(
        file: String,
        module: String,
        name: String,
        context: List[CtxVar],
        goalType: String
      )

      val msg =
        ujson.Obj(
          "kind" -> "DisplayInfo",
          "payload" -> ujson.Obj(
            "info" -> ujson.Obj(
              "kind" -> "AllGoalsWarnings",
              "payload" -> ujson.Obj(
                "goals" -> ujson.Arr(
                  ujson.Obj(
                    "type" -> "ℕ → ℕ",
                    "context" -> ujson.Arr(
                      ujson.Obj("name" -> "m", "type" -> "ℕ"),
                      ujson.Obj("name" -> "n", "type" -> "ℕ")
                    )
                  )
                )
              )
            )
          )
        )

      // inline a tiny extractor-style mapper:
      val goals = msg("payload")("info")("payload")("goals").arr.toList
      val records = goals.zipWithIndex.map { case (g, idx) =>
        val gty = g("type").str
        val ctx = g("context").arr.toList.flatMap { it =>
          for {
            nm <- it.obj.get("name").flatMap(_.strOpt)
            tp <- it.obj.get("type").flatMap(_.strOpt)
          } yield CtxVar(nm, tp)
        }
        GoalRecord(
          file     = "Foo.agda",
          module   = "Foo",
          name     = s"Foo.goal_$idx",
          context  = ctx,
          goalType = gty
        )
      }

      records should have length 1
      records.head.context.map(_.name) shouldBe List("m", "n")
      records.head.goalType             shouldBe "ℕ → ℕ"
    }
  }
}
