/**
 * build.sbt
 *
 * Description:
 *   SBT build configuration for the ETL module of the ML pipeline.
 *
 * File: agda-ai-prover/ml-pipeline/build.sbt
 *
 * Copyright (c) 2025 Thmpr Lab, LLC.
 */

name := "ml-pipeline"
version := "0.1"

ThisBuild / scalaVersion := "2.12.18"

lazy val etl = project.in(file("etl")).settings(
  name := "ETL",
  Compile / mainClass := Some("PreprocessAgda"),

  // Spark deps + test
  libraryDependencies ++= Seq(
    "org.apache.spark" %% "spark-sql" % "3.5.1",
    "org.scalatest"    %% "scalatest" % "3.2.19" % Test
      // "org.apache.spark" %% "spark-core" % "3.4.1", // % "provided",
      // "org.apache.spark" %% "spark-sql"  % "3.4.1" // % "provided"
  ),

  // Nice defaults
  scalacOptions ++= Seq("-deprecation", "-feature"),
  Test / parallelExecution := false,

  // We fork java and grant JDK21 module opens for Spark (Run + Test)
  fork := true,
  // These apply to `sbt run` (which our `make etl` uses):
  Compile / run / fork := true,
  Compile / run / javaOptions ++= Seq(
    "--add-exports=java.base/sun.nio.ch=ALL-UNNAMED",
    "--add-opens=java.base/java.nio=ALL-UNNAMED"
  ),
    // ---------- IMPORTANT for Java 17/21 ----------
    // Fixes "IllegalAccessError: sun.nio.ch.DirectBuffer" when running Spark under Java 17+.
    // These apply to `sbt test` (Spark inside tests).
    // If we ever switch dev shell to JDK 17, we can remove these flags.
  Test / javaOptions ++= Seq(
    "--add-exports=java.base/sun.nio.ch=ALL-UNNAMED",
    "--add-opens=java.base/java.nio=ALL-UNNAMED"
  )
)

lazy val root = (project in file("."))
  .aggregate(etl)
  .settings(
    name := "ml-pipeline",
    // keep test output readable
    Test / parallelExecution := false
  )



// // Correctly typed override
// dependencyOverrides := Seq(
//   "org.apache.hadoop" % "hadoop-client-api" % "3.3.4",
//   "org.apache.hadoop" % "hadoop-client-runtime" % "3.3.4"
// )

// // JVM options for JDK 17 compatibility
// ThisBuild / fork := true
// ThisBuild / classLoaderLayeringStrategy := ClassLoaderLayeringStrategy.Flat
// ThisBuild / javaOptions ++= Seq(
//   "--add-exports=java.base/sun.nio.ch=ALL-UNNAMED",
//   "-Dspark.driver.userClassPathFirst=true",
//   "-Dspark.executor.userClassPathFirst=true",
//   "-Dspark.driver.extraClassPath=target/scala-2.12/classes",
//   "-Dspark.executor.extraClassPath=target/scala-2.12/classes"
// )

// Global / excludeLintKeys += classLoaderLayeringStrategy
