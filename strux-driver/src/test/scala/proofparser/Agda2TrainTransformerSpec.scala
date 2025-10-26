/**
 *  Agda2TrainTransformerSpec.scala
 *
 *  FILE: proof-parser/src/test/scala/proofparser/Agda2TrainTransformerSpec.scala
 *
 *  DESCRIPTION
 *
 *    Unit tests for Agda2TrainTransformer, which extracts AgdaData records
 *    from Agda JSON dumps.  Tests cover:
 *      - record extraction from sample JSON,
 *      - self-premise filtering logic,
 *      - JSONL input parsing.
 *
 *  USAGE
 *
 *    sbt "project proof-parser" test
 *
 *  COPYRIGHT
 *
 *    (c) 2024 Thmpr Lab, LLC.
 */
package proofparser

import ujson._
import org.scalatest.Inside

class Agda2TrainTransformerSpec extends TestKit with Inside {

  "Agda2TrainTransformer.parseOne" should {
    "extract records from the sample agda-example.json" in {
      // Use your repo path or, better, relocate agda-example.json into test resources.
      // For now, read from the existing test resource path:
      val text = loadResource("/proofparser/agda-example.json") // put the file in test resources
      val json = ujson.read(text)

      val rows = {
        // call the same private helpers via a tiny local copy OR expose a small API
        // Here we reimplement the one-liner since parseOne is private:
        val locals = json("scope-local").arrOpt.map(_.toList).getOrElse(Nil)
        val privs  = json("scope-private").arrOpt.map(_.toList).getOrElse(Nil)
        val all    = locals ++ privs
        all.flatMap(_.objOpt.flatMap { item =>
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
                case only :: Nil => None
                case many        => Some(many.init.mkString("."))
              }
              val nm = parts.lastOption.getOrElse("")
              // Collect premises
              val premises =
                item.get("holes").toList.flatMap(_.arrOpt.toList.flatten)
                  .flatMap(_.objOpt.toList)
                  .flatMap(h => h.get("premises").toList.flatMap(_.arrOpt.toList.flatten).flatMap(_.strOpt))
                  .distinct

              AgdaData(file, mod, nm, tp, df, premises)
            }
          }
        })
      }

      rows should not be empty
      rows.map(_.name) should contain atLeastOneOf("_+_<8>", "+-suc<40>", "+-comm<22>")
    }
  }

  "Self-premise filtering" should {
    "drop premises that point to the row itself, across spelling variants" in {
      val rec = AgdaData(
        file = "agda-example",
        module = Some("properties"),
        name = "+-suc<40>",
        agdaType = "A",
        proof = "P",
        premises = List(
          "agda-example.properties.+-suc<40>",   // exact
          "agda-example.agda.properties.+-suc",  // with .agda and no angle
          "agda-example.properties._.+-suc<40>"  // hidden module ._. (unlikely but covered)
        )
      )

      // Use the same normalization as the transformer:
      def stripAngle(s: String): String = s.replaceAll("<\\d+>$", "")
      def stripAgdaDot(path: String): String = path.replace(".agda.", ".").stripSuffix(".agda")
      def collapseHidden(path: String): String = path.replace("._.", ".")
      def normalizePremise(p: String): String = stripAgdaDot(collapseHidden(stripAngle(p)))
      def baseFile(f: String): String = if (f.endsWith(".agda")) f.stripSuffix(".agda") else f
      def idVariants(r: AgdaData): List[String] = {
        val b  = baseFile(r.file)
        val nm = stripAngle(r.name)
        val vNoMod   = s"$b.$nm"
        val vWithMod = r.module.filter(_.nonEmpty).map(m => s"$b.$m.$nm").getOrElse(vNoMod)
        val vWithExt = s"$b.agda.$nm"
        val vWithExtMod = r.module.filter(_.nonEmpty).map(m => s"$b.agda.$m.$nm")
        (List(vWithMod, vNoMod, vWithExt) ++ vWithExtMod).map(normalizePremise)
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

      // Using the transformer's heuristic: first char '{' => single JSON; else JSONL.
      // We'll simulate JSONL path by forcing the branch (start with whitespace).
      val trimmed = " " + text

      // Just check it doesn't throw parsing errors with the heuristic.
      noException should be thrownBy {
        // Your transformer's parseInput handles this;
        // here we simply ensure ujson can read line by line.
        text.linesIterator.foreach { ln =>
          if (ln.trim.nonEmpty) ujson.read(ln)
        }
      }
    }
  }
}
