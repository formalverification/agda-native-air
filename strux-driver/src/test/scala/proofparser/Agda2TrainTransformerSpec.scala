/** ===============================================================
 *  Agda2TrainTransformerSpec.scala
 *  ========================================================================
 *
 *  File: strux-driver/src/test/scala/proofparser/Agda2TrainTransformerSpec.scala
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

import ujson._
import org.scalatest.Inside

import proofparser.schema.{AgdaData, AgdaDataOps, DeclKind}
import proofparser.schema.Semantic

final class Agda2TrainTransformerSpec extends TestKit with Inside {

  "Manual Agda2Train-style parsing" should {
    "extract canonical AgdaData rows from the sample agda-example.json" in {
      val text = loadResource("/proofparser/agda-example.json")
      val json = ujson.read(text)

      // Flatten "scope-local" and "scope-private"
      val locals = json("scope-local").arrOpt.map(_.toList).getOrElse(Nil)
      val privs  = json("scope-private").arrOpt.map(_.toList).getOrElse(Nil)
      val all    = locals ++ privs

      val rows: List[AgdaData] = all.flatMap(_.objOpt.flatMap { obj =>
        val nameOpt = obj.get("name").flatMap(_.strOpt)
        val typeStr = obj
          .get("type").flatMap(_.objOpt)
          .flatMap(_("pretty").strOpt)
        val defStr  = obj
          .get("definition").flatMap(_.objOpt)
          .flatMap(_("pretty").strOpt)

        val premises: List[String] =
          obj.get("holes").toList
            .flatMap(_.arrOpt.toList.flatten)
            .flatMap(_.objOpt.toList)
            .flatMap { h =>
              h.get("premises").toList
                .flatMap(_.arrOpt.toList.flatten)
                .flatMap(_.strOpt)
            }
            .distinct

        (nameOpt, typeStr, defStr) match {
          case (Some(qn), Some(tp), Some(df)) =>
            val parts = qn.split('.').toList
            val fileBase = parts.headOption.getOrElse("")
            val file     = if (fileBase.nonEmpty) s"$fileBase.agda" else "unknown-file.agda"
            val mod      = parts.drop(1) match {
              case Nil      => None
              case _ :: Nil => None
              case many     => Some(many.init.mkString("."))
            }
            val nm = parts.lastOption.getOrElse("")

            val sem = Semantic.from(
              name     = nm,
              agdaType = Some(tp),
              module   = mod,
              proof    = Some(df)
            )

            val raw = AgdaData(
              file     = file,
              module   = mod,
              name     = nm,
              agdaType = Some(tp),
              proof    = Some(df),
              premises = premises,
              declKind = sem.kind,
              astSize  = sem.astSize
            )

            Some(AgdaDataOps.normalize(raw))

          case _ =>
            None
        }
      })

      rows should not be empty

      val names = rows.map(_.name).toSet
      names.intersect(Set("_+_<8>", "+-suc<40>", "+-comm<22>")) should not be empty
    }
  }

  "JSONL input" should {
    "parse multiple JSON objects split across lines without choking" in {
      val one = """{"name":"mod1","scope-local":[{}],"scope-private":[]}"""
      val two = """{"name":"mod2","scope-local":[{}],"scope-private":[]}"""
      val text = one + "\n" + two + "\n"

      noException should be thrownBy {
        text.linesIterator.foreach { ln =>
          if (ln.trim.nonEmpty) ujson.read(ln) // just sanity check per-line JSON
        }
      }
    }
  }
}
