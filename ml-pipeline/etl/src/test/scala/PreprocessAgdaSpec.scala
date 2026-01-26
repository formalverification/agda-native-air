/**
 * PreprocessAgdaSpec.scala
 *
 * File: agda-ai-prover/ml-pipeline/etl/src/test/scala/PreprocessAgdaSpec.scala
 * Copyright: (c) 2025-2026 Thmpr Lab
 *
 * Fixture-driven integration test for PreprocessAgda ETL process.
 * + uses a tiny JSONL fixture in src/test/resources
 * + runs PreprocessAgda.process
 * + validates Parquet output + schema
 */

package etl

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import java.nio.file.{Files, Path, Paths}
import org.apache.spark.sql.SparkSession

class PreprocessAgdaSpec extends AnyFunSuite with Matchers {

  private def mkTempDir(prefix: String): Path =
    Files.createTempDirectory(prefix)

  test("PreprocessAgda writes Parquet with expected columns (fixture-driven)") {
    val spark = SparkSession.builder()
      .appName("PreprocessAgdaSpec")
      .master(sys.props.getOrElse("spark.master", "local[*]"))
      .getOrCreate()

    val outDir    = mkTempDir("etl-preprocess-agda-")
    val trainPath = outDir.resolve("train.parquet")
    val testPath  = outDir.resolve("test.parquet")

    val fixtureUrl =
      Option(getClass.getResource("/backend-full.example.jsonl"))
        .getOrElse(fail("Missing fixture: src/test/resources/backend-full.example.jsonl"))
    val inJsonl = Paths.get(fixtureUrl.toURI).toString

    try {
      // Run ETL directly (no reliance on ../../data/train.jsonl)
      PreprocessAgda.process(spark, inJsonl = inJsonl, outDir = outDir.toString)

      Files.exists(trainPath) shouldBe true
      Files.exists(testPath)  shouldBe true

      val df = spark.read.parquet(trainPath.toString)

      val cols = df.columns.toSet
      cols should contain ("file")
      cols should contain ("module")
      cols should contain ("name")
      cols should contain ("qname")
      cols should contain ("prettyModule")
      cols should contain ("prettyName")
      cols should contain ("prettyQname")
      cols should contain ("defKind")

      cols should contain ("type")
      cols should contain ("body")
      cols should contain ("hasBody")
      cols should contain ("typeAstVersion")
      cols should contain ("typeAstJson")
      cols should contain ("dependencies")
      cols should contain ("astSize")

      cols should contain ("lenType")
      cols should contain ("lenProof")
      cols should contain ("lenBody")
      cols should contain ("hasTypeAst")
      cols should contain ("typeAstBytes")

      df.count() should be > 0L

      // Sanity: at least one row should have typeAstJson (fixture includes it)
      df.filter("hasTypeAst = true").count() should be > 0L

    } finally {
      spark.stop()
    }
  }
}
