/**
 * PreprocessAgda.scala
 *
 * File: agda-ai-prover/ml-pipeline/etl/src/main/scala/PreprocessAgda.scala
 * Copyright: (c) 2025-2026 Thmpr Lab
 *
 * Description:
 *   Preprocess canonical Agda backend JSONL (agda-json --format full) to Parquet.
 *
 * Input:
 *   JSONL file with (at minimum):
 *     file, module, name, qname, prettyQname, type, typeAstVersion, typeAst, body, hasBody, defKind, dependencies, astSize
 *
 * Output:
 *   Parquet train/test datasets with a few helper features.
 *
 * Notes:
 *   - We store `typeAst` as a JSON STRING column (`typeAstJson`) for versioning + ML friendliness.
 *   - We can later add derived / flattened features from `typeAstJson`.
 *
 * Usage:
 *   sbt "run"       # uses defaults: repo-root/data -> ml-pipeline/features
 *   sbt "run /abs/in/train.jsonl /abs/out/dir"
 *
 */

import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._

object PreprocessAgda {

  def process(spark: SparkSession, inJsonl: String, outDir: String): Unit = {

    // Read JSONL as raw lines, then extract only what we want.
    // This keeps nested JSON (`typeAst`) stable by storing it as a string column.
    val lines = spark.read.text(inJsonl).toDF("raw")

    val extracted = lines.select(
      get_json_object(col("raw"), "$.file").as("file"),
      get_json_object(col("raw"), "$.module").as("module"),
      get_json_object(col("raw"), "$.name").as("name"),

      get_json_object(col("raw"), "$.qname").as("qname"),
      get_json_object(col("raw"), "$.prettyModule").as("prettyModule"),
      get_json_object(col("raw"), "$.prettyName").as("prettyName"),
      get_json_object(col("raw"), "$.prettyQname").as("prettyQname"),

      get_json_object(col("raw"), "$.defKind").as("defKind"),

      // Canonical string forms
      get_json_object(col("raw"), "$.type").as("type"),
      get_json_object(col("raw"), "$.body").as("body"),
      get_json_object(col("raw"), "$.hasBody").cast(BooleanType).as("hasBody"),

      // Canonical structural form (store as JSON string)
      get_json_object(col("raw"), "$.typeAstVersion").as("typeAstVersion"),
      get_json_object(col("raw"), "$.typeAst").as("typeAstJson"),

      // Arrays: parse JSON array string into Spark ArrayType
      from_json(get_json_object(col("raw"), "$.dependencies"), ArrayType(StringType)).as("dependencies"),

      // Numeric (may be absent/null)
      get_json_object(col("raw"), "$.astSize").cast(IntegerType).as("astSize")
    )

    // Basic sanity features (useful for quick baselines/debugging)
    val cleaned = extracted
      .withColumn("lenType", length(coalesce(col("type"), lit(""))))
      .withColumn("lenBody", length(coalesce(col("body"), lit(""))))
      .withColumn("hasTypeAst", col("typeAstJson").isNotNull)
      .withColumn("typeAstBytes", length(coalesce(col("typeAstJson"), lit(""))))

    // Keep rows that at least have a type; bodies can legitimately be null/empty for some defKinds.
    val filtered = cleaned.filter(col("type").isNotNull && length(col("type")) > 0)

    val Array(train, test) = filtered.randomSplit(Array(0.9, 0.1), seed = 42L)

    train.write.mode("overwrite").parquet(s"$outDir/train.parquet")
    test.write.mode("overwrite").parquet(s"$outDir/test.parquet")
  }

  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("ETL Agda JSONL -> Parquet")
      .master(sys.props.getOrElse("spark.master", "local[*]"))
      .getOrCreate()

    try {
      // Defaults match Makefile (but prefer passing an explicit JSONL path):
      //   sbt "project etl" "runMain PreprocessAgda /abs/in.jsonl /abs/outdir"
      val in  = if (args.length >= 1) args(0) else new java.io.File("../../data/train.jsonl").getAbsolutePath
      val out = if (args.length >= 2) args(1) else new java.io.File("../features").getAbsolutePath

      process(spark, in, out)
    } finally {
      spark.stop()
    }
  }
}
