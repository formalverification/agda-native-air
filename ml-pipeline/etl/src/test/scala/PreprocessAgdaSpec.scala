/**
 * PreprocessAgdaSpec.scala
 *
 * Test suite for PreprocessAgda ETL process.
 *
 * This test checks that given the input JSONL file exists and is non-empty,
 * the ETL process produces Parquet files with the expected schema.
 *
 * This test:
 * +  Skips itself (via `assume`) if `../../data/train.jsonl` isn’t present yet.
 * +  Calls our real `PreprocessAgda.main` (integration-style).
 * +  Verifies Parquet files exist and checks a few expected columns + row count.
 *
 * To run this test, ensure you have run `make extract` to generate the
 * necessary JSONL data file.  Then do
 *
 *     cd ml-pipeline/etl
 *     sbt -batch test
 *
 * File: agda-ai-prover/ml-pipeline/etl/src/test/scala/PreprocessAgdaSpec.scala
 *
 * Copyright (c) 2025 Thmpr Lab, LLC.
 */

package etl

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import java.io.File
import java.nio.file.{Files, Paths}
import org.apache.spark.sql.SparkSession

class PreprocessAgdaSpec extends AnyFunSuite with Matchers {

  private val repoData   = Paths.get("../../data/train.jsonl").toFile
  private val trainPath  = Paths.get("../features/train.parquet")
  private val testPath   = Paths.get("../features/test.parquet")

  test("PreprocessAgda writes Parquet with expected columns (if JSONL exists)") {
    // Make this test a no-op if you haven't run `make extract` yet
    assume(repoData.exists() && repoData.length() > 0,
      s"Skipping: ${repoData.getPath} not found or empty. Run `make extract` first.")

    // Run the ETL main (writes ../features/*.parquet)
    PreprocessAgda.main(Array.empty)

    // Check outputs exist
    Files.exists(trainPath) shouldBe true
    Files.exists(testPath)  shouldBe true

    // Open Spark to validate schema quickly
    val spark = SparkSession.builder()
      .appName("PreprocessAgdaSpec")
      .master(sys.props.getOrElse("spark.master", "local[*]"))
      .getOrCreate()

    try {
      val df = spark.read.parquet(trainPath.toString)

      // Columns we expect given PreprocessAgda.scala
      val cols = df.columns.toSet
      cols should contain ("file")
      cols should contain ("module")
      cols should contain ("name")
      cols should contain ("agdaType")
      cols should contain ("proof")
      cols should contain ("premises")
      cols should contain ("lenType")
      cols should contain ("lenProof")

      // And we expect at least one row when train.jsonl was non-empty
      df.count() should be > 0L
    } finally {
      spark.stop()
    }
  }
}
