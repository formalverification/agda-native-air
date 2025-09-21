/**
 * build.sbt
 *
 * Description:
 *   SBT build configuration for the ETL module of the ML pipeline.
 *
 * File: agda-ai-prover/ml-pipeline/etl/build.sbt
 *
 * Copyright (c) 2024 Thmpr.
 */
name := "ETL"
version := "0.1"

ThisBuild / scalaVersion := "2.12.18"

libraryDependencies ++= Seq(
  // Spark dependencies
  "org.apache.spark" %% "spark-sql" % "3.5.1",   // compile scope so `sbt run` works
  "org.scalatest"    %% "scalatest" % "3.2.19" % Test
  // "org.apache.spark" %% "spark-core" % "3.4.1", // % "provided",
  // "org.apache.spark" %% "spark-sql"  % "3.4.1" // % "provided"
)

scalacOptions ++= Seq("-deprecation", "-feature")

// We run Spark in a separate JVM
ThisBuild / fork := true
Test / fork      := true

// ---------- IMPORTANT for Java 17/21 ----------
// Fixes "IllegalAccessError: sun.nio.ch.DirectBuffer" when running Spark under Java 17+.
// These apply to `sbt test` (Spark inside tests).
// If we ever switch dev shell to JDK 17, we can remove these flags.
Test / javaOptions ++= Seq(
  "--add-exports=java.base/sun.nio.ch=ALL-UNNAMED",
  "--add-opens=java.base/java.nio=ALL-UNNAMED"
)

// These apply to `sbt run` (which our `make etl` uses):
Compile / run / fork := true
Compile / run / javaOptions ++= Seq(
  "--add-exports=java.base/sun.nio.ch=ALL-UNNAMED",
  "--add-opens=java.base/java.nio=ALL-UNNAMED"
)

// QoL: which main to run by default if we do plain `sbt run`
Compile / mainClass := Some("PreprocessAgda")

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
