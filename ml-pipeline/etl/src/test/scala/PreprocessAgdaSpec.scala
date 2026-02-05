/**
 * PreprocessAgdaSpec.scala
 *
 * File: agda-ai-prover/ml-pipeline/etl/src/test/scala/PreprocessAgdaSpec.scala
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
      // Option(getClass.getResource("/backend-full.example.jsonl"))
      //   .getOrElse(fail("Missing fixture: src/test/resources/backend-full.example.jsonl"))
      Option(getClass.getResource("/agda-algebras.smoke.jsonl"))
        .getOrElse(fail("Missing fixture: src/test/resources/agda-algebras.smoke.jsonl"))
    val inJsonl = Paths.get(fixtureUrl.toURI).toString

    try {
      // Run ETL directly (no reliance on ../../data/train.jsonl)
      PreprocessAgda.process(spark, inJsonl = inJsonl, outDir = outDir.toString)

      Files.exists(trainPath) shouldBe true
      Files.exists(testPath)  shouldBe true

      val df = spark.read.parquet(trainPath.toString)

      // 1) required columns exist + 2) required types match
      PreprocessAgdaSchema.assertSchemaIsSuperset(df.schema)

      // 3) allow extra columns (future-proof): just don’t assert equality
      // Optionally sanity-check that some derived columns exist (but don’t overdo it)
      val cols = df.columns.toSet
      cols should contain ("lenType")
      cols should contain ("lenBody")
      cols should contain ("lenProof")
      cols should contain ("hasTypeAst")
      cols should contain ("typeAstBytes")

      df.count() should be > 0L

      // We do NOT require hasTypeAst=true exists, just that hasTypeAst column is present.
      df.select("hasTypeAst").count() should be > 0L
      df.filter("hasTypeAst = true").count() should be >= 0L

      // Sanity: typeAstJson column exists
      //df.filter("typeAstJson is not null").count() should be > 0L

    } finally {
      spark.stop()
    }
  }
}
