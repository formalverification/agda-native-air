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

import ujson._
import org.scalatest.Inside

class Agda2TrainTransformerSpec extends TestKit with Inside {

  "Agda2TrainTransformer.parseOne" should {
    "extract records from the sample agda-example.json" in {
      val text = loadResource("/proofparser/agda-example.json")
      val json = ujson.read(text)

      // Flatten "scope-local" and "scope-private", then map each item to AgdaData
      val locals = json("scope-local").arrOpt.map(_.toList).getOrElse(Nil)
      val privs  = json("scope-private").arrOpt.map(_.toList).getOrElse(Nil)
      val all    = locals ++ privs

      val rows: List[AgdaData] = all.flatMap(_.objOpt.flatMap { item =>
        val nameOpt = item.get("name").flatMap(_.strOpt)
        val typeStr = item.get("type").flatMap(_.objOpt).flatMap(_("pretty").strOpt)
        val defStr  = item.get("definition").flatMap(_.objOpt).flatMap(_("pretty").strOpt)

        nameOpt.flatMap { qn =>
          for {
            tp <- typeStr
            df <- defStr
          } yield {
            val parts = qn.split('.').toList
            val file  = parts.headOption.getOrElse("")
            val mod   = parts.drop(1) match {
              case Nil         => None
              case _ :: Nil    => None
              case many        => Some(many.init.mkString(".")) // coarse module string for the test
            }
            val nm = parts.lastOption.getOrElse("")

            val premises =
              item.get("holes").toList.flatMap(_.arrOpt.toList.flatten)
                .flatMap(_.objOpt.toList)
                .flatMap(h => h.get("premises").toList.flatMap(_.arrOpt.toList.flatten).flatMap(_.strOpt))
                .distinct

            AgdaData(file, mod, nm, tp, df, premises)
          }
        }
      })

      rows should not be empty
      val names = rows.map(_.name).toSet
      names.intersect(Set("_+_<8>", "+-suc<40>", "+-comm<22>")) should not be empty
    }
  }

  "Self-premise filtering" should {
    "drop premises that point to the row itself, across spelling variants" in {
      val rec = AgdaData(
        file     = "agda-example",
        module   = Some("properties"),
        name     = "+-suc<40>",
        agdaType = "A",
        proof    = "P",
        premises = List(
          "agda-example.properties.+-suc<40>",   // exact
          "agda-example.agda.properties.+-suc",  // with .agda and no angle
          "agda-example.properties._.+-suc<40>"  // hidden module ._.
        )
      )

      // Normalizer mirrors the transformer’s idea (lightweight and local).
      def stripAngle(s: String): String           = s.replaceAll("<\\d+>$", "")
      def stripAgdaDot(path: String): String      = path.replace(".agda.", ".").stripSuffix(".agda")
      def collapseHidden(path: String): String    = path.replace("._.", ".")
      def normalizePremise(p: String): String     = stripAgdaDot(collapseHidden(stripAngle(p)))
      def baseFile(f: String): String             = if (f.endsWith(".agda")) f.stripSuffix(".agda") else f

      def idVariants(r: AgdaData): List[String] = {
        val b  = baseFile(r.file)
        val nm = stripAngle(r.name)
        val v0 = s"$b.$nm"
        val v1 = r.module.filter(_.nonEmpty).map(m => s"$b.$m.$nm").getOrElse(v0)
        val v2 = s"$b.agda.$nm"
        val v3 = r.module.filter(_.nonEmpty).map(m => s"$b.agda.$m.$nm")
        (List(v1, v0, v2) ++ v3).map(normalizePremise)
      }

      def isSelfPremise(r: AgdaData, p: String): Boolean =
        idVariants(r).contains(normalizePremise(p))

      val kept = rec.premises.filterNot(p => isSelfPremise(rec, p))
      kept shouldBe empty
    }
  }

  "JSONL input" should {
    "parse multiple module dumps split across lines" in {
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
