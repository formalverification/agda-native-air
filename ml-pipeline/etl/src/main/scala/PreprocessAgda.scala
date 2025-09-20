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
 *   Parquet files for training and testing datasets.
 *
 * Usage:
 *   spark-submit --class PreprocessAgda your-jar-file.jar
 *
 * Assumes input file is located at ../../data/train.jsonl relative to the working directory.
 * Outputs Parquet files to ../features/train.parquet and ../features/test.parquet.
 *
 * Copyright (c) 2025 Thmpr.
 */

import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._

object PreprocessAgda {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("ETL Agda JSONL -> Parquet")
      .master(sys.props.getOrElse("spark.master", "local[*]"))
      .getOrCreate()

    // Expect repo-root/data/train.jsonl produced by proof-parser
    val jsonl = new java.io.File("../../data/train.jsonl").getAbsolutePath

    // JSON Lines: one JSON object per line
    val df = spark.read
      .option("multiLine", "false")
      .json(jsonl)  // schema inferred: file,module,name,agdaType,proof,premises

    val cleaned = df
      .withColumn("module", coalesce(col("module"), lit(null))) // Option[String]
      .withColumn("lenType", length(col("agdaType")))
      .withColumn("lenProof", length(col("proof")))

    // Simple split for now
    val Array(train, test) = cleaned.randomSplit(Array(0.9, 0.1), seed = 42L)

    train.write.mode("overwrite").parquet("../features/train.parquet")
    test.write.mode("overwrite").parquet("../features/test.parquet")

    spark.stop()
  }
}
