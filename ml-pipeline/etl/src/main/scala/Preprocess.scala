/**
 * Preprocess.scala
 *
 * File: agda-native-air/ml-pipeline/etl/src/main/scala/Preprocess.scala
 *
 * LEGACY / DEMO ONLY.
 *
 * This file is a generic Spark CSV ETL example and is NOT used by the Agda pipeline.
 * The real Agda ETL is `etl.PreprocessAgda`.
 *
 * A simple ETL pipeline using Apache Spark to preprocess data.
 *
 * Description:
 *   Reads a CSV file, cleans the data, and splits it into training and
 *   testing datasets.
 *
 * Input:
 *  CSV file with columns: feature1, feature2, label
 *
 * Output:
 *   Parquet files for training and testing datasets.
 *
 * Usage:
 *   spark-submit --class Preprocess your-jar-file.jar
 *
 * Assumes input file is located at ../data/raw/data.csv relative to the
 * working directory.  Outputs Parquet files to features/train.parquet and
 * features/test.parquet.
 */

import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._

object Preprocess {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("ETL Pipeline (Legacy CSV Demo)")
      .master("local[*]")
      .getOrCreate()

    val csvPath = new java.io.File("../data/raw/data.csv").getAbsolutePath

    val raw = spark.read
      .option("header", "true")
      .csv(csvPath)

    val processed = raw
      .filter("label IS NOT NULL")
      .withColumn("feature1", col("feature1").cast("double"))
      .withColumn("feature2", col("feature2").cast("double"))
      .withColumn("label", col("label").cast("int"))

    val Array(train, test) = processed.randomSplit(Array(0.8, 0.2))

    train.write.mode("overwrite").parquet("features/train.parquet")
    test.write.mode("overwrite").parquet("features/test.parquet")

    spark.stop()
  }
}
