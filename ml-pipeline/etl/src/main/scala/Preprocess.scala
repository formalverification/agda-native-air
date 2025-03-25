import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._

object Preprocess {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder()
      .appName("ETL Pipeline")
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
