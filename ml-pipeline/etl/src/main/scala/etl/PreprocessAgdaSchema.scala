/**
 * PreprocessAgdaSchema.scala
 *
 * File: agda-ai-prover/ml-pipeline/etl/src/main/scala/etl/PreprocessAgdaSchema.scala
 *
 * Description:
 *   Schema for preprocessed Agda definitions.  This is the gold standard schema used
 *   to validate that ETL output conforms to expectations.
 */

package etl

import org.apache.spark.sql.types._

object PreprocessAgdaSchema {

  // Keep this strict for “contract fields”.
  // If you later add optional fields, add them as optional, not required.
  val base: Seq[StructField] = Seq(
    StructField("file", StringType, nullable = true),
    StructField("module", StringType, nullable = true),
    StructField("name", StringType, nullable = true),
    StructField("qname", StringType, nullable = true),
    StructField("prettyModule", StringType, nullable = true),
    StructField("prettyName", StringType, nullable = true),
    StructField("prettyQname", StringType, nullable = true),
    StructField("defKind", StringType, nullable = true),
    StructField("type", StringType, nullable = true),
    StructField("body", StringType, nullable = true),
    StructField("hasBody", BooleanType, nullable = true),
    StructField("typeAstVersion", StringType, nullable = true),
    StructField("typeAstJson", StringType, nullable = true),
    // NOTE: Spark's `ArrayType(StringType)` defaults to `containsNull = true`,
    // and our ETL currently parses dependencies with that default.
    // Also, `coalesce(..., array())` makes the column itself effectively non-nullable.
    // We match the produced Parquet schema here to avoid brittle test failures.
    StructField("dependencies", ArrayType(StringType, containsNull = true), nullable = false),
    StructField("astSize", IntegerType, nullable = true),
  )

  val derived: Seq[StructField] = Seq(
    StructField("lenType", IntegerType, nullable = true),
    StructField("lenProof", IntegerType, nullable = true),
    StructField("lenBody", IntegerType, nullable = true),
    StructField("hasTypeAst", BooleanType, nullable = true),
    StructField("typeAstBytes", IntegerType, nullable = true)
  )

  val required: Seq[StructField] = base ++ derived

  val requiredNames: Set[String] = required.map(_.name).toSet

  def assertSchemaIsSuperset(actual: StructType): Unit = {
    val m = actual.fields.map(f => f.name -> f).toMap

    val missing = requiredNames.diff(m.keySet)
    require(missing.isEmpty, s"Missing required columns: ${missing.toList.sorted.mkString(", ")}")

    // Stronger: type checks for required columns.
    val badTypes =
      required.flatMap { exp =>
        m.get(exp.name).toList.flatMap { got =>
          if (got.dataType != exp.dataType)
            List(s"${exp.name}: expected ${exp.dataType.simpleString}, got ${got.dataType.simpleString}")
          else Nil
        }
      }

    require(badTypes.isEmpty, s"Schema type mismatches:\n- ${badTypes.mkString("\n- ")}")
  }
}
