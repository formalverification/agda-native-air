/**
 * PreprocessAgda.scala
 *
 * File: agda-ai-prover/ml-pipeline/etl/src/main/scala/PreprocessAgda.scala
 *
 * Description:
 *   Preprocess Agda proof data from JSON Lines format to Parquet.
 *
 * Input:
 *   JSONL file with fields: file, module, name, agdaType, proof, premises
 *
 * Output:
 *   Parquet train/test datasets with a few helper features.
 *
 * Usage:
 *   sbt "run"       # uses defaults: repo-root/data -> ml-pipeline/features
 *   sbt "run /abs/in/train.jsonl /abs/out/dir"
 *
 * Copyright (c) 2025 Thmpr.
 */

import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._

object PreprocessAgda {

  def process(spark: SparkSession, inJsonl: String, outDir: String): Unit = {

    // Explicit schema keeps `module` as String (avoid accidental ArrayType)
    val schema = StructType(Seq(
      StructField("file", StringType, true),
      StructField("module", StringType, true),
      StructField("name", StringType, true),
      StructField("agdaType", StringType, true),
      StructField("proof", StringType, true),
      StructField("premises", ArrayType(StringType), true)
    ))

    val df = spark.read
      .schema(schema)
      .json(inJsonl)

    val cleaned = df
      .withColumn("lenType", length(col("agdaType")))
      .withColumn("lenProof", length(col("proof")))

    val Array(train, test) = cleaned.randomSplit(Array(0.9, 0.1), seed = 42L)

    train.write.mode("overwrite").parquet(s"$outDir/train.parquet")
    test.write.mode("overwrite").parquet(s"$outDir/test.parquet")
  }

  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("ETL Agda JSONL -> Parquet")
      .master(sys.props.getOrElse("spark.master", "local[*]"))
      .getOrCreate()

    try {
      // Defaults match Makefile: repo-root/data/train.jsonl -> ml-pipeline/features
      val in  = if (args.length >= 1) args(0) else new java.io.File("../../data/train.jsonl").getAbsolutePath
      val out = if (args.length >= 2) args(1) else new java.io.File("../features").getAbsolutePath

      process(spark, in, out)
    } finally {
      spark.stop()
    }
  }
}
